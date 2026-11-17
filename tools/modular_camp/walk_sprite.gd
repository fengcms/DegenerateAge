class_name SampleWalkSprite
extends Sprite2D
## 隔离营地主角行走试装：按实际位移推进单向图集；停步保持朝向站姿，未制作方向或关闭试装时回退原图。
## 沿既有角色清单的frameSize/pivot/frames约定构建共享区域，不加载正式CharacterLook的全量预载资源。
var enabled := true
var walking := false
var walk_frame := 0
var phase_distance := 0.0
var stride_pixels := 64.0
var facing_id := ""
var rear_idle: Texture2D
var directional_idle: Texture2D
var idle_texture: Texture2D
var idle_offset := Vector2.ZERO
var walk_offset := Vector2.ZERO
var frames: Array[AtlasTexture] = []

## 加载期一次性切分一列多行的单方向图集，保留原图作为明确回退；运行不创建新纹理。
func setup(idle: Texture2D, atlas: Texture2D, matching_idle: Texture2D, matching_rear: Texture2D, spec: Dictionary) -> void:
	idle_texture = idle
	directional_idle = matching_idle
	rear_idle = matching_rear
	idle_offset = -Vector2(idle.get_width()*0.5,idle.get_height())
	walk_offset = -Vector2(spec.pivot[0],spec.pivot[1])
	stride_pixels = float(spec.stridePixels)
	assert(spec.directions==["se"] and stride_pixels>0)
	var size := Vector2(spec.frameSize[0],spec.frameSize[1])
	assert(atlas.get_size()==size*Vector2(1,spec.states.walk.frames))
	assert(directional_idle.get_size()==size and rear_idle.get_size()==size)
	for index in range(spec.states.walk.frames):
		var region := AtlasTexture.new()
		region.atlas = atlas
		region.region = Rect2(Vector2(0,index*size.y),size)
		region.filter_clip = true
		frames.append(region)
	centered = false
	texture = idle_texture
	offset = idle_offset

## 位移是碰撞后的世界屏幕像素；意图只决定朝向，不推进相位，不移动角色或改变物理。
func update_motion(displacement: Vector2, intent := Vector2.ZERO) -> void:
	var facing := intent if intent.length_squared()>0.0001 else displacement
	if facing.length_squared()>0.0001:
		facing_id = _direction_id(facing)
	var moving := displacement.length_squared()>0.0001
	var supported := enabled and facing_id=="se" and moving and _supports(displacement)
	if not supported:
		walking = false
		phase_distance = 0
		walk_frame = 0
		var resting: Texture2D = idle_texture
		if enabled and facing_id=="se":
			resting = directional_idle
		elif enabled and facing_id=="ne":
			resting = rear_idle
		if texture != resting:
			texture = resting
			offset = idle_offset if resting==idle_texture else walk_offset
		return
	walking = true
	phase_distance = fposmod(phase_distance+displacement.length(),stride_pixels)
	walk_frame = floori(phase_distance/stride_pixels*frames.size())
	if texture != frames[walk_frame]:
		texture = frames[walk_frame]
		offset = walk_offset

## 单向试装范围以屏幕右下(2,1)为中心；调用前保证向量非零，不冒充其他方向。
func _supports(direction: Vector2) -> bool:
	return direction.normalized().dot(Vector2(2,1).normalized())>=0.9238795

## 只返回已制作的两个朝向；其他方向显式回退，不复制正面或镜像武器来充数。
func _direction_id(direction: Vector2) -> String:
	if _supports(direction):
		return "se"
	if direction.normalized().dot(Vector2(2,-1).normalized())>=0.9238795:
		return "ne"
	return ""
