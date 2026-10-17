extends Node2D
## 初始角色六状态八向动画的独立审稿场景。
## 只播放已打包图集，不修改正式玩家与怪物状态机；按数字 1—6 切换状态。

const DIR_LABELS := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
const STATES := ["idle", "walk", "attack", "hit", "death", "sit"]
const FRAMES := [4, 8, 6, 2, 6, 4]
const FPS := [6.0, 10.0, 12.0, 10.0, 8.0, 6.0]
const TEXTURES := [
	preload("res://assets/sprites/player/guardian/animations/guardian_idle_atlas.png"),
	preload("res://assets/sprites/player/guardian/animations/guardian_walk_atlas.png"),
	preload("res://assets/sprites/player/guardian/animations/guardian_attack_atlas.png"),
	preload("res://assets/sprites/player/guardian/animations/guardian_hit_atlas.png"),
	preload("res://assets/sprites/player/guardian/animations/guardian_death_atlas.png"),
	preload("res://assets/sprites/player/guardian/animations/guardian_sit_atlas.png"),
]

var _sprites: Array[Sprite2D] = []
var _state_label: Label
var _state_index := 0
var _clock := 0.0

## 创建八向角色及说明标签，默认播放待机。
func _ready() -> void:
	var help := Label.new()
	help.text = "look_01 animation preview | 1 Idle   2 Walk   3 Attack   4 Hit   5 Death   6 Sit"
	help.position = Vector2(45, 70)
	help.add_theme_font_size_override("font_size", 23)
	add_child(help)
	_state_label = Label.new()
	_state_label.position = Vector2(45, 135)
	_state_label.add_theme_font_size_override("font_size", 27)
	add_child(_state_label)
	for direction in range(8):
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.hframes = 8
		sprite.offset = -Vector2(32, 64)
		sprite.position = Vector2(90 + direction * 150, 365)
		sprite.scale = Vector2(2.0, 2.0)
		add_child(sprite)
		_sprites.append(sprite)
		var label := Label.new()
		label.text = DIR_LABELS[direction]
		label.position = Vector2(70 + direction * 150, 420)
		label.add_theme_font_size_override("font_size", 22)
		add_child(label)
	_select_state(0)

## 绘制中性深色底板，方便检查透明边缘与像素轮廓。
func _draw() -> void:
	draw_rect(Rect2(-300, -300, 1800, 1300), Color("10191e"))
	draw_line(Vector2(45, 367), Vector2(1220, 367), Color("536267"), 1.0)

## 使用状态的预览帧率推进所有方向，同帧对照脚底与造型一致性。
func _process(delta: float) -> void:
	_clock += delta
	var phase := posmod(int(_clock * FPS[_state_index]), FRAMES[_state_index])
	for direction in range(8):
		_sprites[direction].frame_coords = Vector2i(direction, phase)

## 数字 1—6 切换动作状态；本审稿场景不响应战斗输入。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var digit: int = int(event.keycode) - int(KEY_1)
		if digit >= 0 and digit < STATES.size():
			_select_state(digit)

## 更换整张状态图集与行数，时间从首帧重新开始。
func _select_state(index: int) -> void:
	_state_index = index
	_clock = 0.0
	_state_label.text = "%s | %d frames × 8 directions | %.0f FPS" % [STATES[index], FRAMES[index], FPS[index]]
	for sprite in _sprites:
		sprite.texture = TEXTURES[index]
		sprite.vframes = FRAMES[index]
		sprite.frame_coords = Vector2i(_sprites.find(sprite), 0)
