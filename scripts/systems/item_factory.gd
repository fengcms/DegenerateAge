class_name ItemFactory
extends RefCounted
## 装备实例唯一生成入口；任务、商店与怪物掉落共用档位/品质/词条规则。

## M10-1：循环装备只复用第 51 套的十个型号；改这个常量等于改整套经济口径。
const DYNAMIC_BASE_TIER := 51
## D-21「十级一套」：60 级后每 10 级一套（61—70 / 71—80 …），套内 10 件按槽位偏移依次解锁。
## 改这个跨度等于改整套经济口径（`PaceTest` 与产品 13 §2.4 必须同步）。
const TIER_SPAN := 10
## 实例等级上界，与 `GameState.PLAYER_LEVEL_CAP` 同值（`DynamicEquipTest` 锁死两者相等）。
## 这里写字面量是为了让本模块不依赖 autoload —— `Balance` 同类约定，可离线推演。
const INSTANCE_LEVEL_CAP := 9999
## 实例规则版本：4 = 1—60 存量（等级等于模板），5 = 61+ 动态（等级由生成时决定）。
const RULE_VERSION_BASE := 4
const RULE_VERSION_DYNAMIC := 5

## 返回装备规则；生成、掉落和售价共同读取这一份配置。
static func rules() -> Dictionary:
	var raw: Variant = DataLoader.get_table("equipmentRules")
	return raw if raw is Dictionary else {}

## 将来源等级映射到所属套的起点；当前 1—10 为第一套、11—20 为第二套。
static func tier_for_level(source_level: int) -> int:
	var chosen := 1
	for value in rules().get("tiers", []):
		var tier := int(value)
		if tier <= source_level and tier > chosen:
			chosen = tier
	return chosen

## 取得型号所属套的起点；实际穿戴等级由模板单独定义。
static func tier_start_for_template(item_id: String) -> int:
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	if not tpl is Dictionary:
		return 0
	var bases: Variant = tpl.get("tierBases", {})
	return int(bases.keys()[0]) if bases is Dictionary and bases.size() == 1 else 0

## 60+ 的套起点：61—70 → 61、71—80 → 71、…​、991—1000 → 991。
## ≤ 60 原样返回（前 60 级的分档仍由 `tier_for_level` 负责）。
## 🔴 末档保护：最大槽位偏移是 9，套起点一旦越过「上限 − 9」就会造出等级 > `INSTANCE_LEVEL_CAP`
## 的实例，而 `_valid_item` 会拒 ⇒ 下次读档整档作废。所以把套起点夹在 `上限 − 9`。
static func dynamic_tier_start(level: int) -> int:
	if level <= Balance.SOFTCAP_LEVEL:
		return level
	var base := DYNAMIC_BASE_TIER + TIER_SPAN
	var tier := base + int(floor(float(level - base) / float(TIER_SPAN))) * TIER_SPAN
	return mini(tier, INSTANCE_LEVEL_CAP - (TIER_SPAN - 1))

## 十级套起点：1—10 → 1、11—20 → 11 …​、991—1000 → 991。
## 🔴 与 `dynamic_tier_start` 的分工：后者在 ≤ 60 时**原样返回等级**（动态生成分支的入口），
## 拿它当「这件装备属于哪一套」会让 L60 玩家的当前套变成 60，从而把当前第 51 套误判成旧套。
## 本函数不看等级分区、一律按十级带宽归一，是套档判断的唯一口径（铁匠合成与出售预设共用）。
static func suit_start(level: int) -> int:
	if level < 1 or level > INSTANCE_LEVEL_CAP:
		return 0
	return floori(float(level - 1) / 10.0) * 10 + 1

## 槽位偏移 = 模板 `requiredLevel − 51`：武器 0、鞋 1、甲 2 …​、项链 9。
## 这不是新数据 —— 前 60 级每套的 10 件本来就是按这个顺序铺满 10 个槽位的。
## 非循环套返回 -1（`make_equip_dynamic` 据此显式失败）。
static func slot_offset_for_template(item_id: String) -> int:
	if tier_start_for_template(item_id) != DYNAMIC_BASE_TIER:
		return -1
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	if not tpl is Dictionary:
		return -1
	return int((tpl as Dictionary).get("requiredLevel", 0)) - DYNAMIC_BASE_TIER

## 这件装备在 `level` 这个档上应有的穿戴等级 = 套起点 + 槽位偏移。
## 例：L67 的武器 61、鞋 62、甲 63 …​；L1099 的武器 1091。非循环套返回 0。
static func dynamic_level_for(item_id: String, level: int) -> int:
	var offset := slot_offset_for_template(item_id)
	if offset < 0:
		return 0
	return dynamic_tier_start(level) + offset

## level 参数兼容来源等级调用；未指定时使用该型号所属套。
static func make_equip(item_id: String, level: int = 0, instance_prefix: String = "inst") -> Dictionary:
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	if not tpl is Dictionary:
		return {}
	var bases: Variant = tpl.get("tierBases", {})
	if not bases is Dictionary or bases.size() != 1:
		return {}
	var tier_start := tier_for_level(level) if level > 0 else int(bases.keys()[0])
	return make_equip_roll(item_id, tier_start, String(tpl.get("defaultQuality", "common")), null, instance_prefix)

## 按型号所属套生成实例；传入其他套起点时显式失败。
## `dynamic_level > 60` 时改走 M10-1 动态分支：等级取该值、基底 × S(level−60)、
## 词条 × affixTierScale[51] × S(level−60)、版本标 5。默认 0 走原分支，
## 随机数调用顺序**逐字不变**（1—60 的掉落结果不可能变）。
## 🔴 `dynamic_level` 必须是**已归一的槽位等级**（`dynamic_level_for`）。
static func make_equip_roll(item_id: String, tier_start: int, quality: String,
		rng: RandomNumberGenerator = null, instance_prefix: String = "inst",
		dynamic_level: int = 0) -> Dictionary:
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	var cfg := rules()
	var qualities: Variant = cfg.get("qualities", {})
	if not tpl is Dictionary or not qualities is Dictionary or not qualities.has(quality):
		return {}
	var raw_bases: Variant = tpl.get("tierBases", {})
	if not raw_bases is Dictionary or not raw_bases.get(str(tier_start)) is Dictionary:
		push_error("[ItemFactory] %s 缺少第 %d 套装备基底" % [item_id, tier_start])
		return {}
	var dynamic := dynamic_level > Balance.SOFTCAP_LEVEL
	if dynamic and tier_start != DYNAMIC_BASE_TIER:
		# 动态实例的基底与词条倍率都锚在循环套上；混入其他套会让经济口径失真。
		push_error("[ItemFactory] %s 的动态实例必须挂在第 %d 套" % [item_id, DYNAMIC_BASE_TIER])
		return {}
	var required_level := int(tpl.get("requiredLevel", 0))
	if dynamic:
		required_level = dynamic_level
	elif required_level < tier_start or required_level >= tier_start + 10:
		push_error("[ItemFactory] %s 穿戴等级与所属套不符" % item_id)
		return {}
	var scale_values: Variant = cfg.get("affixTierScale", {})
	# 动态分支只认循环套的词条倍率（tier_start 已校验等于 DYNAMIC_BASE_TIER）。
	var scale_key := str(DYNAMIC_BASE_TIER if dynamic else tier_start)
	if not scale_values is Dictionary or not scale_values.has(scale_key):
		push_error("[ItemFactory] 缺少第 %s 套词条倍率" % scale_key)
		return {}
	var scale_factor := 1.0
	if dynamic:
		scale_factor = Balance.scale(required_level - Balance.SOFTCAP_LEVEL)
	var affix_scale := float(scale_values[scale_key]) * scale_factor
	var q: Dictionary = qualities[quality]
	var r := rng if rng != null else _default_rng()
	var rolled := _roll_affixes(item_id, quality, affix_scale, r)
	if not bool(rolled.get("ok", false)):
		return {}
	var raw: Dictionary = (raw_bases[str(tier_start)] as Dictionary).duplicate(true)
	if dynamic:
		var scaled := {}
		for stat in raw:
			scaled[String(stat)] = maxi(1, int(round(float(raw[stat]) * scale_factor)))
		raw = scaled
	return {
		"kind": "equip", "itemId": item_id,
		"instanceId": "%s_%s" % [instance_prefix, Crypto.new().generate_random_bytes(16).hex_encode()],
		"equipmentRuleVersion": RULE_VERSION_DYNAMIC if dynamic else RULE_VERSION_BASE,
		"requiredLevel": required_level, "level": required_level,
		"quality": quality, "star": 0,
		"favorite": false,
		# 工程 77：耐久写在**固定字段区**，不得插进 `_roll_affixes` 的 rng 调用序列
		# （随机数顺序红线，ReforgeTest 用例 14 锁死）。新实例恒满耐久。
		"durability": Durability.max_durability(),
		"rawBaseAttrs": raw,
		"qualityMultiplierSnapshot": float(q.get("baseMultiplier", 1.0)),
		"starMultiplierSnapshot": float(cfg.get("starMult", 0.1)),
		"affixes": rolled.affixes, "pctAttrs": rolled.pctAttrs, "count": 1,
	}

## 掷词条的唯一实现（M10-8 抽取）：新品生成与装备重铸共用同一段逻辑。
## 🔴 **随机数调用顺序必须逐字不变**：
## `randf()`（百分比判定）→ `randi_range`（选百分比属性）→ `randf_range`（百分比数值）
## → 循环 { `randi_range`（选固定属性）→ `randi_range`（固定数值） }。
## 把 `randf()` 挪到循环后、或把「选属性」与「滚数值」调换，1—60 级所有掉落结果都会变；
## `tests/ReforgeTest` 用例 14 用固定种子快照锁死这条顺序（唯一防线）。
## `affix_scale` 由调用方按**实例等级**算好传入（见 `reroll_affixes`）。
##
## 工程 81：`locked_fixed` / `locked_pct` 是**锁定条目**（`{stat, value}`），原样进结果、
## **不消耗随机数**；两者都为空时本函数的语句序列与改造前**逐句相同**（快照用例 14 守着）。
## 🔴 锁定的 stat 必须从候选池里剔除 —— 否则未锁定部分又掷出同一 stat，出现两条 `hp`，
## 而 `Equipment.bonus()` 是按 stat 累加的 ⇒ **静默叠加、零报错**，玩家只看到「锁的那条变了」。
## 🔴 锁定了百分比词条时必须**跳过 `randf()` 判定**：否则 50% 概率整条消失，间歇性发作最难查。
static func _roll_affixes(item_id: String, quality: String, affix_scale: float,
		rng: RandomNumberGenerator, locked_fixed: Array = [], locked_pct: Array = [],
		floor_ratio: float = 0.0) -> Dictionary:
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	var cfg := rules()
	var qualities: Variant = cfg.get("qualities", {})
	if not tpl is Dictionary or not qualities is Dictionary or not qualities.has(quality):
		push_error("[ItemFactory] %s 的品质 %s 未登记" % [item_id, quality])
		return {"ok": false, "reason": "quality"}
	var q: Dictionary = qualities[quality]
	var r := rng if rng != null else _default_rng()
	var affix_count := int(q.get("affixCount", 0))
	var pool: Array = tpl.get("affixPool", [])
	var fixed_cfg: Dictionary = cfg.get("fixedAffixes", {})
	var pct_cfg: Dictionary = cfg.get("percentAffixes", {})
	var fixed: Array = []
	var percent: Array = []
	var locked_stats: Dictionary = {}
	for entry in locked_fixed:
		if entry is Dictionary:
			fixed.append((entry as Dictionary).duplicate())
			locked_stats[String((entry as Dictionary).get("stat", ""))] = true
	for entry in locked_pct:
		if entry is Dictionary:
			percent.append((entry as Dictionary).duplicate())
			locked_stats[String((entry as Dictionary).get("stat", ""))] = true
	var available: Array = []
	for stat in pool:
		if fixed_cfg.has(String(stat)) and not locked_stats.has(String(stat)):
			available.append(String(stat))
	if (locked_pct as Array).is_empty():
		if affix_count > 0 and float(q.get("percentChance", 0.0)) > 0.0 and r.randf() < float(q.percentChance):
			var pct_available: Array = []
			for stat in pool:
				if pct_cfg.has(String(stat)) and not locked_stats.has(String(stat)):
					pct_available.append(String(stat))
			if not pct_available.is_empty():
				var stat: String = pct_available[r.randi_range(0, pct_available.size() - 1)]
				var bounds: Dictionary = pct_cfg[stat]
				# 工程 86：精炼只抬**下限**；ratio == 0 时下式与改造前逐字相同（含浮点值）。
				var pct_lo := float(bounds.min)
				var pct_hi := float(bounds.max)
				if floor_ratio > 0.0:
					pct_lo += (pct_hi - pct_lo) * floor_ratio
				percent.append({"stat": stat, "value": snappedf(r.randf_range(pct_lo, pct_hi), 0.001)})
	while fixed.size() + percent.size() < affix_count and not available.is_empty():
		var index := r.randi_range(0, available.size() - 1)
		var stat: String = available[index]
		available.remove_at(index)
		var bounds: Dictionary = fixed_cfg[stat]
		var lo := maxi(1, int(round(float(bounds.min) * affix_scale)))
		var hi := maxi(lo, int(round(float(bounds.max) * affix_scale)))
		if floor_ratio > 0.0:
			lo = mini(hi, lo + int(round(float(hi - lo) * floor_ratio)))
		fixed.append({"stat": stat, "value": r.randi_range(lo, hi)})
	if fixed.size() + percent.size() != affix_count:
		push_error("[ItemFactory] %s 的 %s 品质词条池不足" % [item_id, quality])
		return {"ok": false, "reason": "pool"}
	return {"ok": true, "affixes": fixed, "pctAttrs": percent}

## 重掷一件**既有实例**的词条（M10-8 装备重铸）：成功返回 `{ok, affixes, pctAttrs}`，
## 失败返回 `{ok: false, reason}`。
## 工程 81：`locked_stats` 是要**保留**的属性名数组（`["hp", "hpPercent"]`）；空数组（默认）
## 走原路径 —— 既有调用零改动。**合法性由 `Reforge.validate_locks` 在扣费前把关**，
## 这里对取不到的 stat 仍显式失败（不猜不修）。
## 🔴 只读实例的 `itemId` / `quality` / `requiredLevel`，**不改 item**（由 `GameState` 写回）。
## 🔴 词条倍率必须按**实例等级**算：`affixTierScale[51] × Balance.scale(L − 60)`。
## 不能用 `tier_start_for_template(itemId)` 推 —— 循环套恒为 51，用它会把 L1000 的
## 词条砸回 L60 数值（这就是负向 N-3）。判据用 `requiredLevel > 60` 而非
## `equipmentRuleVersion`：老档实例可能缺这个字段，而等级是必有的。
static func reroll_affixes(item: Dictionary, rng: RandomNumberGenerator = null,
		locked_stats: Array = [], floor_ratio: float = 0.0) -> Dictionary:
	var item_id := String(item.get("itemId", ""))
	if item_id.is_empty():
		return {"ok": false, "reason": "id"}
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	if not tpl is Dictionary:
		return {"ok": false, "reason": "template"}
	var quality := String(item.get("quality", ""))
	if quality.is_empty():
		quality = String((tpl as Dictionary).get("defaultQuality", "common"))
	var level := int(item.get("requiredLevel", 1))
	var dynamic := level > Balance.SOFTCAP_LEVEL
	var scale_key := str(DYNAMIC_BASE_TIER) if dynamic else str(tier_for_level(level))
	var scale_values: Variant = rules().get("affixTierScale", {})
	if not scale_values is Dictionary or not (scale_values as Dictionary).has(scale_key):
		push_error("[ItemFactory] 缺少第 %s 套词条倍率" % scale_key)
		return {"ok": false, "reason": "scale"}
	var factor := Balance.scale(level - Balance.SOFTCAP_LEVEL) if dynamic else 1.0
	var affix_scale := float((scale_values as Dictionary)[scale_key]) * factor
	if (locked_stats as Array).is_empty():
		return _roll_affixes(item_id, quality, affix_scale, rng, [], [], floor_ratio)
	var split := _split_locked_entries(item, locked_stats)
	if not bool(split.get("ok", false)):
		return {"ok": false, "reason": String(split.get("reason", "lock"))}
	return _roll_affixes(item_id, quality, affix_scale, rng,
		split.get("fixed", []) as Array, split.get("pct", []) as Array, floor_ratio)

## 把「要保留的属性名」翻译成「要保留的**完整条目**」并分流到固定 / 百分比两组。
## 🔴 取 stat 时**连数值一起取**（`{stat, value}` 整体保留），不是只取属性名重新掷数值。
## 🔴 归类只认 `fixedAffixes` / `percentAffixes` 两张表：认不出来的 stat 直接失败 ——
## 硬塞进固定组会把 5.4% 的百分比当成 +5 点写回去。
static func _split_locked_entries(item: Dictionary, locked_stats: Array) -> Dictionary:
	var cfg := rules()
	var fixed_cfg: Dictionary = cfg.get("fixedAffixes", {})
	var pct_cfg: Dictionary = cfg.get("percentAffixes", {})
	var wanted: Array[String] = []
	for raw in locked_stats:
		var stat := String(raw)
		if stat.is_empty() or wanted.has(stat):
			continue
		wanted.append(stat)
	var fixed_entries: Array = []
	var pct_entries: Array = []
	for stat in wanted:
		var found := false
		for key in ["affixes", "pctAttrs"]:
			var arr: Variant = item.get(String(key), [])
			if not arr is Array:
				continue
			for e in arr as Array:
				if not e is Dictionary or String((e as Dictionary).get("stat", "")) != stat:
					continue
				if fixed_cfg.has(stat):
					fixed_entries.append((e as Dictionary).duplicate())
				elif pct_cfg.has(stat):
					pct_entries.append((e as Dictionary).duplicate())
				else:
					return {"ok": false, "reason": "unclassified"}
				found = true
				break
			if found:
				break
		if not found:
			return {"ok": false, "reason": "missing"}
	return {"ok": true, "fixed": fixed_entries, "pct": pct_entries}

## M10-1 / D-21：循环装备实例门面，**生产代码的唯一入口**（`Loot` 只走这里）。
## `level ≤ 60` 退回普通路径（60 级拿到的仍是 tier51 原版）；
## `level > 60` **不直接用来源等级**，而是归一到「套起点 + 槽位偏移」——
## 直接用来源等级就是逐级装备（61/62/63…），与「十级一套」的既有规律相悖。
## 型号必须在循环套内，否则显式失败。
static func make_equip_dynamic(item_id: String, level: int, quality: String,
		rng: RandomNumberGenerator = null, instance_prefix: String = "dyn") -> Dictionary:
	if level <= Balance.SOFTCAP_LEVEL:
		return make_equip_roll(item_id, tier_for_level(level), quality, rng, instance_prefix)
	var exact := dynamic_level_for(item_id, level)
	if exact <= 0:
		push_error("[ItemFactory] %s 不在循环装备型号表" % item_id)
		return {}
	return make_equip_exact(item_id, exact, quality, rng, instance_prefix)

## 精确等级门面：把来源等级**原样**当实例等级用，不做「十级一套」归一。
## 🔴 **只给测试与离线推演**（数值表 / 随机流快照 / 旧档语义复现）。生产路径走
## `make_equip_dynamic`，绕过它就会重新造出逐级装备。
static func make_equip_exact(item_id: String, level: int, quality: String,
		rng: RandomNumberGenerator = null, instance_prefix: String = "dyn") -> Dictionary:
	if level <= Balance.SOFTCAP_LEVEL:
		return make_equip_roll(item_id, tier_for_level(level), quality, rng, instance_prefix)
	if tier_start_for_template(item_id) != DYNAMIC_BASE_TIER:
		push_error("[ItemFactory] %s 不在循环装备型号表" % item_id)
		return {}
	return make_equip_roll(item_id, DYNAMIC_BASE_TIER, quality, rng, instance_prefix, level)

## 依 id 自动判类构造（装备 / 药水 / 杂项 / 如意）。找不到返回空字典。
## 装备不参与堆叠，count 被忽略（5.8）。
static func make_any(item_id: String, count: int = 1) -> Dictionary:
	if item_id.is_empty():
		return {}
	if DataLoader.get_entry("equipments", item_id) is Dictionary:
		return make_equip(item_id)
	if DataLoader.get_entry("potions", item_id) is Dictionary:
		return {"kind": "potion", "itemId": item_id, "count": count}
	if DataLoader.get_entry("miscItems", item_id) is Dictionary:
		return {"kind": "misc", "itemId": item_id, "count": count}
	if DataLoader.get_entry("runes", item_id) is Dictionary:
		return {"kind": "rune", "itemId": item_id, "count": count}
	return {}

## 为正常游戏生成随机词条；测试可传入带固定种子的随机数发生器。
static func _default_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r
