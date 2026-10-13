class_name EquipmentSlot
extends ItemSlot
## 人物面板的图标槽。缺少物品贴图时绘制品类轮廓，不用装备名替代图标。

var slot_id := ""
var slot_kind := ""

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not draggable or item.is_empty():
		return null
	_spawn_drag_visual()
	return {"from": ROLE_EQUIP, "slot_id": slot_id, "item": item,
		"token": Warehouse.item_token(item)}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and int((data as Dictionary).get("from", -1)) == ROLE_BAG \
		and (data as Dictionary).get("item", null) is Dictionary \
		and String((data as Dictionary).item.get("kind", "")) == "equip"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(index, data as Dictionary)

func _draw() -> void:
	if icon != null:
		return
	var color := ItemUtil.quality_color(String(item.get("quality", "common"))) if not item.is_empty() else Color("667987")
	var c := size * 0.5
	match slot_kind:
		"weapon":
			draw_line(c + Vector2(-10, 12), c + Vector2(10, -12), color, 4.0, true)
			draw_line(c + Vector2(-8, 3), c + Vector2(0, 11), color, 3.0, true)
		"shield":
			draw_colored_polygon(PackedVector2Array([c+Vector2(-12,-12),c+Vector2(12,-12),c+Vector2(10,5),c+Vector2(0,15),c+Vector2(-10,5)]), color)
		"helmet":
			draw_arc(c+Vector2(0,3), 12, PI, TAU, 20, color, 3.0, true)
			draw_line(c+Vector2(-12,3), c+Vector2(12,3), color, 3.0, true)
		"armor":
			draw_colored_polygon(PackedVector2Array([c+Vector2(-12,-12),c+Vector2(-5,-15),c+Vector2(5,-15),c+Vector2(12,-12),c+Vector2(10,14),c+Vector2(-10,14)]), color)
		"shoes":
			draw_line(c+Vector2(-12,7), c+Vector2(-1,12), color, 5.0, true)
			draw_line(c+Vector2(2,7), c+Vector2(13,12), color, 5.0, true)
		"necklace":
			draw_arc(c+Vector2(0,-3), 12, 0, PI, 20, color, 3.0, true)
			draw_circle(c+Vector2(0,10), 4, color)
		"ring":
			draw_arc(c, 10, 0, TAU, 24, color, 4.0, true)
		"knee", "bracer", "bracelet":
			draw_arc(c, 11, 0.45, PI-0.45, 14, color, 4.0, true)
			draw_arc(c, 11, PI+0.45, TAU-0.45, 14, color, 4.0, true)
		_:
			draw_circle(c, 10, color)
