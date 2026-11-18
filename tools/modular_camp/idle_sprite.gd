class_name SampleIdleSprite
extends Sprite2D
## 隔离营地怪物待机和单次攻击试装：缓存图集区域并按秒循环，不控制移动、碰撞、AI或伤害。
## 仅加载期构建区域，热路径切换引用；关闭动作恢复原静态图，切图由父场景释放。
var attacking := false
var attack_elapsed := 0.0
var attack_duration := 0.0
var attack_seconds: Array[float] = []
var attack_regions: Array[AtlasTexture] = []
var regions: Array[AtlasTexture] = []
var original: Texture2D
var original_offset := Vector2.ZERO
var idle_offset := Vector2.ZERO
var fps := 3.0
var elapsed := 0.0
var current_frame := 0
var enabled := true
var paused := false

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
	attacking = false
	attack_elapsed = 0
	enabled = value
	elapsed = 0.0
	current_frame = 0
	texture = regions[0] if enabled else original
	offset = idle_offset if enabled else original_offset
	set_process(enabled and not paused)

## 固定数量对象按秒更新；卡顿后直接恢复正确循环相位，不累积补帧队列。
func _process(delta: float) -> void:
	if attacking:
		attack_elapsed += delta
		if attack_elapsed>=attack_duration:
			_finish_attack()
			return
		var boundary := attack_seconds[0]
		current_frame = 0
		while attack_elapsed>=boundary and current_frame<attack_regions.size()-1:
			current_frame += 1
			boundary += attack_seconds[current_frame]
		texture = attack_regions[current_frame]
		return
	elapsed = fposmod(elapsed+delta,regions.size()/fps)
	var next := floori(elapsed*fps)
	if next!=current_frame:
		current_frame = next
		texture = regions[current_frame]

## 原地保留当前帧与时间余量暂停，仅停止待机回调，不暂停物理或场景树。
func set_paused(value: bool) -> void:
	paused = value
	set_process(enabled and not paused)

## 暂停并前进一步，待机末帧循环、攻击末帧回待机首帧；原图对照关闭状态不换图，恢复播放从该帧开始。
func step_frame() -> void:
	set_paused(true)
	if not enabled:
		return
	if attacking:
		if current_frame==attack_regions.size()-1:
			_finish_attack()
		else:
			current_frame += 1
			attack_elapsed = 0
			for index in range(current_frame):
				attack_elapsed += attack_seconds[index]
			texture = attack_regions[current_frame]
		return
	current_frame = (current_frame+1)%regions.size()
	elapsed = current_frame/fps
	texture = regions[current_frame]

## 加载单方向攻击图集和秒制阶段，复用待机帧格与锚点；不创建AI、碰撞或伤害事件。
func setup_attack(atlas: Texture2D, spec: Dictionary) -> void:
	assert(spec.frames==4 and not spec.loop and spec.frameSeconds.size()==4)
	var size := Vector2(spec.frameSize[0],spec.frameSize[1])
	assert(atlas.get_size()==size*Vector2(1,4) and size==regions[0].region.size)
	assert(Vector2(spec.pivot[0],spec.pivot[1])==-idle_offset)
	for index in range(4):
		var region: AtlasTexture = regions[index].duplicate()
		region.atlas = atlas
		attack_regions.append(region)
		var seconds := float(spec.frameSeconds[index])
		assert(seconds>0)
		attack_seconds.append(seconds)
		attack_duration += seconds

## 单次原地攻击预览；播放中或原图对照时拒绝，暂停时停在首帧供逐帧审查。
func start_attack() -> bool:
	if not enabled or attacking or attack_regions.is_empty():
		return false
	attacking = true
	attack_elapsed = 0
	current_frame = 0
	texture = attack_regions[0]
	return true

## 完成后恢复待机首帧并保留暂停选择；不遗留计时器、信号或动作队列。
func _finish_attack() -> void:
	attacking = false
	attack_elapsed = 0
	elapsed = 0
	current_frame = 0
	texture = regions[0]
