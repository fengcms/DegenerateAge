extends Node
## 工程 112：如意重掷取优（重铸 + 保星）—— 10 组用例。
##
## 四条最值钱的断言：
## 1. **零如意时随机流逐位不变** —— 用 `RandomNumberGenerator.state` 对比「走结算」与
##    「手动单次重掷」。这是 `ReforgeTest` 用例 14 那条快照红线的运行期版本：
##    多掷一次不会让旧用例立刻变红，但会让所有玩家的重铸结果整体漂移。
## 2. **取优结果必须等于该种子下 N 次抽样的最高分** —— 判据在外部（`Equipment.score`），
##    不复用被测的 `RuneCharge.pick_best`，否则它写错也照样绿。
## 3. **先掷后扣** —— 金币不足 / 如意不在背包 / 材料失效，都必须是「一枚如意都不掉」。
## 4. **非保星模式不吃如意** —— 四紫升紫的成功率是「件数换概率」的刻意设计（D2 拍板）。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[RuneRerollTest] " + label)

func _ready() -> void:
	_test_auto_best()
	_test_weights()
	_test_tries()
	_test_plan()
	_test_zero_rune_stream_unchanged()
	_test_best_is_max_of_samples()
	_test_settlement_consumes_runes()
	_test_reject_consumes_nothing()
	_test_transfer_best()
	_test_non_transfer_ignores_runes()
	_test_ui_rows()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[RuneRerollTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error(failure)
		print("[RuneRerollTest] 失败 %d 项" % failures.size())

# ---- 1) 权重表：四档读数据，递增且不重复 ----

func _test_weights() -> void:
	var expected := {"rune_iron": 0.5, "rune_jade": 1.0, "rune_gold": 2.0, "rune_diamond": 4.0}
	for rune_id in expected.keys():
		check(is_equal_approx(RuneCharge.weight_of(String(rune_id)), float(expected[rune_id])),
			"%s 的重掷权重应为 %.1f，实际 %.2f" % [
				rune_id, float(expected[rune_id]), RuneCharge.weight_of(String(rune_id))])
	check(is_zero_approx(RuneCharge.weight_of("")), "空 id 的权重应为 0")
	check(is_zero_approx(RuneCharge.weight_of("rune_not_exists")), "未登记的如意权重应为 0")
	# 从数据推导「严格递增」：写死数字的断言在改档位时会假红，而这条永远跟着数据走。
	var templates = DataLoader.get_table("runes")
	var previous := 0.0
	if templates is Array:
		for template in templates:
			if not template is Dictionary:
				continue
			var weight := float((template as Dictionary).get("rerollWeight", 0.0))
			check(weight > previous, "四档权重必须严格递增：%s 的 %.1f 不大于上一档的 %.1f" % [
				String((template as Dictionary).get("id", "")), weight, previous])
			previous = weight

# ---- 2) 重掷次数 ----

func _test_tries() -> void:
	check(RuneCharge.tries([]) == 1, "不投如意应只掷 1 次")
	check(RuneCharge.tries(["", "", "", ""]) == 1, "四格全空应只掷 1 次")
	check(RuneCharge.tries(["rune_iron"]) == 2, "1 枚铁如意应掷 2 次（round(1.5)）")
	check(RuneCharge.tries(["rune_iron", "rune_iron", "rune_iron", "rune_iron"]) == 3,
		"4 枚铁如意应掷 3 次，实际 %d" % RuneCharge.tries([
			"rune_iron", "rune_iron", "rune_iron", "rune_iron"]))
	check(RuneCharge.tries(["rune_jade", "rune_jade", "rune_jade", "rune_jade"]) == 5,
		"4 枚玉如意应掷 5 次")
	check(RuneCharge.tries(["rune_gold", "rune_gold", "rune_gold", "rune_gold"]) == 9,
		"4 枚金如意应掷 9 次")
	check(RuneCharge.tries(["rune_diamond", "rune_diamond", "rune_diamond", "rune_diamond"]) == 17,
		"4 枚钻石如意应掷 17 次")
	check(RuneCharge.tries(["rune_gold", "rune_gold", "rune_iron", "rune_iron"]) == 6,
		"2 金 + 2 铁应掷 6 次")
	# 封顶：数据被改成更大的权重也不能突破上限（否则「取优」会变成「必得」）。
	var oversized: Array[String] = []
	for i in range(20):
		oversized.append("rune_diamond")
	check(RuneCharge.tries(oversized) == RuneCharge.MAX_TRIES,
		"超过上限应封顶到 %d，实际 %d" % [RuneCharge.MAX_TRIES, RuneCharge.tries(oversized)])

# ---- 3) 校验与扣除计划 ----

func _test_plan() -> void:
	GameState.reset_to_defaults()
	GameState.inventory[0] = _rune("rune_diamond", 1)
	var plan := RuneCharge.plan(GameState.inventory, ["rune_diamond", "", "", ""])
	check(bool(plan.get("ok", false)), "背包有货时应通过校验：%s" % String(plan.get("reason", "")))
	check(int(plan.get("tries", 0)) == 5, "1 枚钻石如意应掷 5 次")
	check(int(plan.get("count", 0)) == 1, "应记 1 枚")
	var over := RuneCharge.plan(GameState.inventory,
		["rune_diamond", "rune_diamond", "", ""])
	check(not bool(over.get("ok", true)), "只有 1 枚却选了 2 枚应被拒绝")
	var missing := RuneCharge.plan(GameState.inventory, ["rune_gold", "", "", ""])
	check(not bool(missing.get("ok", true)), "背包没有的档位应被拒绝")
	var junk := RuneCharge.plan(GameState.inventory, ["rune_not_exists", "", "", ""])
	check(not bool(junk.get("ok", true)), "不存在的如意模板应被拒绝")
	# 跨堆叠：两堆 3 枚，选 4 枚应当能凑出来（`uses` 应覆盖两个下标）。
	GameState.inventory[0] = _rune("rune_iron", 3)
	GameState.inventory[1] = _rune("rune_iron", 3)
	var spread := RuneCharge.plan(GameState.inventory,
		["rune_iron", "rune_iron", "rune_iron", "rune_iron"])
	check(bool(spread.get("ok", false)), "两堆 3 枚凑 4 枚应通过")
	check((spread.get("uses", []) as Array).size() == 2, "扣除计划应覆盖两个堆叠")
	GameState.reset_to_defaults()

# ---- 4) 零如意时随机流逐位不变（运行期版本的随机数红线）----

func _test_zero_rune_stream_unchanged() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var target := _make("c6_equip_necklace", 100, "legendary", 2601)
	check(not target.is_empty(), "目标实例应能生成")
	if target.is_empty():
		return
	GameState.inventory[0] = target
	# 参照：同一份实例、同一个种子，只调一次 `reroll_affixes`。
	var reference := _rng(2602)
	var manual := ItemFactory.reroll_affixes(target.duplicate(true), reference, [], 0.0)
	check(bool(manual.get("ok", false)), "参照重掷应成功")
	# 实测：走结算但一枚如意都不投。
	var stream := _rng(2602)
	var result := GameState.reforge_equipment("bag", 0, String(target.get("instanceId", "")),
		stream, [], [], 1.0, [])
	check(bool(result.get("ok", false)), "零如意重铸应成功：%s" % String(result.get("reason", "")))
	check(stream.state == reference.state,
		"零如意时随机流消耗必须与单次重掷完全相同（state 应相等）")
	check(int(result.get("tries", 0)) == 1, "零如意时 tries 应为 1")
	check(str(result.get("affixes", [])) == str(manual.get("affixes", [])),
		"零如意时结果应与直接重掷逐字段相同")
	GameState.reset_to_defaults()

# ---- 5) 取优 = 该种子下 N 次抽样的最高分（外部判据，不复用 pick_best）----

func _test_best_is_max_of_samples() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var target := _make("c6_equip_necklace", 100, "legendary", 2611)
	check(not target.is_empty(), "目标实例应能生成")
	if target.is_empty():
		return
	GameState.inventory[0] = target
	GameState.inventory[1] = _rune("rune_diamond", 10)
	var tries := RuneCharge.tries(["rune_diamond", "rune_diamond", "rune_diamond", "rune_diamond"])
	# 独立重放：同一种子连掷 tries 次，取最高分（判据在外部算，不问被测函数）。
	var replay := _rng(2612)
	var best := -INF
	var first := 0.0
	for i in range(tries):
		var sample := ItemFactory.reroll_affixes(target.duplicate(true), replay, [], 0.0)
		check(bool(sample.get("ok", false)), "重放抽样应成功")
		var score := _sample_score(target, sample)
		if i == 0:
			first = score
		best = maxf(best, score)
	var stream := _rng(2612)
	var result := GameState.reforge_equipment("bag", 0, String(target.get("instanceId", "")),
		stream, [], [], 1.0, ["rune_diamond", "rune_diamond", "rune_diamond", "rune_diamond"])
	check(bool(result.get("ok", false)), "投如意重铸应成功：%s" % String(result.get("reason", "")))
	check(int(result.get("tries", 0)) == tries, "tries 应为 %d，实际 %d" % [tries, int(result.get("tries", 0))])
	var got := _sample_score(target, result)
	check(is_equal_approx(got, best),
		"取优结果必须等于 %d 次抽样的最高分 %.3f，实际 %.3f" % [tries, best, got])
	check(got >= first, "取优不应低于第一次抽样（%.3f < %.3f）" % [got, first])
	GameState.reset_to_defaults()

# ---- 6) 结算扣除如意 ----

func _test_settlement_consumes_runes() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var target := _make("c6_equip_necklace", 100, "legendary", 2621)
	GameState.inventory[0] = target
	GameState.inventory[1] = _rune("rune_jade", 10)
	var result := GameState.reforge_equipment("bag", 0, String(target.get("instanceId", "")),
		_rng(2622), [], [], 1.0, ["rune_jade", "rune_jade", "", ""])
	check(bool(result.get("ok", false)), "投 2 枚玉如意应成功：%s" % String(result.get("reason", "")))
	check(int(result.get("runes", 0)) == 2, "应记录消耗 2 枚，实际 %d" % int(result.get("runes", 0)))
	check(GameState.inventory[1] is Dictionary, "如意堆叠应仍在（只扣 2 枚）")
	if GameState.inventory[1] is Dictionary:
		check(int((GameState.inventory[1] as Dictionary).get("count", 0)) == 8,
			"10 枚投 2 枚应剩 8 枚，实际 %d" % int((GameState.inventory[1] as Dictionary).get("count", 0)))
	# 扣空：3 枚堆里投 3 枚 → 整格清空。
	GameState.inventory[2] = _rune("rune_iron", 3)
	var drain := GameState.reforge_equipment("bag", 0, String(target.get("instanceId", "")),
		_rng(2623), [], [], 1.0, ["rune_iron", "rune_iron", "rune_iron", ""])
	check(bool(drain.get("ok", false)), "投 3 枚铁如意应成功")
	check(GameState.inventory[2] == null, "投光后该格应置空，实际 %s" % str(GameState.inventory[2]))
	GameState.reset_to_defaults()

# ---- 7) 拒绝路径一枚不扣 ----

func _test_reject_consumes_nothing() -> void:
	GameState.reset_to_defaults()
	var target := _make("c6_equip_necklace", 100, "legendary", 2631)
	GameState.inventory[0] = target
	GameState.inventory[1] = _rune("rune_diamond", 5)
	# 金币不足。
	GameState.gold = 0
	var poor := GameState.reforge_equipment("bag", 0, String(target.get("instanceId", "")),
		_rng(2632), [], [], 1.0, ["rune_diamond", "", "", ""])
	check(not bool(poor.get("ok", true)), "金币不足应被拒绝")
	check(_count_of("rune_diamond") == 5, "金币不足时如意一枚都不应扣，实际 %d" % _count_of("rune_diamond"))
	# 如意已被别处用掉（背包里没有）。
	GameState.gold = 1000000
	GameState.inventory[1] = null
	var missing := GameState.reforge_equipment("bag", 0, String(target.get("instanceId", "")),
		_rng(2633), [], [], 1.0, ["rune_diamond", "", "", ""])
	check(not bool(missing.get("ok", true)), "背包没有该如意应被拒绝")
	check(GameState.gold == 1000000, "拒绝时金币不应扣")
	# 目标实例被换掉（快照失效）。
	GameState.inventory[1] = _rune("rune_iron", 4)
	var stale := GameState.reforge_equipment("bag", 0, "inst_not_here",
		_rng(2634), [], [], 1.0, ["rune_iron", "", "", ""])
	check(not bool(stale.get("ok", true)), "实例 id 不匹配应被拒绝")
	check(_count_of("rune_iron") == 4, "实例失效时如意一枚都不应扣")
	GameState.reset_to_defaults()

# ---- 8) 保星：产物词条也取优 ----

func _test_transfer_best() -> void:
	# 🔑 两次必须**各自重建**：`instanceId` 由 `Crypto.generate_random_bytes` 生成，
	# 同一个种子也不一样，拿上一轮的实例 id 去找第二轮的装备必然找不到。
	var plain_set := _setup_transfer()
	var plain := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, plain_set, "",
		_rng(2643))
	check(bool(plain.get("ok", false)), "不投如意的保星应成功：%s" % String(plain.get("reason", "")))
	check(int(plain.get("tries", 0)) == 1, "不投如意时保星 tries 应为 1")
	var rune_set := _setup_transfer()
	var with_runes := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, rune_set, "",
		_rng(2643), ["rune_diamond", "rune_diamond", "rune_diamond", "rune_diamond"])
	check(bool(with_runes.get("ok", false)), "投如意的保星应成功：%s" % String(with_runes.get("reason", "")))
	check(int(with_runes.get("tries", 0)) == 17, "4 枚钻石如意应掷 17 次，实际 %d" % int(with_runes.get("tries", 0)))
	check(int(with_runes.get("runes", 0)) == 4, "应记录消耗 4 枚")
	check(_count_of("rune_diamond") == 6, "10 枚投 4 枚应剩 6 枚，实际 %d" % _count_of("rune_diamond"))
	var gained: Dictionary = with_runes.get("item", {})
	check(not gained.is_empty(), "保星应产出装备")
	check(int(gained.get("star", 0)) == Upgrade.max_star(), "产物必须是 12 星")
	check(String(gained.get("quality", "")) == "legendary", "产物必须仍是紫装")
	var plain_gained: Dictionary = plain.get("item", {})
	if not gained.is_empty() and not plain_gained.is_empty():
		# 🔑 两条一起才有牙：只写 `>=` 的话，把取优整个删掉（产物 = 第 1 次掷，两侧完全相同）
		# 依旧成立 —— 那是典型的假绿。`!=` 负责证明"取优真的接管了结果"，
		# `>=` 负责证明方向没反（取优不能越取越差）。
		check(str(gained.get("affixes", [])) != str(plain_gained.get("affixes", [])),
			"同种子下投 17 次的产物词条不应与只掷 1 次完全相同（说明取优没有接管结果）")
		check(Equipment.score(gained) >= Equipment.score(plain_gained),
			"同种子下投如意的产物评分不应低于不投（%.3f < %.3f）" % [
				Equipment.score(gained), Equipment.score(plain_gained)])
	GameState.reset_to_defaults()

## 建一组可保星的现场（12★ 旧件 + 高档 0★ 新件 + 10 枚钻石如意），返回两件材料。
func _setup_transfer() -> Array[Dictionary]:
	GameState.reset_to_defaults()
	GameState.gold = 10000000
	var old_item := _make("c6_equip_weapon", 100, "legendary", 2641)
	var new_item := _make("c6_equip_weapon", 110, "legendary", 2642)
	if old_item.is_empty() or new_item.is_empty():
		return []
	old_item["star"] = Upgrade.max_star()
	GameState.inventory[0] = old_item
	GameState.inventory[1] = new_item
	GameState.inventory[2] = _rune("rune_diamond", 10)
	var result: Array[Dictionary] = [old_item, new_item]
	return result

# ---- 9) 非保星模式不吃如意 ----

func _test_non_transfer_ignores_runes() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var parts: Array[Dictionary] = []
	for i in range(4):
		var item := _make("c6_equip_weapon", 100, "legendary", 2651 + i)
		parts.append(item)
		GameState.inventory[i] = item
	GameState.inventory[4] = _rune("rune_diamond", 10)
	var plain := GameState.forge_equipment(EquipmentFusion.PURPLE_TARGET, parts, "weapon",
		_rng(2656))
	check(bool(plain.get("ok", false)), "四紫定向应成功：%s" % String(plain.get("reason", "")))
	check(int(plain.get("tries", 0)) == 1, "四紫定向的 tries 应恒为 1")
	# 复原后带上如意再跑一次：结果必须与不投完全一致，且如意一枚不扣。
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	parts = []
	for i in range(4):
		var item := _make("c6_equip_weapon", 100, "legendary", 2651 + i)
		parts.append(item)
		GameState.inventory[i] = item
	GameState.inventory[4] = _rune("rune_diamond", 10)
	var with_runes := GameState.forge_equipment(EquipmentFusion.PURPLE_TARGET, parts, "weapon",
		_rng(2656), ["rune_diamond", "rune_diamond", "", ""])
	check(bool(with_runes.get("ok", false)), "带如意的四紫定向应成功")
	check(int(with_runes.get("tries", 0)) == 1, "非保星模式不得因如意增加抽样")
	check(int(with_runes.get("runes", 0)) == 0, "非保星模式不得消耗如意")
	check(_count_of("rune_diamond") == 10, "非保星模式如意应原封不动，实际 %d" % _count_of("rune_diamond"))
	# 🔑 不比整个 item：`instanceId` 是 `Crypto` 随机串，两次生成必然不同。
	# 要比的是「这次掷出来的词条」，那才是如意唯一能影响的东西。
	var plain_item: Dictionary = plain.get("item", {})
	var rune_item: Dictionary = with_runes.get("item", {})
	check(str(rune_item.get("affixes", [])) == str(plain_item.get("affixes", [])),
		"非保星模式的固定词条应与不投如意逐字段相同")
	check(str(rune_item.get("pctAttrs", [])) == str(plain_item.get("pctAttrs", [])),
		"非保星模式的百分比词条应与不投如意逐字段相同")
	GameState.reset_to_defaults()

# ---- 10) UI：重铸面板四格下拉 + 保星页可见性 ----

func _test_ui_rows() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	GameState.inventory[0] = _make("c6_equip_necklace", 100, "legendary", 2661)
	GameState.inventory[1] = _rune("rune_gold", 3)
	var panel: Control = (load("res://scenes/ui/ReforgePanel.tscn") as PackedScene).instantiate()
	add_child(panel)
	panel.set_open(true)
	check(panel._rune_pickers.size() == RuneCharge.SLOTS,
		"重铸面板应有 %d 格如意，实际 %d" % [RuneCharge.SLOTS, panel._rune_pickers.size()])
	# 🔴 布局红线：如意格**不能把面板最小宽度顶出去**。
	# 一行四格时，每个下拉的最小宽度由最长项文字「钻石如意 ×12」决定（约 141px），
	# 4 个 + 3 个间距 = 588 ⇒ `_content` 的最小宽度从设计值 520 被顶到 588，
	# 面板随之变宽 68px；而 `_resize()` 里的并排算式仍按 520 算留位 ⇒ 窄屏时面板会盖住背包。
	# 实测第一版就是这样：截图里右侧一整个下拉被切在画面外，测试却全绿。
	# 两列栅格的最小宽度只有 290，不会顶出去 —— 这里断的就是「设计宽度没被内容撑破」。
	# 🔴 520 是 `ReforgePanel.WIDTH` 的**字面值**，故意不引用那个常量：
	# 引用它等于「常量改坏照样绿」（坑 37）。真要改面板宽度，请连这条断言一起改，并重出图确认。
	check(panel._content.get_combined_minimum_size().x <= 520.0,
		"内容区最小宽度不应超过设计宽度 520，实际 %.0f（如意格把面板撑宽了）"
			% panel._content.get_combined_minimum_size().x)
	# 🔴 高度**不在这里断**：内容区里有自动换行的 Label，独立测试的宿主根控件宽度为 0 时
	# 每个字换一行，最小高度会算出 3387 这种数（实测），是测试环境伪影、不是真实布局。
	# 面板高度的实际余量见 `tools/rune_reroll_preview` 的输出（1280×800 下 764，上下各 18px）。
	var hint := String(panel._rune_hint.text)
	check(hint.contains("1"), "未投入如意时提示应说明只掷 1 次，实际「%s」" % hint)
	# 选中一格金如意 → 提示应变成 3 次（round(1+2)）。
	panel._rune_choices[0] = "rune_gold"
	panel._refresh_runes()
	hint = String(panel._rune_hint.text)
	check(hint.contains("3"), "1 枚金如意应提示掷 3 次，实际「%s」" % hint)
	panel.set_open(false)
	check(panel._rune_choices[0].is_empty(), "关面板应清空如意选择")
	panel.queue_free()
	# 保星面板：如意区只在保星页可见。
	var fusion: Control = (load("res://scenes/ui/EquipmentFusionPanel.tscn") as PackedScene).instantiate()
	add_child(fusion)
	fusion._mode = EquipmentFusion.PURPLE_TARGET
	fusion.set_open(true)
	check(not bool(fusion._rune_row.visible), "非保星页不应显示如意格")
	fusion._mode = EquipmentFusion.STAR_TRANSFER
	fusion.set_open(false)
	fusion.set_open(true)
	check(bool(fusion._rune_row.visible), "保星页应显示如意格")
	check(fusion._rune_pickers.size() == RuneCharge.SLOTS, "保星页如意格应为 4 个")
	fusion.set_open(false)
	fusion.queue_free()
	GameState.reset_to_defaults()

# ---- 辅助 ----

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func _make(item_id: String, level: int, quality: String, seed_value: int) -> Dictionary:
	if level > Balance.SOFTCAP_LEVEL:
		return ItemFactory.make_equip_exact(item_id, level, quality, _rng(seed_value))
	return ItemFactory.make_equip_roll(item_id, ItemFactory.tier_start_for_template(item_id),
		quality, _rng(seed_value))

func _rune(rune_id: String, count: int) -> Dictionary:
	return {"kind": "rune", "itemId": rune_id, "count": count}

## 某档如意的背包总枚数（跨堆叠求和）。
func _count_of(rune_id: String) -> int:
	return int(RuneCharge.inventory_counts(GameState.inventory).get(rune_id, 0))

## 把一次抽样贴回原装备算评分 —— 与 `RuneCharge._sample_score` 同口径，
## 但这里**不复用**它：判据必须独立于被测实现。
func _sample_score(base_item: Dictionary, sample: Dictionary) -> float:
	var probe := base_item.duplicate(true)
	probe["affixes"] = sample.get("affixes", [])
	probe["pctAttrs"] = sample.get("pctAttrs", [])
	return Equipment.score(probe)

## 自动填充按实际重掷收益选最优四枚，跨堆叠计数且不提前消耗。
func _test_auto_best() -> void:
	var inv: Array = [
		{"kind": "rune", "itemId": "rune_iron", "count": 9},
		{"kind": "rune", "itemId": "rune_diamond", "count": 1},
		{"kind": "rune", "itemId": "rune_gold", "count": 1},
		{"kind": "rune", "itemId": "rune_gold", "count": 1}]
	var before := inv.duplicate(true)
	check(RuneCharge.best_available(inv) == ["rune_diamond", "rune_gold", "rune_gold", "rune_iron"],
		"如意如意跨堆叠选择收益最高的四枚")
	check(inv == before, "自动预选不扣除背包库存")
	check(RuneCharge.best_available([inv[1]]) == ["rune_diamond", "", "", ""], "不足四枚留空")
	check(RuneCharge.best_available([]) == ["", "", "", ""], "空背包不虚构如意")
	var panel := preload("res://scenes/ui/EquipmentFusionPanel.tscn").instantiate()
	add_child(panel)
	GameState.inventory = inv.duplicate(true)
	panel._mode = EquipmentFusion.STAR_TRANSFER
	panel._risk_confirmed = true
	panel._on_auto_runes()
	check(panel._rune_choices == RuneCharge.best_available(inv) and not panel._risk_confirmed,
		"自动填充更新四格并使风险确认失效")
	check(String(panel._rune_pickers[0].get_item_metadata(panel._rune_pickers[0].selected)) == "rune_diamond",
		"自动填充同步下拉显示")
	check(GameState.inventory == before, "界面自动填充不消耗库存")
	panel.queue_free()
	GameState.reset_to_defaults()
