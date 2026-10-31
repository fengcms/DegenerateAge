class_name AutoRoamPlan
extends RefCounted
## 自动巡游静态规划：12格主路线加探索区块补漏点；只在导航版本/连通区域变化时构建。
## 复用Ground与CaveLayout，不执行A*、揭图或读取怪物刷新位置。

var primary: Array[Vector2] = []
var supplements: Array[Vector2] = []
var blocks: Dictionary = {}
var _covered: Dictionary = {}
var _ground: IsoGround
var _component := 0
var _xs: Array[int] = []
var _ys: Array[int] = []
var _phase := 0
var _cursor := 0
var _block_keys: Array = []

## 创建规划工作状态；只缓存轴候选，实际全图扫描由advance预算推进。
func _init(ground: IsoGround, origin: Vector2i, step: int = 12) -> void:
	_ground = ground
	_component = ground.cave.component_at(origin) if ground.cave != null else 0
	_xs = _axis(ground.grid_size.x, step)
	_ys = _axis(ground.grid_size.y, step)

## 每次最多工作约指定微秒；完成返回true，最小单元是一点覆盖或一个可走格检查。
func advance(budget_usec: int = 1500) -> bool:
	var start := Time.get_ticks_usec()
	var units := 0
	while _phase < 3:
		_step()
		units += 1
		if budget_usec > 0 and units % 8 == 0 and Time.get_ticks_usec() - start >= budget_usec:
			break
	return _phase == 3

## 主采样完成后允许先走主路线，补漏扫描继续分帧，避免原地等全图规划。
func primary_ready() -> bool:
	return _phase > 0

## 一个有界规划单元；全图只扫一次，不构造任何A*路线。
func _step() -> void:
	if _phase == 0:
		if _cursor >= _xs.size() * _ys.size():
			_phase = 1
			_cursor = 0
			return
		var row := _cursor / _xs.size()
		var col := _cursor % _xs.size()
		var cell := Vector2i(_xs[col] if row % 2 == 0 else _xs[_xs.size() - col - 1], _ys[row])
		_cursor += 1
		if _reachable(_ground, cell, _component):
			primary.append(Iso.grid_to_world(cell))
			_cover(_covered, cell, _ground.grid_size)
	elif _phase == 1:
		if _cursor >= _ground.grid_size.x * _ground.grid_size.y:
			_block_keys = blocks.keys()
			_phase = 2
			_cursor = 0
			return
		var cell := Vector2i(_cursor % _ground.grid_size.x, _cursor / _ground.grid_size.x)
		_cursor += 1
		if not _reachable(_ground, cell, _component):
			return
		var block := Vector2i(cell.x / Fog.BLOCK_SIZE, cell.y / Fog.BLOCK_SIZE)
		var center := Vector2(block * Fog.BLOCK_SIZE) + Vector2(1.5, 1.5)
		if not blocks.has(block) or Vector2(cell).distance_squared_to(center) < Vector2(blocks[block]).distance_squared_to(center):
			blocks[block] = cell
	else:
		if _cursor >= _block_keys.size():
			if primary.is_empty():
				primary.assign(supplements)
				supplements.clear()
			_phase = 3
			return
		var block: Vector2i = _block_keys[_cursor]
		_cursor += 1
		if not _covered.has(block):
			var cell: Vector2i = blocks[block]
			supplements.append(Iso.grid_to_world(cell))
			_cover(_covered, cell, _ground.grid_size)

## 测试与离线统计用同步入口；正式巡游必须调用advance分帧，不在热路径一次扫完。
static func build(ground: IsoGround, origin: Vector2i, step: int = 12) -> Dictionary:
	var plan := AutoRoamPlan.new(ground, origin, step)
	plan.advance(0)
	return {"primary":plan.primary, "supplements":plan.supplements, "blocks":plan.blocks.keys()}

## 同原边界约定保留首尾点；小地图不会因步长大于尺寸而没有候选。
static func _axis(size: int, step: int) -> Array[int]:
	var values: Array[int] = []
	for value in range(2, maxi(3, size - 2), maxi(1, step)):
		values.append(value)
	var last := maxi(2, size - 3)
	if values.is_empty() or values.back() != last:
		values.append(last)
	return values

## 仅做掩码与缓存连通分量查询，绝不对候选构造完整路线。
static func _reachable(ground: IsoGround, cell: Vector2i, component: int) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= ground.grid_size.x or cell.y >= ground.grid_size.y or not ground.is_walkable_cell(cell):
		return false
	return ground.cave == null or (component > 0 and ground.cave.component_at(cell) == component)

## 模拟现有Fog圆形揭示能覆盖的区块，仅记录规划集合，不更改玩家探索状态。
static func _cover(covered: Dictionary, cell: Vector2i, size: Vector2i) -> void:
	for y in range(maxi(0, cell.y - Fog.REVEAL_RADIUS), mini(size.y, cell.y + Fog.REVEAL_RADIUS + 1)):
		for x in range(maxi(0, cell.x - Fog.REVEAL_RADIUS), mini(size.x, cell.x + Fog.REVEAL_RADIUS + 1)):
			if cell.distance_squared_to(Vector2i(x, y)) <= Fog.REVEAL_RADIUS * Fog.REVEAL_RADIUS:
				covered[Vector2i(x / Fog.BLOCK_SIZE, y / Fog.BLOCK_SIZE)] = true
