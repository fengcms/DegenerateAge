extends Control
## M6-0a（创意 07 §4）：Boss 顶部血条。
##
## 挂 `Main.tscn` 的 `UI` 下（随 UI 轴缩放，见 `SettingsRuntime.apply_ui_scale_to`）。
## 数据源＝`EventBus.boss_hp_changed`（由 `Monster` 在受击 / 阶段变更 / 进入仇恨 / 死亡时广播）。
## 显隐：任一更新 → 显示；脱战 3s 无更新 → 隐藏；死亡（hp≤0）停留 0.6s 后淡出。

const MONO_FONT := preload("res://assets/themes/mono_font.tres")

const HIDE_AFTER := 3.0           # 脱战隐藏延迟（s）
const FADE_AFTER_DEATH := 0.6     # 死亡后停留（s），随后淡出
const BAR_W := 480.0
const BAR_H := 18.0
const TOP_Y := 22.0
## 三阶段名（对应 monsters.json 的 bossSkill.phases 0/1/2，创意 07 §4）。
const PHASE_KEYS := ["ui.boss.phase_sealed", "ui.boss.phase_cracked", "ui.boss.phase_corrupted"]

const COL_BG := Color(0.06, 0.02, 0.03, 0.88)
const COL_EDGE := Color(0.58, 0.18, 0.18, 0.95)
const COL_FILL := Color(0.78, 0.16, 0.18, 1.0)
const COL_TICK := Color(1.0, 0.85, 0.4, 0.8)
const COL_NAME := Color(0.96, 0.89, 0.87, 1.0)
const COL_PHASE := Color(0.96, 0.74, 0.64, 1.0)
const COL_HP_TEXT := Color(1.0, 1.0, 1.0, 0.85)

var _boss_name := ""
var _hp := 0
var _max_hp := 1
var _phase := 0
var _since_update := 0.0
var _dying := false
var _tween: Tween = null

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.boss_hp_changed.connect(_on_boss_hp)

func _process(delta: float) -> void:
	if not visible or _dying:
		return
	_since_update += delta
	if _since_update >= HIDE_AFTER:
		visible = false

func _on_boss_hp(boss_name: String, hp: int, max_hp: int, phase: int) -> void:
	if hp <= 0:
		_begin_death_fade(boss_name)
		return
	_kill_tween()
	_boss_name = boss_name
	_hp = hp
	_max_hp = maxi(1, max_hp)
	_phase = phase
	_since_update = 0.0
	_dying = false
	modulate.a = 1.0
	visible = true
	queue_redraw()

func _begin_death_fade(boss_name: String) -> void:
	if not visible:
		return
	_boss_name = boss_name
	_hp = 0
	_since_update = 0.0
	queue_redraw()
	_dying = true
	_kill_tween()
	_tween = create_tween()
	_tween.tween_interval(FADE_AFTER_DEATH)
	_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	_tween.tween_callback(_hide_now)

func _hide_now() -> void:
	visible = false
	_dying = false
	modulate.a = 1.0
	_tween = null

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

func _draw() -> void:
	var cx := size.x * 0.5
	var left := cx - BAR_W * 0.5
	# 名称（血条上方居中）
	draw_string(MONO_FONT, Vector2(left, TOP_Y - 7.0), _boss_name,
		HORIZONTAL_ALIGNMENT_CENTER, BAR_W, 17, COL_NAME)
	# 底板 + 血量
	draw_rect(Rect2(left, TOP_Y, BAR_W, BAR_H), COL_BG)
	var ratio := clampf(float(_hp) / float(_max_hp), 0.0, 1.0)
	if ratio > 0.0:
		draw_rect(Rect2(left, TOP_Y, BAR_W * ratio, BAR_H), COL_FILL)
	# 阶段刻度（60% / 30%）
	for t in [0.6, 0.3]:
		var tx := left + BAR_W * float(t)
		draw_line(Vector2(tx, TOP_Y), Vector2(tx, TOP_Y + BAR_H), COL_TICK, 2.0, true)
	draw_rect(Rect2(left, TOP_Y, BAR_W, BAR_H), COL_EDGE, false, 2.0)
	# 血量数值（左）+ 阶段名（中）
	draw_string(MONO_FONT, Vector2(left + 8.0, TOP_Y + BAR_H - 4.0), "%d / %d" % [_hp, _max_hp],
		HORIZONTAL_ALIGNMENT_LEFT, BAR_W - 16.0, 11, COL_HP_TEXT)
	var phase_name := Localization.tr_key(PHASE_KEYS[clampi(_phase, 0, PHASE_KEYS.size() - 1)])
	draw_string(MONO_FONT, Vector2(left, TOP_Y + BAR_H - 4.0), phase_name,
		HORIZONTAL_ALIGNMENT_CENTER, BAR_W, 11, COL_PHASE)
