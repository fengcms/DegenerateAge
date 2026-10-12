class_name Inventory
extends RefCounted
## 背包存储层（产品文档 05.8）：40 格；装备不可堆叠、药品 / 材料堆叠（上限来自配置）。
##
## 存储数据为「物品实例数组」——空位为 null，占用位为 Dictionary。
## 保存于 GameState.inventory（随存档序列化）。本层只做存储语义，
## 不涉及 UI 与穿戴（穿戴 / 14 槽在 M1-7 接入）。
## 函数显式接收 inv 数组，便于单测与解耦（不依赖 Autoload 单例）。

const SLOTS := 40

## 新建一个空背包。
static func create(size: int = SLOTS) -> Array:
	var inv: Array = []
	inv.resize(size)
	inv.fill(null)
	return inv

## 已占用格数。
static func used_slots(inv: Array) -> int:
	var n := 0
	for i in range(inv.size()):
		if inv[i] != null:
			n += 1
	return n

## 是否已满（无任何空位）。
static func is_full(inv: Array) -> bool:
	return used_slots(inv) >= inv.size()

## 容量必须覆盖整批数量；拒绝非法数量，不允许部分成功。
static func has_space_for(inv: Array, item: Dictionary) -> bool:
	if item.is_empty():
		return false
	if not ItemUtil.is_stackable(item):
		return _first_empty(inv) >= 0
	var count: Variant = item.get("count", 1)
	if not (count is int or count is float) or not is_finite(float(count)) or float(count) != floor(float(count)) or float(count) <= 0:
		return false
	var remaining := float(count)
	var maximum := ItemUtil.stack_max(item)
	if maximum <= 0:
		return false
	for entry in inv:
		if entry == null:
			remaining -= maximum
		elif _same_stack(entry, item):
			remaining -= maxi(0, maximum - int(entry.get("count", 1)))
		if remaining <= 0:
			return true
	return false

## 先完整预检，再分配已有堆与空格；失败时背包和输入物品均不变。
static func add(inv: Array, item: Dictionary) -> bool:
	if not has_space_for(inv, item):
		return false
	if not ItemUtil.is_stackable(item):
		inv[_first_empty(inv)] = item.duplicate(true)
		return true
	var remaining := int(item.get("count", 1))
	var maximum := ItemUtil.stack_max(item)
	for i in range(inv.size()):
		var entry: Variant = inv[i]
		if not _same_stack(entry, item):
			continue
		var amount := mini(remaining, maxi(0, maximum - int(entry.get("count", 1))))
		if amount > 0:
			inv[i] = entry.duplicate(true)
			inv[i].count = int(entry.get("count", 1)) + amount
		remaining -= amount
		if remaining == 0:
			return true
	for i in range(inv.size()):
		if inv[i] != null:
			continue
		var amount := mini(remaining, maximum)
		inv[i] = item.duplicate(true)
		inv[i].count = amount
		remaining -= amount
		if remaining == 0:
			return true
	return false

static func _same_stack(entry: Variant, item: Dictionary) -> bool:
	if not entry is Dictionary or entry.get("kind", "") != item.get("kind", "") or entry.get("itemId", "") != item.get("itemId", ""):
		return false
	var left: Dictionary = entry.duplicate(true)
	var right := item.duplicate(true)
	left.erase("count")
	right.erase("count")
	return left == right

## 移除指定格，返回被移除物品（空位返回 {}）。
static func remove_at(inv: Array, index: int) -> Dictionary:
	if index < 0 or index >= inv.size() or inv[index] == null:
		return {}
	var it: Dictionary = inv[index]
	inv[index] = null
	return it

## 首个空位下标（无则 -1）。
static func _first_empty(inv: Array) -> int:
	for i in range(inv.size()):
		if inv[i] == null:
			return i
	return -1

## 可继续堆叠的同类堆下标（无则 -1）。
static func _find_stack_with_room(inv: Array, item: Dictionary) -> int:
	var id := String(item.get("itemId", ""))
	var max_n := ItemUtil.stack_max(item)
	for i in range(inv.size()):
		var s = inv[i]
		if s is Dictionary and String(s.get("kind", "")) == String(item.get("kind", "")) \
				and String(s.get("itemId", "")) == id and int(s.get("count", 1)) < max_n:
			return i
	return -1
