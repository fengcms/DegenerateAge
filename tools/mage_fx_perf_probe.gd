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
## 场景：
##   baseline  空场景（引擎自身开销）
##   fireball  2 个投射物同屏（攻击间隔下限 0.2s + 飞行上限 0.20s + 爆点 0.10s ⇒ 真实峰值）
##   meteor    1 个陨石术钉在**预警期**（最重的一段：2 条抗锯齿折线 + 填充）
##   flame     1 个火焰喷发钉在爆发满（20 道 × 3 层多边形 + 着火点 + 范围环）
##   frost     1 个冰咆哮钉在推进中段（约 18 条短折线 + 若干冰晶 + 扇形边界）
##   shield    1 个魔法盾前层（呼吸 + 8 条经线，**它是常驻的**，按每帧成本算）
##   全部同时  最坏叠加
## 另加 ×100 / ×200 的**敏感性标定**，用差值反推单价 —— 单个的差异通常落在噪声里。

const FRAMES := 150
const METEOR_RADIUS := 7.0 * 64.0
const FLAME_RADIUS := 3.5 * 64.0
const FROST_RADIUS := 4.5 * 64.0
## 停在预警期 40%：填充 + 48 段外环 + 40 段内环 + 12 段高亮。
const METEOR_AGE := 0.28
## 投射物停在航程 25%：6 节彗尾 + 辉光 + 主体 + 白芯。
const BOLT_ELAPSED := 0.05
## 火焰停在爆发期 2/3 处：20 道 × 3 层多边形 + 20 个着火点 + 范围环。
const FLAME_AGE := 0.18
## 冰咆哮停在推进中段：第 2 波最亮、第 3 波刚起，同屏折线最多。
const FROST_AGE := 0.21

## 单场景模式可选的场景表：`-- --one=flame`。
## 🔴 为什么要单开进程：本机跑十几秒后 macOS 会把帧时间压到一个 **~6.9ms（145fps）的地板**上，
##    任何工作量低于地板的场景读数都会被压平到同一个数字（两个独立进程都复现）⇒
##    长跑里「flame ×1 和 shield ×1 读数完全一样」不是物理，是节流。
##    单场景进程只要 2—3 秒，稳定落在地板出现之前。
const SCENES := {
	"fireball": {"bolts": 2},
	"meteor": {"meteors": 1},
	"flame": {"flames": 1},
	"frost": {"frosts": 1},
	"shield": {"shields": 1},
	"both": {"bolts": 2, "meteors": 1, "flames": 1, "frosts": 1, "shields": 1},
}

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
	var one := _one_arg()
	if one != "":
		await _run_single(one)
		print("=== PROBE DONE ===")
		get_tree().quit(0)
		return
	# 🔴 预热是**必须**的：首轮测量会把着色器编译 / 纹理上传算进去，
	#    表现为「越往后越快、后测的场景比空场景还快」（首次跑本探针就是这个结果）。
	await _warmup()
	# 🔴 每个场景测两遍取**最小值**：最小值最接近「纯工作量」，均值会被偶发卡顿抬高。
	# 🔴 baseline 首尾各测一次再取最小：先测的那个场景恒偏慢（进程还在爬坡），
	#    只测开头会让「后测的特效比空场景还快」—— 那不是物理，是测量伪影（首版就撞了）。
	var b0 := minf(await _measure_empty(), await _measure_empty())
	var two := minf(await _measure_with({"bolts": 2}), await _measure_with({"bolts": 2}))
	var meteor := minf(await _measure_with({"meteors": 1}), await _measure_with({"meteors": 1}))
	var flame := minf(await _measure_with({"flames": 1}), await _measure_with({"flames": 1}))
	var frost := minf(await _measure_with({"frosts": 1}), await _measure_with({"frosts": 1}))
	var shield := minf(await _measure_with({"shields": 1}), await _measure_with({"shields": 1}))
	var both := minf(await _measure_with({"bolts": 2, "meteors": 1, "flames": 1,
		"frosts": 1, "shields": 1}),
		await _measure_with({"bolts": 2, "meteors": 1, "flames": 1, "frosts": 1, "shields": 1}))
	# 「有牙」校验 + 标定：探针必须能测出**数量级**差异，否则「和基线差不多」只能说明
	# 探针不灵敏，不能说明特效便宜。
	var many_bolt := minf(await _measure_with({"bolts": 200}), await _measure_with({"bolts": 200}))
	var many_flame := minf(await _measure_with({"flames": 100}),
		await _measure_with({"flames": 100}))
	var many_frost := minf(await _measure_with({"frosts": 100}),
		await _measure_with({"frosts": 100}))
	var many_shield := minf(await _measure_with({"shields": 200}),
		await _measure_with({"shields": 200}))
	var b1 := minf(await _measure_empty(), await _measure_empty())
	var baseline := minf(b0, b1)
	_report("baseline 空场景（首测）", b0, b0)
	_report("baseline 空场景（尾测）", b1, b0)
	_report("fireball ×2 同屏", two, baseline)
	_report("meteor ×1 预警期", meteor, baseline)
	_report("flame ×1 爆发期", flame, baseline)
	_report("frost ×1 推进期", frost, baseline)
	_report("shield ×1（常驻）", shield, baseline)
	_report("全部同时（最坏叠加）", both, baseline)
	_report("标定 fireball ×200", many_bolt, baseline)
	_report("标定 flame ×100", many_flame, baseline)
	_report("标定 frost ×100", many_frost, baseline)
	_report("标定 shield ×200", many_shield, baseline)
	# `_measure` 返回 µs/帧，换算 ms 要再除 1000 —— 漏掉会把单价放大 1000 倍。
	var bolt_unit := (many_bolt - baseline) / 200.0 / 1000.0
	var flame_unit := (many_flame - baseline) / 100.0 / 1000.0
	var frost_unit := (many_frost - baseline) / 100.0 / 1000.0
	var shield_unit := (many_shield - baseline) / 200.0 / 1000.0
	print("PROBE 反推单价｜fireball %.4f｜flame %.4f｜frost %.4f｜shield %.4f ms/帧/个" % [
		bolt_unit, flame_unit, frost_unit, shield_unit])
	# 🔴 `%` 比 `+` 结合得紧：`"a" + "b" % [...]` 只会格式化后半段。整条格式串必须加括号。
	print("PROBE 换算｜最坏叠加实测 %.3f ms/帧，占 60fps 预算（16.7ms）的 %.1f%%" % [
		both / 1000.0, both / 1000.0 / 16.7 * 100.0])
	# 🔴 外部节流地板检测：本机长跑时 macOS 会把帧时间压到一个**地板**上（实测 ~6.9ms / 145fps），
	#    任何工作量低于地板的场景读数都会被压平到同一个数字 ⇒ 单场景差值全部归零。
	#    判据＝尾测基线远高于首测（进程被降频/遮挡），且几个工作量天差地别的场景读数几乎相同。
	if b1 > b0 * 2.0 and absf(flame - frost) < 0.005 * b1:
		print("PROBE ⚠ 检出外部节流地板（首测基线 %.3f ms，尾测 %.3f ms，且不同场景读数被压平）"
			% [b0 / 1000.0, b1 / 1000.0])
		print("PROBE ⚠ ⇒ 单场景的「相对基线」一栏本次**不可用**，只看 ×100/×200 标定反推的单价")
	if many_bolt < baseline + 0.5:
		print("PROBE ⚠ 敏感性校验没拉开差距：本探针分辨不出 200 个投射物，"
			+ "上面「和基线差不多」的结论**不成立**（不是特效便宜，是探针不灵敏）")
	print("=== PROBE DONE ===")
	get_tree().quit(0)

## 烧热管线：全部特效同时上，跑 90 帧。
func _warmup() -> void:
	await _warmup_with({"bolts": 2, "meteors": 1, "flames": 1, "frosts": 1, "shields": 1})

func _warmup_with(spec: Dictionary) -> void:
	_keeper.spawn(spec)
	for _i in range(90):
		await get_tree().process_frame
	_keeper.clear()
	await get_tree().process_frame

## 读取 `-- --one=<场景名>`；没给返回空串（走长跑的标定模式）。
func _one_arg() -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--one="):
			var name := s.substr(6)
			if not SCENES.has(name):
				print("PROBE ⚠ 未知场景 `%s`，可选：%s" % [name, str(SCENES.keys())])
				return ""
			return name
	return ""

## 单场景短进程：预热 → 基线 → 场景 ×2 → 基线，全程 2—3 秒，落在地板出现之前。
func _run_single(name: String) -> void:
	var spec: Dictionary = SCENES[name]
	await _warmup_with(spec)
	var b0 := await _measure_empty()
	var v1 := await _measure_with(spec)
	var v2 := await _measure_with(spec)
	var b1 := await _measure_empty()
	var base := minf(b0, b1)
	var best := minf(v1, v2)
	print("PROBE[%s] 基线 %.3f / %.3f ms｜场景 %.3f / %.3f ms｜相对基线 %+.3f ms" % [
		name, b0 / 1000.0, b1 / 1000.0, v1 / 1000.0, v2 / 1000.0, (best - base) / 1000.0])
	# 尾测基线远高于首测 ⇒ 本进程已撞上节流地板，差值不可用（必须如实喊出来）。
	if b1 > b0 * 2.0:
		print("PROBE[%s] ⚠ 尾测基线 %.3f ms ≫ 首测 %.3f ms —— 本进程已撞节流地板，差值不可用" % [
			name, b1 / 1000.0, b0 / 1000.0])

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

func _measure_empty() -> float:
	return await _measure()

func _measure_with(spec: Dictionary) -> float:
	_keeper.spawn(spec)
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
	const FlameFx := preload("res://scripts/systems/flame_burst_fx.gd")
	const FrostFx := preload("res://scripts/systems/frost_roar_fx.gd")
	const ShieldAura := preload("res://scripts/entities/magic_shield_aura.gd")

	var _bolts: Array[Node] = []
	var _pinned: Array[Node] = []
	var _shield_age: Array[Node] = []
	var _bolt_elapsed := 0.05
	var _meteor_age := 0.28
	var _flame_age := 0.18
	var _frost_age := 0.21

	func spawn(spec: Dictionary) -> void:
		_bolt_elapsed = float(spec.get("bolt_elapsed", 0.05))
		_meteor_age = float(spec.get("meteor_age", 0.28))
		_flame_age = float(spec.get("flame_age", 0.18))
		_frost_age = float(spec.get("frost_age", 0.21))
		var host := get_parent() as Node2D
		for i in range(int(spec.get("bolts", 0))):
			var b := Projectile.new() as Node2D
			host.add_child(b)
			b.call("setup", Vector2(120.0 + float(i) * 6.0, 640.0),
				Vector2(420.0 + float(i) * 6.0, 400.0), Color("ffb347"), 8.0, 0.20)
			_bolts.append(b)
		for _i in range(int(spec.get("meteors", 0))):
			# 陨石术一律落在画面中央：它是**目标类** fx，铺开多份没有意义（且会叠成一坨）。
			_add_pinned(host, MeteorFx.new() as Node2D, Vector2(640.0, 360.0),
				{"target": Vector2(640.0, 360.0), "radius": 7.0 * 64.0})
		for i in range(int(spec.get("flames", 0))):
			_add_pinned(host, FlameFx.new() as Node2D, _grid(i, 300.0),
				{"origin": _grid(i, 300.0), "radius": 3.5 * 64.0})
		for i in range(int(spec.get("frosts", 0))):
			_add_pinned(host, FrostFx.new() as Node2D, _grid(i, 300.0),
				{"origin": _grid(i, 300.0), "facing": Vector2.RIGHT, "radius": 4.5 * 64.0})
		for i in range(int(spec.get("shields", 0))):
			# 盾是**常驻**的（30 秒），不钉时刻：让它自己的 `_process` 推进呼吸与相位，
			# 那正是真实运行时的每帧成本。`visible` 默认 true，`front_pass` 才有网与轮廓。
			var aura := ShieldAura.new() as Node2D
			host.add_child(aura)
			aura.set("front_pass", true)
			aura.position = _grid(i, 220.0)
			_shield_age.append(aura)

	func _add_pinned(host: Node2D, node: Node2D, at: Vector2, ctx: Dictionary) -> void:
		host.add_child(node)
		node.call("setup", ctx)
		node.global_position = at
		_pinned.append(node)

	## 生成位置：一排铺开，避免叠在同一个点上被「同类合并」掉（draw 命令不会合并，
	## 但重叠会让肉眼误判规模）。按 8 个一行。
	## 🔴 用位运算取行/列：`index / 8` 在 GDScript 里是整数除法，会触发
	##    `INTEGER_DIVISION` 警告，而本项目 `warnings_as_errors` 开着 ⇒ 编译失败。
	func _grid(index: int, top: float) -> Vector2:
		const PER_ROW := 8
		var row := index >> 3
		var col := index & (PER_ROW - 1)
		return Vector2(80.0 + float(col) * 140.0, top + float(row) * 120.0)

	func clear() -> void:
		for n in _bolts:
			if is_instance_valid(n):
				n.queue_free()
		for n in _pinned:
			if is_instance_valid(n):
				n.queue_free()
		for n in _shield_age:
			if is_instance_valid(n):
				n.queue_free()
		_bolts.clear()
		_pinned.clear()
		_shield_age.clear()

	func _process(_delta: float) -> void:
		for n in _bolts:
			if is_instance_valid(n):
				n.set("_elapsed", _bolt_elapsed)
		for n in _pinned:
			if not is_instance_valid(n):
				continue
			# 🔴 变量名不能叫 `script`：那会遮蔽 `Object.script`，触发 SHADOWED_VARIABLE 警告。
			var scr: Variant = n.get_script()
			if scr == MeteorFx:
				n.set("_age", _meteor_age)
			elif scr == FlameFx:
				n.set("_age", _flame_age)
			elif scr == FrostFx:
				n.set("_age", _frost_age)
			n.call("queue_redraw")
