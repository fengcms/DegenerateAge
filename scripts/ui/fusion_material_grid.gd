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

## 接收背包载荷；是否装备以及品质、星级和档位由面板给出具体错误提示。
func _can_drop_data(point: Vector2, data: Variant) -> bool:
	return data is Dictionary and int((data as Dictionary).get("from", -1)) == ItemSlot.ROLE_BAG \
		and (data as Dictionary).get("item", {}) is Dictionary and slot_at(point) >= 0

## 把目标格和原始载荷交给合成面板验证，格网自身不改背包。
func _drop_data(point: Vector2, data: Variant) -> void:
	item_dropped.emit(slot_at(point), data as Dictionary)
