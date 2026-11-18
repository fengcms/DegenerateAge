extends "res://tools/camp_combat/route.gd"
## 外围满预算实战验收：12固定刷新点、10普通怪上限，正式刷新/伤害/奖励，独立高等级测试角色。
static var completed := false
static var baseline_nodes := 0
var peak_alive := 0
var measured_frames: Array[float] = []
var last_usec := 0
var drawn_begin := 0
var peak_nodes := 0

## 注入同一外围地图的高密度测试点，不覆盖生产配置；所有刷新间隔仍为60秒。
func _map_definition() -> Dictionary:
	var definition := super._map_definition()
	definition.spawnPoints = []
	for index in range(12):
		definition.spawnPoints.append({"monsterId":"wolf_corrupted" if index%2==0 else "shellback_bug","count":1,"respawnTime":60,"cell":[19+index%4,5+index/4*2]})
	return definition

## 在持续战斗中记录实际窗口帧间隔及峰值活动量；不截帧，不改变时间推进。
func _process(delta: float) -> void:
	super._process(delta)
	if last_usec==0:
		return
	var now := Time.get_ticks_usec()
	measured_frames.append(float(now-last_usec)/1000)
	last_usec = now
	peak_alive = maxi(peak_alive,spawner.alive_count())
	peak_nodes = maxi(peak_nodes,get_tree().get_node_count())
	assert(spawner.alive_count()<=10,"正式刷新预算超出10")

## 实际持续120秒后退回安全营地，检验满预算、后备点补位、60秒刷新及存活回程。
func _verify_route() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP,true)
	for _frame in range(3):
		await get_tree().process_frame
	if completed:
		assert(get_tree().get_node_count()==baseline_nodes,"压力场重开后节点未回到同一初始数量")
		print("CAMP_ROUTE_STRESS_OK: reload_nodes=",baseline_nodes)
		get_tree().quit()
		return
	baseline_nodes = get_tree().get_node_count()
	GameState.add_xp(30000)
	GameState.player.hp = GameState.max_hp()
	print("ROUTE_STRESS_READY level=",GameState.player.level," hp=",GameState.max_hp()," points=",spawner.point_count())
	assert(spawner.point_count()==12 and spawner.alive_count()==10)
	await get_tree().process_frame
	last_usec = Time.get_ticks_usec()
	drawn_begin = Engine.get_frames_drawn()
	_travel(1)
	await get_tree().create_timer(4.0).timeout
	GameState.set_auto_battle(true)
	var deadline := Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		await get_tree().create_timer(5.0).timeout
		assert(not hero.is_dead,"压力角色死亡")
		print("ROUTE_STRESS_PROGRESS kills=",kills," alive=",spawner.alive_count()," created=",spawner.created," hp=",GameState.player.hp)
	assert(peak_alive==10 and kills>=12 and spawner.created>12 and pickups>0,"未覆盖满预算、后备点和真实倒计时刷新")
	_travel(0)
	deadline = Time.get_ticks_msec()+30000
	while not MapService.is_in_safe_area(ROUTE_ID,hero.position) and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
	assert(MapService.is_in_safe_area(ROUTE_ID,hero.position) and not hero.is_dead)
	last_usec = 0
	var drawn := Engine.get_frames_drawn()-drawn_begin
	print("ROUTE_DRAW_COVERAGE: ",drawn,"/",measured_frames.size())
	assert(drawn>=measured_frames.size()*0.9,"压力场未持续绘制")
	measured_frames.sort()
	print("ROUTE_STRESS_RESULT: ",JSON.stringify({"frames":measured_frames.size(),"drawn":drawn,"p95_ms":measured_frames[floori(measured_frames.size()*0.95)],"p99_ms":measured_frames[floori(measured_frames.size()*0.99)],"peak_ms":measured_frames[-1],"peak_nodes":peak_nodes,"nodes":get_tree().get_node_count(),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"peak_alive":peak_alive,"kills":kills,"created":spawner.created}))
	completed = true
	get_tree().reload_current_scene()
