extends Node
## 等级差探针（工程 113）：装备停在 450，玩家继续升级，怪也跟着升 —— 到底慢了多少？
##
## 用途：回答「装备不换、只涨等级，为什么手感没明显变差」。它扫一串等级，
## 每个等级都**完整还原**玩家侧（等级 / 基础攻防 / 职业），再走真实门面
## （`GameState.total_attack()` / `total_defense()` / `max_hp()` / 攻速 / 暴击），
## 怪物侧沿用 `Endgame.norm() × Balance.scale()`（与 `monster.gd` 同式）。
##
## 🔴 与 `boss_ttk_probe` 的关键差别：那支只还原 `player.level` 与 `equipment`，
##    **不还原 `player.attack` / `player.defense` / `player.classId`** ⇒ 读出来的是
##    「1 级基础攻防 + 满级装备 + 武士系数」，总攻少算约 10%、生命多算约 49%。
##    本探针把 player 全量从存档铺回去，只在你指定的等级上覆写 `attack` / `defense`。
##
## ⚠ 只读：绝不调用 SaveManager，不写盘。
## 运行：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/level_gap_probe.tscn`
## （放 `tools/` 而非 `tests/`：`--all` 会 glob `tests/*.tscn`。）

const REAL_SAVE := "user://saves/slot_1.json"
## 百首禁域代表席位（与 map.json 的 bossSpawns[0] 同参）。
const MONSTER_ID := "c6_boss03"
const HP_MULT := 2.0
const ATK_MULT := 3.0
## 玩家侧不随等级变化、不参与本诊断的属性一律从存档取（攻速 / 暴击 / 词条）。

const LEVELS: Array = [450, 460, 466, 480, 500, 516, 560, 600, 700, 800]

## 存档原文，扫描前还原用。
var _save_player: Dictionary = {}

func _ready() -> void:
	if not _load_save():
		print("[GAP] 读不到 %s，退出" % REAL_SAVE)
		get_tree().quit(1)
		return

	var norm: Dictionary = Endgame.norm(MONSTER_ID)
	print("[GAP] 数据源=%s  职业=%s  装备等级=%d" % [
		REAL_SAVE, PlayerClass.current_id(), _gear_level()])
	print("[GAP] 怪物=%s  norm=%s  hp×%.1f  atk×%.1f" % [
		MONSTER_ID, JSON.stringify(norm), HP_MULT, ATK_MULT])
	print("[GAP] 装备加成：atk=%.0f def=%.0f hpPercent=%.3f hpFlat=%.0f  套装=%.2f" % [
		GameState.equip_bonus().get("atk", 0.0), GameState.equip_bonus().get("def", 0.0),
		GameState.equip_bonus().get("hpPercent", 0.0), GameState.equip_bonus().get("hp", 0.0),
		GameState.set_bonus_pct()])

	# 攻击力构成（当前等级）
	var lv := int(_save_player.get("level", 1))
	_apply_level(lv)
	var equip_atk := float(GameState.equip_bonus().get("atk", 0.0))
	var base_atk := float(Balance.base_attack(lv))
	print("[GAP] 攻击构成 @Lv%d：等级基础 %.0f（%.1f%%）  装备 %.0f（%.1f%%）" % [
		lv, base_atk, base_atk / maxf(1.0, base_atk + equip_atk) * 100.0,
		equip_atk, equip_atk / maxf(1.0, base_atk + equip_atk) * 100.0])

	print("")
	print("[GAP] 等级 | 总攻 | 怪HP | 每击伤害 | TTK普攻 | TTK技能 | AOE3只/只 | Boss每击 | 占血% | 破防余量")
	for raw in LEVELS:
		_row(int(raw), norm)

	print("")
	print("[GAP] 玩家侧明细")
	for raw in [LEVELS[0], int(_save_player.get("level", 1))]:
		_player_row(int(raw))

	# 破防临界：Boss 原始攻 × 倍率 首次超过 玩家防御 × 0.5
	print("")
	print("[GAP] 破防临界等级 ≈ %.1f（低于它 Boss 每击恒为保底值）" % _break_level(norm))
	get_tree().quit(0)

func _row(level: int, norm: Dictionary) -> void:
	_apply_level(level)
	var atk := float(GameState.total_attack())
	var defense := float(GameState.total_defense())
	var hp := float(GameState.max_hp())
	var interval := maxf(0.01, float(GameState.total_attack_interval()))
	var crit := 1.0 + float(GameState.total_crit_chance()) * (float(GameState.total_crit_multiplier()) - 1.0)
	var scaled := Balance.scale(level - Balance.SOFTCAP_LEVEL)
	var boss_hp := float(norm.get("hp", 1)) * scaled * HP_MULT
	var boss_atk := float(norm.get("atk", 1)) * scaled * ATK_MULT
	var boss_def := float(norm.get("def", 0)) * scaled

	var hit := atk - boss_def * 0.5
	var dps := hit * crit / interval
	var ttk := boss_hp / maxf(1.0, dps)
	# 技能轮转：实测平均系数 1.755（单怪）；3 只同拉 AOE 全中时 4.098
	var ttk_skill := ttk / 1.755
	var ttk_aoe3 := ttk_skill * (1.755 / 4.098)

	var raw_in := boss_atk - defense * 0.5
	var floor_hit := clampf(hp * 0.0025, 10.0, 60.0)
	var incoming := raw_in if raw_in > 0.0 else floor_hit
	var margin := defense * 0.5 / maxf(1.0, boss_atk)

	print("[GAP] %4d | %s | %s | %s | %.1fs | %.2fs | %.2fs | %s | %.2f%% | %.2f×" % [
		level, _n(atk), _n(boss_hp), _n(hit), ttk, ttk_skill, ttk_aoe3,
		_n(incoming), incoming / maxf(1.0, hp) * 100.0, margin])

## 玩家侧四项：总攻 / 总防 / 最大生命 / 攻速。答案里的「你的血几乎没涨」靠这一行。
func _player_row(level: int) -> void:
	_apply_level(level)
	print("[GAP]   Lv%-4d 总攻=%-9s 总防=%-9s max_hp=%-9s 攻速=%.3fs 暴击期望=%.4f" % [
		level, _n(GameState.total_attack()), _n(GameState.total_defense()),
		_n(GameState.max_hp()), GameState.total_attack_interval(),
		1.0 + GameState.total_crit_chance() * (GameState.total_crit_multiplier() - 1.0)])

## 千分位：GDScript 的 `%` 格式化不支持 `%,d`，只能自己拼。
func _n(value: float) -> String:
	var text := str(int(round(value)))
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0 and text[i - 1] != "-":
			out = "," + out
	return out

## 把玩家侧铺到指定等级：基础攻防随等级走，其余（攻速 / 暴击 / 词条 / 职业）保持存档值。
func _apply_level(level: int) -> void:
	for key in _save_player.keys():
		GameState.player[String(key)] = _save_player[key]
	GameState.player["level"] = level
	GameState.player["attack"] = Balance.base_attack(level)
	GameState.player["defense"] = Balance.base_defense(level)

func _break_level(norm: Dictionary) -> float:
	var lo := 61.0
	var hi := 1200.0
	for _i in range(60):
		var mid := (lo + hi) * 0.5
		_apply_level(int(mid))
		var boss_atk := float(norm.get("atk", 1)) * Balance.scale(int(mid) - Balance.SOFTCAP_LEVEL) * ATK_MULT
		if boss_atk > float(GameState.total_defense()) * 0.5:
			hi = mid
		else:
			lo = mid
	return hi

## 装备里最高 requiredLevel（回答「装备停在几级」）。
func _gear_level() -> int:
	var top := 0
	for raw_key in GameState.equipment.keys():
		var item: Variant = GameState.equipment[raw_key]
		if item is Dictionary:
			top = maxi(top, int((item as Dictionary).get("requiredLevel", 0)))
	return top

## 读真实存档：`player` 全量 + `equipment`。只读，不碰 SaveManager。
func _load_save() -> bool:
	if not FileAccess.file_exists(REAL_SAVE):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REAL_SAVE))
	if not parsed is Dictionary:
		return false
	var data: Dictionary = parsed
	var p: Variant = data.get("player", null)
	if not p is Dictionary:
		return false
	_save_player = (p as Dictionary).duplicate(true)
	GameState.player = _save_player.duplicate(true)
	var eq: Variant = data.get("equipment", null)
	if not eq is Dictionary:
		return false
	GameState.equipment = {}
	var src: Dictionary = eq
	for raw_key in src.keys():
		var item: Variant = src.get(raw_key)
		if item is Dictionary:
			GameState.equipment[String(raw_key)] = item
	return true
