extends Node2D
## `look_01` 腐化之翼八向审稿场景。
## 上方展示佩戴双翼，下方展示同方向未佩戴角色，以相同缩放核对体量；按 1/2 切换待机和行走。

const WING_IDLE := preload("res://docs/素材设计/样板/初始角色C/corrupted_wing_idle_candidate_atlas.png")
const WING_WALK := preload("res://docs/素材设计/样板/初始角色C/corrupted_wing_walk_candidate_atlas.png")
const BASE_IDLE := preload("res://assets/sprites/player/guardian/animations/guardian_idle_atlas.png")
const BASE_WALK := preload("res://assets/sprites/player/guardian/animations/guardian_walk_atlas.png")
const DIRECTIONS := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]

var _wing_sprites: Array[Sprite2D] = []
var _base_sprites: Array[Sprite2D] = []
var _mode := 0
var _clock := 0.0
var _label: Label

## 建立上方双翼与下方原角色情形，按方向逐列对齐脚底线。
func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(35, 35)
	_label.add_theme_font_size_override("font_size", 25)
	add_child(_label)
	for direction in range(8):
		var wing := Sprite2D.new()
		wing.centered = false
		wing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		wing.hframes = 8
		wing.vframes = 4
		wing.offset = -Vector2(64, 104)
		wing.position = Vector2(95 + direction * 150, 340)
		wing.scale = Vector2(2.0, 2.0)
		add_child(wing)
		_wing_sprites.append(wing)
		var base := Sprite2D.new()
		base.centered = false
		base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		base.hframes = 8
		base.vframes = 4
		base.offset = -Vector2(32, 64)
		base.position = Vector2(95 + direction * 150, 650)
		base.scale = Vector2(2.0, 2.0)
		add_child(base)
		_base_sprites.append(base)
		var label := Label.new()
		label.text = DIRECTIONS[direction]
		label.position = Vector2(65 + direction * 150, 385)
		label.add_theme_font_size_override("font_size", 20)
		add_child(label)
	_select_mode(0)

## 绘制深底与两条地面线，便于观察脚底锚点和轮廓亮度。
func _draw() -> void:
	draw_rect(Rect2(-300, -300, 1800, 1300), Color("10191e"))
	draw_line(Vector2(35, 340), Vector2(1220, 340), Color("536267"), 1.0)
	draw_line(Vector2(35, 650), Vector2(1220, 650), Color("536267"), 1.0)

## 以统一时间推进两排角色的方向帧，查看双翼与未佩戴版本的动作差别。
func _process(delta: float) -> void:
	_clock += delta
	var fps := 6.0 if _mode == 0 else 10.0
	var wing_frame := posmod(int(_clock * fps), 4)
	var base_frame := posmod(int(_clock * fps), 4 if _mode == 0 else 8)
	for direction in range(8):
		_wing_sprites[direction].frame_coords = Vector2i(direction, wing_frame)
		_base_sprites[direction].frame_coords = Vector2i(direction, base_frame)

## 数字 1/2 切换双翼待机和地面移动审稿状态。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_select_mode(0)
		elif event.keycode == KEY_2:
			_select_mode(1)

## 切换两排图集与帧行数，并从首帧重新播放。
func _select_mode(mode: int) -> void:
	_mode = mode
	_clock = 0.0
	_label.text = "Corrupted Wing | 1 Idle / 2 Walk | top: winged guardian, bottom: unmounted guardian"
	for wing in _wing_sprites:
		wing.texture = WING_IDLE if mode == 0 else WING_WALK
		wing.vframes = 4
	for base in _base_sprites:
		base.texture = BASE_IDLE if mode == 0 else BASE_WALK
		base.vframes = 4 if mode == 0 else 8
