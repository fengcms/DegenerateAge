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

## 能否容纳该物品：可堆叠 → 有未满堆 或 有空位；不可堆叠 → 需空位。
static func has_space_for(inv: Array, item: Dictionary) -> bool:
	if item.is_empty():
		return false
	if ItemUtil.is_stackable(item):
		if _find_stack_with_room(inv, item) >= 0:
			return true
	return _first_empty(inv) >= 0

## 入包。成功返回 true；失败（背包满）返回 false 且不改变背包。
static func add(inv: Array, item: Dictionary) -> bool:
	if item.is_empty():
		return false
	if ItemUtil.is_stackable(item):
		var si := _find_stack_with_room(inv, item)
		if si >= 0:
			var max_n := ItemUtil.stack_max(item)
			var cur := int(inv[si].get("count", 1))
			var add_n := int(item.get("count", 1))
			inv[si]["count"] = mini(max_n, cur + add_n)
			return true
	var ei := _first_empty(inv)
	if ei < 0:
		return false
	inv[ei] = item.duplicate(true)
	return true

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
