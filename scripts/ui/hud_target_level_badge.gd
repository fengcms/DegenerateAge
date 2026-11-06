extends "res://scripts/ui/hud_level_badge.gd"
## 普通/精英目标的等级徽章：继承人物金边、描边布局与字宽适配，只监听选中目标事件。
## 等级取Monster运行实例；NPC和空目标隐藏。Boss继续使用顶部专用状态栏，不创建第二份目标卡。

## 初始化共享徽章并订阅目标切换，节点释放时引擎自动断开连接，无逐帧目标扫描。
func _ready() -> void:
	super._ready()
	visible = false
	EventBus.target_changed.connect(_on_target_changed)

## 目标切换时显示实际动态等级；清空非怪物目标，避免NPC沿用上一只怪物的数字。
func _on_target_changed(target: Node) -> void:
	visible = is_instance_valid(target) and not target.is_queued_for_deletion() and target is Monster and not target.is_dead
	_label.text = str(target.level) if visible else ""
	_label.tooltip_text = "%s %d" % [Localization.tr_key("ui.hud.level"), target.level] if visible else ""
	if visible:
		_fit_text()
