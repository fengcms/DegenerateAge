extends MonsterActorArt
## 隔离战斗样板表现适配器；继承正式动作接口，伤害和奖励完全由宿主结算。
## 加载期缓存图集区域，实际位移驱动步态；八向独立图集，不镜像。
const DIRECTIONS := ["s","sw","w","nw","n","ne","e","se"]
static var packs: Dictionary = {}
var clips: Dictionary
var kind := "hero"
var previous_position := Vector2.ZERO
var walk_distance := 0.0
var action := ""
var action_time := 0.0
var action_duration := 0.0
var attack_count := 0
var hit_count := 0

## 绑定现有实体的视觉，资源只在首次同种角色装配时加载一次。
func setup(actor: CharacterBody2D, actor_kind: String) -> void:
	kind = actor_kind
	if not packs.has(kind):
		packs[kind] = _load_pack(kind)
	clips = packs[kind]
	centered = false
	hframes = 1
	vframes = 1
	offset = Vector2(-56,-112) if kind=="hero" else Vector2(-64,-80)
	previous_position = actor.global_position
	_show_clip("idle",0)

## 读取已构建运行图集，保持每种状态和方向共享AtlasTexture，不在热路径I/O。
func _load_pack(actor_kind: String) -> Dictionary:
	var result: Dictionary = {}
	var directions: Array = DIRECTIONS.duplicate() if actor_kind=="hero" else ["sw"]
	var extra: Dictionary = {}
	if actor_kind!="hero" and FileAccess.file_exists("res://assets/art_pilot/combat_monsters_v1/manifest.json"):
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_pilot/combat_monsters_v1/manifest.json"))
		extra = manifest.packs[actor_kind]
		directions.append_array(extra.keys())
	for direction in directions:
		result[direction] = {}
		for state in ["idle","walk","attack","hit","death"]:
			var stem: String = actor_kind+"_"+state+"_v1"
			if actor_kind=="hero":
				var version: String = "v3" if state=="idle" or (state=="walk" and direction=="se") else "v2" if state=="walk" and direction in ["ne","nw"] else "v1"
				stem = "hero_"+state+"_"+direction+"_"+version
			var path := "res://assets/art_pilot/"+stem+".png"
			if extra.has(direction):
				path = "res://assets/art_pilot/combat_monsters_v1/"+String(extra[direction][state])
			var atlas := load(path) as Texture2D
			assert(atlas != null)
			var size := Vector2(112,128) if actor_kind=="hero" else Vector2(128,96)
			var count := 1 if actor_kind=="hero" and state=="idle" else 4
			assert(atlas.get_size()==size*Vector2(1,count),"运行图集尺寸不符："+path)
			var frames: Array[AtlasTexture] = []
			for index in range(count):
				var region := AtlasTexture.new()
				region.atlas = atlas
				region.region = Rect2(Vector2(0,index*size.y),size)
				region.filter_clip = true
				frames.append(region)
			result[direction][state] = frames
	assert(result.size()==8,"战斗样板要求完整八方向图集")
	return result

## 只切缓存帧引用，既有八向编号与正式SampleActorArt一致。
func _show_clip(state: String, index: int) -> void:
	pose = state
	var direction: String = DIRECTIONS[facing]
	assert(clips.has(direction),"动作朝向未装配")
	var frames: Array = clips[direction][state]
	phase = clampi(index,0,frames.size()-1)
	texture = frames[phase]

## 正式近战同一调用立即结算；视觉从接触阶段开始，不额外增加玩法前摇。
func attack(vector: Vector2, interval: float) -> void:
	if action=="death":
		return
	face(vector)
	attack_count += 1
	action = "attack"
	action_time = 0
	action_duration = clampf(interval*0.65,0.12,0.36)
	_show_clip("attack",2)

## 正式受击事件打断攻击表现，不修改宿主硬直、血量或移动。
func hit() -> void:
	if action=="death":
		return
	hit_count += 1
	action = "hit"
	action_time = 0
	action_duration = 0.16
	_show_clip("hit",0)

## 正式Monster死亡流程调用，取消其他动作并让原有清理流程等待完整倒地。
func begin_death() -> void:
	action = "death"
	action_time = 0
	action_duration = death_duration()
	_show_clip("death",0)

## 只提供视觉播放时长，结算仍发生在Monster._die入口且只发生一次。
func death_duration() -> float:
	return 0.90

## 读取宿主实际位移及死亡状态，维持脚底排序；不驱动任何游戏规则。
func _process(delta: float) -> void:
	var actor := get_parent() as CharacterBody2D
	if actor == null or clips.is_empty():
		return
	_clock += delta
	var displacement := actor.global_position-previous_position
	previous_position = actor.global_position
	actor.z_index = clampi(roundi(actor.global_position.y),-3500,3500)
	if actor.get("is_dead")==true and action!="death":
		begin_death()
	if not action.is_empty():
		action_time += delta
		var progress := minf(1.0,action_time/action_duration)
		_show_clip(action,mini(3,2+floori(progress*2)) if action=="attack" else mini(3,floori(progress*4)))
		if progress>=1 and action!="death":
			action = ""
		return
	if displacement.length_squared()>0.0001:
		face(displacement)
		walk_distance = fposmod(walk_distance+displacement.length(),64)
		_show_clip("walk",floori(walk_distance/16))
	else:
		walk_distance = 0
		_show_clip("idle",posmod(floori(_clock*3.0),4))
