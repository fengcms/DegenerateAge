class_name SampleMonsterMotion
extends CharacterBody2D
## 隔离营地两怪的单方向真实试走，复用CaveLayout直线通行和引擎碰撞。
## 不实现AI或战斗；最多两个控制器，空闲不更新，随布局释放；贴图保持既有世界坐标排序。
var art: SampleIdleSprite
var layout: CaveLayout
var target := Vector2.ZERO
var active := false
var distance_pixels := 0.0

## 绑定同一布局的现有精灵；只创建一个半径12碰撞，关闭对其他角色的阻挡，不改导航事实源。
func setup(sprite: SampleIdleSprite, navigation: CaveLayout) -> void:
	art = sprite
	layout = navigation
	position = art.position
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.001
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12
	shape.shape = circle
	add_child(shape)
	set_physics_process(false)

## 仅支持已制作的左前方向，前进两格；路径有阻挡或动作不可用就拒绝，不转向或镜像冒充缺稿。
func start_walk() -> bool:
	if active or art.paused or not art.enabled or art.preview_state in ["hit","death"]:
		return false
	position = art.position
	target = position + Iso.grid_pt(-2,0)
	if not layout.segment_walkable(position,target):
		return false
	art.reset_preview()
	assert(art.start_preview("walk"))
	art.distance_driven_walk = true
	distance_pixels = 0
	active = true
	set_physics_process(true)
	return true

## 每物理帧最多一次移动；按真实位移推进步态，碰壁或完成后待机，反应/关闭/重置立即取消路线。
func _physics_process(delta: float) -> void:
	if not art.enabled or art.preview_state!="walk":
		stop_walk(false)
		return
	if art.paused:
		return
	var remaining := position.distance_to(target)
	if remaining<0.1:
		stop_walk(true)
		return
	velocity = position.direction_to(target)*minf(80.0,remaining/delta)
	var before := position
	move_and_slide()
	var traveled := position.distance_to(before)
	art.position = position
	art.z_index = roundi(position.y)
	distance_pixels += traveled
	art.show_walk_distance(distance_pixels)
	if traveled<0.01:
		stop_walk(true)

## 结束控制，保留受击/倒地等外部新状态；正常抵达才回待机，取消后不遗留速度或逐帧回调。
func stop_walk(reset_art: bool) -> void:
	active = false
	velocity = Vector2.ZERO
	art.distance_driven_walk = false
	if reset_art:
		art.reset_preview()
	set_physics_process(false)
