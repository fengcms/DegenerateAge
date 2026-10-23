extends Node
## 职业平衡探针（工程 98 §5.4）。
##
## 用途：改 `classes.json` 的任何系数之前，先跑一遍拿到「两职业的血 / 蓝 / 攻击 / DPS /
## 对同一只 Boss 的击杀耗时 / 每击承伤 / 开盾与断盾的生存比 / 蓝收支」。
##
## 口径与 `boss_ttk_probe` 完全一致（读真实存档 → `EquipmentMath` 派生 → `Endgame.norm()`）：
## **只读不写**，绝不调用 `SaveManager`（否则会触发迁移与回写）。
##
## ⚠ 它不是权威：权威是 `game_state.gd` / `combat.gd` / `monster.gd`。改公式必须同步这里。
##
## 运行：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/class_balance_probe.tscn`

const REAL_SAVE := "user://saves/slot_3.json"
const FALLBACK_LEVEL := 100
const FALLBACK_QUALITY := "legendary"
const FALLBACK_STAR := 12
## 代表 Boss：百首禁域（100 席、atk ×3.0）—— 平衡判据必须压在**玩家真的会反复刷的**目标上。
const REPORT_MAP := "c7_boss_field"
## Boss 出手率（与 boss_ttk_probe 同一实测值：追击 / 前摇期间不出手）。
const HIT_RATE_FACTOR := 0.55

func _ready() -> void:
	var used_save := _load_real_save()
	if not used_save:
		_dress(FALLBACK_QUALITY, FALLBACK_STAR)
		GameState.player.level = FALLBACK_LEVEL
	print("[CLASS] 数据源=%s  玩家等级=%d" % [
		REAL_SAVE if used_save else "（造装备）", int(GameState.player.level)])

	var boss := _representative_boss()
	if boss.is_empty():
		print("[CLASS] 读不到 %s 的 bossSpawns，无法出平衡报告" % REPORT_MAP)
		get_tree().quit(1)
		return

	var rows := {}
	for class_id in PlayerClass.ids():
		rows[String(class_id)] = _measure(String(class_id), boss)
	_report(rows, boss)
	get_tree().quit(0)

## 代表 Boss：取席位里**出现次数最多**的怪 + 全部席位里**最低**的攻击倍率
## （最保守的那一只；写死会在配置调整后静默失真）。
func _representative_boss() -> Dictionary:
	var map_data: Variant = DataLoader.get_entry("maps", REPORT_MAP)
	if not (map_data is Dictionary):
		return {}
	var seats: Array = (map_data as Dictionary).get("bossSpawns", [])
	if seats.is_empty():
		return {}
	var counts := {}
	var lowest_atk := INF
	var lowest_hp := INF
	for raw in seats:
		if not (raw is Dictionary):
			continue
		var seat: Dictionary = raw
		var mid := String(seat.get("monsterId", ""))
		counts[mid] = int(counts.get(mid, 0)) + 1
		lowest_atk = minf(lowest_atk, float(seat.get("atkMultiplier", 1.0)))
		lowest_hp = minf(lowest_hp, float(seat.get("hpMultiplier", 1.0)))
	var rep := ""
	var rep_count := 0
	for raw_key in counts.keys():
		if int(counts[String(raw_key)]) > rep_count:
			rep = String(raw_key)
			rep_count = int(counts[String(raw_key)])
	var from_player: Variant = (map_data as Dictionary).get("levelFromPlayer", {})
	var min_level := Balance.SOFTCAP_LEVEL
	if from_player is Dictionary:
		min_level = int((from_player as Dictionary).get("minLevel", Balance.SOFTCAP_LEVEL))
	var map_level := maxi(min_level, int(GameState.player.level))
	var norm: Dictionary = Endgame.norm(rep)
	var scaled := Balance.scale(map_level - Balance.SOFTCAP_LEVEL)
	return {
		"id": rep, "level": map_level, "count": rep_count, "seats": seats.size(),
		"hp": float(norm.get("hp", 0.0)) * scaled * lowest_hp,
		"atk": float(norm.get("atk", 0.0)) * scaled * lowest_atk,
		"def": float(norm.get("def", 0.0)) * scaled,
		"interval": float(DataLoader.get_entry("monsters", rep).get("attackInterval", 1.2)),
	}

## 单个职业的全部指标。**切换 `classId` 走真实派生门面**，不手工乘系数 ——
## 手工乘会漏掉「系数该乘在哪一层」这件事，而那正是 R1 要守的东西。
func _measure(class_id: String, boss: Dictionary) -> Dictionary:
	GameState.player.classId = class_id
	var max_hp := float(GameState.max_hp())
	var max_mp := float(GameState.max_mp())
	var attack := float(GameState.total_attack())
	var defense := float(GameState.total_defense())
	var interval := float(GameState.total_attack_interval())
	var crit_exp := 1.0 + float(GameState.total_crit_chance()) * (float(GameState.total_crit_multiplier()) - 1.0)
	var dps := attack * crit_exp / maxf(0.01, interval)

	# 玩家 → Boss：破防是差值，所以「攻击 +8%」在高防目标上远不止 8% 伤害，必须实算。
	var per_hit_out := maxf(1.0, attack * crit_exp - float(boss.get("def", 0.0)) * 0.5)
	var ttk := float(boss.get("hp", 1.0)) / maxf(1.0, per_hit_out / maxf(0.01, interval))

	# Boss → 玩家：每击 + 保底口径（`monster.gd::_min_hit_on_player()`）。
	var min_hit := clampi(int(round(max_hp * 0.0025)), 10, 60)
	var raw_hit := float(boss.get("atk", 0.0)) - defense * 0.5
	var per_hit_in := raw_hit if raw_hit > 0.0 else float(min_hit)
	var shield_pct := 0.0
	var shield_skill: Variant = DataLoader.get_entry("skills", "magic_shield")
	if shield_skill is Dictionary and HotbarConfig.usable_skill("magic_shield", class_id):
		shield_pct = float((shield_skill as Dictionary).get("effects", {}).get("damageToManaPct", 0.0))
	var shielded_hit := per_hit_in * (1.0 - shield_pct)
	var mana_per_hit := per_hit_in * shield_pct
	var interval_boss := maxf(0.1, float(boss.get("interval", 1.2)))
	return {
		"max_hp": max_hp, "max_mp": max_mp, "attack": attack, "defense": defense,
		"interval": interval, "dps": dps,
		"per_hit_out": per_hit_out, "ttk": ttk,
		"per_hit_in": per_hit_in, "shielded_hit": shielded_hit, "mana_per_hit": mana_per_hit,
		"survive_sec": max_hp / maxf(1.0, per_hit_in / interval_boss * HIT_RATE_FACTOR),
		"survive_sec_shield": max_hp / maxf(1.0, shielded_hit / interval_boss * HIT_RATE_FACTOR),
		"mana_drain": mana_per_hit / interval_boss * HIT_RATE_FACTOR,
	}

func _report(rows: Dictionary, boss: Dictionary) -> void:
	print("")
	print("[CLASS] Boss 代表 %s ×%.0f 席（共 %d 席）Lv%d  hp=%.0f atk=%.0f def=%.0f interval=%.2fs" % [
		String(boss.get("id", "")), float(boss.get("count", 0)), int(boss.get("seats", 0)),
		int(boss.get("level", 0)), float(boss.get("hp", 0)), float(boss.get("atk", 0)),
		float(boss.get("def", 0)), float(boss.get("interval", 1.2))])
	for class_id in rows.keys():
		var r: Dictionary = rows[class_id]
		print("[CLASS] %-7s hp=%.0f mp=%.0f atk=%.0f def=%.0f interval=%.3f 期望DPS=%.0f" % [
			String(class_id), float(r.max_hp), float(r.max_mp), float(r.attack), float(r.defense),
			float(r.interval), float(r.dps)])
		print("[CLASS] %-7s 每击对 Boss=%.0f ⇒ 击杀 %.1fs；挨每击 %.0f（开盾 %.0f / 转蓝 %.0f）" % [
			String(class_id), float(r.per_hit_out), float(r.ttk), float(r.per_hit_in),
			float(r.shielded_hit), float(r.mana_per_hit)])
		print("[CLASS] %-7s 裸站存活 %.1fs / 开盾 %.1fs；护盾蓝耗 %.0f/s" % [
			String(class_id), float(r.survive_sec), float(r.survive_sec_shield), float(r.mana_drain)])

	var base: Dictionary = rows.get("warrior", {})
	if base.is_empty():
		return
	print("")
	print("[CLASS] ======== 比值（相对 warrior，工程 98 §5.1 判据）========")
	for class_id in rows.keys():
		if String(class_id) == "warrior":
			continue
		var r: Dictionary = rows[class_id]
		print("[CLASS] %-7s 击杀耗时 ×%.3f（应 0.90—1.00）｜开盾存活 ×%.3f（应 0.85—1.15）｜断盾存活 ×%.3f（应 ≥1.50）" % [
			String(class_id),
			float(r.ttk) / maxf(0.001, float(base.ttk)),
			float(r.survive_sec_shield) / maxf(0.001, float(base.survive_sec)),
			float(r.survive_sec) / maxf(0.001, float(base.survive_sec))])
		print("[CLASS] %-7s 血池 ×%.3f（hpMult=%.2f）｜蓝池 ×%.3f（mpMult=%.2f）｜攻击 ×%.3f" % [
			String(class_id),
			float(r.max_hp) / maxf(1.0, float(base.max_hp)), PlayerClass.mult("hpMult", String(class_id)),
			float(r.max_mp) / maxf(1.0, float(base.max_mp)), PlayerClass.mult("mpMult", String(class_id)),
			float(r.attack) / maxf(1.0, float(base.attack))])

	# 蓝收支：三档蓝药供给 - 护盾消耗 - 技能循环（按单次循环总蓝耗 / 平均 CD 摊）。
	var mage: Dictionary = rows.get("mage", {})
	if mage.is_empty():
		return
	var supply := 0.0
	for pid in ["potion_mp_small", "potion_mp_mid", "potion_mp_large"]:
		var tpl: Variant = DataLoader.get_entry("potions", pid)
		if not (tpl is Dictionary):
			continue
		supply += float(mage.max_mp) * float((tpl as Dictionary).get("restorePercent", 0.0)) \
			/ maxf(1.0, float((tpl as Dictionary).get("cooldown", 1.0)))
	var cycle_per_sec := 0.0
	for sid in PlayerClass.active_skills("mage"):
		var tpl: Variant = DataLoader.get_entry("skills", String(sid))
		if not (tpl is Dictionary) or bool((tpl as Dictionary).get("basic", false)):
			continue
		var cd := maxf(1.0, float((tpl as Dictionary).get("cooldown", 1.0)))
		cycle_per_sec += _pct_of(String(sid)) * float(mage.max_mp) / cd
	print("")
	print("[CLASS] 蓝收支：药水供给 %.0f/s（%.2f%%/s）− 护盾 %.0f/s（%.2f%%/s）− 技能循环 %.0f/s（%.2f%%/s）= %.2f%%/s" % [
		supply, supply / maxf(1.0, float(mage.max_mp)) * 100.0,
		float(mage.mana_drain), float(mage.mana_drain) / maxf(1.0, float(mage.max_mp)) * 100.0,
		cycle_per_sec, cycle_per_sec / maxf(1.0, float(mage.max_mp)) * 100.0,
		(supply - float(mage.mana_drain) - cycle_per_sec) / maxf(1.0, float(mage.max_mp)) * 100.0])

func _pct_of(skill_id: String) -> float:
	var tpl: Variant = DataLoader.get_entry("skills", skill_id)
	return float((tpl as Dictionary).get("manaCostPct", 0.0)) if tpl is Dictionary else 0.0

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
	GameState.player.classId = PlayerClass.normalize(String((p as Dictionary).get("classId", "")))
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
