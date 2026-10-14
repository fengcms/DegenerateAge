class_name QualityFrameOverlay
extends TextureRect
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

var _region := AtlasTexture.new()
var _elapsed := 0.0
var _frame := -1

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)

func set_quality(quality: String) -> void:
	if not ATLASES.has(quality):
		visible = false
		set_process(false)
		texture = null
		return
	_region.atlas = ATLASES[quality]
	texture = _region
	_elapsed = 0.0
	_frame = -1
	visible = true
	_update_frame()
	set_process(true)

func _process(delta: float) -> void:
	_elapsed += delta
	_update_frame()

func _update_frame() -> void:
	var next_frame := int(_elapsed * FPS) % FRAME_COUNT
	if next_frame == _frame:
		return
	_frame = next_frame
	_region.region = Rect2((_frame % COLUMNS) * FRAME_SIZE,
		floori(float(_frame) / COLUMNS) * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
