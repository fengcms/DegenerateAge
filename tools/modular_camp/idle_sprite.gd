class_name SampleIdleSprite
extends Sprite2D
## 隔离营地怪物待机试装：缓存图集区域并按秒循环，不控制移动、碰撞、AI或伤害。
## 仅加载期构建区域，热路径切换引用；关闭动作恢复原静态图，切图由父场景释放。
var regions: Array[AtlasTexture] = []
var original: Texture2D
var original_offset := Vector2.ZERO
var idle_offset := Vector2.ZERO
var fps := 3.0
var elapsed := 0.0
var current_frame := 0
var enabled := true

## 以运行图集和清单初始化一次，原静态图及落点用于J键对照；不加工源稿。
func setup(atlas: Texture2D, spec: Dictionary) -> void:
	original = texture
	original_offset = offset
	idle_offset = -Vector2(spec.pivot[0],spec.pivot[1])
	fps = float(spec.fps)
	var size := Vector2(spec.frameSize[0],spec.frameSize[1])
	assert(spec.frames==4 and fps>0 and atlas.get_size()==size*Vector2(1,4))
	for index in range(4):
		var region := AtlasTexture.new()
		region.atlas = atlas
		region.region = Rect2(Vector2(0,index*size.y),size)
		region.filter_clip = true
		regions.append(region)
	set_enabled(true)

## 切换到原图或待机首帧并清零相位，位置、缩放和排序不变；关闭时停止帧回调。
func set_enabled(value: bool) -> void:
	enabled = value
	elapsed = 0.0
	current_frame = 0
	texture = regions[0] if enabled else original
	offset = idle_offset if enabled else original_offset
	set_process(enabled)

## 固定数量对象按秒更新；卡顿后直接恢复正确循环相位，不累积补帧队列。
func _process(delta: float) -> void:
	elapsed = fposmod(elapsed+delta,regions.size()/fps)
	var next := floori(elapsed*fps)
	if next!=current_frame:
		current_frame = next
		texture = regions[current_frame]
