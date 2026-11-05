extends Control
## HUD 等级徽章：按完整等级文字的实际字宽扩展金边底牌，仅在文字/主题变化时重新布局。
## 保持右缘位置，向头像一侧扩展，避免遮挡右侧自动战斗等状态图标；不改变角色等级数据。

const MIN_WIDTH := 35.0
const TEXT_PADDING := 10.0
@onready var _label: Label = $LevelLabel
var _layers: Array[StyleBoxFlat] = []

## 缓存圆角底牌样式并监听字体/文字最小尺寸变化，无逐帧测量与资源创建。
func _ready() -> void:
	for color in ["13120f", "917139", "d2b571", "43331f", "614726"]:
		var layer := StyleBoxFlat.new()
		layer.bg_color = Color(color)
		layer.corner_detail = 12
		_layers.append(layer)
	_label.minimum_size_changed.connect(_fit_text)
	resized.connect(queue_redraw)
	_fit_text()

## 按当前主题字体测量完整数字，保留左右内边距和原右缘；短等级恢复原圆形大小。
func _fit_text() -> void:
	var font := _label.get_theme_font("font")
	var font_size := _label.get_theme_font_size("font_size")
	var width := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var right := position.x + size.x
	size.x = maxf(MIN_WIDTH, ceilf(width + TEXT_PADDING * 2.0))
	position.x = right - size.x
	queue_redraw()

## 绘制同一组圆角金边；宽度等于高度时为圆形，长等级自然延展为胶囊。
func _draw() -> void:
	var insets := [0.0, 2.0, 4.0, 5.5, 7.0]
	for i in range(_layers.size()):
		var inset: float = insets[i]
		var radius := maxi(0, int((size.y - inset * 2.0) * 0.5))
		for corner in range(4):
			_layers[i].set_corner_radius(corner, radius)
		draw_style_box(_layers[i], Rect2(Vector2.ZERO, size).grow(-inset))
	for point in [Vector2(3, size.y * 0.5), Vector2(size.x - 3, size.y * 0.5), Vector2(size.x * 0.5, 3), Vector2(size.x * 0.5, size.y - 3)]:
		draw_circle(point, 1.0, Color("f4dc9a"))
