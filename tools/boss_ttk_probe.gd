extends Node
## 孤王绝域 TTK / 承伤探针（工程 92 D-30）。
##
## 用途：改这张图的任何数值之前，先跑一遍拿到「每击伤害 / 裸站存活 / 药水收支 / 击杀耗时」。
## 读的是**真实链路**（`ItemFactory.make_equip_dynamic` 造 100 级紫装 → `EquipmentMath` 派生
## → `GameState.max_hp()/total_defense()` → `Endgame.norm()` + `Balance.scale()` 复原 Boss）。
##
## ⚠ 它**不是权威**：权威是 `monster.gd` / `game_state.gd` / `balance.gd` 的实现。
##   改公式必须同步这里；且装备词条每次随机生成 ⇒ 绝对值有 ±5% 波动，**比例才是指标**。
##
## 运行：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/boss_ttk_probe.tscn`
## （不在 `tests/` 下，故不会被 `run_isolated_tests.py --all` 的 `tests/*.tscn` 扫到。）

const MAP_ID := "c7_solo_boss"
const BOSS_ID := "boss_corrupted_beast"
const BOSS_LEVEL := 100
const HP_MULTIPLIER := 20.0
const BOSS_INTERVAL := 1.4
## Boss 平均出击频率（阶段 1/2 是 1.4s，阶段 3 攻速 +30% ⇒ 1.077s；加权约 0.8 次/秒）。
const BOSS_HITS_PER_SEC := 0.8
## 优先读真实存档（存在则用它的等级与装备复算，最贴近实机）；不存在才造一套满星紫装。
## 🔴 只读不写：绝不调用 SaveManager，避免触发迁移 / 回写。
const REAL_SAVE := "user://saves/slot_3.json"

func _ready() -> void:
	var used_save := _load_real_save()
	if not used_save:
		_dress("legendary", 12)
		GameState.player.level = BOSS_LEVEL
	GameState.current_map = MAP_ID
	var boss_level := maxi(BOSS_LEVEL, int(GameState.player.level))
	var max_hp := float(GameState.max_hp())
	var defense := float(GameState.total_defense())
	var attack := float(GameState.total_attack())
	var interval := float(GameState.total_attack_interval())
	var crit := float(GameState.total_crit_chance())
	print("[PROBE] crit=%.2f%% critMult=%.2f" % [crit * 100.0, float(GameState.total_crit_multiplier())])
	print("[PROBE] 数据源=%s  玩家等级=%d" % [
		REAL_SAVE if used_save else "（造装备）", int(GameState.player.level)])
	print("[PROBE] 玩家 max_hp=%.0f  def=%.0f  atk=%.0f  interval=%.3f" % [max_hp, defense, attack, interval])

	var norm: Dictionary = Endgame.norm(BOSS_ID)
	# 🔑 Boss 等级由 `levelFromPlayer` 现算：max(minLevel 100, 玩家等级)。
	var scaled := Balance.scale(boss_level - Balance.SOFTCAP_LEVEL)
	var boss_hp := float(norm.get("hp", 0)) * scaled * HP_MULTIPLIER
	var boss_atk := float(norm.get("atk", 0)) * scaled
	var boss_def := float(norm.get("def", 0)) * scaled
	var boss_interval := BOSS_INTERVAL
	print("[PROBE] S(%d)=%.4f" % [boss_level - Balance.SOFTCAP_LEVEL, scaled])
	print("[PROBE] Boss Lv%d hp=%.0f  atk=%.1f  def=%.1f  interval=%.2f" % [
		boss_level, boss_hp, boss_atk, boss_def, boss_interval])
	print("[PROBE] 破防阈值 = 防×0.5 = %.0f（Boss 攻 %.0f 需要 %.2f 倍才够）" % [
		defense * 0.5, boss_atk, defense * 0.5 / maxf(1.0, boss_atk)])

	# 地图实际配置的攻击倍率（0 = 未配，按 1.0 算）
	var seat_atk_mult := 1.0
	var map_data: Variant = DataLoader.get_entry("maps", MAP_ID)
	if map_data is Dictionary:
		var seats: Variant = (map_data as Dictionary).get("bossSpawns", [])
		if seats is Array and not (seats as Array).is_empty():
			seat_atk_mult = float((seats[0] as Dictionary).get("atkMultiplier", 1.0))
	print("[PROBE] 地图当前 atkMultiplier = %.2f ⇒ Boss 实攻 %.0f" % [seat_atk_mult, boss_atk * seat_atk_mult])

	# 玩家 → Boss
	var my_hit := boss_atk * 1.0 - defense * 0.5
	print("[PROBE] Boss 每击对玩家（未暴击）= %.1f（防×0.5=%.1f）" % [my_hit, defense * 0.5])
	var floor_hit := clampi(int(round(max_hp * 0.0025)), 10, 60)
	print("[PROBE] 不破防保底 = %d" % floor_hit)

	# 玩家 → Boss 输出
	var player_hit := attack * 1.0 - boss_def * 0.5
	print("[PROBE] 玩家每击对 Boss = %.1f，击杀需 %.1f 击，耗时约 %.1f 秒" % [
		player_hit, boss_hp / maxf(1.0, player_hit), boss_hp / maxf(1.0, player_hit) * interval])

	# 挨打能力
	var hits_to_die := max_hp / maxf(1.0, my_hit)
	print("[PROBE] 破防态可挨 %.1f 击 = %.1f 秒（不吃药）" % [hits_to_die, hits_to_die * boss_interval])
	var hits_to_die_floor := max_hp / float(floor_hit)
	print("[PROBE] 保底态可挨 %.0f 击 = %.0f 秒" % [hits_to_die_floor, hits_to_die_floor * boss_interval])

	print("[PROBE] dodge=%.3f block=%.3f  miss=%.3f" % [
		float(GameState.total_dodge()), float(GameState.total_block()),
		Combat.miss_chance(float(GameState.total_dodge()))])

	# 药水供给（按 max_hp 百分比恢复，各档独立 CD）
	var supply := 0.0
	for pid in ["potion_hp_small", "potion_hp_mid", "potion_hp_large"]:
		var tpl: Dictionary = DataLoader.get_entry("potions", pid)
		var pct := float(tpl.get("restorePercent", 0.0))
		var cd := float(tpl.get("cooldown", 1.0))
		supply += max_hp * pct / cd
		print("[PROBE] %s 回复 %.0f / CD %.0fs = %.0f/s" % [pid, max_hp * pct, cd, max_hp * pct / cd])
	var big_only := max_hp * 0.2 / 20.0
	print("[PROBE] 三档全开供给 %.0f/s；只用大红 %.0f/s" % [supply, big_only])

	# 击杀时长（含暴击期望）
	var crit_mult := 1.0 + float(GameState.total_crit_chance()) * (float(GameState.total_crit_multiplier()) - 1.0)
	var dps := attack * crit_mult / interval
	var ttk := boss_hp / dps
	print("[PROBE] 期望 DPS=%.0f 击杀耗时=%.0f 秒" % [dps, ttk])

	print("[PROBE] --- 攻击倍率扫描（站桩，Boss 平均出击 %.2f/s）---" % BOSS_HITS_PER_SEC)
	# 候选档位 + 地图当前值（改完配置重跑时能一眼看到「现在落在哪一行」）。
	var mults: Array = [2.4, 2.7, 3.0, 3.3, 3.6, 4.0]
	if not mults.has(seat_atk_mult):
		mults.append(seat_atk_mult)
	mults.sort()
	for raw_mult in mults:
		var m := float(raw_mult)
		var atk2 := boss_atk * m
		var per_hit := atk2 - defense * 0.5
		var rate := per_hit * BOSS_HITS_PER_SEC
		var die_s := max_hp / maxf(1.0, rate)
		var total := rate * ttk
		var tag := "  ← 当前配置" if is_equal_approx(m, seat_atk_mult) else ""
		print("[PROBE] x%.2f atk=%.0f 每击=%.0f (%.2f%%血) 承伤=%.0f/s 裸站死=%.0fs 全程承伤=%.0f 三档药净=%+.0f/s 大红净=%+.0f/s%s" % [
			m, atk2, per_hit, per_hit / max_hp * 100.0, rate, die_s, total,
			supply - rate, big_only - rate, tag])
	get_tree().quit(0)

## 读真实存档的等级与装备（**只读**，不碰 SaveManager）。返回是否成功。
func _load_real_save() -> bool:
	if not FileAccess.file_exists(REAL_SAVE):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REAL_SAVE))
	if not parsed is Dictionary:
		return false
	var data: Dictionary = parsed
	var p: Variant = data.get("player", null)
	if not p is Dictionary:
		return false
	GameState.player.level = int((p as Dictionary).get("level", 1))
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

func _dress(quality: String, star: int) -> void:
	var by_kind := {}
	var table: Variant = DataLoader.get_table("equipments")
	if table is Array:
		for raw in table:
			if not raw is Dictionary:
				continue
			var tpl: Dictionary = raw
			if bool(tpl.get("debug", false)) or not bool(tpl.get("lootable", true)):
				continue
			var bases: Variant = tpl.get("tierBases", {})
			if not bases is Dictionary or not (bases as Dictionary).has(str(ItemFactory.DYNAMIC_BASE_TIER)):
				continue
			var kind := String(tpl.get("slot", ""))
			if not by_kind.has(kind):
				by_kind[kind] = String(tpl.get("id", ""))
	GameState.equipment = {}
	for slot_def in Equipment.SLOT_DEFS:
		var def: Dictionary = slot_def
		var kind := String(def.get("kind", ""))
		var item: Dictionary = ItemFactory.make_equip_dynamic(String(by_kind[kind]), 100, quality)
		item["star"] = star
		GameState.equipment[String(def.get("id", ""))] = item
