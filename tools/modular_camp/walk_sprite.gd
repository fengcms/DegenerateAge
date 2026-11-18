class_name SampleWalkSprite
extends Sprite2D
## 隔离营地主角行走试装：按实际位移推进八个已制作方向的图集；停步保持朝向站姿，关闭试装时回退原图。
## 沿既有角色清单的frameSize/pivot/frames约定构建共享区域，不加载正式CharacterLook的全量预载资源。
const DIRECTION_VECTORS := {"se":Vector2(0.89442719,0.44721360),"ne":Vector2(0.89442719,-0.44721360),"sw":Vector2(-0.89442719,0.44721360),"nw":Vector2(-0.89442719,-0.44721360),"s":Vector2.DOWN,"n":Vector2.UP,"e":Vector2.RIGHT,"w":Vector2.LEFT}
var extra_frames: Dictionary = {}
var extra_idles: Dictionary = {}
var reaction_state := ""
var reaction_playing := false
var reaction_elapsed := 0.0
var reaction_frame := 0
var reaction_frames: Dictionary = {}
var reaction_seconds: Dictionary = {}
var reaction_durations: Dictionary = {}
var attack_variants: Dictionary = {}
var attacking := false
var attack_elapsed := 0.0
var attack_frame := 0
var attack_frames: Array[AtlasTexture] = []
var attack_seconds: Array[float] = []
var attack_duration := 0.0
var enabled := true
var walking := false
var walk_frame := 0
var phase_distance := 0.0
var stride_pixels := 64.0
var facing_id := ""
var front_idle: Texture2D
var front_frames: Array[AtlasTexture] = []
var left_rear_idle: Texture2D
var left_rear_frames: Array[AtlasTexture] = []
var left_idle: Texture2D
var left_frames: Array[AtlasTexture] = []
var rear_idle: Texture2D
var directional_idle: Texture2D
var idle_texture: Texture2D
var idle_offset := Vector2.ZERO
var walk_offset := Vector2.ZERO
var frames: Array[AtlasTexture] = []
var rear_frames: Array[AtlasTexture] = []

## 加载期一次性切分一列多行的四个方向图集，保留原图作为明确回退；运行不创建新纹理。
func setup(idle: Texture2D, atlas: Texture2D, matching_idle: Texture2D, matching_rear: Texture2D, rear_atlas: Texture2D, left_atlas: Texture2D, matching_left: Texture2D, left_rear_atlas: Texture2D, matching_left_rear: Texture2D, spec: Dictionary) -> void:
	idle_texture = idle
	directional_idle = matching_idle
	rear_idle = matching_rear
	left_idle = matching_left
	left_rear_idle = matching_left_rear
	idle_offset = -Vector2(idle.get_width()*0.5,idle.get_height())
	walk_offset = -Vector2(spec.pivot[0],spec.pivot[1])
	stride_pixels = float(spec.stridePixels)
	assert(spec.directions==["se","ne","sw","nw","s","n","e","w"] and stride_pixels>0)
	var size := Vector2(spec.frameSize[0],spec.frameSize[1])
	assert(atlas.get_size()==size*Vector2(1,spec.states.walk.frames))
	assert(rear_atlas.get_size()==atlas.get_size() and left_atlas.get_size()==atlas.get_size())
	assert(left_idle.get_size()==size and left_rear_idle.get_size()==size)
	assert(left_rear_atlas.get_size()==atlas.get_size())
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
		var left_rear: AtlasTexture = region.duplicate()
		left_rear.atlas = left_rear_atlas
		left_rear_frames.append(left_rear)
	centered = false
	texture = idle_texture
	offset = idle_offset

## 位移是碰撞后的世界屏幕像素；意图只决定朝向，不推进相位，不移动角色或改变物理。
func update_motion(displacement: Vector2, intent := Vector2.ZERO) -> void:
	if not reaction_state.is_empty():
		if reaction_state=="death":
			_show_reaction()
			return
		if not enabled or intent.length_squared()>0.0001 or displacement.length_squared()>0.0001:
			reset_reaction()
		else:
			return
	if attacking:
		if not enabled or intent.length_squared()>0.0001 or displacement.length_squared()>0.0001:
			cancel_attack()
		else:
			return
	var facing := intent if intent.length_squared()>0.0001 else displacement
	if facing.length_squared()>0.0001:
		facing_id = _direction_id(facing)
	var moving := displacement.length_squared()>0.0001
	var supported := enabled and not facing_id.is_empty() and moving and _direction_id(displacement)==facing_id
	if not supported:
		walking = false
		phase_distance = 0
		walk_frame = 0
		var resting := idle_for_direction(facing_id) if enabled else idle_texture
		if texture != resting:
			texture = resting
			offset = idle_offset if resting==idle_texture else walk_offset
		return
	walking = true
	phase_distance = fposmod(phase_distance+displacement.length(),stride_pixels)
	var active: Array[AtlasTexture] = frames if facing_id=="se" else (rear_frames if facing_id=="ne" else (left_frames if facing_id=="sw" else (left_rear_frames if facing_id=="nw" else (front_frames if facing_id=="s" else extra_frames[facing_id]))))
	walk_frame = floori(phase_distance/stride_pixels*active.size())
	if texture != active[walk_frame]:
		texture = active[walk_frame]
		offset = walk_offset

## 从八个等距投影朝向中选最接近者；完整覆盖一周，避免旧方向锥之间回退或先后顺序偏置。
func _direction_id(direction: Vector2) -> String:
	if direction.length_squared()<0.0001:
		return ""
	var normalized := direction.normalized()
	var best := ""
	var similarity := -2.0
	for key in DIRECTION_VECTORS:
		var score: float = normalized.dot(DIRECTION_VECTORS[key])
		if score>similarity:
			similarity = score
			best = key
	return best

## 返回对应独立站姿；初始化前或无朝向时仍保留明确原图回退。
func idle_for_direction(direction: String) -> Texture2D:
	match direction:
		"se": return directional_idle
		"ne": return rear_idle
		"sw": return left_idle
		"nw": return left_rear_idle
		"s": return front_idle
	return extra_idles.get(direction,idle_texture)

## 加载期切分挥剑图集并校验秒制阶段时长；区域复用共享纹理，不连接伤害事件。
func setup_attack(atlas: Texture2D, spec: Dictionary) -> void:
	assert(spec.direction in ["se","ne"] and not spec.loop and spec.frames==4)
	var cached_frames: Array[AtlasTexture] = []
	var cached_seconds: Array[float] = []
	var duration := 0.0
	var size := Vector2(spec.frameSize[0],spec.frameSize[1])
	assert(atlas.get_size()==size*Vector2(1,spec.frames) and spec.frameSeconds.size()==spec.frames)
	assert(Vector2(spec.pivot[0],spec.pivot[1])==-walk_offset)
	for index in range(spec.frames):
		var region := AtlasTexture.new()
		region.atlas = atlas
		region.region = Rect2(Vector2(0,index*size.y),size)
		region.filter_clip = true
		cached_frames.append(region)
		var seconds := float(spec.frameSeconds[index])
		assert(seconds>0)
		cached_seconds.append(seconds)
		duration += seconds
	attack_variants[spec.direction] = {"frames":cached_frames,"seconds":cached_seconds,"duration":duration}

## 按已制作方向开始单次挥剑；缺稿、关闭或播放中拒绝重入，不改变位置或伤害。
func start_attack(direction := "se") -> bool:
	if not enabled or attacking or not reaction_state.is_empty() or not attack_variants.has(direction):
		return false
	attack_frames = attack_variants[direction].frames
	attack_seconds = attack_variants[direction].seconds
	attack_duration = attack_variants[direction].duration
	facing_id = direction
	walking = false
	phase_distance = 0
	walk_frame = 0
	attacking = true
	attack_elapsed = 0
	attack_frame = 0
	texture = attack_frames[0]
	offset = walk_offset
	return true

## 由物理步长推进一次性视觉动作，掉帧可跳过显示帧但不延长总时长；结束恢复对应站姿。
func advance_attack(delta: float) -> void:
	if not attacking:
		return
	assert(delta>=0)
	attack_elapsed += delta
	if attack_elapsed>=attack_duration:
		cancel_attack()
		return
	var boundary := attack_seconds[0]
	attack_frame = 0
	while attack_elapsed>=boundary and attack_frame<attack_frames.size()-1:
		attack_frame += 1
		boundary += attack_seconds[attack_frame]
	texture = attack_frames[attack_frame]

## 清除单次动作状态；移动、切换展示开关或播放完成时调用，不遗留定时器或异步回调。
func cancel_attack() -> void:
	attacking = false
	attack_elapsed = 0
	attack_frame = 0
	update_motion(Vector2.ZERO)

## 在既有四斜向初始化后补正前图集，复用同一帧格和脚底锚点；不改变运动和攻击逻辑。
func setup_front(atlas: Texture2D, idle: Texture2D) -> void:
	front_idle = idle
	assert(atlas.get_size()==frames[0].atlas.get_size() and idle.get_size()==directional_idle.get_size())
	for frame in frames:
		var region: AtlasTexture = frame.duplicate()
		region.atlas = atlas
		front_frames.append(region)

## 补齐正后与左右侧向，区域共享纹理；需在首个运动更新前完成，避免部分初始化。
func setup_extra(direction: String, atlas: Texture2D, idle: Texture2D) -> void:
	assert(direction in ["n","e","w"] and not extra_frames.has(direction))
	assert(atlas.get_size()==frames[0].atlas.get_size() and idle.get_size()==directional_idle.get_size())
	var cached: Array[AtlasTexture] = []
	for frame in frames:
		var region: AtlasTexture = frame.duplicate()
		region.atlas = atlas
		cached.append(region)
	extra_frames[direction] = cached
	extra_idles[direction] = idle

## 加载期缓存右前受击或死亡图集，沿用统一帧格；状态时长不连接正式结算事件。
func setup_reaction(atlas: Texture2D, spec: Dictionary) -> void:
	var state: String = spec.state
	assert(state in ["hit","death"] and spec.direction=="se" and not spec.loop)
	assert(spec.frames==4 and spec.frameSeconds.size()==4 and spec.holdLast==(state=="death"))
	assert(atlas.get_size()==frames[0].atlas.get_size() and Vector2(spec.pivot[0],spec.pivot[1])==-walk_offset)
	var cached: Array[AtlasTexture] = []
	var seconds: Array[float] = []
	var duration := 0.0
	for index in range(4):
		var region: AtlasTexture = frames[index].duplicate()
		region.atlas = atlas
		cached.append(region)
		var interval := float(spec.frameSeconds[index])
		assert(interval>0)
		seconds.append(interval)
		duration += interval
	reaction_frames[state] = cached
	reaction_seconds[state] = seconds
	reaction_durations[state] = duration

## 受击打断挥剑，死亡可打断受击；死亡期间拒绝新动作，同类重复输入不重置相位。
func start_reaction(state: String) -> bool:
	assert(state in ["hit","death"])
	if not enabled or reaction_state=="death" or reaction_state==state or not reaction_frames.has(state):
		return false
	cancel_attack()
	facing_id = "se"
	walking = false
	phase_distance = 0
	walk_frame = 0
	reaction_state = state
	reaction_playing = true
	reaction_elapsed = 0
	reaction_frame = 0
	_show_reaction()
	return true

## 按物理步长推进受击/死亡，受击完成回站姿，死亡完成保持末帧直到显式重置。
func advance_reaction(delta: float) -> void:
	if not reaction_playing:
		return
	assert(delta>=0)
	reaction_elapsed = minf(reaction_elapsed+delta,reaction_durations[reaction_state])
	if reaction_elapsed>=reaction_durations[reaction_state]:
		if reaction_state=="hit":
			reset_reaction()
			return
		reaction_playing = false
		reaction_frame = 3
	else:
		var seconds: Array[float] = reaction_seconds[reaction_state]
		var boundary := seconds[0]
		reaction_frame = 0
		while reaction_elapsed>=boundary and reaction_frame<3:
			reaction_frame += 1
			boundary += seconds[reaction_frame]
	_show_reaction()

## H只隐藏死亡画面而不解除死亡锁；恢复显示时仍用当前动作帧，避免原图对照意外复活。
func _show_reaction() -> void:
	texture = reaction_frames[reaction_state][reaction_frame] if enabled else idle_texture
	offset = walk_offset if enabled else idle_offset

## V键清空展示状态，恢复当前朝向站姿；正式复活和存档不由此函数处理。
func reset_reaction() -> void:
	attacking = false
	attack_elapsed = 0
	attack_frame = 0
	reaction_state = ""
	reaction_playing = false
	reaction_elapsed = 0
	reaction_frame = 0
	update_motion(Vector2.ZERO)

## 仅供隔离样板判断死亡预览是否锁住移动和试走入口，状态不写入正式玩家数据。
func blocks_preview_motion() -> bool:
	return reaction_state=="death"
