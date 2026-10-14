class_name EquipmentSlot
extends ItemSlot
## 人物面板的装备槽。实际物品图标由 ItemSlot 装饰；缺素材时显示装备名缩写。

var slot_id := ""
var slot_kind := ""

func _get_drag_data(at_position: Vector2) -> Variant:
	if not draggable or item.is_empty():
		return null
	_spawn_drag_visual(at_position)
	return {"from": ROLE_EQUIP, "slot_id": slot_id, "item": item,
		"token": Warehouse.item_token(item)}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and int((data as Dictionary).get("from", -1)) == ROLE_BAG \
		and (data as Dictionary).get("item", null) is Dictionary \
		and String((data as Dictionary).item.get("kind", "")) == "equip"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(index, data as Dictionary)
