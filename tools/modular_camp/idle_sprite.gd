class_name SampleIdleSprite
extends Sprite2D
## 隔离营地怪物待机、攻击、步态与反应试装：缓存区域按秒播放，不控制移动、碰撞、AI或伤害。
## 仅加载期构建区域，热路径切换引用；关闭动作恢复原静态图，切图由父场景释放。
var preview_clips: Dictionary = {}
var preview_state := ""
var preview_elapsed := 0.0
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
	preview_state = ""
	preview_elapsed = 0
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
	if not preview_state.is_empty():
		_advance_preview(delta)
		return
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

## 暂停并逐帧：待机/步态循环，攻击/受击结束回待机，倒地末帧保持；原图关闭不换图。
func step_frame() -> void:
	set_paused(true)
	if not enabled:
		return
	if not preview_state.is_empty():
		var clip: Dictionary = preview_clips[preview_state]
		if current_frame==3:
			if preview_state=="hit":
				reset_preview()
			elif preview_state=="walk":
				preview_elapsed = 0
				current_frame = 0
				texture = clip.regions[0]
		else:
			current_frame += 1
			preview_elapsed = 0
			for index in range(current_frame):
				preview_elapsed += clip.seconds[index]
			texture = clip.regions[current_frame]
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
	if not enabled or attacking or not preview_state.is_empty() or attack_regions.is_empty():
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

## 加载期缓存行走、受击、倒地四帧；共用待机帧格和锚点，不复制图片。
func setup_preview(atlas: Texture2D, spec: Dictionary) -> void:
	var state: String = spec.state
	assert(state in ["walk","hit","death"] and spec.frames==4)
	assert(atlas.get_size()==regions[0].atlas.get_size() and Vector2(spec.pivot[0],spec.pivot[1])==-idle_offset)
	assert(spec.loop==(state=="walk") and spec.holdLast==(state=="death"))
	var cached: Array[AtlasTexture] = []
	var seconds: Array[float] = []
	var duration := 0.0
	for index in range(4):
		var region: AtlasTexture = regions[index].duplicate()
		region.atlas = atlas
		cached.append(region)
		assert(float(spec.frameSeconds[index])>0)
		seconds.append(float(spec.frameSeconds[index]))
		duration += seconds[index]
	preview_clips[state] = {"regions":cached,"seconds":seconds,"duration":duration}

## 启动原地姿态预览，死亡优先且拒绝重入；不模拟AI移动或结算伤害。
func start_preview(state: String) -> bool:
	if not enabled or not preview_clips.has(state) or preview_state=="death" or preview_state==state:
		return false
	if preview_state=="hit" and state=="walk":
		return false
	attacking = false
	attack_elapsed = 0
	preview_state = state
	preview_elapsed = 0
	current_frame = 0
	texture = preview_clips[state].regions[0]
	return true

## 每帧推进至当前时间对应姿态，倒地保持末帧，受击结束回待机；循环不累积队列。
func _advance_preview(delta: float) -> void:
	var clip: Dictionary = preview_clips[preview_state]
	preview_elapsed += delta
	if preview_state=="walk":
		preview_elapsed = fposmod(preview_elapsed,clip.duration)
	elif preview_elapsed>=clip.duration:
		if preview_state=="hit":
			reset_preview()
			return
		preview_elapsed = clip.duration
		current_frame = 3
		texture = clip.regions[3]
		return
	var boundary: float = clip.seconds[0]
	current_frame = 0
	while current_frame<3 and preview_elapsed>=boundary:
		current_frame += 1
		boundary += clip.seconds[current_frame]
	texture = clip.regions[current_frame]

## 显式清空所有视觉动作并恢复待机，保留暂停选择，不改变落点或导航。
func reset_preview() -> void:
	preview_state = ""
	preview_elapsed = 0
	_finish_attack()
	if not enabled:
		texture = original
