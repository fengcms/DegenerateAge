class_name AutoBattle
extends Node
## 自动战斗 / 自动拾取决策机（产品文档 3.14；4.6 手动接管；9.9 拾取）。
##
## 挂为 Player 的子节点（Player.tscn → AutoPilot），只做**决策**——
## 移动与攻击仍调用玩家自身接口（`set_auto_move` / `try_auto_attack`），
## 与手动操作共用同一条代码路径，不另写一套战斗逻辑（3.14 原则）。
##
## 状态机（3.14）：
##   OFF / SEARCH_TARGET / PATH_TO_TARGET / ATTACK_TARGET /
##   SEARCH_LOOT / PATH_TO_LOOT / PICK_UP / RECOVER / MANUAL_OVERRIDE / BLOCKED
##
## 硬性异常规则（3.14「必须实现」）逐条落地：
##   ① 连续 5 次「角色无位移」→ 目标短期黑名单重搜（T08 不可达改选；口径见工程文档 69 §5 P1）；
##   ①′ 黑名单 3s + 目标粘性：只要原目标仍有有效、仍可达，重选就回到它（P2，同上 §5）；
##   ② 目标消失 / 死亡 / 切图 → 停旧指令（每帧校验目标有效性）；
##   ③ 手动接管 → 立即取消、松手后 1.5 秒恢复（4.6）；
##   ④ 背包满 → 不走向该掉落物、不循环重试（T10，靠节流 + 目标剔除，不做每帧重试）；
##   ⑤ MP / 冷却不足 → 不施放该技能（T11，见 choose_skill）；
##   ⑥ 死亡 → 自动转 off；真正暂停与 NPC 对话 → 停决策；普通面板与窗口失焦仍继续挂机。
##
## M1 范围说明（见工程文档 02 / 产品文档 03 §3.14）：
##   · 玩家 Lv1 仅解锁普攻 basic_slash，故本阶段实际施放普攻；`choose_skill`
##     的 MP / 冷却 / 等级判据已按 3.14 完整实现并纳入回归（T11），
##     待 M3 技能系统接线后由 `WIRED_SKILLS` 放开即可直接生效；
##   · **药水已接线（M2.5）**：生命/法力各自达到阈值时自动喝对应药（同时不足时先红后蓝）；
##     **药尽仍继续战斗**（Q5 拍板，不再停战）——见工程文档 12；
##   · 地图为无障碍开阔地，接近采用「直线趋近 + 节流重算」替代 A*；
##     卡住检测与黑名单机制与地图形态无关，M3 换 TileMap 后可直接复用。
##   · G 关时掉落留地待点击；F/G 同开时，附近可收取的地面物优先于怪物。
##     已认领物从 `ground_items` 脱组；背包无空间的物品不进入寻物决策。

enum State {
	OFF,
	SEARCH_TARGET,
	PATH_TO_TARGET,
	ATTACK_TARGET,
	SEARCH_LOOT,
	PATH_TO_LOOT,
	PICK_UP,
	RECOVER,
	MANUAL_OVERRIDE,
	BLOCKED,
	ROAM,
}

# ---- 节流与阈值（初始参数，试玩校准）----
const SEARCH_INTERVAL := 0.35          # 搜怪节流（s）：无目标待机时不得每帧搜索
const REPATH_INTERVAL := 0.25          # 接近方向重算节流（s）
const STUCK_INTERVAL := 0.3            # 卡住检测间隔（s）
## P1（工程文档 69 §5）：追击期的卡住判据是「角色本间隔内的**自身位移**」，
## 不再是「与目标的直线距离」——绕障时直线距离可能不降甚至变大，被 Boss 技能击退 / 倒地时同样如此，
## 用距离判据会把这两种**正常**情况误判成「不推进」并把 Boss 拉黑改选。
const STUCK_MOVE_EPS := 4.0            # 单次检测内角色自身的最小位移（px）；低于它才算一次「没动」
## 巡游（`_tick_roam`）与手动点击行走（`player.gd::_map_direction`）仍用**折线推进量**判据。
const STUCK_PROGRESS_EPS := 6.0        # 两次检测间的最小接近量（px）
const STUCK_LIMIT := 5                 # 连续「没动」次数上限 → 黑名单（3.14 ①，约 1.5s）
## P2（工程文档 69 §5）：8s 黑名单足够跑去把隔壁一只打完，「中途换 Boss」于是变成事实；
## 收到 3s，并用下面的粘性记忆在黑名单到点后把原目标捡回来。
const BLACKLIST_TIME := 3.0            # 目标黑名单时长（s）
const STICKY_TIME := 4.0               # 目标粘性记忆时长（s，= 黑名单 + 1s 宽限）
const MANUAL_RESUME_DELAY := 1.5       # 手动接管后恢复延迟（s，4.6）
const BLOCKED_TIME := 1.0             # 受阻停留（s）
const LOOT_SEARCH_RADIUS := 6.0        # 顺路拾取搜索半径（格）
const LOOT_ARRIVE_EPS := 6.0           # 判定「已抵达掉落物」（px；≤1.5 格由 GroundItem 自动入包）
const STOP_GAP := 8.0                  # 攻击范围内提前停步（px，避免与目标互相顶开）
const ROAM_GRID_STEP := 7               # 巡游采样间隔（格），往返覆盖地图有效区域
const ROAM_ARRIVE_EPS := 12.0
## 喝药阈值兜底值（3.14 设置项）。正式取值一律读 `GameState.settings.potionThreshold`，
## 本常量仅在该字段缺失时生效——避免「常量 + 设置」两个事实源（M2.5 收敛，见工程文档 12 §3.4）。
const DEFAULT_POTION_THRESHOLD := 0.35
const DANGER_TOAST_CD := 4.0           # 「危险血量」提示节流（s）
## 百 Boss 图预留至少 32 件单次掉落空间；达到阈值时停自动战斗，手动击杀仍保全奖励。
const BOSS_LOOT_RESERVE := 32

## 已接线的自动施放范围技；普攻由攻击间隔单独驱动，不进此表。
## R4-d：`spirit_storm`（L40，circle × 3 段）在 `_best_area_skill` 里按「命中数 × 总系数」参评。
const WIRED_SKILLS: Array[String] = ["earth_cleave", "whirlwind", "spirit_storm"]
## R4-d：单体技能单独一条路径 —— 范围技要求 ≥2 只才放，单体技（破甲重击）正是用来打单个硬目标。
const WIRED_SINGLE_SKILLS: Array[String] = ["armor_break"]
## 工程 98：法师的接线白名单。**必须与 `skills.json` 里引擎真实支持的能力对齐** ——
## 火焰喷发 / 冰咆哮 / 陨石术走 `hits` + `debuff`（已实现），雷电术走 `defensePierce`（已实现）。
const MAGE_AREA_SKILLS: Array[String] = ["flame_burst", "frost_roar", "meteor"]
const MAGE_SINGLE_SKILLS: Array[String] = ["lightning"]
## 工程 98 §4.6 低蓝保盾：低于 25% 停攻击技能、回到 40% 恢复。
## 不实现这条，挂机法师会在蓝见底时「盾断 + 继续挥技能」，两头落空。
const MAGE_LOW_MANA := 0.25
const MAGE_MANA_RESUME := 0.40
## 自动补盾提前量；基础冷却 10 秒、持续 30 秒，避免恰好到期时出现断档。
const MAGE_SHIELD_REFRESH_WINDOW := 5.0

var _player: PlayerCharacter = null
var _state: int = State.OFF
var _phase: String = ""

var _target: Node = null
var _loot: Node = null

var _search_t: float = 0.0
var _repath_t: float = 0.0
var _stuck_t: float = 0.0
var _stuck_count: int = 0
var _blocked_t: float = 0.0
var _manual_t: float = 0.0
var _danger_t: float = 0.0
## 工程 95：自动四金合紫的节流计时（s）。同时是「一次只合一组」的天然限速 ——
## 否则一开开关会把背包里 20 组存量料连合成渣，金币瞬间见底。
var _auto_forge_t: float = 0.0
var _roam_points: Array[Vector2] = []
var _roam_index: int = -1
var _roam_built := false
var _roam_ground: IsoGround
var _roam_revision := -1
var _roam_component := 0
var _roam_last_dist := INF
var _roam_stuck_t := 0.0
var _roam_stuck_count := 0
## 工程 98 §4.6：法师低蓝保盾的滞回状态（低于 25% 进、回到 40% 出）。
var _mana_saver := false
var _cave_nav := CaveNavigator.new()
var _last_position := Vector2.INF

## instance_id → 剩余秒数（短期黑名单，3.14 ①）
var _blacklist: Dictionary = {}
## P2 目标粘性：上一只因「确实走不动」被拉黑的候选。黑名单一到点、它仍有效且可达时优先回去，
## 否则「就近重选」必然落到隔壁那只 —— 那正是「打一半绕出去打别的 Boss」的观感来源。
var _sticky_target: Node = null
var _sticky_left := 0.0

func _ready() -> void:
	_player = get_parent() as PlayerCharacter
	if _player == null:
		push_warning("[AutoBattle] 必须作为 PlayerCharacter 的子节点")
	EventBus.auto_state_changed.connect(_on_auto_state_changed)  # G-P2-2：生命周期约定见 event_bus.gd 顶部。
	_on_auto_state_changed(GameState.auto_battle_on, GameState.auto_pickup_on)
	set_physics_process(true)

## 开启自动战斗时重置搜索节流。
func _on_auto_state_changed(battle: bool, _pickup: bool) -> void:
	if battle and _player != null:
		_search_t = 0.0
		_repath_t = 0.0
		_stuck_count = 0
		_last_position = Vector2.INF
		_cave_nav.clear()
		_blacklist.clear()
		_sticky_target = null
		_sticky_left = 0.0
		_roam_index = -1
	else:
		_target = null
		_loot = null
		_roam_index = -1

## 切图/读档后丢弃旧世界的目标、走位与攻击意图；保留 F/G 开关。
func reset_after_travel() -> void:
	if _player == null:
		return
	_player.clear_travel_intent()
	_target = null
	_loot = null
	_sticky_target = null
	_sticky_left = 0.0
	_roam_index = -1
	_roam_points.clear()
	_roam_built = false
	_roam_ground = null
	_cave_nav.clear()
	_last_position = Vector2.INF
	_manual_t = 0.0
	_blocked_t = 0.0
	_search_t = 0.0
	_repath_t = 0.0
	if not GameState.auto_battle_on:
		_set_state(State.OFF)
	else:
		_set_state(State.SEARCH_TARGET)

## 当前地图是否启用「未领取战利品停战」；返回地图 id（空 = 不启用）。
##
## 🔑 判据只看**数据**（`preserveUnclaimedLoot` + `unclaimedLootCap > 0`），不认地图 id 白名单：
## 工程 88 之前的写法是 `current_map == "c7_boss_field"`，于是每新增一张同类图都会**静默**少一层
## 保护。真正的分界不是「哪张图」，而是「这张图会不会按 FIFO 淘汰未领取奖励」。
func _loot_guard_map() -> String:
	var data: Variant = MapService.data_for(GameState.current_map)
	if not data is Dictionary:
		return ""
	if not bool((data as Dictionary).get("preserveUnclaimedLoot", false)):
		return ""
	if int((data as Dictionary).get("unclaimedLootCap", 0)) <= 0:
		return ""
	return GameState.current_map

func _physics_process(delta: float) -> void:
	_tick_blacklist(delta)
	if _player == null or not is_instance_valid(_player):
		return

	# 关闭：一律回到 OFF（优先于手动接管计时，保证随时关得掉）
	if not GameState.auto_battle_on:
		if _state != State.OFF:
			_player.set_auto_move(Vector2.ZERO)
			_target = null
			_loot = null
			_manual_t = 0.0
			_blocked_t = 0.0
			_set_state(State.OFF)
		return

	# ⑥ 死亡 → 自动转 off（4.7 / 3.14）。
	# 必须排在「手动接管计时」之前：否则接管期间阵亡会因计时未走完而漏关。
	if _player.is_dead:
		_player.set_auto_move(Vector2.ZERO)
		_manual_t = 0.0
		GameState.set_auto_battle(false)
		_set_state(State.OFF)
		return
	# 未领取战利品停战：判据改为**数据驱动**（工程 91）。
	# 🔴 原来是写死 `current_map == "c7_boss_field"` + 中文文案，新增循环图时天然没有这层保护 ——
	# 而 `preserveUnclaimedLoot` 地图一旦超过 `unclaimedLootCap`，超出部分会被按 FIFO 静默删除，
	# 也就是「打着打着奖励没了」且玩家毫无提示。凡是配了 `preserveUnclaimedLoot` 的图都必须进这里。
	if _loot_guard_map() != "" and GameState.unclaimed_count(GameState.current_map) \
			>= GameState.unclaimed_loot_cap(GameState.current_map) - BOSS_LOOT_RESERVE:
		_player.set_auto_move(Vector2.ZERO)
		GameState.set_auto_battle(false)
		EventBus.toast_requested.emit(
			Localization.tr_key("msg.auto_battle.loot_cap",
				[MapService.display_name(GameState.current_map)]), "danger")
		_set_state(State.OFF)
		return
	if _player.is_sitting:
		_player.set_auto_move(Vector2.ZERO)
		_target = null
		_loot = null
		_set_state(State.RECOVER, Localization.tr_key("ui.auto.sitting"))
		return
	# 工程 101：面板打开**不再**打断挂机（原 NPC 会话档已拆）。挂机停不停只由
	# 「世界在不在跑」决定 —— 真正的暂停由引擎冻结本节点，下面这段是给
	# PROCESS_MODE 调整后留的显式兜底，正常路径不会走到。
	if get_tree().paused:
		_player.set_auto_move(Vector2.ZERO)
		_set_state(State.RECOVER, Localization.tr_key("ui.auto.paused"))
		return

	# 持续手动操作先刷新计时；松手后才开始倒计时，避免按住时提前恢复。
	if _player.map_move_active or _player.manual_attack_active or (not GameState.world_controls_blocked() and _has_manual_input()):
		begin_manual_override()
		return
	if _manual_t > 0.0:
		_manual_t = maxf(0.0, _manual_t - delta)
		if _manual_t > 0.0:
			_set_state(State.MANUAL_OVERRIDE, Localization.tr_key("ui.auto.manual_countdown") % _manual_t)
			return
		_toast(Localization.tr_key("ui.auto.resumed"), "info")
		_set_state(State.SEARCH_TARGET)

	_tick(delta)

## 输入事件到达即可取消旧决策，不依赖下一物理帧。
func begin_manual_override() -> void:
	_player.set_auto_move(Vector2.ZERO)
	_target = null
	_loot = null
	# 手动接管是玩家的新指令：清掉粘性记忆，避免 1.5s 后自动战斗把人物带回原来的 Boss（4.6）。
	_sticky_target = null
	_sticky_left = 0.0
	_roam_index = -1
	_manual_t = MANUAL_RESUME_DELAY if GameState.auto_battle_on else 0.0
	if GameState.auto_battle_on:
		_set_state(State.MANUAL_OVERRIDE, Localization.tr_key("ui.auto.manual_wait"))

# ---- 决策主体 ----

func _tick(delta: float) -> void:
	# 工程 95：自动四金合紫。放在所有分支之前 —— 追击 / 拾取 / 巡游任一状态下都该继续合成，
	# 它不依赖拾取事件（背包里已有的存量料，一开开关也能被处理）。
	_tick_auto_forge(delta)

	# 受阻停留（3.14 ① 拉黑目标后的短暂停顿，避免同帧立即重选）
	if _blocked_t > 0.0:
		_blocked_t = maxf(0.0, _blocked_t - delta)
		_player.set_auto_move(Vector2.ZERO)
		_set_state(State.BLOCKED)
		return

	# 生命和法力各自按设置阈值判断；两者都不足时先保命，下一帧再补法力。
	# 药尽仍继续战斗，不因任一颜色缺药而停寻怪。
	var hp_low := _needs_potion(Consumable.KIND_RED)
	if hp_low and _try_drink(Consumable.KIND_RED):
		_danger_t = 0.0
		return
	if _needs_potion(Consumable.KIND_BLUE) and _try_drink(Consumable.KIND_BLUE):
		return
	if hp_low:
		_danger_t = maxf(0.0, _danger_t - delta)       # 无药 / 全在冷却 → 继续战斗（不停战）
		if _danger_t <= 0.0:
			_danger_t = DANGER_TOAST_CD
			_toast(Localization.tr_key("ui.auto.low_hp_no_potion"), "danger")
	else:
		_danger_t = 0.0

	# 工程 98：法师保盾优先于一切攻击决策 —— 盾断了等于把 30% 伤害从法力搬回血条。
	if _tick_mage_shield():
		return

	# ② 每帧校验目标有效性（死亡 / 释放 / 进黑名单 → 停旧指令）
	if _target != null and (not is_instance_valid(_target)
			or _target.get("is_dead") == true or _is_blacklisted(_target)):
		_target = null
		_stuck_count = 0

	# F/G 同开时优先捡可收取的地面物；背包无空间时 _can_pick 会将其排除。
	if GameState.auto_pickup_on and _tick_loot():
		return
	_loot = null

	if _target == null:
		_search_t = maxf(0.0, _search_t - delta)
		if _search_t <= 0.0:
			_search_t = SEARCH_INTERVAL
			_target = _find_target()
			if _target != null:
				_roam_index = -1
				# A new target must not inherit the previous roam/target direction.
				_repath_t = 0.0
				_player.set_auto_move(Vector2.ZERO)
				_player.select_target(_target as Node2D, _player.target_is_manual and _player.locked_target == _target)
				_stuck_count = 0
				_last_position = Vector2.INF
				_cave_nav.clear()
		if _target == null:
			_tick_roam(delta)
		return

	var target2d := _target as Node2D
	var dist := _player.global_position.distance_to(target2d.global_position)
	# 工程 98 P2：停步距离必须跟**职业射程**走（法师 4 格）。改这一行即可让挂机在 4 格停住放技能。
	var reach := _player.attack_range_px() - STOP_GAP

	# 安全区只屏蔽伤害，不屏蔽寻怪/移动。靠近边缘目标时先穿出边界再攻击。
	if dist > reach or MapService.is_in_safe_area(GameState.current_map, _player.global_position):
		_set_state(State.PATH_TO_TARGET)
		if _cave_ground() != null and _direction_to(target2d.global_position) == Vector2.ZERO:
			_blacklist_target(_target)
			return
		_tick_stuck(delta)
		if _blocked_t > 0.0:
			return
		_repath_t = maxf(0.0, _repath_t - delta)
		if _repath_t <= 0.0:
			_repath_t = REPATH_INTERVAL
			_player.set_auto_move(_direction_to(target2d.global_position))
		return

	# 已在攻击范围内 → 停步并攻击（施放节奏由玩家自身攻击冷却控制，3.9 不绕过攻速）
	_player.set_auto_move(Vector2.ZERO)
	_set_state(State.ATTACK_TARGET)
	_stuck_count = 0
	if _try_battle_focus(_target):
		return
	# 工程 98 §4.6：低蓝保盾期只普攻 —— 盾与普攻都不耗蓝，蓝会靠药水回上来。
	if not _mana_allows_attack():
		_player.try_auto_attack(_target)
		return
	var skill := _best_area_skill(_target)
	if not skill.is_empty() and _player.cast_skill(String(skill.id), _target):
		return
	var single := _best_single_skill(_target)
	if not single.is_empty() and _player.cast_skill(String(single.id), _target):
		return
	_player.try_auto_attack(_target)

## 工程 95：自动四金合紫。开关未开时把计时器清零 —— 下次开开关**立刻**尝试一组，
## 而不是先白等 2 秒（与「勾选即时生效」同口径）。
func _tick_auto_forge(delta: float) -> void:
	if not GameState.auto_forge_enabled():
		_auto_forge_t = 0.0
		return
	_auto_forge_t = maxf(0.0, _auto_forge_t - delta)
	if _auto_forge_t > 0.0:
		return
	_auto_forge_t = Durability.auto_forge_interval()
	GameState.auto_forge_gold()

## 只在真实可攻击目标已进入近战范围时启动自身增益；巡游、追路和拾取阶段均不空放。
func _try_battle_focus(target: Node) -> bool:
	# 工程 98：战意觉醒是**武士**技能。不加这一句，法师挂机每次贴脸都会花 30 点蓝放一个
	# 法力一点不影响的增益（而且技能面板里根本没有它）。
	if not HotbarConfig.usable_skill("battle_focus"):
		return false
	if not _player.valid_target(target) or not _player.is_attack_ready():
		return false
	if _player.global_position.distance_to((target as Node2D).global_position) > _player.attack_range_px():
		return false
	if GameState.buff_remaining("battle_focus") > 0.0:
		return false
	var skill := SkillProgression.current("battle_focus")
	if skill.is_empty() or int(GameState.player.level) < int(skill.get("unlockLevel", 1)):
		return false
	if int(GameState.player.mp) < GameState.skill_mana_cost(skill) or _player.skill_cooldown("battle_focus") > 0.0:
		return false
	return _player.cast_skill("battle_focus")

## 工程 98：法师自动维持魔法盾。与手动施放共用 `cast_skill`（不绕过冷却、不绕过蓝）。
## 返回 true 表示本帧已被盾占用，调用方应直接 return。
func _tick_mage_shield() -> bool:
	if not PlayerClass.is_ranged() or not HotbarConfig.usable_skill("magic_shield"):
		return false
	if GameState.buff_remaining("magic_shield") > MAGE_SHIELD_REFRESH_WINDOW:
		return false
	var skill := SkillProgression.current("magic_shield")
	if skill.is_empty() or int(GameState.player.level) < int(skill.get("unlockLevel", 1)):
		return false
	if _player.skill_cooldown("magic_shield") > 0.0 or \
			int(GameState.player.mp) < GameState.skill_mana_cost(skill):
		return false
	return _player.cast_skill("magic_shield")

## 工程 98 §4.6 低蓝保盾（滞回）：低于 25% 进省蓝态，回到 40% 才恢复。
## 武士恒为 true —— 这条策略只对「蓝是第二条血」的职业有意义。
func _mana_allows_attack() -> bool:
	if not PlayerClass.is_ranged():
		return true
	var maximum := maxi(1, GameState.max_mp())
	var ratio := float(GameState.player.mp) / float(maximum)
	if _mana_saver:
		if ratio < MAGE_MANA_RESUME:
			return false
		_mana_saver = false
	elif ratio < MAGE_LOW_MANA:
		_mana_saver = true
		return false
	return true

## 本职业已接线的范围技白名单。
func _wired_area_skills() -> Array:
	return MAGE_AREA_SKILLS if PlayerClass.is_ranged() else WIRED_SKILLS

## 本职业已接线的单体技白名单。
func _wired_single_skills() -> Array:
	return MAGE_SINGLE_SKILLS if PlayerClass.is_ranged() else WIRED_SINGLE_SKILLS

## 把百分比蓝耗折算成绝对量后交给 `choose_skill`（它只认 `manaCost`，且是纯静态函数）。
## 🔴 不做这一步，法师的每个技能在自动战斗眼里都是「0 蓝，随便放」—— 就是 R3 的空挥。
func _skill_for_choice(skill: Dictionary) -> Dictionary:
	var copy := skill.duplicate()
	copy["manaCost"] = GameState.skill_mana_cost(skill)
	return copy

## 按实际命中集合选择范围技；只有至少两只怪在技能形状内才消耗法力。
## R4-d：评分从「命中数优先」升级为「命中数 × 总系数」——否则 3 段的灵刃风暴
## （总系数 3.0）会被 1.4 的裂地斩按便宜优先挤掉，多段能力等于没接线。
func _best_area_skill(target: Node) -> Dictionary:
	if not _player.is_attack_ready():
		return {}
	var chosen := {}
	var best_value := 0.0
	for skill_id in _wired_area_skills():
		var skill := SkillProgression.current(skill_id)
		if skill.is_empty():
			continue
		var hit_count := _player.skill_targets(skill, target).size()
		if hit_count < 2 or choose_skill([_skill_for_choice(skill)], int(GameState.player.level),
			int(GameState.player.mp), _player.skill_cooldowns, hit_count).is_empty():
			continue
		var value := float(hit_count) * skill_value(skill)
		if value > best_value or (is_equal_approx(value, best_value) and
			GameState.skill_mana_cost(skill) < GameState.skill_mana_cost(chosen)):
			chosen = skill
			best_value = value
	return chosen

## R4-d：单体技能只在真有目标时施放；评分口径与范围技共用 `skill_value`。
func _best_single_skill(target: Node) -> Dictionary:
	if not _player.is_attack_ready() or not _player.valid_target(target):
		return {}
	var chosen := {}
	for skill_id in _wired_single_skills():
		var skill := SkillProgression.current(skill_id)
		if skill.is_empty():
			continue
		if _player.skill_targets(skill, target).is_empty():
			continue
		if choose_skill([_skill_for_choice(skill)], int(GameState.player.level), int(GameState.player.mp),
			_player.skill_cooldowns, 1).is_empty():
			continue
		if chosen.is_empty() or skill_value(skill) > skill_value(chosen):
			chosen = skill
	return chosen

# ---- 自动喝药（M2.5；3.14「自动只调用与玩家相同的喝药接口」）----

## 喝药阈值（3.14 设置项，默认 35%）。
func _potion_threshold() -> float:
	return float(GameState.settings.get("potionThreshold", DEFAULT_POTION_THRESHOLD))

func _needs_potion(kind: String) -> bool:
	var maximum := Consumable.max_of(kind)
	return maximum > 0 and float(Consumable.current_of(kind)) / float(maximum) <= _potion_threshold()

## 对应资源不足时尝试指定颜色药水。返回是否成功喝到。
## 与手动喝药共用 `Consumable.use`，不另写一套实现；`silent` 抑制单次失败提示，由本层统一节流。
func _try_drink(kind: String) -> bool:
	var idx := Consumable.pick_index(kind)
	if idx < 0:
		return false
	var res := Consumable.use(idx, true)
	if not bool(res.get("ok", false)):
		return false
	_toast(Localization.tr_key("ui.auto.auto_potion") % String(res.get("message", "")), "info")
	return true

# ---- 目标搜索 ----

## 当前画面可见区域内搜索敌人（3.14）。排除 Boss（除非设置允许）、黑名单目标。
## M1 目标优先级：距离最近；同距离取血量更低者（「优先低代价 / 弱目标」的最小实现）。
## P2：「原目标仍有效且可达」这一档**优先于**「距离最近」——先回到原来那只，再谈就近（工程文档 69 §5）。
func _find_target() -> Node:
	# 明确选中的目标优先；黑名单仍生效，避免不可达目标循环。
	if _player.target_is_manual and _player.valid_target(_player.locked_target) and not _is_blacklisted(_player.locked_target):
		if _route_reachable((_player.locked_target as Node2D).global_position):
			return _player.locked_target
	# 目标粘性（P2，工程文档 69 §5）：上一只因「确实走不动」被拉黑的那只，一旦出了黑名单、
	# 仍有效且仍可达，就优先回到它 —— 只按「谁最近」重选会必然落到隔壁的 Boss 身上。
	if _sticky_left > 0.0 and _sticky_target != null and is_instance_valid(_sticky_target) \
			and _sticky_target is Node2D and _sticky_target.get("is_dead") != true \
			and not _is_blacklisted(_sticky_target) \
			and _route_reachable((_sticky_target as Node2D).global_position):
		return _sticky_target
	var allow_boss := bool(GameState.settings.get("allowBoss", false))
	var best: Node = null
	var best_dist := INF
	var best_hp := INF
	var world := get_tree().get_first_node_in_group("map_world")
	if world == null or not world.has_method("visible_enemies"):
		return null
	for e in world.visible_enemies():
		if not is_instance_valid(e) or e.get("is_dead") == true or not (e is Node2D):
			continue
		if _is_blacklisted(e):
			continue
		if not allow_boss:
			var tpl = e.get("template")
			if tpl is Dictionary and String(tpl.get("kind", "normal")) == "boss":
				continue
		if not _route_reachable((e as Node2D).global_position):
			continue
		var d := _player.global_position.distance_to((e as Node2D).global_position)
		var hp_v = e.get("hp")           # Node.get 只接受 1 个参数（无默认值重载）
		var hp := float(hp_v) if hp_v != null else 0.0
		if d < best_dist - 0.001 or (absf(d - best_dist) <= 0.001 and hp < best_hp):
			best_dist = d
			best_hp = hp
			best = e
	return best

## 寻找附近未认领的地面物（9.9）；T10：背包满时排除需要入包的掉落物。
func _find_loot() -> GroundItem:
	var radius := LOOT_SEARCH_RADIUS * Iso.TILE_W
	var best: GroundItem = null
	var best_d := INF
	for g in get_tree().get_nodes_in_group("ground_items"):
		if not (g is GroundItem):
			continue
		var gi := g as GroundItem
		if gi.item.is_empty() or not _can_pick(gi):
			continue
		var d := _player.global_position.distance_to(gi.global_position)
		if d > radius:
			continue
		if not _route_reachable(gi.global_position):
			continue
		if d < best_d:
			best_d = d
			best = gi
	return best

func _tick_loot() -> bool:
	if _loot != null and (not is_instance_valid(_loot)
			or (_loot as GroundItem).item.is_empty() or not _can_pick(_loot as GroundItem)):
		_loot = null
	if _loot == null:
		_loot = _find_loot()
		if _loot == null:
			return false
	var d := _player.global_position.distance_to((_loot as Node2D).global_position)
	if d <= LOOT_ARRIVE_EPS:
		_player.set_auto_move(Vector2.ZERO)
		_set_state(State.PICK_UP)                 # 进入 1.5 格后由 GroundItem 自动入包（9.9）
		return true
	_set_state(State.PATH_TO_LOOT)
	var direction := _direction_to((_loot as Node2D).global_position)
	_player.set_auto_move(direction)
	if _cave_ground() != null and direction == Vector2.ZERO:
		_loot = null
		return false
	return true

## 无可见怪物时按地图有效格往返巡游；每个物理帧仍走上方的节流搜怪。
func _tick_roam(delta: float) -> void:
	var ground := _cave_ground()
	var revision := ground.cave.navigation_revision if ground != null else -1
	var component := ground.cave.component_at(Vector2i(Iso.world_to_grid(_player.global_position).round())) if ground != null else 0
	if not _roam_built or ground != _roam_ground or revision != _roam_revision or component != _roam_component:
		_build_roam_points()
	if _roam_points.is_empty():
		_player.set_auto_move(Vector2.ZERO)
		_set_state(State.SEARCH_TARGET)
		return
	if _roam_index < 0:
		var nearest := INF
		for i in range(_roam_points.size()):
			var d := _player.global_position.distance_squared_to(_roam_points[i])
			if d < nearest:
				nearest = d
				_roam_index = i
		_reset_roam_progress()
	var point := _roam_points[_roam_index]
	var dist := _player.global_position.distance_to(point)
	if dist <= ROAM_ARRIVE_EPS:
		_advance_roam()
		point = _roam_points[_roam_index]
		dist = _player.global_position.distance_to(point)
	_roam_stuck_t += delta
	if _roam_stuck_t >= STUCK_INTERVAL:
		_roam_stuck_t = 0.0
		_roam_stuck_count = _roam_stuck_count + 1 if _roam_last_dist - dist < STUCK_PROGRESS_EPS else 0
		_roam_last_dist = dist
		if _roam_stuck_count >= STUCK_LIMIT:
			_advance_roam()
			point = _roam_points[_roam_index]
	var direction := _direction_to(point)
	if direction == Vector2.ZERO and _cave_ground() != null:
		_advance_roam()
		_player.set_auto_move(Vector2.ZERO)
		return
	_player.set_auto_move(direction)
	_set_state(State.ROAM)

func _direction_to(point: Vector2) -> Vector2:
	var ground := get_tree().get_first_node_in_group("map_ground") as IsoGround
	return _cave_nav.direction(ground, _player.global_position, point)

func _cave_ground() -> IsoGround:
	var ground := get_tree().get_first_node_in_group("map_ground") as IsoGround
	return ground if ground != null and ground.cave != null else null

func _route_reachable(point: Vector2) -> bool:
	var ground := _cave_ground()
	return ground == null or ground.cave.reachable(
		Vector2i(Iso.world_to_grid(_player.global_position).round()), Vector2i(Iso.world_to_grid(point).round()))

func _build_roam_points() -> void:
	_roam_points.clear()
	var ground := get_tree().get_first_node_in_group("map_ground") as IsoGround
	if ground == null:
		return
	_roam_built = true
	_roam_ground = ground if ground.cave != null else null
	_roam_revision = ground.cave.navigation_revision if ground.cave != null else -1
	var origin_cell := Vector2i(Iso.world_to_grid(_player.global_position).round())
	_roam_component = ground.cave.component_at(origin_cell) if ground.cave != null else 0
	_roam_index = -1
	var xs: Array[int] = []
	var ys: Array[int] = []
	for x in range(2, maxi(3, ground.grid_size.x - 2), ROAM_GRID_STEP):
		xs.append(x)
	for y in range(2, maxi(3, ground.grid_size.y - 2), ROAM_GRID_STEP):
		ys.append(y)
	if xs.is_empty() or xs.back() != ground.grid_size.x - 3:
		xs.append(maxi(2, ground.grid_size.x - 3))
	if ys.is_empty() or ys.back() != ground.grid_size.y - 3:
		ys.append(maxi(2, ground.grid_size.y - 3))
	for row in range(ys.size()):
		for col in range(xs.size()):
			var x: int = xs[col] if row % 2 == 0 else xs[xs.size() - col - 1]
			var cell := Vector2i(x, ys[row])
			if ground.is_walkable_cell(cell):
				var point := Iso.grid_to_world(cell)
				if ground.cave == null or ground.cave.reachable(origin_cell, cell):
					_roam_points.append(point)

func _advance_roam() -> void:
	_roam_index = (_roam_index + 1) % _roam_points.size()
	_reset_roam_progress()

func _reset_roam_progress() -> void:
	_roam_last_dist = INF
	_roam_stuck_t = 0.0
	_roam_stuck_count = 0

## T10：该掉落物当前是否可被拾取（背包满则不可，避免无限拾取满背包）。
func _can_pick(gi: GroundItem) -> bool:
	if not gi.visible or gi.is_queued_for_deletion():
		return false
	# 工程 89：玩家主动丢弃物只能点击拾取，不能进「顺路拾取」候选 ——
	# 否则挂机时会绕路把刚扔掉的垃圾一件件捡回来。
	if gi.manual_only:
		return false
	if String(gi.item.get("kind", "")) == "coin":
		return not GameState.gold_is_capped()
	return Inventory.has_space_for(GameState.inventory, gi.item)

# ---- 卡住检测与黑名单（3.14 ①，T08）----

## 追击期的卡住判据 = **角色自身位移**（P1，见工程文档 69 §3.1 / §5）。
## 旧口径拿「与目标的**直线距离**每 0.3s 是否下降 6px」当判据，会把两类**正常**行为误判成不可达：
##   ① 绕障：路径要求先侧向甚至反向绕过悬崖/墙体，头 0.9s 内直线距离几乎不变；
##   ② 被击退 / 倒地：距离不降反增（`monster.gd` 的 SKILL_KNOCKBACK_DISTANCE / SKILL_KNOCKDOWN_DURATION）。
## 现在只对「角色本间隔内一步都没挪动（< STUCK_MOVE_EPS）」计数，连续 STUCK_LIMIT 次才拉黑改选——
## 这才是 3.14 ①「不可达」的本意：角色确实走不动，而不是「走得绕」。
func _tick_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t < STUCK_INTERVAL:
		return
	_stuck_t = 0.0
	var moved := _player.global_position.distance_to(_last_position) if _last_position.is_finite() else INF
	_last_position = _player.global_position
	if moved >= STUCK_MOVE_EPS:
		_stuck_count = 0
		return
	_stuck_count += 1
	if _stuck_count >= STUCK_LIMIT:
		_blacklist_target(_target)

## 目标短期拉黑并改选（寻路空 / 终点占位 / 连续无位移 → 3.14 ①）。
func _blacklist_target(t: Node) -> void:
	if t != null and is_instance_valid(t):
		_blacklist[t.get_instance_id()] = BLACKLIST_TIME
		# P2：记住它。若这次拉黑本身就是误判，黑名单到点后粘性会把原目标捡回来。
		_sticky_target = t
		_sticky_left = STICKY_TIME
		_toast(Localization.tr_key("ui.auto.unreachable"), "info")
	_target = null
	_cave_nav.clear()
	_last_position = Vector2.INF
	_stuck_count = 0
	_blocked_t = BLOCKED_TIME
	_set_state(State.BLOCKED)
	_player.set_auto_move(Vector2.ZERO)

func _tick_blacklist(delta: float) -> void:
	# P2 粘性记忆与黑名单同一时间轴衰减，只是多留 1 秒宽限（黑名单先失效，记忆后失效）。
	if _sticky_left > 0.0:
		_sticky_left = maxf(0.0, _sticky_left - delta)
		if _sticky_left <= 0.0:
			_sticky_target = null
	if _blacklist.is_empty():
		return
	var expired: Array = []
	for id in _blacklist.keys():
		_blacklist[id] = float(_blacklist[id]) - delta
		if float(_blacklist[id]) <= 0.0:
			expired.append(id)
	for id in expired:
		_blacklist.erase(id)

func _is_blacklisted(t: Node) -> bool:
	return _blacklist.has(t.get_instance_id())

## 当前被拉黑的目标数（供回归断言）。
func blacklist_size() -> int:
	return _blacklist.size()

# ---- 手动接管检测（4.6）----

func _has_manual_input() -> bool:
	if Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.05:
		return true
	if Input.is_action_pressed("attack") or Input.is_action_pressed("target_next"):
		return true
	# 世界右键在 Game._unhandled_input 中直接 begin_manual_command；这里轮询鼠标会把面板内右键也误判为手动接管。
	return false

# ---- 状态与提示 ----

func _set_state(s: int, phase_override: String = "") -> void:
	if _state == s and phase_override.is_empty():
		return
	_state = s
	var label := phase_override if not phase_override.is_empty() else state_name(s)
	if label != _phase:
		_phase = label
		EventBus.auto_phase_changed.emit(_phase)

func _toast(text: String, kind: String = "info") -> void:
	EventBus.toast_requested.emit(text, kind)

## 状态名（供 HUD 显示「自动中 / 手动接管 / 暂停中」等，4.6）。
static func state_name(s: int) -> String:
	match s:
		State.OFF:
			return Localization.tr_key("ui.auto.off")
		State.SEARCH_TARGET:
			return Localization.tr_key("ui.auto.search_target")
		State.PATH_TO_TARGET:
			return Localization.tr_key("ui.auto.approach")
		State.ATTACK_TARGET:
			return Localization.tr_key("ui.auto.attacking")
		State.SEARCH_LOOT:
			return Localization.tr_key("ui.auto.search_loot")
		State.PATH_TO_LOOT:
			return Localization.tr_key("ui.auto.approach_loot")
		State.PICK_UP:
			return Localization.tr_key("ui.auto.pickup")
		State.RECOVER:
			return Localization.tr_key("ui.auto.paused")
		State.MANUAL_OVERRIDE:
			return Localization.tr_key("ui.auto.manual")
		State.BLOCKED:
			return Localization.tr_key("ui.auto.blocked")
		State.ROAM:
			return Localization.tr_key("ui.auto.roaming")
		_:
			return Localization.tr_key("ui.auto.unknown")

func current_state() -> int:
	return _state

func current_phase() -> String:
	return _phase

func current_target() -> Node:
	return _target

# ---- 技能选择（3.14「优先可用范围技（命中 ≥2），否则单体 / 普攻；不绕过冷却」）----

## T11：MP / 冷却 / 等级任一不足即**不施放**该技能。
## 返回选中的技能字典；`{}` = 不施放技能（回退普攻）。
## 纯静态函数，便于无头回归（不依赖场景与玩家节点）。
## R4-d：技能价值 = 单段系数 × 段数（`hits` 缺省 1）。
## 多段技能的实际输出来自段数，只比 `coefficient` 会把灵刃风暴（1.0×3）误判成比裂地斩（1.4）弱。
static func skill_value(skill: Dictionary) -> float:
	return float(skill.get("coefficient", 0.0)) * float(maxi(1, int(skill.get("hits", 1))))

static func choose_skill(skills: Array, level: int, mp: int, cooldowns: Dictionary,
		target_count: int) -> Dictionary:
	var aoe := {}
	var single := {}
	for s in skills:
		if not (s is Dictionary):
			continue
		var sid := String(s.get("id", ""))
		# 普攻由攻击间隔单独驱动。工程 98：改用数据标记 `basic` 而不是写死 `basic_slash`，
		# 否则法师的火球术会被当成主动技能参与评分（它有 id、有系数、CD 为 0）。
		if sid.is_empty() or bool(s.get("basic", false)):
			continue
		if String(s.get("kind", "attack")) != "attack":
			continue
		if int(s.get("unlockLevel", 1)) > level:
			continue                                   # 未解锁
		if int(s.get("manaCost", 0)) > mp:
			continue                                   # MP 不足 → 不施放
		if float(cooldowns.get(sid, 0.0)) > 0.0:
			continue                                   # 冷却中 → 不施放
		var is_aoe := String(s.get("shape", "single")) != "single"
		if is_aoe and target_count >= 2:
			if aoe.is_empty() or int(s.get("manaCost", 0)) < int(aoe.get("manaCost", 0)):
				aoe = s
		elif String(s.get("shape", "single")) == "single":
			if single.is_empty() or skill_value(s) > skill_value(single):
				single = s
	if not aoe.is_empty():
		return aoe
	return single

## 自动战斗是否愿意施放该技能（按职业白名单）。
## R4-d：单体技能走独立白名单，与范围技同名同权；工程 98 增法师两表与魔法盾。
func can_cast(skill_id: String) -> bool:
	return WIRED_SKILLS.has(skill_id) or WIRED_SINGLE_SKILLS.has(skill_id) \
		or MAGE_AREA_SKILLS.has(skill_id) or MAGE_SINGLE_SKILLS.has(skill_id) \
		or skill_id == "magic_shield"
