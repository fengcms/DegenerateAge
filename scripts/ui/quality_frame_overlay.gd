class_name QualityFrameOverlay
extends TextureRect
## 装备品质边框动画：复用品质图集，以真实时钟选帧；节点隐藏时停更，不处理装备规则。
## Animated square border for an equipment instance's quality.

const ATLASES := {
	"uncommon": preload("res://assets/sprites/equip/quality_frames/uncommon_atlas.png"),
	"rare": preload("res://assets/sprites/equip/quality_frames/rare_atlas.png"),
	"epic": preload("res://assets/sprites/equip/quality_frames/epic_atlas.png"),
	"legendary": preload("res://assets/sprites/equip/quality_frames/legendary_atlas.png"),
}
const FRAME_SIZE := 64
const COLUMNS := 6
const FRAME_COUNT := 24
const FPS := 12.0
const OUTSET := 2.0

var _region := AtlasTexture.new()
var _quality := ""
var _started_usec := 0
var _frame := -1

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = -OUTSET
	offset_top = -OUTSET
	offset_right = OUTSET
	offset_bottom = OUTSET
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	visibility_changed.connect(_sync_processing)

func set_quality(quality: String) -> void:
	if quality == _quality:
		return
	_quality = quality
	if not ATLASES.has(quality):
		visible = false
		set_process(false)
		texture = null
		return
	_region.atlas = ATLASES[quality]
	texture = _region
	_started_usec = Time.get_ticks_usec()
	_frame = -1
	visible = true
	_update_frame()
	_sync_processing()

func _sync_processing() -> void:
	set_process(is_visible_in_tree() and ATLASES.has(_quality))

func _process(_delta: float) -> void:
	_update_frame()

func _update_frame() -> void:
	var elapsed := (Time.get_ticks_usec() - _started_usec) / 1000000.0
	var next_frame := int(elapsed * FPS) % FRAME_COUNT
	if next_frame == _frame:
		return
	_frame = next_frame
	_region.region = Rect2((_frame % COLUMNS) * FRAME_SIZE,
		floori(float(_frame) / COLUMNS) * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
