class_name RuneCharge
extends RefCounted
## 工程 112：如意在「后保星时代」的第二个用途 —— **重掷取优**。
##
## 背景（工程 112 §1）：四档如意的原唯一出口是升星成功率，而保星 `100% 成功 + 不掷点`
## 直接把「0★ → 12★」这段掷点整段绕过 ⇒ 后期玩家的如意只能卖店。售价又极高
## （钻石如意单枚回收 36,000），等于一条每小时约 9 万金币的隐形水龙头。
##
## 本类的语义扩展刻意**只加抽样、不加数值**：不新增词条条数、不提高品质、不改词条上下界，
## 只是「同一件事多掷几次，取评分最高的那次」。玩家拿到的永远是原本就可能出现的极值，
## 不可能出现改造前掷不出来的结果。
##
## 口径分工（不要在这里加第二套）：
## - 合法性校验与背包扣除计划 → 复用 [method Upgrade.rune_plan]（四格、按背包顺序取堆叠）；
## - 「哪一次更好」的比较 → 复用 [method Equipment.score]（工程 90 的评分唯一口径）；
## - 每枚折算多少次 → `data/runes.json` 的 `rerollWeight`（0.5 / 1 / 2 / 4）。

## 投入格数。与升星面板的四格一致；玩家已经熟悉「最多四枚」。
const SLOTS := 4

## 重掷次数上限 = 1 次基础 + 4 枚钻石如意 × 4。超过这个数再多投也没有边际收益，
## 封顶是为了让「堆更多如意」不能无限接近满值 —— 那是「必得」而不是「取优」。
const MAX_TRIES := 17

## 模板没登记 `rerollWeight` 时的权重。取 0 而不是 1：缺配置等于「这枚不生效」，
## 配合 `DataLoader` 的必填校验，宁可少给也不能凭空放大消耗。
const DEFAULT_WEIGHT := 0.0

## 单枚如意的重掷权重（浮点，四枚铁如意合起来才 +2 次）。
static func weight_of(rune_id: String) -> float:
	if rune_id.is_empty():
		return 0.0
	var tpl = DataLoader.get_entry("runes", rune_id)
	if not tpl is Dictionary:
		return DEFAULT_WEIGHT
	var raw: Variant = tpl.get("rerollWeight", DEFAULT_WEIGHT)
	if not (raw is float or raw is int):
		return DEFAULT_WEIGHT
	return maxf(0.0, float(raw))

## 本次要掷几次：`round(1 + Σ权重)`，夹在 `[1, MAX_TRIES]`。
## 🔑 一枚铁如意（0.5）单独投也是 2 次（`round(1.5) == 2`）—— 不存在「投了却一点用没有」的档位，
## 否则玩家会以为自己被系统吞了道具。
## 4 枚铁 = 3 次、4 玉 = 5 次、4 金 = 9 次、4 钻 = 17 次（封顶）。
static func tries(rune_ids: Array) -> int:
	var total := 1.0
	for raw in rune_ids:
		total += weight_of(String(raw))
	return clampi(int(round(total)), 1, MAX_TRIES)

## 校验 + 扣除计划 + 重掷次数，一次返回。
## `uses` 与 [method Upgrade.rune_plan] 同构（`[{index, count}]`，背包下标 + 件数），
## 由调用方在**结算成功时**才真正扣除（先掷后扣，与材料/金币同批）。
## 🔴 不在这里扣：重铸与保星都可能在「掷出来了但背包满」等后续校验上失败，
## 提前扣会留下「如意没了、装备没变」的中间态。
static func plan(inv: Array, rune_ids: Array) -> Dictionary:
	var base := Upgrade.rune_plan(inv, rune_ids)
	if not bool(base.get("ok", false)):
		return base
	return {
		"ok": true,
		"uses": base.get("uses", []),
		"count": int(base.get("count", 0)),
		"tries": tries(rune_ids),
		"reason": "",
	}

## 从若干次抽样里挑评分最高的一次。
## `base_item` 只用于拼装比较样本 —— 固定词条之外的所有字段（基底 / 品质 / 星级 / 等级）
## 都来自它，所以差异只可能来自 `affixes` / `pctAttrs`。
## 🔴 必须走 `Equipment.score()`：另写一套「词条求和」会把百分比词条（0.05）与
## 固定词条（+5）当成同一量级，选出来的「最优」在界面上看起来更差（工程 90 §2 同族）。
static func pick_best(samples: Array, base_item: Dictionary) -> Dictionary:
	if samples.is_empty():
		return {}
	if samples.size() == 1:
		return samples[0]
	var best: Dictionary = samples[0]
	var best_score := _sample_score(best, base_item)
	for i in range(1, samples.size()):
		var score := _sample_score(samples[i], base_item)
		if score > best_score:
			best_score = score
			best = samples[i]
	return best

static func _sample_score(sample: Dictionary, base_item: Dictionary) -> float:
	if not sample is Dictionary or base_item.is_empty():
		return 0.0
	var probe := base_item.duplicate(true)
	probe["affixes"] = sample.get("affixes", [])
	probe["pctAttrs"] = sample.get("pctAttrs", [])
	return Equipment.score(probe)

## 面板用：`{rune_id: 背包里可用枚数}`（同模板跨堆叠求和）。
## 与 `upgrade_panel._refresh_runes` 的统计口径一致，避免两处各数一遍数出不同结果。
static func inventory_counts(inv: Array) -> Dictionary:
	var counts := {}
	for entry in inv:
		if not entry is Dictionary:
			continue
		if String(entry.get("kind", "")) != "rune":
			continue
		var rune_id := String(entry.get("itemId", ""))
		counts[rune_id] = int(counts.get(rune_id, 0)) + maxi(0, int(entry.get("count", 0)))
	return counts

## 按重掷权重从高到低预选四枚；只读背包，不扣除堆叠。
static func best_available(inv: Array) -> Array[String]:
	var counts := inventory_counts(inv)
	var ids := counts.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var wa := weight_of(a)
		var wb := weight_of(b)
		return a < b if is_equal_approx(wa, wb) else wa > wb)
	var chosen: Array[String] = []
	for raw in ids:
		var rune_id := String(raw)
		if weight_of(rune_id) <= 0.0:
			continue
		for _i in range(mini(int(counts[rune_id]), SLOTS - chosen.size())):
			chosen.append(rune_id)
		if chosen.size() == SLOTS:
			break
	while chosen.size() < SLOTS:
		chosen.append("")
	return chosen
