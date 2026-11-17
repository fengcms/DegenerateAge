class_name SampleWalkSprite
extends Sprite2D
## 隔离营地主角行走试装：按实际位移推进单向图集；停步、未制作方向或关闭试装时回退原图。
## 沿既有角色清单的frameSize/pivot/frames约定构建共享区域，不加载正式CharacterLook的全量预载资源。
var enabled := true
var walking := false
var walk_frame := 0
var phase_distance := 0.0
var stride_pixels := 64.0
var idle_texture: Texture2D
var idle_offset := Vector2.ZERO
var walk_offset := Vector2.ZERO
var frames: Array[AtlasTexture] = []

## 加载期一次性切分一列多行的单方向图集，保留原图作为明确回退；运行不创建新纹理。
func setup(idle: Texture2D, atlas: Texture2D, spec: Dictionary) -> void:
	idle_texture = idle
	idle_offset = -Vector2(idle.get_width()*0.5,idle.get_height())
	walk_offset = -Vector2(spec.pivot[0],spec.pivot[1])
	stride_pixels = float(spec.stridePixels)
	assert(spec.directions==["se"] and stride_pixels>0)
	var size := Vector2(spec.frameSize[0],spec.frameSize[1])
	assert(atlas.get_size()==size*Vector2(1,spec.states.walk.frames))
	for index in range(spec.states.walk.frames):
		var region := AtlasTexture.new()
		region.atlas = atlas
		region.region = Rect2(Vector2(0,index*size.y),size)
		region.filter_clip = true
		frames.append(region)
	centered = false
	texture = idle_texture
	offset = idle_offset

## 位移单位为世界屏幕像素，必须在move_and_slide后传入；不会移动角色或改变速度、碰撞。
func update_motion(displacement: Vector2) -> void:
	var moving := enabled and displacement.length_squared()>0.0001
	var supported := moving and displacement.normalized().dot(Vector2(2,1).normalized())>=0.9238795
	if not supported:
		walking = false
		phase_distance = 0
		walk_frame = 0
		if texture != idle_texture:
			texture = idle_texture
			offset = idle_offset
		return
	walking = true
	phase_distance = fposmod(phase_distance+displacement.length(),stride_pixels)
	walk_frame = floori(phase_distance/stride_pixels*frames.size())
	if texture != frames[walk_frame]:
		texture = frames[walk_frame]
		offset = walk_offset
