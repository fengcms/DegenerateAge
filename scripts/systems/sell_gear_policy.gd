class_name SellGearPolicy
extends RefCounted
## 装备批量出售的纯筛选规则：按角色等级/档位、品质和保护状态生成本次清单。
## 不修改背包或金币；背包直卖与货郎暂存共用此预览，最终交易仍须重新校验。

const CAUTIOUS := "cautious"
const STANDARD := "standard"
const AGGRESSIVE := "aggressive"
## 暴力：跳过全部「价值判断」，背包内所有可售装备一次性打包出售（工程 61）。
## 「可售」仍是硬门槛 —— 任务物品与无价物品回收价为 0，卖了等于白扔，
## 且任务装备消失会让主线节点指向不存在的物品。收藏同样不卖（玩家亲手打的保护标记）。
const BRUTAL := "brutal"
const PRESETS := [CAUTIOUS, STANDARD, AGGRESSIVE, BRUTAL]
## 可写进存档的预设。**暴力不在其中**，两理由：
##   ① 存档里出现 `brutal` 而 `SettingsRuntime.CHOICE_VALUES` 漏登记 ⇒ 整档判损坏（M5-9c 同款事故）；
##   ② 持久化会让「下次打开面板时 40 格装备已经全部勾好」，一次手滑清空背包。
const PERSISTABLE := [CAUTIOUS, STANDARD, AGGRESSIVE]
## 拾取自动出售的等级门槛（产品决策：60 级才允许开启）。
## 放这里而不是散在 UI 里 —— 设置界面与运行时校验都读它，改数字只需改一处。
const AUTO_SELL_MIN_LEVEL := 60
## `level_gap` 为**可选键**：不写该键即表示该预设不设等级门槛（积极）。
## `require_older_suit` 为真时改用「旧套档」判据 —— 与「十级一套」模型对齐，见 `ItemFactory.suit_start`。
## 三个预设的品质上限：谨慎只放行普通，标准/积极放行到稀有（白/蓝/绿）。
## 暴力走 `entry()` 里的独立分支，不读本表；登记空字典只为防止误用 `RULES[preset]` 时崩。
const RULES := {
	CAUTIOUS: {"level_gap": 10, "max_quality": "common"},
	STANDARD: {"require_older_suit": true, "max_quality": "rare"},
	AGGRESSIVE: {"max_quality": "rare"},
	BRUTAL: {},
}

## 「仅提示」原因：写进 `reasons` 供界面展示，但**不否决默认勾选**。
##
## 🔴 `damaged` 为什么从否决项降级为提示项（工程 99）：
##   工程 77 把它设成否决项，理由是「破损件 `score()` 归 0 ⇒ 失去『属性更高』保护 ⇒
##   可能被静默卖掉可修的稀有件」。但工程 88 已把 `score()` 改成「破损只砍词条、
##   给基底分」—— 该前提不复存在：破损件仍会被 `upgrade`（评分可提升）与 `starred`
##   （已升星）两条真正拦截。
##   而否决项的**实际后果**是：背包里所有耐久归零的垃圾（含 Lv1 白装）在三档常规预设下
##   永远不被勾选，玩家只能逐件手勾 + 二次风险确认 —— 快速出售对破损件整体失效。
##   ⇒ 破损件照常参与预设判断，只在清单里标注「已损坏」，玩家能看见也能手动取消。
##   `auto_sell()` 用 `auto_sell_blockers()`：`damaged` 在那里**仍是**否决项
##   （拾取自动出售没有「取消勾选」，破损件一旦卖掉就再也拿不回来）。
##
## 🔑 `duplicate`（工程 102）：同部位升级候选超出额度，该件不再享受「评分可提升」保护。
##   它在两个入口都是**通过**的 —— 手动清单里它已经被勾上，自动出售里它就是那个要被卖掉的件。
##   与 `damaged` 方向**相反**，所以两个入口各用各的过滤器，绝不用同一个集合承载两种语义。
const NOTES_ONLY := ["damaged", "duplicate"]
## 自动出售里「不否决」的原因（工程 102）。与 `NOTES_ONLY` 刻意不同：
## `damaged` 只在这里被当成否决项，`duplicate` 两边都放行。
const SELL_THROUGH := ["duplicate"]

## 返回预设是否合法，供设置入口和存档校验共用。
static func valid_preset(preset: String) -> bool:
	return PRESETS.has(preset)

## 从完整原因集里滤掉「仅提示」项，得到真正**否决默认勾选**的原因（工程 99 / 102）。
## 🔑 全项目只有 `entry()` 该用它判 `default_selected`。
static func blocking_reasons(reasons: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for reason in reasons:
		if not NOTES_ONLY.has(reason):
			out.append(reason)
	return out

## 自动出售的否决原因（工程 102）。比 `blocking_reasons()` 多放行 `duplicate`：
## 那一类件正是「超出额度、该被卖掉」的，拦下它等于本功能不生效。
## ⚠ `upgrade` 也不在此列 —— 升级候选的去留由额度逻辑单独判定（见 `auto_sell()`）。
static func auto_sell_blockers(reasons: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for reason in reasons:
		if reason == "upgrade" or SELL_THROUGH.has(reason):
			continue
		out.append(reason)
	return out

## 某部位「升级候选」的保留额度 = 该部位的槽位数（戒指/护腕/护膝/手镯各 2，其余 1）。
## 额度直接取槽位数而不是做成设置项：双槽部位自然该留两件，这是最不容易配错的取值。
static func quota_for(kind: String) -> int:
	return maxi(1, Equipment.slots_for_kind(kind).size())

## 同部位「升级候选」的排位上下文（工程 102）。返回 `{"ready": true, "keep": {id: true}, "groups": {}}`。
##
## 🔴 返回空字典 = 「未计算」，`entry()` / `_judge()` 收到后按**旧口径**保护全部升级候选。
##   调用方漏传是**安全方向**的退化（多留几件），不会把该留的件卖掉；但功能等于没生效，
##   所以必须有端到端断言守着（见 `tests/sell_gear_quota_test.gd` E 组）。
##
## `keep` 只装「排名前 N」的实例 ID。金紫参与排位（口径 B）但永远不会被卖 ——
## 所以背包最终形态是「最多 N 件可售候选 + 任意多件金紫」，这不是额度失效（工程 102 R6）。
##
## `only_kind` 非空时只算该部位：拾取判定每次掉落都要算一次，而背包里九成装备都不是这个部位
## （`_judge()` 实测约 37µs/件，137 件满包全扫就是 5ms —— 一次拾取卡掉三分之一帧）。
## 部位判断放在 `_judge()` **之前**，这才是省下来的那部分。
static func rank_context(inventory: Array, player_level: int, equipment: Dictionary,
		preset: String, only_kind: String = "") -> Dictionary:
	if not PERSISTABLE.has(preset):
		return {}          # 暴力跳过全部价值判断，额度对它无意义（工程 61）
	var groups := {}
	for i in range(inventory.size()):
		var raw: Variant = inventory[i]
		if not (raw is Dictionary):
			continue
		var item := raw as Dictionary
		if String(item.get("kind", "")) != "equip":
			continue
		var kind := Equipment.item_kind(item)
		if kind.is_empty() or (not only_kind.is_empty() and kind != only_kind):
			continue
		if not bool(_judge(item, player_level, equipment, preset).get("stronger", false)):
			continue
		if not groups.has(kind):
			groups[kind] = []
		groups[kind].append(_rank_row(item, i))
	var keep := {}
	for kind in groups.keys():
		var rows: Array = groups[kind]
		_sort_rank(rows)
		for r in range(mini(quota_for(String(kind)), rows.size())):
			keep[String(rows[r].id)] = true
	return {"ready": true, "keep": keep, "groups": groups}

## 排位用的最小记录：背包格序 + 评分 + 实例 ID（+ 自动出售时附原物品用于驱逐）。
static func _rank_row(item: Dictionary, bag_index: int) -> Dictionary:
	return {"index": bag_index, "score": Equipment.score(item),
		"id": String(item.get("instanceId", "")), "item": item}

## 🔴 排位必须是**全序**：评分降序 + 背包格序升序。
##   评分相同的件谁进额度、谁被卖掉，必须由「背包格序」决定 —— 否则玩家看到的是
##   「两件一模一样的戒指，系统随机留了一件」，且不同调用点的结果可能对不上。
##   ⚠ 真正的「清单已变化」风险不在排序（同一份输入 ⇒ 同一份结果），而在
##   `build_preview()` 与 `validate_equipment_sale()` **各算一份额度上下文**，
##   任一处漏传就会整行翻转（工程 102 R2）。
static func _sort_rank(rows: Array) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := float(a.get("score", 0.0))
		var right := float(b.get("score", 0.0))
		if not is_equal_approx(left, right):
			return left > right
		return int(a.get("index", 0)) < int(b.get("index", 0)))

## 这件装备能不能被「驱逐」（工程 102 R3 的四层护栏）：除「评分可提升」以外完全符合出售条件。
## 品质高于预设、已升星、已收藏、已损坏、无价 —— 一条命中就不可驱逐，改由后面的候选让位。
static func _evictable(item: Dictionary, player_level: int, equipment: Dictionary,
		preset: String) -> bool:
	var judged := _judge(item, player_level, equipment, preset)
	var reasons: Array[String] = judged["reasons"]
	if not auto_sell_blockers(reasons).is_empty():
		return false
	var preview: Dictionary = judged["preview"]
	if bool(preview.get("empty", true)):
		return false
	return Shop.sell_price(item) > 0

## 价值判断的**唯一实现**：拆出 reasons / preview / sellable / favorite / stronger。
## `entry()`（手动清单）与 `auto_sell()`（拾取瞬间）共用 —— 两处若各写一套，规则必然漂移。
## ⚠ 调用方必须已确认 `preset` 不是 BRUTAL：暴力档的 `RULES` 是空字典，没有 `max_quality` 键。
##
## `quota` 是 `rank_context()` 的产物（工程 102）；空字典 = 未计算 ⇒ 按旧口径保护全部升级候选。
static func _judge(item: Dictionary, player_level: int, equipment: Dictionary,
		preset: String, quota: Dictionary = {}) -> Dictionary:
	var preview := Equipment.replacement_preview(equipment, item)
	var favorite := bool(item.get("favorite", false))
	var sellable := Shop.can_sell(item)
	var reasons: Array[String] = []
	if favorite:
		reasons.append("favorite")
	if not sellable and not favorite:
		reasons.append("unsellable")
	# V1：空槽（评分基准 0）不计入保护 —— 该槽类还有空位时不再整类卖不掉。
	var stronger := not bool(preview.get("empty", true)) and bool(preview.get("score_increase", false))
	var quota_on := bool(quota.get("ready", false))
	var keep: Dictionary = quota.get("keep", {})
	# 工程 102：「评分可提升」从**绝对保护**改成**相对排位** —— 只有同部位排名前 N 的候选
	# 才继续享有它；排名之外的降级为 `duplicate`（仅提示，两个入口都放行 ⇒ 会被卖掉）。
	var protected_upgrade := stronger \
		and (not quota_on or keep.has(String(item.get("instanceId", ""))))
	if stronger:
		reasons.append("upgrade" if protected_upgrade else "duplicate")
	if int(item.get("star", 0)) > 0:
		reasons.append("starred")
	# 工程 77 引入；工程 99 降级为「仅提示」—— 见 `NOTES_ONLY` 的长注释。
	# reasons 里保留它，是为了让清单能写明「已损坏」，而不是无声地当成好件卖掉。
	if Durability.is_broken(item):
		reasons.append("damaged")
	var quality := Shop.item_quality(item)
	var quality_rank := Shop.QUALITY_ORDER.find(quality)
	var rule: Dictionary = RULES[preset]
	if quality_rank > Shop.QUALITY_ORDER.find(String(rule.max_quality)):
		reasons.append("quality")
	if rule.has("level_gap") and Equipment.level_req(item) > player_level - int(rule.level_gap):
		reasons.append("level")
	if bool(rule.get("require_older_suit", false)):
		var suit := ItemFactory.suit_start(Equipment.level_req(item))
		if suit == 0 or suit >= ItemFactory.suit_start(player_level):
			reasons.append("suit")
	return {"preview": preview, "favorite": favorite, "sellable": sellable,
		"reasons": reasons, "stronger": stronger, "protected_upgrade": protected_upgrade}

## 给一件背包装备生成稳定的预览条目；非装备返回空字典。
## `bag_index` 只用于展示，成交按 instanceId 重定位；实例快照供确认时防止误卖。
## `quota` 传 `rank_context()` 的结果（工程 102）；不传 = 按旧口径保护全部升级候选。
static func entry(item: Dictionary, bag_index: int, player_level: int,
		equipment: Dictionary, preset: String, quota: Dictionary = {}) -> Dictionary:
	if String(item.get("kind", "")) != "equip" or not valid_preset(preset):
		return {}
	# 暴力预设（工程 61）：只保留「能不能卖」这一条硬门槛，其余价值判断全部跳过。
	# 不调用 `Equipment.replacement_preview` —— 玩家已明确不看评分，算了也不展示。
	if preset == BRUTAL:
		var brutal_sellable := Shop.can_sell(item)
		var brutal_reasons: Array[String] = []
		# 理由只用于 tooltip 说明「为什么它没被勾上」；收藏与无价是仅剩的两个拦截原因。
		if bool(item.get("favorite", false)):
			brutal_reasons.append("favorite")
		elif not brutal_sellable:
			brutal_reasons.append("unsellable")
		return {"instance_id": String(item.get("instanceId", "")), "bag_index": bag_index,
			"item_snapshot": item.duplicate(true), "price": Shop.sell_price(item),
			"player_level": player_level, "preset": preset, "score_delta": 0.0,
			"default_selected": brutal_sellable, "manual_selectable": brutal_sellable,
			"reasons": brutal_reasons, "protected_upgrade": false}
	var judged := _judge(item, player_level, equipment, preset, quota)
	var preview: Dictionary = judged["preview"]
	var reasons: Array[String] = judged["reasons"]
	# 破损（`damaged`）与超额度（`duplicate`）都只提示不否决 —— 否则破损垃圾在常规预设下
	# 永远进不了快速出售（工程 99），而超额度候选永远清不掉（工程 102）。
	var automatic := blocking_reasons(reasons).is_empty() and bool(preview.get("ok", false))
	return {"instance_id": String(item.get("instanceId", "")), "bag_index": bag_index,
		"item_snapshot": item.duplicate(true), "price": Shop.sell_price(item),
		"player_level": player_level, "preset": preset,
		"score_delta": float(preview.get("score_delta", 0.0)),
		"default_selected": automatic,
		"manual_selectable": bool(judged["sellable"]) and not bool(judged["favorite"]),
		"reasons": reasons, "protected_upgrade": bool(judged["protected_upgrade"])}

## 拾取瞬间的自动出售判定（工程 63 / 102）。返回 `{sell, reason, price, evict_id, evict_price}`；
## `reason` 仅供排查，不面向玩家。
##
## 与 `entry()` 共用 `_judge()` 的理由集，另加三条**自动出售专属否决**：
##   ① 等级门槛（60 级）：运行时再拦一次，不能只靠界面灰显（改档 / 导入档 / 将来降级都可能带 true）；
##   ② 金币已满：卖出等于白扔装备，宁可留在背包让玩家自己处理；
##   ③ **该槽为空**：`_judge()` 的 V1 规则刻意不给空槽加保护（手动清单里玩家能取消勾选），
##      但自动出售没有「取消勾选」这一步 —— 不否决的话，某槽捡到的第一件会被当场卖掉，
##      玩家永远穿不上那一件（工程 63 §2.3）。
##
## 工程 102 起多两件事：
##   - `duplicate`（超出同部位额度）不再否决，它就是该被卖掉的那件；
##   - 新件若挤进前 N，会返回被挤掉那件的 `evict_id` / `evict_price`，由调用方执行驱逐。
##     这里**不碰背包**（纯规则层），扣件与入账都归 `GameState.pickup_loot()`。
static func auto_sell(item: Dictionary, player_level: int, equipment: Dictionary,
		preset: String, gold_capped: bool, inventory: Array = []) -> Dictionary:
	if String(item.get("kind", "")) != "equip":
		return {"sell": false, "reason": "not_equip", "price": 0}
	# 暴力不进设置（`PERSISTABLE`），这里再挡一次：双保险，防止将来有人绕开设置直接调本函数。
	if not PERSISTABLE.has(preset):
		return {"sell": false, "reason": "preset_locked", "price": 0}
	if player_level < AUTO_SELL_MIN_LEVEL:
		return {"sell": false, "reason": "level_gate", "price": 0}
	if gold_capped:
		return {"sell": false, "reason": "gold_capped", "price": 0}
	# 额度上下文先算：`_judge()` 要靠它把「超额度」标成 `duplicate` 而不是 `upgrade`。
	# 新件还没入包，所以这里的排名只含背包里已有的件；新件自己的去留由下方 merged 排名决定。
	var kind := Equipment.item_kind(item)
	var quota := rank_context(inventory, player_level, equipment, preset, kind)
	var judged := _judge(item, player_level, equipment, preset, quota)
	var reasons: Array[String] = judged["reasons"]
	# 工程 102：`duplicate` 放行、`damaged` 仍否决（`auto_sell_blockers()` 只管这个差别）。
	var blocking := auto_sell_blockers(reasons)
	if not blocking.is_empty():
		return {"sell": false, "reason": blocking[0], "price": 0}
	var preview: Dictionary = judged["preview"]
	if bool(preview.get("empty", true)):
		return {"sell": false, "reason": "empty_slot", "price": 0}
	var price := Shop.sell_price(item)
	if price <= 0:
		return {"sell": false, "reason": "unsellable", "price": 0}
	if not bool(judged["stronger"]):
		return {"sell": true, "reason": "", "price": price}
	# ---- 升级候选：过同部位额度闸（工程 102）----
	# 新件还没入包，必须和「已在背包里的更优候选 + 自己」一起排，否则永远判成「额度没满」。
	var candidates: Array = (quota.get("groups", {}) as Dictionary).get(kind, [])
	var merged := candidates.duplicate()
	var mine := _rank_row(item, inventory.size())   # 格序取 `size()` ⇒ 同分时新件排最后
	merged.append(mine)
	_sort_rank(merged)
	var rank := 0
	for r in range(merged.size()):
		var row: Dictionary = merged[r]
		if int(row.get("index", -1)) == int(mine.get("index", -2)) \
				and String(row.get("id", "")) == String(mine.get("id", "")):
			rank = r
			break
	# 排在第 N 名之外 ⇒ 它就是「超额的那一件」，按预设卖掉。
	# 🔴 用严格比较而不是 `>=`：同分时让已在背包里的那件留下，避免「刚捡的顶掉刚留的」观感事故。
	if rank >= quota_for(kind):
		return {"sell": true, "reason": "duplicate", "price": price}
	# 新件进前 N ⇒ 把掉出前 N 的那件挤掉（挑最弱且可卖的；一件都挑不出来就不驱逐）。
	var victim := _pick_victim(merged, quota_for(kind), player_level, equipment, preset)
	# `reason` 沿用 `upgrade`：语义是「它是升级候选，留下」。有没有驱逐看 `evict_id` 是否为空。
	# 额度没满时同样走这里（不算拒卖，只是「留着」）。
	if victim.is_empty():
		return {"sell": false, "reason": "upgrade", "price": 0}
	var evicted: Dictionary = victim.get("item", {})
	return {"sell": false, "reason": "upgrade", "price": 0,
		"evict_id": String(victim.get("id", "")),
		"evict_price": Shop.sell_price(evicted)}

## 新件挤进前 N 后，从「掉出前 N 的那些」里挑一件可卖的作为驱逐对象（由弱到强找）。
## 一件都挑不出来（全被品质/星级/收藏/破损保护）时返回空字典 —— 新件照留，背包暂时 N+1。
static func _pick_victim(merged: Array, quota: int, player_level: int,
		equipment: Dictionary, preset: String) -> Dictionary:
	for r in range(merged.size() - 1, quota - 1, -1):
		var row: Dictionary = merged[r]
		var victim: Dictionary = row.get("item", {})
		if victim.is_empty() or String(row.get("id", "")).is_empty():
			continue
		if _evictable(victim, player_level, equipment, preset):
			return row
	return {}

## 按当前背包格顺序构建一次性清单；最多扫描背包容量，不在逐帧入口调用。
## 工程 102：额度上下文**只算一次**再逐件套用 —— 每件都重算的话，一件装备的 rank 会被
## 自己的出现影响，且 O(n²) 的 `score()` 调用会拖慢清单打开。
static func build_preview(inventory: Array, player_level: int,
		equipment: Dictionary, preset: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not valid_preset(preset):
		return rows
	var quota := rank_context(inventory, player_level, equipment, preset)
	for i in range(inventory.size()):
		if inventory[i] is Dictionary:
			var row := entry(inventory[i], i, player_level, equipment, preset, quota)
			if not row.is_empty():
				rows.append(row)
	return rows
