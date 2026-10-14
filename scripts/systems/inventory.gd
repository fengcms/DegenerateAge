class_name Inventory
extends RefCounted
## 背包存储层（产品文档 05.8）：40 格；装备不可堆叠、药品 / 材料堆叠（上限来自配置）。
##
## 存储数据为「物品实例数组」——空位为 null，占用位为 Dictionary。
## 保存于 GameState.inventory（随存档序列化）。本层只做存储语义，
## 不涉及 UI 与穿戴（穿戴 / 14 槽在 M1-7 接入）。
## 函数显式接收 inv 数组，便于单测与解耦（不依赖 Autoload 单例）。

const SLOTS := 40
const ORGANIZE_KINDS := ["equip", "potion", "rune", "misc", "quest"]

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

## 背包手动排布：拖到空格为移动，拖到占用格为交换；保留物品实例。
static func move_or_swap(inv: Array, source: int, target: int) -> bool:
	if source < 0 or target < 0 or source >= inv.size() or target >= inv.size() \
			or source == target or not inv[source] is Dictionary:
		return false
	var displaced: Variant = inv[target]
	inv[target] = inv[source]
	inv[source] = displaced
	return true

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

## 整理当前容器：分类 / 模板 / 装备品质星级排序，安全合并同数据堆叠，空格置末尾。
## 返回是否发生变化；不增减装备实例，也不修改词条。
static func organize(slots: Array) -> bool:
	var entries: Array[Dictionary] = []
	for index in range(slots.size()):
		if slots[index] is Dictionary:
			entries.append({"item": (slots[index] as Dictionary).duplicate(true), "index": index})
	entries.sort_custom(_organize_less)
	var packed: Array[Dictionary] = []
	for entry in entries:
		var item: Dictionary = entry.item
		if ItemUtil.is_stackable(item):
			var remaining := int(item.get("count", 1))
			var limit := maxi(1, ItemUtil.stack_max(item))
			for existing in packed:
				if not _same_stack(existing, item):
					continue
				var amount := mini(remaining, maxi(0, limit - int(existing.get("count", 1))))
				if amount > 0:
					existing["count"] = int(existing.get("count", 1)) + amount
					remaining -= amount
				if remaining == 0:
					break
			while remaining > 0:
				var stack := item.duplicate(true)
				stack["count"] = mini(remaining, limit)
				packed.append(stack)
				remaining -= int(stack["count"])
		else:
			packed.append(item)
	if packed.size() > slots.size():
		return false
	var changed := false
	for index in range(slots.size()):
		var next = packed[index] if index < packed.size() else null
		if slots[index] != next:
			changed = true
		slots[index] = next
	return changed

static func _organize_less(a: Dictionary, b: Dictionary) -> bool:
	var left: Dictionary = a.item
	var right: Dictionary = b.item
	var left_kind := ORGANIZE_KINDS.find(String(left.get("kind", "")))
	var right_kind := ORGANIZE_KINDS.find(String(right.get("kind", "")))
	left_kind = 999 if left_kind < 0 else left_kind
	right_kind = 999 if right_kind < 0 else right_kind
	if left_kind != right_kind:
		return left_kind < right_kind
	var left_id := String(left.get("itemId", ""))
	var right_id := String(right.get("itemId", ""))
	if left_id != right_id:
		return left_id < right_id
	if String(left.get("kind", "")) == "equip":
		var left_quality := ItemUtil.QUALITIES.find(String(left.get("quality", "common")))
		var right_quality := ItemUtil.QUALITIES.find(String(right.get("quality", "common")))
		if left_quality != right_quality:
			return left_quality > right_quality
		if int(left.get("star", 0)) != int(right.get("star", 0)):
			return int(left.get("star", 0)) > int(right.get("star", 0))
	return int(a.index) < int(b.index)

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
