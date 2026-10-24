extends Node
## 工程 98 第一层与工程 103 法力成长：职业框架契约。
##
## 这一层最怕的不是「法师不好玩」，而是**改坏了武士**。所以本文件一半的断言是「武士逐位不变」：
## 默认职业全系数 1.0、L1 血蓝仍是 102 / 35、防御不降。另一半守三条容易静默失效的规则：
##   ① 旧档 / 被改档的 `classId` 必须回退 warrior 而不是拒档；
##   ② 技能必须按职业过滤（否则法师面板里混着永远拖不动的灰行）；
##   ③ 快捷栏里**别的职业**的技能格必须清空（否则点了没反应、还找不到它）。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[ClassFrameTest] " + label)

func _ready() -> void:
	_test_data()
	_test_default_class()
	_test_warrior_untouched()
	_test_derivation_layers()
	_test_migration()
	_test_skill_filter()
	_test_hotbar_defaults()
	_test_hotbar_prune()
	_test_load_prunes_hotbar()
	_test_legacy_save_passes_validation()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[ClassFrameTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[ClassFrameTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 数据与默认职业 ----

## 职业表与技能表必须双向自洽：只写一边会出现「面板里有、快捷栏拖不上」。
func _test_data() -> void:
	var ids := PlayerClass.ids()
	check(ids.size() == 2, "应登记 2 个职业，实际 %d" % ids.size())
	check(ids.has("warrior") and ids.has("mage"), "必须同时存在 warrior 与 mage")
	for class_id in ids:
		var skills := HotbarConfig.active_skills(String(class_id))
		check(skills.size() == 6, "%s 应有 6 条技能，实际 %d" % [String(class_id), skills.size()])
		check(skills.has(PlayerClass.basic_skill(String(class_id))),
			"%s 的技能表必须包含自己的普攻" % String(class_id))
		for sid in skills:
			var tpl: Variant = DataLoader.get_entry("skills", String(sid))
			check(tpl is Dictionary and String((tpl as Dictionary).get("class", "")) == String(class_id),
				"%s 的技能 %s 在 skills 表里归属不符" % [String(class_id), String(sid)])
	check(PlayerClass.basic_skill("warrior") == "basic_slash", "武士普攻应是基础斩击")
	check(PlayerClass.basic_skill("mage") == "basic_fireball", "法师普攻应是火球术")

## 默认职业的每个系数都必须**恰好** 1.0（不是「接近 1」）。
func _test_default_class() -> void:
	for key in ["hpMult", "mpMult", "atkMult", "defMult"]:
		check(is_equal_approx(PlayerClass.mult(key, "warrior"), 1.0),
			"默认职业 warrior 的 %s 必须为 1.0，实际 %.4f（改它等于改全部武士玩家）"
			% [key, PlayerClass.mult(key, "warrior")])
	check(is_equal_approx(PlayerClass.attack_range("warrior"), 1.0), "武士普攻射程必须是 1 格")
	check(not PlayerClass.is_ranged("warrior"), "武士不是远程职业")
	check(PlayerClass.is_ranged("mage"), "法师必须是远程职业")

## L1 新档的血 / 蓝是产品文档 4.4 的公开数字：改职业框架不能把它们改掉。
func _test_warrior_untouched() -> void:
	GameState.reset_to_defaults()
	check(String(GameState.player.classId) == "warrior", "新档默认职业必须是 warrior")
	check(GameState.max_hp() == 102, "L1 武士 max_hp 应仍为 102，实际 %d" % GameState.max_hp())
	check(GameState.max_mp() == 35, "L1 武士 max_mp 应仍为 35，实际 %d" % GameState.max_mp())
	check(int(GameState.player.hp) == 102 and int(GameState.player.mp) == 35,
		"新档当前血 / 蓝应等于上限（法师由职业系数派生，武士必须仍是 102 / 35）")

## 三处派生的**乘在哪一层**就是本工程最大的坑（R1）：
## 系数必须乘在最外层，`max_hp` 内部用的 `_base_attack()` / `_base_defense()` 不许带职业系数。
func _test_derivation_layers() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 100
	GameState.player.attack = 50000
	GameState.player.defense = 60000
	GameState.player.classId = "warrior"
	var hp_w := GameState.max_hp()
	var mp_w := GameState.max_mp()
	var atk_w := GameState.total_attack()
	var def_w := GameState.total_defense()
	GameState.player.classId = "mage"
	var hp_m := GameState.max_hp()
	var mp_m := GameState.max_mp()
	var atk_m := GameState.total_attack()
	var def_m := GameState.total_defense()
	check(hp_m == int(round(float(hp_w) * 0.64)),
		"法师血池应恰为武士的 0.64（%d → %d，实际 %d）" % [hp_w, int(round(float(hp_w) * 0.64)), hp_m])
	check(mp_m > mp_w * 2 and float(mp_m) / float(hp_m) >= 1.1,
		"法师高等级蓝池须随攻防成长并超过自身血量（武士蓝 %d / 法师血 %d、蓝 %d）" % [mp_w, hp_m, mp_m])
	check(atk_m == int(round(float(atk_w) * 1.08)), "法师攻击应恰为武士的 1.08 倍（%d → %d）" % [atk_w, atk_m])
	check(def_m == def_w, "两职业防御必须相同（承伤是差值公式，防御打九折 = 承伤 +39%）")
	# 血池只放一次：若 atkMult 误入 `_base_attack()`，法师血会被放大两遍（0.64×1.08 的反向）。
	check(hp_m < hp_w, "法师血池必须小于武士（误入 _base_attack 会二次放大）")

# ---- 存档 ----

## 旧档没有 classId ⇒ 补 warrior；被改档的非法值 ⇒ 回退 warrior（**不拒档**）。
func _test_migration() -> void:
	var legacy: Dictionary = SaveManager.call("_migrate_player", {"level": 30, "hp": 500})
	check(String(legacy.get("classId", "")) == "warrior", "旧档迁移必须补 classId=warrior")
	var broken: Dictionary = SaveManager.call("_migrate_player", {"classId": "necromancer"})
	check(String(broken.get("classId", "")) == "warrior", "非法 classId 必须回退 warrior")
	var mage: Dictionary = SaveManager.call("_migrate_player", {"classId": "mage"})
	check(String(mage.get("classId", "")) == "mage", "合法 classId 必须原样保留")
	check(PlayerClass.normalize("") == "warrior", "空 classId 归一为 warrior")
	check(PlayerClass.normalize("mage") == "mage", "合法 id 归一后不变")

# ---- 技能过滤 ----

func _test_skill_filter() -> void:
	var warrior := HotbarConfig.active_skills("warrior")
	var mage := HotbarConfig.active_skills("mage")
	check(warrior.has("spirit_storm") and not warrior.has("meteor"), "武士技能表不得含法师技能")
	check(mage.has("meteor") and not mage.has("spirit_storm"), "法师技能表不得含武士技能")
	check(not HotbarConfig.usable_skill("lightning", "warrior"), "武士不可用雷电术")
	check(HotbarConfig.usable_skill("lightning", "mage"), "法师可用雷电术")

## 默认快捷栏第三格必须是**本职业**普攻：写死 basic_slash 会让法师新档第一格点了没反应。
func _test_hotbar_defaults() -> void:
	GameState.reset_to_defaults("mage")
	check(String(GameState.player.classId) == "mage", "按职业重置后 classId 应为 mage")
	var entry: Variant = GameState.hotbar[2]
	check(entry is Dictionary and String((entry as Dictionary).get("id", "")) == "basic_fireball",
		"法师默认快捷栏第三格应是火球术，实际 %s" % str(entry))
	check(GameState.hotbar[0].id == "red" and GameState.hotbar[1].id == "blue", "默认红蓝药不受职业影响")

## 读档清理：别的职业技能格必须变 null，药水 / 杂项一格不动。
func _test_hotbar_prune() -> void:
	GameState.reset_to_defaults("mage")
	GameState.hotbar[3] = {"kind": "skill", "id": "earth_cleave"}
	GameState.hotbar[4] = {"kind": "skill", "id": "lightning"}
	GameState.hotbar[5] = {"kind": "potion", "id": "potion_hp_small"}
	var cleared := GameState.prune_hotbar_for_class()
	check(cleared == 1, "应只清掉 1 个越界技能格，实际 %d" % cleared)
	check(GameState.hotbar[3] == null, "武士技能格必须被清空")
	check(GameState.hotbar[4] is Dictionary and GameState.hotbar[4].id == "lightning", "本职业技能格不得被清")
	check(GameState.hotbar[5] is Dictionary and GameState.hotbar[5].id == "potion_hp_small", "药水格不得被清")
	# 反向：武士档里的法师技能同样要被清（不能只处理一边）。
	GameState.reset_to_defaults("warrior")
	GameState.hotbar[3] = {"kind": "skill", "id": "meteor"}
	check(GameState.prune_hotbar_for_class() == 1 and GameState.hotbar[3] == null,
		"武士档里的法师技能格同样必须被清空")

## 读档**链路**：上面那条只证明 `prune_hotbar_for_class()` 本身写得对，
## 证明不了 `save_manager.apply_to_game_state()` 真的调了它。
## 🔴 工程 98 N-6 实测：把 `save_manager` 里那句调用整行删掉，上面那条仍然全绿 ——
##    假绿。所以这里必须走「存档里有非法格 → 读回来 → 被清空」的真实往返。
##
## 用 **9 号格**当「读档真的写回内存了」的见证：`defaults()` 只填 0—2 格，9 号恒为 null，
## 所以前置断言不会随默认栏调整而失效（拿 3 号格当见证就是在赌默认栏不长个子）。
func _test_load_prunes_hotbar() -> void:
	GameState.reset_to_defaults("warrior")
	GameState.hotbar[3] = {"kind": "skill", "id": "meteor"}          # 法师技能，武士档非法
	GameState.hotbar[9] = {"kind": "skill", "id": "battle_focus"}    # 本职业，合法
	var saved := SaveManager._collect()
	# 🔴 这条守的是 P1 引入的**读档全灭**回归：`_is_valid_save` 会把 `default_player()`
	# 里除 `name` 外的每个键当非负数校验，加了字符串 `classId` 却不放行 ⇒ **所有存档都读不进来**。
	# 报错文案是「player.classId 应为非负数」，跟职业一点关系都没有，极易误判成别的问题。
	check(SaveManager._is_valid_save(saved), "带 classId 的存档必须通过合法性校验（否则读档全灭）")
	GameState.reset_to_defaults("mage")
	check(GameState.hotbar[3] == null and GameState.hotbar[9] == null,
		"前置：重置后 3 / 9 号格都应为空，否则下面的断言分不清「读档写的」还是「上一轮残留」")
	SaveManager.apply_to_game_state(saved)
	check(String(GameState.player.classId) == "warrior", "读档必须恢复建档时的职业")
	check(GameState.hotbar[9] is Dictionary and String(GameState.hotbar[9].get("id", "")) == "battle_focus",
		"读档必须真的把快照写回内存（9 号格应是 battle_focus，实际 %s）" % str(GameState.hotbar[9]))
	check(GameState.hotbar[3] == null,
		"读档后越界技能格必须被清空（`save_manager` 里那句 `prune_hotbar_for_class()` 不能被删）")

## 旧档（**没有** `classId` 键）必须照样能通过合法性校验。
## 🔴 这是 P1 最危险的一步：`_is_valid_save` 按 `default_player()` 逐键校验 `player`，
##    新键只在 `v == 0` 分支补 ⇒ 存量档在下一版上线时**全部判为损坏**（实测续档直接报
##    「player.classId 非法」然后走备份恢复）。M5-9c 加设置键时踩过一模一样的一条。
func _test_legacy_save_passes_validation() -> void:
	GameState.reset_to_defaults("warrior")
	var legacy := SaveManager._collect()
	(legacy["player"] as Dictionary).erase("classId")
	check(SaveManager._is_valid_save(legacy),
		"旧档（无 classId）必须通过合法性校验，否则存量玩家一上线就读不了档")
	SaveManager.apply_to_game_state(legacy)
	check(String(GameState.player.classId) == "warrior", "旧档读回后职业必须补成默认 warrior")
