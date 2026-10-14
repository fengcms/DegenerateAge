class_name LootNotify
extends RefCounted
## M6-0e（创意 07 §10）：批次摘要与传说提示的**文本构造 + 时刻计算**。
##
## 纯静态、无节点、无副作用 —— 便于单测（不依赖场景树 / 时间推进）。
## 由 `Monster._settle_rewards` 在死亡帧调用，取文本与延迟后自行广播 toast。
##
## §10 摘要格式：
##   "<名> 掉落：装备 N 件（稀有 a、史诗 b）· 金币 G · 大红药×2 [· 如意×1]
##    [· 背包不足，N 件装备已保留]"
##   · 括号**只列稀有以上**（稀有 / 史诗 / 传说）且件数 > 0 者；全为 0 时省略括号。
##   · 金币 / 药水 / 如意**有则列、无则省略**；药水 / 如意名取 `data` 表（唯一真相源）。
##   · 未领取装备 > 0 ⇒ 追加「背包不足，N 件装备已保留」，不把总产出误报成全部入包（§10 / §11.1）。

## 摘要括号内列出的品质（稀有以上；§10）。
const LISTED_QUALITIES := ["rare", "epic", "legendary"]

## 传说提示前缀（§10「传说 · 铁制短刃」）。
const LEGENDARY_PREFIX_KEY := "msg.loot_notify.legendary_prefix"

## 批次摘要文本。`rolled` = `Loot.roll` 产出数组；`unclaimed_equip` = 本批未入包的装备件数。
static func summary_text(monster_name: String, rolled: Array, unclaimed_equip: int, manual_pickup: bool = false) -> String:
	var equip := 0
	var q_count := {}
	var gold := 0
	var potion := ""
	var rune := 0
	for it in rolled:
		if not (it is Dictionary):
			continue
		var item: Dictionary = it
		match String(item.get("kind", "")):
			"equip":
				equip += 1
				var q := String(item.get("quality", "common"))
				q_count[q] = int(q_count.get(q, 0)) + 1
			"coin":
				gold += int(item.get("gold", 0))
			"potion":
				potion = _potion_text(item)
			"rune":
				rune += maxi(1, int(item.get("count", 1)))
	var parts: Array[String] = []
	parts.append(Localization.tr_key("msg.loot_notify.p001") % [equip, _quality_bracket(q_count)])
	if gold > 0:
		parts.append(Localization.tr_key("msg.loot_notify.p002") % gold)
	if not potion.is_empty():
		parts.append(potion)
	if rune > 0:
		parts.append(Localization.tr_key("msg.loot_notify.p003") % rune)
	var text := Localization.tr_key("msg.loot_notify.p004") % [monster_name, " · ".join(parts)]
	if unclaimed_equip > 0:
		text += (Localization.tr_key("msg.loot_notify.p005") if manual_pickup else Localization.tr_key("msg.loot_notify.p006")) % unclaimed_equip
	return text

## 品质括号："（稀有 1、史诗 1）"；无稀有以上时返回空串（§10）。
static func _quality_bracket(q_count: Dictionary) -> String:
	var listed: Array[String] = []
	for q in LISTED_QUALITIES:
		var n := int(q_count.get(q, 0))
		if n > 0:
			listed.append("%s %d" % [ItemUtil.quality_name(q), n])
	if listed.is_empty():
		return ""
	return "（%s）" % "、".join(listed)

## 药水文本："大红药×2"（名取 `potions` 表；单瓶不带 ×N）。
static func _potion_text(item: Dictionary) -> String:
	var n := maxi(1, int(item.get("count", 1)))
	var base := ItemUtil.template_name(item)
	if n <= 1:
		return base
	return "%s×%d" % [base, n]

## 传说提示文本（§10）：本批有传说装备时返回 "传说 · <名>"，否则空串。
static func legendary_text(rolled: Array) -> String:
	for it in rolled:
		if not (it is Dictionary):
			continue
		var item: Dictionary = it
		if String(item.get("kind", "")) == "equip" and String(item.get("quality", "")) == "legendary":
			return Localization.tr_key(LEGENDARY_PREFIX_KEY) + ItemUtil.template_name(item)
	return ""

## 摘要弹出时刻（§10「最后一份出场完成时」）：全部落地时刻 = max(appear + land_time)。
## `anim=false`（关闭 dropFlyAnim）⇒ 立即（0，仅保留摘要）。
static func summary_delay(plan: Array, anim: bool) -> float:
	if not anim:
		return 0.0
	var t := 0.0
	for row in plan:
		if row is Dictionary:
			var r: Dictionary = row
			t = maxf(t, float(r.get("appear", 0.0)) + float(r.get("land_time", 0.0)))
	return t
