extends SceneTree
## 营地地图编辑器主屏幕注册测试。需使用 Godot 的 --editor --script 运行，
## 检查实际编辑器是否创建页面与顶部标签，弥补普通场景测试无法实例化 EditorPlugin 的缺口。

## 编辑器初始化完成后查找主屏幕页面和可见标签，并用进程退出码报告结果。
func _initialize() -> void:
	call_deferred("_verify_main_screen")

## 最多等待 120 帧，以覆盖编辑器加载布局和插件的时序差异。
func _verify_main_screen() -> void:
	for _frame in range(120):
		await process_frame
		var main_screen := EditorInterface.get_editor_main_screen()
		if main_screen == null:
			continue
		var found_panel := false
		for child in main_screen.get_children():
			if child.name == "营地地图编辑":
				found_panel = true
				break
		if not found_panel:
			continue
		for button in EditorInterface.get_base_control().find_children("*", "Button", true, false):
			if button.text == "营地地图" and button.is_visible_in_tree() and button.icon != null:
				print("[CampMapEditorMainScreenTest] PASS · 页面和顶部标签均已注册")
				quit(0)
				return
	printerr("[CampMapEditorMainScreenTest] FAIL · 未找到可见的营地地图顶部标签")
	quit(1)
