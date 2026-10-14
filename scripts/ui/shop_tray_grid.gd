class_name ShopTrayGrid
extends GridContainer
## 让出售托盘的格间空隙也成为投放区域；具体格位取最近的格中心。

signal item_dropped(index: int, payload: Dictionary)

func slot_at(point: Vector2) -> int:
	var nearest := -1
	var best := INF
	for child in get_children():
		var slot := child as ItemSlot
		if slot == null:
			continue
		var center := slot.position + slot.size * 0.5
		var distance := point.distance_squared_to(center)
		if distance < best:
			best = distance
			nearest = slot.index
	return nearest

func _can_drop_data(point: Vector2, data: Variant) -> bool:
	return data is Dictionary and int((data as Dictionary).get("from", -1)) == ItemSlot.ROLE_BAG \
		and slot_at(point) >= 0

func _drop_data(point: Vector2, data: Variant) -> void:
	item_dropped.emit(slot_at(point), data as Dictionary)
