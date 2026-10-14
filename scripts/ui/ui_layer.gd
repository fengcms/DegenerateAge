extends CanvasLayer
## 对运行中创建的提示、任务行和交易行应用与静态 UI 相同的文字倍率。

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is Label or node is Button or node is LineEdit or node is OptionButton or node is TabBar:
		_apply_new_text.call_deferred(node.get_instance_id())

func _apply_new_text(node_id: int) -> void:
	var node := instance_from_id(node_id) as Node
	if node == null or not is_ancestor_of(node):
		return
	SettingsRuntime.apply_text_scale_to(node)
