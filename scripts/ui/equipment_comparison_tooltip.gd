extends GridContainer
## 原生 tooltip 在独立弹窗内；使用实时来源而非创建时的旧物品快照。

var source_slot: WeakRef

func _ready() -> void:
	EventBus.equipment_changed.connect(_refresh)
	EventBus.inventory_changed.connect(_refresh)
	EventBus.upgrade_completed.connect(_refresh)
	EventBus.settings_changed.connect(_refresh)
	EventBus.data_loaded.connect(_refresh)
	EventBus.target_changed.connect(_on_reference_target_changed)
	EventBus.player_leveled.connect(func(_level: int) -> void: _refresh())

func _refresh() -> void:
	var source: Object = source_slot.get_ref() if source_slot != null else null
	if source == null or not is_instance_valid(source):
		hide()
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var item: Dictionary = source.get("item")
	if String(item.get("kind", "")) != "equip":
		hide()
		return
	show()
	source.call("_populate_equipment_tooltip", self)

## 悬停期间切换战斗目标也更新跨级参考，沿用既有弱引用与布局刷新入口。
func _on_reference_target_changed(_target: Node) -> void:
	_refresh()
