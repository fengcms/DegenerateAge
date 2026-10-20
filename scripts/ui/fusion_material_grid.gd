class_name FusionMaterialGrid
extends GridContainer
## 合成材料格的整块投放区域；格间缝隙按最近格中心归属。

signal item_dropped(index: int, payload: Dictionary)

## 返回鼠标位置最近的材料格，保证投在格间空白也能命中。
func slot_at(point: Vector2) -> int:
	var nearest := -1
	var best := INF
	for child in get_children():
		var slot := child as ItemSlot
		if slot == null or not slot.visible:
			continue
		var distance := point.distance_squared_to(slot.position + slot.size * 0.5)
		if distance < best:
			best = distance
			nearest = slot.index
	return nearest

## 接收背包载荷，以及打开了 `accept_equip_source` 的目标格收到的穿戴载荷（工程 65）；
## 是否装备以及品质、星级和档位由面板给出具体错误提示。
func _can_drop_data(point: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not (data as Dictionary).get("item", {}) is Dictionary:
		return false
	var index := slot_at(point)
	if index < 0:
		return false
	var source := int((data as Dictionary).get("from", -1))
	if source == ItemSlot.ROLE_BAG:
		return true
	if source != ItemSlot.ROLE_EQUIP:
		return false
	for child in get_children():
		var slot := child as ItemSlot
		if slot != null and slot.index == index:
			return slot.accept_equip_source
	return false

## 把目标格和原始载荷交给合成面板验证，格网自身不改背包。
func _drop_data(point: Vector2, data: Variant) -> void:
	item_dropped.emit(slot_at(point), data as Dictionary)
