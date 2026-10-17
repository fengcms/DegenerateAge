extends Node
## 实例化主场景，核对功能面板实际外框类型，防止只美化按钮却遗漏根面板。

var _failures: Array[String] = []

## 遍历 09 清单中的所有独立面板，并确认原生确认框已经替换。
func _ready() -> void:
	GameState.reset_to_defaults()
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	var ui: Node = main.get_node("UI")
	for name in ["InventoryPanel", "CharacterPanel", "SkillPanel", "MountPanel", "ShopPanel",
			"SettingsPanel", "QuestPanel", "CarterPanel", "BlacksmithPanel", "SavePanel",
			"MenuPanel", "WarehousePanel", "UpgradePanel", "MapBigPanel", "DeathPanel",
			"FlowFeedback", "EquipmentConfirmation"]:
		var panel := ui.get_node_or_null(name)
		_check(panel != null, "%s 存在" % name)
		if panel != null:
			_check(not panel.find_children("*", "PanelChrome", true, false).is_empty(),
				"%s 实际接入共用外框" % name)
	var save: Control = ui.get_node("SavePanel")
	var settings: Control = ui.get_node("SettingsPanel")
	_check(save.get("_overwrite_dialog") is PanelConfirmDialog, "存档覆盖使用共用确认弹层")
	_check(settings.get("_conflict") is PanelConfirmDialog, "改键冲突使用共用确认弹层")
	# FileDialog 是平台文件选择器（继承 ConfirmationDialog），属明确例外：存档导出 / 导入需要它选外部文件，
	# 且工程文档《人物存档导出与导入设计方案》§8 明确不引入原生对话框。其余原生确认框一律禁止
	# （FileDialog 自带的内部确认框「覆盖文件？」等也算选择器的一部分，一并排除）。
	var legacy_dialogs: Array[Node] = []
	for node in ui.find_children("*", "ConfirmationDialog", true, false):
		if not node is FileDialog and not _inside_file_dialog(node):
			legacy_dialogs.append(node)
	_check(legacy_dialogs.is_empty(), "主场景没有遗留的原生确认弹窗：%s" % str(legacy_dialogs))
	if _failures.is_empty():
		print("[PanelChromeCoverageTest] 全部通过 ✅")
	else:
		for failure in _failures:
			push_error("[PanelChromeCoverageTest] 失败：" + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

## 累积结构检查的失败项，供隔离运行器以非零状态报告。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

## 节点是否位于某个 FileDialog 之内（含 FileDialog 自身的内部确认框）。
func _inside_file_dialog(node: Node) -> bool:
	var current := node.get_parent()
	while current != null:
		if current is FileDialog:
			return true
		current = current.get_parent()
	return false
