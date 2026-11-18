class_name SampleWalkSprite
extends Sprite2D
## 隔离营地主角行走试装：按实际位移推进三个已制作方向的图集；停步保持朝向站姿，未制作方向或关闭试装时回退原图。
## 沿既有角色清单的frameSize/pivot/frames约定构建共享区域，不加载正式CharacterLook的全量预载资源。
var enabled := true
var walking := false
var walk_frame := 0
var phase_distance := 0.0
var stride_pixels := 64.0
var facing_id := ""
var left_idle: Texture2D
var left_frames: Array[AtlasTexture] = []
var rear_idle: Texture2D
var directional_idle: Texture2D
var idle_texture: Texture2D
var idle_offset := Vector2.ZERO
var walk_offset := Vector2.ZERO
var frames: Array[AtlasTexture] = []
var rear_frames: Array[AtlasTexture] = []

## 加载期一次性切分一列多行的三个方向图集，保留原图作为明确回退；运行不创建新纹理。
func setup(idle: Texture2D, atlas: Texture2D, matching_idle: Texture2D, matching_rear: Texture2D, rear_atlas: Texture2D, left_atlas: Texture2D, matching_left: Texture2D, spec: Dictionary) -> void:
	idle_texture = idle
	directional_idle = matching_idle
	rear_idle = matching_rear
	left_idle = matching_left
	idle_offset = -Vector2(idle.get_width()*0.5,idle.get_height())
	walk_offset = -Vector2(spec.pivot[0],spec.pivot[1])
	stride_pixels = float(spec.stridePixels)
	assert(spec.directions==["se","ne","sw"] and stride_pixels>0)
	var size := Vector2(spec.frameSize[0],spec.frameSize[1])
	assert(atlas.get_size()==size*Vector2(1,spec.states.walk.frames))
	assert(rear_atlas.get_size()==atlas.get_size() and left_atlas.get_size()==atlas.get_size())
	assert(left_idle.get_size()==size)
	assert(directional_idle.get_size()==size and rear_idle.get_size()==size)
	for index in range(spec.states.walk.frames):
		var region := AtlasTexture.new()
		region.atlas = atlas
		region.region = Rect2(Vector2(0,index*size.y),size)
		region.filter_clip = true
		frames.append(region)
		var rear: AtlasTexture = region.duplicate()
		rear.atlas = rear_atlas
		rear_frames.append(rear)
		var left: AtlasTexture = region.duplicate()
		left.atlas = left_atlas
		left_frames.append(left)
	centered = false
	texture = idle_texture
	offset = idle_offset

## 位移是碰撞后的世界屏幕像素；意图只决定朝向，不推进相位，不移动角色或改变物理。
func update_motion(displacement: Vector2, intent := Vector2.ZERO) -> void:
	var facing := intent if intent.length_squared()>0.0001 else displacement
	if facing.length_squared()>0.0001:
		facing_id = _direction_id(facing)
	var moving := displacement.length_squared()>0.0001
	var supported := enabled and not facing_id.is_empty() and moving and _direction_id(displacement)==facing_id
	if not supported:
		walking = false
		phase_distance = 0
		walk_frame = 0
		var resting: Texture2D = idle_texture
		if enabled and facing_id=="se":
			resting = directional_idle
		elif enabled and facing_id=="sw":
			resting = left_idle
		elif enabled and facing_id=="ne":
			resting = rear_idle
		if texture != resting:
			texture = resting
			offset = idle_offset if resting==idle_texture else walk_offset
		return
	walking = true
	phase_distance = fposmod(phase_distance+displacement.length(),stride_pixels)
	var active: Array[AtlasTexture] = frames if facing_id=="se" else (rear_frames if facing_id=="ne" else left_frames)
	walk_frame = floori(phase_distance/stride_pixels*active.size())
	if texture != active[walk_frame]:
		texture = active[walk_frame]
		offset = walk_offset

## 单向试装范围以屏幕右下(2,1)为中心；调用前保证向量非零，不冒充其他方向。
func _supports(direction: Vector2) -> bool:
	return direction.normalized().dot(Vector2(2,1).normalized())>=0.9238795

## 只返回已制作的三个朝向；其他方向显式回退，不复制正面或镜像武器来充数。
func _direction_id(direction: Vector2) -> String:
	if _supports(direction):
		return "se"
	if direction.normalized().dot(Vector2(2,-1).normalized())>=0.9238795:
		return "ne"
	if direction.normalized().dot(Vector2(-2,1).normalized())>=0.9238795:
		return "sw"
	return ""
