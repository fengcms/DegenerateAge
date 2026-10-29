class_name PlayerCharacter
extends CharacterBody2D
## 玩家角色：八向归一化移动 + 普攻 + 受击保护 + 死亡占位。
## 依据：产品文档 4.6 操控 / 3.1 战斗流程 / 3.2 伤害公式 / 3.4 受击保护 / 4.7 死亡。
## M1-3/M1-4：移动 + 普攻结算；M1-5：受击硬直 + 无敌帧 + 死亡复活占位；
## M1-9：暴露自动移动 / 自动攻击接口（供 AutoBattle 决策机驱动，3.14）。
## 普攻设计为「离散事件」——每次成功发动只结算一次，天然满足 T04（不重复结算）。
## 锁定目标超距接近与点击普攻已接入；技能格随后续技能系统接线。
## 形象：按当前武器解析「阶段形象」整体换图（CharacterLook）；魔法盾护罩仅为随身视觉，不参与结算。

const RADIUS := 12.0
const ART_SCALE := 1.5  # 只放大玩家外观；碰撞和战斗距离仍使用原逻辑尺寸。
const COLOR_BODY := Color("e8c07d")
const COLOR_EDGE := Color("6d4c1f")
const COLOR_DEAD := Color("8a8a8a")
const COLOR_HEAD_HP_BG := Color(0.08, 0.08, 0.10, 0.85)
const COLOR_HEAD_HP_FG := Color("61c985")
const MONO_FONT := preload("res://assets/themes/mono_font.tres")

const IFRAME := 0.5            # 3.4：受击后无敌帧时长（s）
const HITSTUN := 0.25          # 3.4：受击硬直时长（s，期间无法主动行动）
const MANUAL_EPS := 0.05       # 手动输入判定阈值（摇杆量）
const REGEN_INTERVAL := 3.0      # 未受击时每三秒结算一次；攻击和移动不重置计时
const IDLE_HP_RATE := 0.01       # 每次结算按最大值恢复，未满时至少恢复 1 点
const IDLE_MP_RATE := 0.02
const SIT_HP_RATE := 0.03
const SIT_MP_RATE := 0.05

## 远程施法的投射物颜色（纯视觉，工程 98 §4.3）。缺省金黄。
const SPELL_COLORS := {
	"basic_fireball": "ffb347",
	"lightning": "9ad8ff",
	"flame_burst": "ff8a4c",
	"frost_roar": "b6f0ff",
	"meteor": "ff9b6b",
	"magic_shield": "a7efed",
}

## 减速是实体运行态，死亡清除，不写存档。
var _slow_pct := 0.0
var _slow_remaining := 0.0

## 同强度刷新时间，较弱减速不会覆盖较强效果；不乘算叠加。
func apply_slow(percent: float, duration: float) -> void:
	if is_dead or percent <= 0 or duration <= 0:
		return
	if percent >= _slow_pct or _slow_remaining <= 0:
		_slow_pct = clampf(percent, 0.0, 0.95)
		_slow_remaining = duration

func movement_multiplier() -> float:
	return 1.0 - _slow_pct if _slow_remaining > 0 else 1.0

## 移动速度（像素/秒）= 属性表 movementSpeed（格/秒）× 瓦片宽
var _speed: float = 256.0
## 普攻冷却计时（s）
var _attack_cd: float = 0.0
## 主动技能冷却为角色运行态；切图保留、暂停冻结、读档重新创建。
var skill_cooldowns: Dictionary = {}
var _pending_skill_id := ""
## 普攻技能定义（skills.json 的**本职业**普攻：武士 basic_slash / 法师 basic_fireball）
var _basic: Dictionary = {}
## 受击保护计时
var _invuln: float = 0.0
var _stun: float = 0.0
## A4（03 §3.4 / 工程文档 56 §2）：Boss 技能击退位移。运行态，死亡 / 复活清除，不入档。
var _knockback_dir := Vector2.ZERO
var _knockback_distance := 0.0   # 本段击退总位移（px）
var _knockback_duration := 1.0
var _knockback_t := 0.0          # 剩余时长（s），归零即位移结束
## 死亡占位计时
var _death_t: float = 0.0
var is_dead: bool = false
var is_sitting: bool = false
## 死亡前是否处于自动战斗（F 挂机）。`_begin_death()` 会主动关掉挂机，故先记录原状态，
## 供死亡界面的「自动原地复活」在复活后按原样恢复挂机（见 death_panel._try_auto_revive）。
var auto_battle_before_death: bool = false
var sample_art: SampleActorArt
var _shield_back: MagicShieldAura
var _shield_front: MagicShieldAura
var _mount_art_visible := false
## 当前阶段形象 id；换装后由 _refresh_look 重新解析。
var _look_id := ""

## 自动战斗的移动意图（3.14）：由 AutoBattle 写入。
## **手动输入优先**——玩家一按方向键即完全接管（4.6），无需 AutoBattle 额外干预。
var auto_move: Vector2 = Vector2.ZERO
## 上一帧是否检测到手动输入（供 auto_battle 判定「手动接管」）。
var manual_input_active: bool = false
## 锁定目标与手动指令归玩家持有；地面/大地图/追击共用移动与普攻，不保存运行态路线。
var locked_target: Node2D = null
var target_is_manual := false
var manual_attack_active := false
var map_move_active := false
var _map_destination := Vector2.ZERO
var _map_check_t := 0.0
var _map_last_distance := INF
var _map_stuck_count := 0
var _cave_path: Array[Vector2] = []
var _cave_path_index := 0
var _cave_target_cell := Vector2i(-1, -1)
var _map_background := false
var _regen_elapsed := 0.0

func valid_target(target: Variant) -> bool:
	return is_instance_valid(target) and target is Node2D and not target.is_queued_for_deletion() and target.get("is_dead") != true and target.has_method("take_hit") and not MapService.is_in_rest_zone(GameState.current_map, target.global_position)

func clear_travel_intent() -> void:
	map_move_active = false
	manual_attack_active = false
	_pending_skill_id = ""
	auto_move = Vector2.ZERO
	velocity = Vector2.ZERO
	_map_destination = global_position
	select_target(null)

func select_target(target: Node2D, manual: bool = true) -> void:
	if target != null and not valid_target(target):
		target = null
	if is_instance_valid(locked_target) and locked_target.has_method("set_selected"):
		locked_target.set_selected(false)
	locked_target = target
	target_is_manual = manual and target != null
	if locked_target != null and locked_target.has_method("set_selected"):
		locked_target.set_selected(true)
	EventBus.target_changed.emit(locked_target)

func begin_manual_command() -> void:
	set_sitting(false)
	auto_move = Vector2.ZERO
	var pilot := get_node_or_null("AutoPilot") as AutoBattle
	if pilot != null:
		pilot.begin_manual_override()

func request_target_attack(target: Node2D) -> bool:
	if is_dead or not valid_target(target):
		return false
	select_target(target)
	_pending_skill_id = ""
	map_move_active = false
	manual_attack_active = true
	reset_move_progress(target.global_position)
	begin_manual_command()
	return true

func reset_move_progress(point: Vector2) -> void:
	_map_destination = point
	_map_last_distance = global_position.distance_to(point)
	_map_check_t = 0.0
	_map_stuck_count = 0
	_cave_path.clear()
	_cave_path_index = 0
	_cave_target_cell = Vector2i(-1, -1)

func _manual_attack_direction(delta: float) -> Vector2:
	if not valid_target(locked_target):
		manual_attack_active = false
		select_target(null)
		return Vector2.ZERO
	var reach := melee_range_px()
	if not _pending_skill_id.is_empty():
		var pending := SkillProgression.current(_pending_skill_id)
		if pending is Dictionary:
			reach = float(pending.get("range", 1.0)) * Iso.TILE_W
	if not MapService.is_in_safe_area(GameState.current_map, global_position) \
		and global_position.distance_to(locked_target.global_position) <= reach - AutoBattle.STOP_GAP:
		_map_stuck_count = 0
		_map_check_t = 0.0
		_map_last_distance = INF
		if not _pending_skill_id.is_empty():
			if cast_skill(_pending_skill_id, locked_target):
				_pending_skill_id = ""
				manual_attack_active = false
		else:
			try_auto_attack(locked_target)
		return Vector2.ZERO
	_map_destination = locked_target.global_position
	return _map_direction(delta)

func request_map_move(point: Vector2) -> bool:
	if is_dead or not point.is_finite():
		return false
	manual_attack_active = false
	_pending_skill_id = ""
	map_move_active = true
	reset_move_progress(point)
	begin_manual_command()
	return true

## 自动寻路进行中时的行进路线折线（世界坐标；首点=人物当前坐标，末点=目标），供地图 UI 画虚线。
## 无洞穴布局的地图为两点直线；洞穴地图为绕障路点序列，已走过的路点会被裁掉。
## 路线尚未算出（洞穴内首帧）时返回空数组——宁可短暂不显示，也不画出穿墙直线。
func map_move_route() -> Array[Vector2]:
	if not map_move_active:
		return []
	var ground: IsoGround = null
	var world := get_tree().get_first_node_in_group("map_world")
	if world != null:
		ground = world.get_node_or_null("Ground") as IsoGround
	if ground == null or ground.cave == null:
		var straight: Array[Vector2] = [global_position, _map_destination]
		return straight
	if _cave_path.is_empty():
		return []
	var points: Array[Vector2] = [global_position]
	for index in range(_cave_path_index, _cave_path.size()):
		points.append(_cave_path[index])
	points.append(_map_destination)
	return points

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_map_background = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_map_background = false

func _map_direction(delta: float) -> Vector2:
	var distance := global_position.distance_to(_map_destination)
	if distance <= AutoBattle.LOOT_ARRIVE_EPS:
		map_move_active = false
		return Vector2.ZERO
	var waypoint := _map_destination
	var world := get_tree().get_first_node_in_group("map_world")
	if world != null:
		var ground := world.get_node_or_null("Ground") as IsoGround
		if ground != null and ground.cave != null:
			var target_cell := Vector2i(Iso.world_to_grid(_map_destination).round())
			if _cave_path.is_empty() or target_cell != _cave_target_cell:
				_cave_path = ground.route(global_position, _map_destination)
				_cave_target_cell = target_cell
				_cave_path_index = 0
			if _cave_path.is_empty():
				map_move_active = false
				manual_attack_active = false
				EventBus.toast_requested.emit(Localization.tr_key("msg.player.p001"), "danger")
				return Vector2.ZERO
			var old_index := _cave_path_index
			while _cave_path_index < _cave_path.size() and global_position.distance_to(_cave_path[_cave_path_index]) < 9.0:
				_cave_path_index += 1
			if _cave_path_index != old_index:
				_map_last_distance = INF
				_map_stuck_count = 0
				_map_check_t = 0.0
			if _cave_path_index < _cave_path.size():
				waypoint = _cave_path[_cave_path_index]
			elif target_cell != Vector2i(Iso.world_to_grid(global_position).round()):
				_cave_path.clear()
				return Vector2.ZERO
			distance = global_position.distance_to(waypoint)
	_map_check_t += delta
	if _map_check_t >= AutoBattle.STUCK_INTERVAL:
		_map_check_t = 0.0
		_map_stuck_count = _map_stuck_count + 1 if _map_last_distance - distance < AutoBattle.STUCK_PROGRESS_EPS else 0
		_map_last_distance = distance
		if _map_stuck_count >= AutoBattle.STUCK_LIMIT:
			map_move_active = false
			manual_attack_active = false
			EventBus.toast_requested.emit(Localization.tr_key("msg.player.p002"), "danger")
			return Vector2.ZERO
	return global_position.direction_to(waypoint)

## 初始化正式场景的外观和护罩；纯逻辑单测可用没有画层的 PlayerCharacter.new()。
func _ready() -> void:
	_shield_back = get_node_or_null("MagicShieldBack") as MagicShieldAura
	_shield_front = get_node_or_null("MagicShieldFront") as MagicShieldAura
	_look_id = CharacterLook.look_id_for(GameState.equipment)
	sample_art = SampleActorArt.attach_look(self, CharacterLook.definition(_look_id))
	sample_art.display_scale = ART_SCALE
	# 工程 98 §3.6：法师暂无专属形象，用冷色调偏移做最小区分（武士 tint 为空 ⇒ 恒等，逐位不变）。
	sample_art.modulate = PlayerClass.tint()
	_refresh_mount_art()
	_sync_magic_shield_visual()
	# G-P2-2：订阅生命周期约定见 autoload/event_bus.gd 顶部（随场景释放自动断开，不逐个补 _exit_tree）。
	EventBus.equipment_changed.connect(_refresh_look)
	EventBus.equipment_changed.connect(_refresh_speed)
	EventBus.mount_changed.connect(_refresh_mount_art)
	add_to_group("player")
	_refresh_speed()
	var b = DataLoader.get_entry("skills", PlayerClass.basic_skill())
	_basic = b if b is Dictionary else {"coefficient": 1.0, "range": 1.0}
	# G-P3-3：该字典为 GameState 冷却运行态的唯一实例，**禁止整体替换**（只增删条目）；
	# 读档 / 新游戏由 GameState 侧置空（`reset_to_defaults`、`apply_to_game_state`）。
	skill_cooldowns = GameState.skill_cooldowns
	EventBus.player_hp_changed.connect(func(_current: int, _maximum: int) -> void: queue_redraw())

## 移速走派生门面（工程 66）：套装加成会改变 `movementSpeed`。
## 🔴 换装后必须重算 —— 只在 `_ready()` 算一次的话，`_speed` 会永远停在进图那一刻的值。
func _refresh_speed() -> void:
	_speed = GameState.total_move_speed() * Iso.TILE_W

## 装备变化后重新解析阶段形象；形象 id 未变化时不换纹理，避免无谓的重载。
func _refresh_look() -> void:
	if sample_art == null:
		return
	var next := CharacterLook.look_id_for(GameState.equipment)
	if next == _look_id:
		return
	_look_id = next
	sample_art.apply_look(CharacterLook.definition(next))
	_refresh_mount_art()

## 骑乘事件或角色外观切换后同步外观、护罩尺寸与头顶信息高度。
## 仅已拥有且等级有效、当前 look 有坐骑图集时才按骑乘外观处理。
func _refresh_mount_art() -> void:
	if sample_art == null:
		return
	var mount_id := GameState.active_mount if GameState.mount_speed_multiplier() > 1.0 else ""
	sample_art.set_mount(mount_id)
	var mount_defs: Dictionary = CharacterLook.definition(_look_id).get("mounts", {})
	_mount_art_visible = not mount_id.is_empty() and mount_defs.has(mount_id)
	if _shield_back != null:
		_shield_back.set_mounted(_mount_art_visible)
	if _shield_front != null:
		_shield_front.set_mounted(_mount_art_visible)
	queue_redraw()

## 只把已生效且有法力可承担伤害的魔法盾映射到护罩画层；断蓝时熄灭，回蓝后恢复。
## 切图的新玩家节点在 _ready 读取当前 Buff，持续过程只切 visible，不逐帧重建几何。
func _sync_magic_shield_visual() -> void:
	if _shield_back == null or _shield_front == null:
		return
	var active := not is_dead and GameState.buff_remaining("magic_shield") > 0.0 \
		and int(GameState.player.mp) > 0
	if _shield_back.visible != active:
		_shield_back.visible = active
		_shield_front.visible = active

## 物理帧推进移动与攻击；护罩可见性只比较 Buff/蓝量状态，不在帧内重绘几何。
func _physics_process(delta: float) -> void:
	_sync_magic_shield_visual()
	if locked_target != null and not valid_target(locked_target):
		manual_attack_active = false
		select_target(null)
	_slow_remaining = maxf(0.0, _slow_remaining - delta)
	_invuln = maxf(0.0, _invuln - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)

	if is_dead:
		auto_move = Vector2.ZERO
		manual_input_active = false
		velocity = Vector2.ZERO
		move_and_slide()
		_update_blink()
		return
	_tick_regen(delta)

	_stun = maxf(0.0, _stun - delta)
	var world_controls_blocked := GameState.world_controls_blocked()
	if is_sitting:
		var wants_move := not world_controls_blocked and Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > MANUAL_EPS
		if wants_move or (not world_controls_blocked and Input.is_action_pressed("attack")):
			set_sitting(false)
		else:
			auto_move = Vector2.ZERO
			manual_input_active = false
			velocity = Vector2.ZERO
			move_and_slide()
			_update_blink()
			return

	# 普通面板保留手动移动与攻击；设置、存档等模态流程和文本编辑才接管键盘。
	# 暂停整棵场景树的菜单、死亡及装备确认由引擎自动冻结本节点。
	if world_controls_blocked:
		manual_attack_active = false
		_pending_skill_id = ""

	# Input.get_vector 已做归一化：斜向不会比正向更快（八向移动）
	var dir := Vector2.ZERO if world_controls_blocked else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	manual_input_active = dir.length() > MANUAL_EPS
	if manual_input_active:
		map_move_active = false
		manual_attack_active = false
		_pending_skill_id = ""
	if not world_controls_blocked and Input.is_action_pressed("attack") and not manual_input_active and not manual_attack_active:
		if valid_target(locked_target):
			request_target_attack(locked_target)
		else:
			map_move_active = false
	if manual_attack_active or map_move_active:
		if _map_background:
			dir = Vector2.ZERO
		elif _stun <= 0.0:
			dir = _manual_attack_direction(delta) if manual_attack_active else _map_direction(delta)
		manual_input_active = true
	# 手动输入优先；无手动输入时由自动战斗的移动意图接管（3.14：自动与手动共用同一移动路径）
	if not manual_input_active and auto_move != Vector2.ZERO:
		dir = auto_move
	if _stun > 0.0:
		dir = Vector2.ZERO   # 硬直期间无法主动移动（3.4）
	velocity = dir * _speed * movement_multiplier() * GameState.mount_speed_multiplier()
	move_and_slide()
	_tick_knockback(delta)

	# 普攻：按住攻击键，冷却结束即发动一次（每次发动 = 一次结算）
	if not world_controls_blocked and not manual_attack_active and _stun <= 0.0 and Input.is_action_pressed("attack") and _attack_cd <= 0.0:
		_try_attack()

	_update_blink()

# ---- 受击保护 / 死亡（3.4 / 4.7）----

## 承受怪物攻击，返回实际扣血量；无敌帧内返回 0，供吸血与附伤判定。
func apply_damage(amount: int) -> int:
	if is_dead or _invuln > 0.0 or amount <= 0 or MapService.is_in_rest_zone(GameState.current_map, global_position):
		return 0
	set_sitting(false)
	if sample_art != null:
		sample_art.hit()
	_invuln = IFRAME
	_stun = HITSTUN
	_reset_regen_after_hit()
	# 工程 98 Q4=A：魔法盾只把**一部分伤害**转成法力，余下照常扣血。
	# 🔴 顺序不能反：先算转嫁（可能要读 mp），再扣血 —— 反过来会让「血已经归零」的帧去扣蓝。
	var to_mana := _shield_absorb(amount)
	var hp_amount := amount - to_mana
	var actual := mini(hp_amount, int(GameState.player.hp))
	if hp_amount > 0 and GameState.damage_player(hp_amount):
		_begin_death()
	return actual

## 魔法盾转嫁（工程 98 §4.5）。返回实际由法力承担的伤害（= 实际扣蓝量）。
##
## 比例来自**已生效的 buff** `damageToManaPct`，不是写死常量 —— 升阶（0.30→0.46）才能真生效。
## 蓝不足时按**剩余量**转嫁，余下全部扣血；蓝为 0 ⇒ 与无盾逐位一致（这也是武士的路径：
## 武士没有任何 buff 带这个键，`buff_effect_total` 返回 0.0，本函数直接早退）。
func _shield_absorb(amount: int) -> int:
	var pct := clampf(GameState.buff_effect_total("damageToManaPct"), 0.0, 0.9)
	if pct <= 0.0 or amount <= 0:
		return 0
	var want := int(round(float(amount) * pct))
	var to_mana := mini(want, int(GameState.player.mp))
	if to_mana <= 0:
		return 0
	# 走 `spend_mp` 而不是直接写 `player.mp`：HUD 蓝条与事件都靠它广播。
	if not GameState.spend_mp(to_mana):
		return 0
	return to_mana

## A4（03 §3.4）：Boss 技能命中后由来源调用，施加击退位移与倒地。
## 只在 `apply_damage` 真正扣到血（返回 > 0）时才该被调用 —— 无敌帧 / 死亡 / 休息区
## 已由受击入口拦掉，因此这里天然不会叠加第二次击退或硬直。
## `origin` 为攻击来源位置：击退方向取「来源 → 玩家」射线（56 §2.5）。
func apply_knockback(origin: Vector2, distance: float, duration: float, knockdown: float) -> void:
	if is_dead:
		return
	if knockdown > 0.0:
		_stun = maxf(_stun, knockdown)   # 倒地沿用既有 `_stun` 抑制路径：期间不寻路、不决策、不普攻
	if distance <= 0.0 or duration <= 0.0:
		return
	var away := global_position - origin
	_knockback_dir = away.normalized() if away.length_squared() > 0.000001 else Vector2.DOWN
	_knockback_distance = distance
	_knockback_duration = duration
	_knockback_t = duration
	# 位移会改变当前位置，洞穴图旧路点随即失效：清掉让下一帧按新位置重规划。
	_cave_path.clear()
	_cave_path_index = 0
	_cave_target_cell = Vector2i(-1, -1)

## 剩余时长 `t` 对应的累计位移：`D × (1 − (t/T)²)`，导数即「线性衰减速度」。
func _knockback_offset(t: float) -> float:
	var ratio := t / _knockback_duration
	return _knockback_distance * (1.0 - ratio * ratio)

## 击退位移：按上式解析积分推进，离散帧叠加后**总位移恰为配置值**；落位前经可行走掩码截断。
## 仅当目标格可走才落位，不做 `nearest_walkable` 吸附 —— 否则一格薄墙会把玩家弹到墙后。
func _tick_knockback(delta: float) -> void:
	if _knockback_t <= 0.0:
		return
	var before := _knockback_offset(_knockback_t)
	_knockback_t = maxf(0.0, _knockback_t - delta)
	var motion := _knockback_dir * (_knockback_offset(_knockback_t) - before)
	if motion == Vector2.ZERO:
		return
	var ground := _map_ground()
	var guess := global_position + motion
	if ground == null:
		global_position = guess
		return
	if not ground.is_walkable_cell(Vector2i(Iso.world_to_grid(guess).round())):
		_knockback_t = 0.0   # 撞墙即截停
		return
	global_position = ground.clamp_to_map(guess)

func _map_ground() -> IsoGround:
	var world := get_tree().get_first_node_in_group("map_world")
	if world == null:
		return null
	return world.get_node_or_null("Ground") as IsoGround

func _begin_death() -> void:
	if is_dead:
		return
	set_sitting(false)
	GameState.clear_buffs()
	map_move_active = false
	manual_attack_active = false
	_pending_skill_id = ""
	select_target(null)
	_slow_remaining = 0.0
	_slow_pct = 0.0
	_knockback_t = 0.0
	is_dead = true
	# 先记录死亡前的挂机状态，再关自动战斗：自动原地复活需要按原样恢复（见 death_panel）。
	auto_battle_before_death = GameState.auto_battle_on
	GameState.set_auto_battle(false)
	preload("res://scripts/systems/death_penalty.gd").drop_one(self)
	_regen_elapsed = 0.0
	_death_t = 0.0
	velocity = Vector2.ZERO
	queue_redraw()
	EventBus.toast_requested.emit(Localization.tr_key("msg.player.p003"), "danger")

## 由死亡选择界面调用；消耗复活卷的校验和扣除由界面入口负责。
func _revive() -> void:
	is_dead = false
	_death_t = 0.0
	_invuln = 1.0
	_stun = 0.0
	_knockback_t = 0.0
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()
	GameState.emit_all()
	queue_redraw()
	EventBus.toast_requested.emit(Localization.tr_key("msg.player.p004"), "info")

## 受击闪烁：无敌帧内高频闪烁，死亡保留半透明。
func _update_blink() -> void:
	if is_dead:
		modulate.a = 0.35
	elif _invuln > 0.0:
		modulate.a = 0.45 + 0.55 * absf(sin(_invuln * 14.0))
	else:
		modulate.a = 1.0

# ---- 自动战斗接口（M1-9，3.14：自动与手动共用同一移动 / 攻击路径）----

## 设置自动移动意图（由 AutoBattle 调用）。手动输入优先，见 _physics_process。
func set_auto_move(dir: Vector2) -> void:
	auto_move = dir

## 攻击是否就绪：未死亡、不在受击硬直、攻击冷却已结束（3.9：自动不绕过攻速）。
func is_attack_ready() -> bool:
	return not is_dead and _stun <= 0.0 and _attack_cd <= 0.0

## 自动战斗对指定目标发动一次普攻。返回是否真正发动。
## 冷却中 / 硬直中 / 目标已失效 → 返回 false（不结算、不推进冷却）。
func try_auto_attack(target: Node) -> bool:
	if not is_attack_ready() or MapService.is_in_safe_area(GameState.current_map, global_position):
		return false
	if not valid_target(target):
		return false
	if not target is Node2D or global_position.distance_to(target.global_position) > melee_range_px():
		return false
	_attack_cd = effective_attack_interval()
	perform_attack(target)
	return true

# ---- 攻击 ----

## 普攻的攻击距离上限（格 → 像素）。超距自动走位（3.15）与自动战斗（3.14）共用。
## 工程 98：射程由**职业**决定（武士 1 格 / 法师 4 格），不再读普攻技能自身的 `range` ——
## 两处都写会让「改 classes.json 不改 skills.json」出现两套射程。
func attack_range_px() -> float:
	return PlayerClass.attack_range() * Iso.TILE_W

## 旧名保留为别名：4 处调用点 + 2 处测试都在用，且语义已收敛到 `attack_range_px()`。
func melee_range_px() -> float:
	return attack_range_px()

## 本职业是否为远程（决定要不要放投射物视觉、以及自动战斗的停步距离）。
func is_ranged_class() -> bool:
	return PlayerClass.is_ranged()

func skill_cooldown(skill_id: String) -> float:
	return float(skill_cooldowns.get(skill_id, 0.0))

func effective_attack_power() -> float:
	return float(GameState.total_attack()) * (1.0 + GameState.buff_effect_total("attackPct"))

func effective_attack_interval() -> float:
	var speed := maxf(0.01, 1.0 + GameState.buff_effect_total("attackSpeedPct"))
	return maxf(Combat.MIN_ATTACK_INTERVAL, GameState.total_attack_interval() / speed)

## 快捷栏手动指令：选中目标后接近至技能射程，再由同一施放入口结算。
func request_skill(skill_id: String) -> bool:
	var skill := SkillProgression.current(skill_id)
	if not HotbarConfig.usable_skill(skill_id):
		return false
	if skill.is_empty():
		EventBus.toast_requested.emit(Localization.tr_key("msg.player.p006"), "danger")
		return false
	if skill_id == PlayerClass.basic_skill():
		if valid_target(locked_target):
			return request_target_attack(locked_target)
		EventBus.toast_requested.emit(Localization.tr_key("msg.player.p005"), "danger")
		return false
	if is_dead or int(GameState.player.level) < int(skill.get("unlockLevel", 1)):
		EventBus.toast_requested.emit(Localization.tr_key("msg.player.p006"), "danger")
		return false
	if int(GameState.player.mp) < GameState.skill_mana_cost(skill):
		EventBus.toast_requested.emit(Localization.tr_key("msg.player.p007"), "danger")
		return false
	if skill_cooldown(skill_id) > 0.0:
		EventBus.toast_requested.emit(Localization.tr_key("msg.player.p008"), "danger")
		return false
	if String(skill.get("kind", "")) == "buff":
		if GameState.buff_remaining(skill_id) > 0.0 and skill_id != "magic_shield":
			EventBus.toast_requested.emit(Localization.tr_key("msg.player.p009"), "danger")
			return false
		begin_manual_command()
		return cast_skill(skill_id)
	# 已锁定敌人时，所有攻击技能都先按各自射程接近该目标。
	# 圆形技能也不能因身边另有敌人就提前空放在远处的锁定目标上。
	if valid_target(locked_target):
		map_move_active = false
		manual_attack_active = true
		_pending_skill_id = skill_id
		reset_move_progress(locked_target.global_position)
		begin_manual_command()
		return true
	if String(skill.get("shape", "")) == "circle":
		if skill_targets(skill).is_empty():
			EventBus.toast_requested.emit(Localization.tr_key("msg.player.p010"), "danger")
			return false
		begin_manual_command()
		if not cast_skill(skill_id):
			EventBus.toast_requested.emit(Localization.tr_key("msg.player.p011"), "danger")
			return false
		return true
	EventBus.toast_requested.emit(Localization.tr_key("msg.player.p005"), "danger")
	return false

## 所有入口共用的实际施放；失败时不耗蓝、不进入冷却。
func cast_skill(skill_id: String, target: Node = null) -> bool:
	var skill := SkillProgression.current(skill_id)
	if not HotbarConfig.usable_skill(skill_id) or skill_id == PlayerClass.basic_skill() or skill.is_empty():
		return false
	if is_dead or _stun > 0.0:
		return false
	if int(GameState.player.level) < int(skill.get("unlockLevel", 1)) or skill_cooldown(skill_id) > 0.0:
		return false
	var mana_cost := GameState.skill_mana_cost(skill)
	if int(GameState.player.mp) < mana_cost:
		return false
	if String(skill.get("kind", "")) == "buff" and String(skill.get("shape", "")) == "self":
		if not GameState.start_buff(skill_id):
			return false
		GameState.spend_mp(mana_cost)
		skill_cooldowns[skill_id] = GameState.cooldown_after_cdr(float(skill.get("cooldown", 0.0)))
		_sync_magic_shield_visual()
		return true
	if _attack_cd > 0.0 or MapService.is_in_safe_area(GameState.current_map, global_position):
		return false
	if target != null:
		if not valid_target(target) or global_position.distance_to((target as Node2D).global_position) > float(skill.get("range", 1.0)) * Iso.TILE_W:
			return false
	var targets := skill_targets(skill, target)
	if targets.is_empty() or not GameState.spend_mp(mana_cost):
		return false
	skill_cooldowns[skill_id] = GameState.cooldown_after_cdr(float(skill.get("cooldown", 0.0)))
	# R4-b：多段技能只在**施放时**设一次攻击间隔，段与段之间不重复等待。
	_attack_cd = effective_attack_interval()
	if sample_art != null:
		sample_art.attack((targets[0] as Node2D).global_position - global_position, _attack_cd)
	var shape := String(skill.get("shape", "circle"))
	var reach := float(skill.get("range", 1.0)) * Iso.TILE_W
	var aim := global_position.direction_to((targets[0] as Node2D).global_position)
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	# 🔴 有 `fx` 的技能，范围提示**全权交给专属 fx**（工程 106 §4.2 规矩 2）。
	#    否则陨石术会同时出现专属预警环与通用的 448px 静态盘 —— 两份提示互相对不上，
	#    玩家不知道该信哪个。单体的 `fx` 技能（雷电术）本来就不画范围，这条对它无影响。
	if String(skill.get("fx", "")) == "":
		var range_fx := preload("res://scripts/systems/skill_range_fx.gd").new() as Node2D
		range_fx.shape = shape
		range_fx.radius = reach
		range_fx.facing = aim if shape == "cone" else Vector2.RIGHT
		add_child(range_fx)
	_spawn_cast_fx(skill, skill_id, targets[0] as Node2D, aim, reach)
	# R4-a：`defensePierce` 是**本击**减防，不进状态；`debuff` 才是持续状态（R4-c）。
	var pierce := clampf(float(skill.get("defensePierce", 0.0)), 0.0, 1.0)
	var hits := maxi(1, int(skill.get("hits", 1)))
	var power := effective_attack_power()
	var player_level := int(GameState.player.get("level", 1))
	for enemy in targets:
		# A2 越级伤害（03 §3.13）：逐目标取等级差放大攻击项——同一技能可同时打到不同等级的怪。
		var gap_power := power * LevelGap.damage_multiplier(player_level, _target_level(enemy))
		for _hit in range(hits):
			# 前置段已打死目标：后续段不再结算，避免死怪重复受击、飘字与事件计数虚高。
			if _target_is_dead(enemy):
				break
			var result := Combat.resolve(gap_power, _target_defense(enemy) * (1.0 - pierce),
				float(skill.get("coefficient", 1.0)), GameState.total_crit_chance(),
				GameState.total_crit_multiplier(), _target_dodge(enemy))
			Fx.damage_number(get_tree(), enemy, result)
			EventBus.damage_dealt.emit(enemy, int(result.get("damage", 0)), bool(result.get("critical", false)))
			enemy.take_hit(result, self)
			# 闪避不附加减益：描述里的「附加破甲」以命中为前提，miss 时不该白赚。
			if not bool(result.get("miss", false)):
				_apply_skill_debuff(enemy, skill)
	return true

## 按真实位置求命中集合；圆形以自身为中心，扇形面向锁定目标。
func skill_targets(skill: Dictionary, target: Node = null) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var shape := String(skill.get("shape", "single"))
	var reach := float(skill.get("range", 1.0)) * Iso.TILE_W
	var facing := Vector2.RIGHT
	if shape == "cone":
		if not valid_target(target):
			return result
		facing = global_position.direction_to((target as Node2D).global_position)
		if facing == Vector2.ZERO:
			facing = Vector2.RIGHT
	for raw in get_tree().get_nodes_in_group("enemies"):
		if not valid_target(raw):
			continue
		var enemy := raw as Node2D
		var offset := enemy.global_position - global_position
		if offset.length() > reach:
			continue
		if shape == "cone" and offset.length() > 0.01 and facing.dot(offset.normalized()) < cos(PI / 4.0):
			continue
		result.append(enemy)
	result.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	if shape == "cone" and target is Node2D and result.has(target):
		# 有命中数量上限时保留玩家明确指定的目标，其余名额给最近的怪。
		result.erase(target)
		result.push_front(target)
	if shape == "cone" and result.size() > int(skill.get("maxTargets", 3)):
		result.resize(int(skill.get("maxTargets", 3)))
	# 单体技能（`shape=single`）在实现上曾是「半径内全员」—— 那与技能描述的单体语义相反，
	# 会让 25 级的「单体穿透重击」变成隐形势 AoE。这里收敛为：有显式目标取目标，否则取最近一只。
	if shape == "single":
		var picked: Node2D = null
		if target is Node2D and result.has(target):
			picked = target as Node2D
		elif not result.is_empty():
			picked = result[0]
		result.clear()
		if picked != null:
			result.append(picked)
	return result

## 尝试普攻：优先锁定目标；无锁定时使用范围内最近敌人。
func _try_attack() -> void:
	if MapService.is_in_safe_area(GameState.current_map, global_position):
		return
	var target: Node = locked_target if valid_target(locked_target) else find_nearest_enemy_in_range()
	if target == null or global_position.distance_to(target.global_position) > melee_range_px():
		return
	_attack_cd = effective_attack_interval()
	perform_attack(target)

## 对指定目标结算一次普攻（供手动 / 自动化测试调用）。返回结算结果。
func perform_attack(target: Node) -> Dictionary:
	if is_dead or MapService.is_in_safe_area(GameState.current_map, global_position) or not valid_target(target):
		return {}
	if sample_art != null:
		sample_art.attack((target as Node2D).global_position - global_position, effective_attack_interval())
		var slash := preload("res://scripts/systems/sample_slash.gd").new() as Node2D
		slash.direction = ((target as Node2D).global_position - global_position).angle()
		slash.position = Vector2(0, -16 * ART_SCALE)
		add_child(slash)
	_spawn_projectile(PlayerClass.basic_skill(), (target as Node2D).global_position)

	var result := Combat.resolve(
		effective_attack_power() * LevelGap.damage_multiplier(
			int(GameState.player.get("level", 1)), _target_level(target)),
		_target_defense(target),
		float(_basic.get("coefficient", 1.0)),
		GameState.total_crit_chance(),
		GameState.total_crit_multiplier(),
		_target_dodge(target))

	Fx.damage_number(get_tree(), target as Node2D, result)
	EventBus.damage_dealt.emit(target, int(result.get("damage", 0)), bool(result.get("critical", false)))
	if locked_target != target:
		select_target(target as Node2D, false)
	target.take_hit(result, self)
	return result

## 施法视觉分派表（工程 106）：key = `skills.json` 的 `fx` 字段，value = fx 脚本。
## 🔴 新增技能特效 = **表里加一行 + 数据里写 `fx`**，不改任何 `if`。
##    靠 `if skill_id == "lightning"` 的话，每加一个技能都要改代码 —— 这正是 105 留下的模式，
##    加到第三个就会退化成坑清单第 69 条「兜底分支承担语义分派」。
const CAST_FX := {
	"thunder": preload("res://scripts/systems/thunder_fx.gd"),
	"meteor": preload("res://scripts/systems/meteor_fx.gd"),
	"flame_burst": preload("res://scripts/systems/flame_burst_fx.gd"),
	"frost_roar": preload("res://scripts/systems/frost_roar_fx.gd"),
}

## 远程施法弹道速度（px/s）与时长上下限（工程 106 §3.1 / R3）。
## 首版时长固定 0.14s：满射程 384px 的等效速度是 2743px/s，60fps 下每帧跳 45.7px
## = 球径 6px 的 7.6 倍，玩家看到的不是「飞过去」而是「一闪」。
const PROJECTILE_SPEED := 2000.0
const PROJECTILE_MIN_DURATION := 0.10
const PROJECTILE_MAX_DURATION := 0.20

## 技能命中瞬间的施法视觉分派（工程 105 / 106）。读 `skills.json` 的 `fx` 字段。
##   - 命中分派表：实例化对应的 fx 脚本，**跳过**飞行投射物 —— 这些技能有自己的「发生方式」，
##     「一颗球飞过去」会把技能身份丢掉（105 玩家报障的观感问题就是这个）；
##   - 未命中分派表：**报警后**回落投射物。不静默 —— 静默回落会让「数据里写了 fx
##     但代码忘了加」退化成一颗球的观感问题，没人会发现（坑清单第 64 条同构）；
##   - 没有 `fx` 字段：沿用通用飞行投射物（武士 5 技能全走这条，行为逐位不变）。
func _spawn_cast_fx(skill: Dictionary, skill_id: String, target: Node2D,
		facing: Vector2, radius: float) -> void:
	var key := String(skill.get("fx", ""))
	if key != "" and not CAST_FX.has(key):
		push_warning("Player: skills.json 声明了未知的 fx「%s」（技能 %s），回落到投射物（工程 106）" % [key, skill_id])
	if key == "" or not CAST_FX.has(key):
		_spawn_projectile(skill_id, target.global_position)
		return
	_spawn_cast_node(CAST_FX[key] as Script, {
		"origin": global_position,
		"target": target.global_position,
		"facing": facing,
		"radius": radius,
	})

## 实例化 fx 并挂到**父级**（与投射物一致）：施法特效不该跟着施法者横移。
## 🔴 `move_child(fx, 0)` 把地面系特效压到**所有角色之下**。`Entities` 没有开 `y_sort`，
##    纯按子树顺序绘制，所以后加入的节点会盖在怪身上 —— 105 踩过「落点光斑把目标整只吞掉」。
##    从天而降的 fx（雷电）自己设 `z_index = 1` 覆盖这条规则，不需要在这里特判。
## 🔴 上下文只由 `setup()` 消费，**不在调用点分派**：105 时每个 fx 都要一个 `_spawn_xxx()` 特例函数。
func _spawn_cast_node(script: Script, ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	var host := get_parent()
	if host == null:
		return
	var fx := script.new() as Node2D
	host.add_child(fx)
	host.move_child(fx, 0)
	if not fx.has_method("setup"):
		# 缺接口是**代码缺陷**，必须大声失败：静默丢掉等于「技能没有特效」，没人查得出来。
		push_error("Player: fx 脚本缺少 setup(ctx)（工程 106 分派契约），已丢弃")
		fx.queue_free()
		return
	fx.call("setup", ctx)

## 远程职业的施法视觉：一道纯视觉投射物飞向目标。
## 🔴 伤害**已在调用点结算完毕**（见 `player_projectile.gd` 顶端）。近战职业直接返回，
##    武士路径因此逐位不变 —— 这一条由 `tests/class_frame_test.gd` 断「武士不产生投射物节点」。
func _spawn_projectile(skill_id: String, to_point: Vector2) -> void:
	if not is_ranged_class() or not is_inside_tree():
		return
	var host := get_parent()
	if host == null:
		return
	var bolt := preload("res://scripts/systems/player_projectile.gd").new() as Node2D
	host.add_child(bolt)
	if bolt.has_method("setup"):
		var from := global_position + Vector2(0, -18.0 * ART_SCALE)
		var duration := clampf(from.distance_to(to_point) / PROJECTILE_SPEED,
			PROJECTILE_MIN_DURATION, PROJECTILE_MAX_DURATION)
		# 球半径 8.0（原 6.0）：这是全法师最高频的视觉，6px 在 1280 宽的屏幕上只有 0.5% 宽，
		# 加上辉光与彗尾后仍偏小（工程 106 §3.1 预览实测）。8.0 时辉光 20.8px、尾长 ≈ 65px。
		bolt.call("setup", from, to_point,
			Color(String(SPELL_COLORS.get(skill_id, "ffd479"))), 8.0, duration)

func _reset_regen_after_hit() -> void:
	_regen_elapsed = 0.0

func _tick_regen(delta: float) -> void:
	if is_dead or delta <= 0.0 or get_tree().paused:
		return
	_regen_elapsed += delta
	if _regen_elapsed < REGEN_INTERVAL:
		return
	var ticks := int(floorf(_regen_elapsed / REGEN_INTERVAL))
	_regen_elapsed -= float(ticks) * REGEN_INTERVAL
	var hp_max := GameState.max_hp()
	var mp_max := GameState.max_mp()
	if int(GameState.player.hp) < hp_max:
		var hp_points := maxi(1, roundi(float(hp_max) * (SIT_HP_RATE if is_sitting else IDLE_HP_RATE)))
		GameState.heal_player(hp_points * ticks)
	if int(GameState.player.mp) < mp_max:
		var mp_points := maxi(1, roundi(float(mp_max) * (SIT_MP_RATE if is_sitting else IDLE_MP_RATE)))
		GameState.restore_mp(mp_points * ticks)

## 攻击范围内的最近敌人（手动普攻的目标搜索；自动战斗为 3.14 的锚点搜索）。
func find_nearest_enemy_in_range() -> Node:
	var rng_px := melee_range_px()
	var best: Node = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not valid_target(e):
			continue
		var d := global_position.distance_to((e as Node2D).global_position)
		if d <= rng_px and d < best_d:
			best_d = d
			best = e
	return best

func _target_defense(t: Node) -> float:
	return t.get_defense() if t.has_method("get_defense") else 0.0

## A2 越级伤害（03 §3.13）：结算用的目标等级。测试桩等无 `level` 的目标按同级处理 ⇒
## `dmgMult` 恒 1.0，不改变既有战斗用例的期望值。
func _target_level(t: Node) -> int:
	var value: Variant = t.get("level")
	return int(value) if value is int or value is float else int(GameState.player.get("level", 1))

## R4-c：把技能配置里的 `debuff` 落到目标身上。
## 能力尚未实现时**不静默跳过**：写入不了就在目标上留下可观测的缺失（测试直接断言状态），
## 避免「描述写了、行为没有」的假技能。
func _apply_skill_debuff(t: Node, skill: Dictionary) -> void:
	var debuff: Variant = skill.get("debuff")
	if not debuff is Dictionary:
		return
	var row: Dictionary = debuff
	match String(row.get("type", "")):
		"armorBreak":
			if t.has_method("apply_armor_break"):
				t.apply_armor_break(float(row.get("duration", 0.0)))
		"slow":
			# 工程 98：冰咆哮。怪物侧 `apply_slow` 自己处理 Boss 减半（见 monster.gd），
			# 这里不做职业 / 目标判断 —— 两个地方各写一份豁免规则必然漂移。
			if t.has_method("apply_slow"):
				t.apply_slow(float(row.get("value", 0.0)), float(row.get("duration", 0.0)))

## 多段结算的提前收手判据：目标已死就不再吃后续段。
func _target_is_dead(t: Node) -> bool:
	var dead: Variant = t.get("is_dead")
	return dead is bool and bool(dead)

func _target_dodge(t: Node) -> float:
	return t.get_dodge() if t.has_method("get_dodge") else 0.0

## 绘制玩家地面阴影和头顶信息；骑乘时抬高名称与血条，给护罩留出空间。
func _draw() -> void:
	if sample_art != null:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, Iso.GROUND_SQUASH))
		draw_circle(Vector2.ZERO, 14 * ART_SCALE, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if is_sitting:
			# 打坐圈画在地面，必须是贴地的等距椭圆
			GroundFx.outline(self, Vector2.ZERO, 19.0, Color("78d8d0"), 1.0, 24)
		_draw_overhead_name(-141.0 if _mount_art_visible else -119.0)
		_draw_overhead_hp(-134.0 if _mount_art_visible else -112.0)
		return
	# 占位角色：圆形身体 + 描边；死亡态转灰（脚底碰撞体见 CollisionShape2D）
	var body := COLOR_DEAD if is_dead else COLOR_BODY
	if is_sitting:
		draw_circle(Vector2(0, 5), RADIUS, body)
		draw_arc(Vector2(0, 5), RADIUS, 0.0, TAU, 28, COLOR_EDGE, 2.0, true)
		draw_line(Vector2(-15, 17), Vector2(15, 17), COLOR_EDGE, 3.0)
	else:
		draw_circle(Vector2.ZERO, RADIUS, body)
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 28, COLOR_EDGE, 2.0, true)
	_draw_overhead_name(-37.0)
	_draw_overhead_hp(-30.0)

func _draw_overhead_name(baseline_y: float) -> void:
	var name := String(GameState.player.get("name", "守护者"))
	var origin := Vector2(-90.0, baseline_y)
	draw_string(MONO_FONT, origin + Vector2(1.0, 1.0), name,
		HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, Color(0.0, 0.0, 0.0, 0.85))
	draw_string(MONO_FONT, origin, name,
		HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, Color("a7efed"))

func _draw_overhead_hp(y: float) -> void:
	var width := 60.0
	var height := 5.0
	var ratio := clampf(float(GameState.player.hp) / float(maxi(1, GameState.max_hp())), 0.0, 1.0)
	var rect := Rect2(-width * 0.5, y, width, height)
	draw_rect(rect, COLOR_HEAD_HP_BG)
	draw_rect(Rect2(rect.position, Vector2(width * ratio, height)), COLOR_HEAD_HP_FG)
	draw_rect(rect, Color(0, 0, 0, 0.65), false, 1.0)

func set_sitting(value: bool) -> void:
	if is_dead and value or is_sitting == value:
		return
	is_sitting = value
	if value:
		GameState.clear_buffs()
		map_move_active = false
		manual_attack_active = false
		auto_move = Vector2.ZERO
		velocity = Vector2.ZERO
		var pilot := get_node_or_null("AutoPilot") as AutoBattle
		if pilot != null:
			pilot.begin_manual_override()
	EventBus.player_sitting_changed.emit(is_sitting)
	queue_redraw()
