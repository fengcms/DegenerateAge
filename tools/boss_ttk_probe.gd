extends Node
## 循环图 Boss 承伤探针（工程 92 / 94）。
##
## 用途：改任何循环图 Boss 的攻击倍率之前，先跑一遍拿到「每击伤害 / 单只战斗掉血 /
## 承伤速率 / 药水收支 / 击杀耗时」。读的是**真实链路**
## （读真实存档的装备 → `EquipmentMath` 派生 → `GameState.max_hp()/total_defense()`
## → `Endgame.norm()` + `Balance.scale()` 复原 Boss），不是估算。
##
## ⚠ 它**不是权威**：权威是 `monster.gd` / `game_state.gd` / `balance.gd` / `combat.gd`。
##   改公式必须同步这里；装备词条随机 ⇒ 造装备时绝对值有 ±5% 波动，**比例才是指标**。
##
## 运行：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/boss_ttk_probe.tscn`
## （不在 `tests/` 下，故不会被 `run_isolated_tests.py --all` 的 `tests/*.tscn` 扫到。）

## 要复算的地图（按顺序输出）。每个记录取该图**席位里出现次数最多**的怪物作代表，
## 并额外报出该图所有怪物的攻击间隔区间 —— 百首禁域混着 1.4s / 1.5s / 1.8s 三档。
const REPORTS: Array = ["c7_boss_field", "c7_solo_boss"]

## 优先读真实存档（存在则用它的等级与装备复算，最贴近实机）；不存在才造一套满星紫装。
## 🔴 只读不写：绝不调用 SaveManager，避免触发迁移 / 回写。
const REAL_SAVE := "user://saves/slot_3.json"
const FALLBACK_LEVEL := 100
const FALLBACK_QUALITY := "legendary"
const FALLBACK_STAR := 12

## 站桩承伤按「处于近战范围内的时间」折算：Boss 有追击/前摇，实测每秒约 0.55 次出手
## （interval 1.8 ⇒ 0.56；interval 1.4 ⇒ 0.71，狂暴后更低）。这里保守取 0.55。
const HIT_RATE_FACTOR := 0.55

## 药水供给缓存（`_ready` 里按真实 max_hp 算好，扫描表直接读）。
var SUPPLY_CACHE := 0.0
var BIG_ONLY_CACHE := 0.0

func _ready() -> void:
	var used_save := _load_real_save()
	if not used_save:
		_dress(FALLBACK_QUALITY, FALLBACK_STAR)
		GameState.player.level = FALLBACK_LEVEL
	print("[PROBE] 数据源=%s  玩家等级=%d" % [
		REAL_SAVE if used_save else "（造装备）", int(GameState.player.level)])

	var max_hp := float(GameState.max_hp())
	var defense := float(GameState.total_defense())
	var attack := float(GameState.total_attack())
	var interval := float(GameState.total_attack_interval())
	var crit_chance := float(GameState.total_crit_chance())
	var crit_mult := float(GameState.total_crit_multiplier())
	var crit_exp := 1.0 + crit_chance * (crit_mult - 1.0)
	var dps := attack * crit_exp / maxf(0.01, interval)
	print("[PROBE] 玩家 max_hp=%.0f  def=%.0f  atk=%.0f  interval=%.3f  crit=%.2f%%×%.2f" % [
		max_hp, defense, attack, interval, crit_chance * 100.0, crit_mult])
	print("[PROBE] 期望 DPS=%.0f  破防线 def×0.5=%.0f" % [dps, defense * 0.5])

	# 药水供给（按 max_hp 百分比恢复，各档独立 CD）——扫描表要用，先算好缓存。
	for pid in ["potion_hp_small", "potion_hp_mid", "potion_hp_large"]:
		var tpl: Dictionary = DataLoader.get_entry("potions", pid)
		var pct := float(tpl.get("restorePercent", 0.0))
		var cd := float(tpl.get("cooldown", 1.0))
		SUPPLY_CACHE += max_hp * pct / cd
		if pid == "potion_hp_large":
			BIG_ONLY_CACHE = max_hp * pct / cd
		print("[PROBE] %s 回复 %.0f / CD %.0fs = %.0f/s" % [pid, max_hp * pct, cd, max_hp * pct / cd])
	print("[PROBE] 药水供给：三档全开 %.0f/s；只用大红 %.0f/s" % [SUPPLY_CACHE, BIG_ONLY_CACHE])

	for raw in REPORTS:
		_report(String(raw), max_hp, defense, dps)
	get_tree().quit(0)

## 复算单张图：优先取席位里出现最多的怪物当代表。
func _report(map_id: String, max_hp: float, defense: float, dps: float) -> void:
	var map_data: Variant = DataLoader.get_entry("maps", map_id)
	if not (map_data is Dictionary):
		print("[PROBE] %s：地图不存在" % map_id)
		return
	var md: Dictionary = map_data
	var seats: Array = []
	var raw_seats: Variant = md.get("bossSpawns", [])
	if raw_seats is Array:
		seats = raw_seats
	if seats.is_empty():
		print("[PROBE] %s：没有 bossSpawns" % map_id)
		return

	# 席位统计：怪物出现次数 / 攻击间隔区间 / 倍率（全部席位必须一致，否则这里会报出来）
	var counts := {}
	var intervals := {}
	var mult_set := {}
	for raw in seats:
		if not (raw is Dictionary):
			continue
		var seat: Dictionary = raw
		var mid := String(seat.get("monsterId", ""))
		counts[mid] = int(counts.get(mid, 0)) + 1
		var tpl: Variant = DataLoader.get_entry("monsters", mid)
		var iv := 1.2
		if tpl is Dictionary:
			iv = float((tpl as Dictionary).get("attackInterval", 1.2))
		intervals[mid] = iv
		mult_set["hp=%.2f atk=%.2f respawn=%s" % [
			float(seat.get("hpMultiplier", 1.0)),
			float(seat.get("atkMultiplier", 1.0)),
			str(seat.get("respawnTime", "-"))]] = true

	var rep_id := ""
	var rep_count := 0
	for raw_key in counts.keys():
		var k := String(raw_key)
		if int(counts[k]) > rep_count:
			rep_id = k
			rep_count = int(counts[k])
	var rep_interval := float(intervals.get(rep_id, 1.2))
	var seat0: Dictionary = seats[0]
	var atk_mult := float(seat0.get("atkMultiplier", 1.0))
	var hp_mult := float(seat0.get("hpMultiplier", 1.0))

	print("")
	print("[PROBE] ======== %s（%s）========" % [map_id, String(md.get("name", ""))])
	print("[PROBE] 席位 %d / 怪物 %d 种 / 代表 %s（%d 席, interval=%.2fs）" % [
		seats.size(), counts.size(), rep_id, rep_count, rep_interval])
	var iv_list: Array = []
	for raw_key in intervals.keys():
		iv_list.append("%s=%.2f" % [String(raw_key), float(intervals[raw_key])])
	iv_list.sort()
	print("[PROBE] 各怪攻击间隔：%s" % ", ".join(iv_list))
	var mult_list: Array = []
	for raw_key in mult_set.keys():
		mult_list.append(String(raw_key))
	mult_list.sort()
	print("[PROBE] 席位倍率组合：%s" % " | ".join(mult_list))

	var level_from_player: Variant = md.get("levelFromPlayer", {})
	var min_level := Balance.SOFTCAP_LEVEL
	if level_from_player is Dictionary:
		min_level = int((level_from_player as Dictionary).get("minLevel", Balance.SOFTCAP_LEVEL))
	var boss_level := maxi(min_level, int(GameState.player.level))
	var scaled := Balance.scale(boss_level - Balance.SOFTCAP_LEVEL)

	var norm: Dictionary = Endgame.norm(rep_id)
	var boss_hp := float(norm.get("hp", 0)) * scaled * hp_mult
	var boss_atk := float(norm.get("atk", 0)) * scaled
	var boss_def := float(norm.get("def", 0)) * scaled
	print("[PROBE] S(%d)=%.4f  Boss Lv%d  hp=%.0f（血 ×%.1f）  基础攻=%.0f  防御=%.0f" % [
		boss_level - Balance.SOFTCAP_LEVEL, scaled, boss_level, boss_hp, hp_mult, boss_atk, boss_def])

	# 玩家 → Boss：击杀一只要多久
	var player_hit := float(GameState.total_attack()) - boss_def * 0.5
	var ttk := boss_hp / maxf(1.0, dps)
	print("[PROBE] 玩家每击对 Boss=%.0f（Boss 防×0.5=%.0f）⇒ 击杀一只 %.1f 秒" % [
		player_hit, boss_def * 0.5, ttk])

	var threshold := defense * 0.5 / maxf(1.0, boss_atk)
	print("[PROBE] 🔑 破防阈值 = %.2f 倍（低于它就是保底 %d）" % [
		threshold, clampi(int(round(max_hp * 0.0025)), 10, 60)])

	# 倍率扫描：核心指标是「单只战斗期间掉多少血」而不是「能撑多久」
	# —— 百首禁域击杀只要十几秒，裸站死的时间永远大于战斗时长，那个数字没意义。
	var hits_per_kill := ttk / rep_interval * HIT_RATE_FACTOR
	print("[PROBE] 单只战斗期间约挨 %.1f 击（interval %.2fs × %.2f 出手率）" % [
		hits_per_kill, rep_interval, HIT_RATE_FACTOR])
	print("[PROBE] 倍率   实攻   每击   占血%%  单只掉血%%  承伤/s  60s 连刷掉血%%  三档药净/s  大红净/s")
	var mults: Array = [1.0, threshold, 2.6, 2.8, 3.0, 3.2, 3.5]
	if not mults.has(atk_mult):
		mults.append(atk_mult)
	mults.sort()
	for raw_mult in mults:
		var m := float(raw_mult)
		var atk2 := boss_atk * m
		var per_hit := atk2 - defense * 0.5
		var floor_hit := clampi(int(round(max_hp * 0.0025)), 10, 60)
		var eff_hit := per_hit if per_hit > 0.0 else float(floor_hit)
		var per_kill_loss := eff_hit * hits_per_kill / max_hp * 100.0
		var rate := eff_hit / rep_interval * HIT_RATE_FACTOR
		var per_60 := rate * 60.0 / max_hp * 100.0
		var tag := "  ← 当前配置" if is_equal_approx(m, atk_mult) else ""
		print("[PROBE] x%.2f  %5.0f  %5.0f  %5.2f%%  %6.1f%%    %5.0f   %6.1f%%      %+6.0f     %+6.0f%s" % [
			m, atk2, eff_hit, eff_hit / max_hp * 100.0, per_kill_loss, rate, per_60,
			SUPPLY_CACHE - rate, BIG_ONLY_CACHE - rate, tag])

	# 被 3 只围（百首禁域同屏 18 只、腐化巨兽还会召唤）是最坏情况
	var per_hit_now := boss_atk * atk_mult - defense * 0.5
	var eff_now := per_hit_now if per_hit_now > 0.0 else float(clampi(int(round(max_hp * 0.0025)), 10, 60))
	var rate3 := eff_now / rep_interval * HIT_RATE_FACTOR * 3.0
	print("[PROBE] 当前配置下被 3 只围：承伤 %.0f/s（三档药 %.0f/s、大红 %.0f/s）⇒ %s" % [
		rate3, SUPPLY_CACHE, BIG_ONLY_CACHE,
		"药能兜住" if rate3 < SUPPLY_CACHE else "会掉血，需要走位"])

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
