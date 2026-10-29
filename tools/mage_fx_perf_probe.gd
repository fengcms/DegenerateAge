extends Node2D
## 工程 106 施法特效的**渲染路径**性能探针（只读，不写档）。
##
## 口径沿用工程 104：判据是「**同时实例数 × 每帧 draw 命令数**」，不是「单次 draw 贵不贵」。
## 这里量的是**墙钟帧时间**（含真实光栅化），不是脚本 `_process` 的耗时 ——
## 后者在 headless 下照样能跑，但会漏掉 draw 命令那一半（104 §6 的教训）。
##
## 🔴 必须窗口模式 + 关垂直同步跑（`--headless` 没有光栅化，量出来恒等于基线）：
##     /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/mage_fx_perf_probe.tscn
## 🔴 不放 `tests/`：`--all` 会 glob `tests/*.tscn` 并当成测试跑。
##
## 四个场景：
##   baseline  空场景（引擎自身开销）
##   fireball  2 个投射物同屏（攻击间隔下限 0.2s + 飞行上限 0.20s + 爆点 0.10s ⇒ 真实峰值）
##   meteor    1 个陨石术钉在**预警期**（本 fx 最重的一段：2 条抗锯齿折线 + 填充）
##   叠加      1 + 2 同时（最坏情况）

const FRAMES := 150
const METEOR_RADIUS := 7.0 * 64.0
## 停在预警期 40%：4 条 draw（填充 + 48 段外环 + 40 段内环 + 12 段高亮）。
const METEOR_AGE := 0.28
## 投射物停在航程 25%：10 条 draw（6 节彗尾 + 辉光 + 主体 + 白芯）。
const BOLT_ELAPSED := 0.05

var _keeper: Keeper

func _ready() -> void:
	SaveManager.autosave_enabled = false
	if DisplayServer.get_name() == "headless":
		print("PROBE ⚠ headless 没有光栅化，本探针必须窗口模式跑")
		get_tree().quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_keeper = Keeper.new()
	add_child(_keeper)
	print("=== 工程 106 施法特效渲染性能探针 ===")
	print("PROBE 参数｜视角 %s｜vsync 关｜每场景 %d 帧 × 2 取样" % [
		str(DisplayServer.window_get_size()), FRAMES])
	# 🔴 预热是**必须**的：首轮测量会把着色器编译 / 纹理上传算进去，
	#    表现为「越往后越快、后测的场景比空场景还快」（首次跑本探针就是这个结果，
	#    数字自相矛盾到无法解读）。先跑一轮重负载把所有管线烧热。
	await _warmup()
	# 🔴 每个场景测两遍取**最小值**：最小值最接近「纯工作量」，均值会被偶发卡顿抬高。
	# 🔴 baseline 在**首尾各测一次**再取最小：先测的那个场景恒偏慢（进程还在爬坡），
	#    只测开头会让「后测的特效比空场景还快」——这不是物理，是测量伪影（首版就撞了这个）。
	var b0 := minf(await _measure(), await _measure())
	var two := minf(await _measure_with(2, 0), await _measure_with(2, 0))
	var meteor := minf(await _measure_with(0, 1), await _measure_with(0, 1))
	var both := minf(await _measure_with(2, 1), await _measure_with(2, 1))
	# 「有牙」校验：探针必须能测出**数量级**的差异，否则「和基线差不多」只能说明
	# 探针不灵敏，不能说明特效便宜。同时这两条也用来**标定单价**（见下面的推算）。
	var many_bolt := minf(await _measure_with(200, 0), await _measure_with(200, 0))
	var many_meteor := minf(await _measure_with(0, 200), await _measure_with(0, 200))
	var b1 := minf(await _measure(), await _measure())
	var baseline := minf(b0, b1)
	_report("baseline 空场景（首测）", b0, b0)
	_report("baseline 空场景（尾测）", b1, b0)
	_report("fireball ×2 同屏", two, baseline)
	_report("meteor ×1 预警期", meteor, baseline)
	_report("全部同时（最坏叠加）", both, baseline)
	_report("标定 fireball ×200", many_bolt, baseline)
	_report("标定 meteor ×200", many_meteor, baseline)
	# 用 200 个的实测差值反推单价 —— 这样即便单个的差异落在噪声里，结论也有量级依据。
	# `_measure` 返回的是 µs/帧，换算成 ms 要再除 1000 —— 漏掉这一步会把单价放大 1000 倍。
	var bolt_unit := (many_bolt - baseline) / 200.0 / 1000.0
	var meteor_unit := (many_meteor - baseline) / 200.0 / 1000.0
	var peak := bolt_unit * 2.0 + meteor_unit
	print("PROBE 反推单价｜fireball %.4f ms/帧/个｜meteor %.4f ms/帧/个" % [
		bolt_unit, meteor_unit])
	# 🔴 `%` 比 `+` 结合得紧：`"a" + "b" % [...]` 只会格式化后半段（首跑就撞了
	#    "not all arguments converted"）。整条格式串必须加括号。
	print("PROBE 换算｜真实峰值（2 投射物 + 1 陨石）≈ %.3f ms/帧，占 60fps 预算（16.7ms）的 %.1f%%" % [
		peak, peak / 16.7 * 100.0])
	if many_bolt < baseline + 0.5:
		print("PROBE ⚠ 敏感性校验没拉开差距：本探针分辨不出 200 个投射物，"
			+ "上面「和基线差不多」的结论**不成立**（不是特效便宜，是探针不灵敏）")
	print("=== PROBE DONE ===")
	get_tree().quit(0)

## 烧热管线：全部特效同时上，跑 90 帧。
func _warmup() -> void:
	_keeper.spawn(2, 1, METEOR_RADIUS, BOLT_ELAPSED, METEOR_AGE)
	for _i in range(90):
		await get_tree().process_frame
	_keeper.clear()
	await get_tree().process_frame

func _report(label: String, us: float, baseline: float) -> void:
	print("PROBE %-22s ⇒ %7.3f ms/帧（%4.0f fps）｜相对基线 %+.3f ms" % [
		label, us / 1000.0, 1e6 / maxf(us, 0.001), (us - baseline) / 1000.0])

func _measure() -> float:
	# 预热两帧：首帧含节点进树 / 纹理上传，不能算进均值。
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for _i in range(FRAMES):
		await get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / float(FRAMES)

func _measure_with(bolts: int, meteors: int) -> float:
	_keeper.spawn(bolts, meteors, METEOR_RADIUS, BOLT_ELAPSED, METEOR_AGE)
	var us := await _measure()
	_keeper.clear()
	await get_tree().process_frame
	return us

## 把特效钉在指定时段：每帧在特效自身 `_process` 之前把计时写回去。
## 树序在前 ⇒ 本节点先跑，随后特效的 `_process` 才加 delta 并重绘。
## 🔴 内部类**看不到外层脚本的常量**（GDScript 内嵌类不继承外层作用域），所以 preload 要重写一份。
class Keeper extends Node:
	const Projectile := preload("res://scripts/systems/player_projectile.gd")
	const MeteorFx := preload("res://scripts/systems/meteor_fx.gd")

	var _bolts: Array[Node] = []
	var _meteors: Array[Node] = []
	var _bolt_elapsed := 0.05
	var _meteor_age := 0.28

	func spawn(bolts: int, meteors: int, radius: float, bolt_elapsed: float,
			meteor_age: float) -> void:
		_bolt_elapsed = bolt_elapsed
		_meteor_age = meteor_age
		var host := get_parent() as Node2D
		for i in range(bolts):
			var b := Projectile.new() as Node2D
			host.add_child(b)
			b.call("setup", Vector2(600.0 + float(i) * 40.0, 700.0),
				Vector2(900.0 + float(i) * 40.0, 420.0), Color("ffb347"), 8.0, 0.20)
			_bolts.append(b)
		for i in range(meteors):
			var m := MeteorFx.new() as Node2D
			host.add_child(m)
			m.call("setup", {"target": Vector2(640.0, 360.0), "radius": radius})
			_meteors.append(m)

	func clear() -> void:
		for n in _bolts:
			if is_instance_valid(n):
				n.queue_free()
		for n in _meteors:
			if is_instance_valid(n):
				n.queue_free()
		_bolts.clear()
		_meteors.clear()

	func _process(_delta: float) -> void:
		for n in _bolts:
			if is_instance_valid(n):
				n.set("_elapsed", _bolt_elapsed)
		for n in _meteors:
			if is_instance_valid(n):
				n.set("_age", _meteor_age)
				n.call("queue_redraw")
