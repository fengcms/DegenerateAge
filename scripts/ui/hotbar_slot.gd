class_name HotbarSlot
extends Button

signal binding_dropped(index: int, payload: Dictionary)
signal clear_requested(index: int)

var index := 0
var entry: Variant = null
var _count: Label
var _cooldown: Label

func _ready() -> void:
	_count = Label.new()
	_count.set_anchors_preset(Control.PRESET_FULL_RECT)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count.add_theme_font_size_override("font_size", 10)
	_count.add_theme_constant_override("outline_size", 2)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	_cooldown = Label.new()
	_cooldown.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cooldown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cooldown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cooldown.add_theme_font_size_override("font_size", 12)
	_cooldown.add_theme_color_override("font_color", Color("ffcb71"))
	_cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cooldown)

func _process(_delta: float) -> void:
	if entry is Dictionary and ["potion", "auto_potion"].has(String(entry.kind)):
		var left := _remaining_cooldown()
		_cooldown.text = "%.0fs" % ceilf(left) if left > 0.0 else ""
	elif entry is Dictionary and String(entry.kind) == "skill":
		var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
		var left := player.skill_cooldown(String(entry.id)) if player != null else 0.0
		_cooldown.text = "%.0fs" % ceilf(left) if left > 0.0 else ""
	else:
		_cooldown.text = ""

func _remaining_cooldown() -> float:
	if String(entry.kind) == "potion":
		return Consumable.cd_of(String(entry.id))
	var minimum := INF
	for raw in GameState.inventory:
		if not raw is Dictionary or raw.get("kind") != "potion":
			continue
		var template = DataLoader.get_entry("potions", String(raw.get("itemId", "")))
		if not template is Dictionary or template.get("kind") != entry.id:
			continue
		var remaining := Consumable.cd_of(String(raw.itemId))
		if remaining <= 0.0:
			return 0.0
		minimum = minf(minimum, remaining)
	return 0.0 if minimum == INF else minimum

func set_count(amount: int) -> void:
	_count.text = str(amount) if amount > 0 else ""
	modulate.a = 0.45 if amount == 0 else 1.0

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		clear_requested.emit(index)
		accept_event()

func _get_drag_data(_at_position: Vector2) -> Variant:
	if entry == null:
		return null
	if get_viewport().gui_is_dragging():
		var layer := get_tree().get_first_node_in_group("drag_ghost_layer")
		if layer != null:
			DragGhost.spawn_text(layer, tooltip_text)
		else:
			var preview := Label.new()
			preview.text = text
			set_drag_preview(preview)
	return {"kind": "hotbar_slot", "index": index}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if data.get("kind") == "hotbar_slot":
		var source := int(data.get("index", -1))
		return source >= 0 and source < HotbarConfig.SIZE and GameState.hotbar[source] != null
	if data.get("kind") == "hotbar_skill":
		return HotbarConfig.valid_entry({"kind": "skill", "id": data.get("id")})
	if int(data.get("from", -1)) == ItemSlot.ROLE_BAG:
		var source := int(data.get("index", -1))
		if source < 0 or source >= GameState.inventory.size() or not GameState.inventory[source] is Dictionary:
			return false
		var item: Dictionary = GameState.inventory[source]
		var binding := HotbarConfig.entry_for_item(item)
		return not binding.is_empty() and Warehouse.token_matches(item, String(data.get("token", "")))
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_at_position, data):
		binding_dropped.emit(index, data as Dictionary)
