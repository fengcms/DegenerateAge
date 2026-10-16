@tool
extends EditorPlugin
## 幸存者营地专用 Godot 主屏幕插件。只在编辑器运行，加载独立草稿画布，
## 由显式“应用到游戏”操作调用现有生成器，不在普通游戏启动时执行。

const PANEL_SCRIPT := preload("res://addons/camp_map_editor/camp_map_panel.gd")
var panel: Control

## 插件启用时创建营地编辑页并挂入 Godot 主屏幕。
func _enter_tree() -> void:
	panel = PANEL_SCRIPT.new()
	panel.name = "营地地图编辑"
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()

## 插件停用时释放编辑页，不保留悬挂的编辑器控件。
func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.queue_free()

## 主屏幕标签名，供使用者在 2D／3D／脚本旁切换到地图编辑页。
func _get_plugin_name() -> String:
	return "营地地图"

## 复用编辑器原生地图图标，不依赖另外制作 SVG 资源。
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("TileMapLayer", "EditorIcons")

## 显示或隐藏主屏幕控件；隐藏时不写入草稿或正式地图。
func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = visible
