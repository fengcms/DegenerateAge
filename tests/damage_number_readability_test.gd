extends Node
## 验证正式场景伤害飘字长文本、缩放锚点和清理。只发送表现事件，不修改测试角色血量。

## 通过正常 Fx 入口投递一次暴击，确保节点在世界遮挡层之上，更新后仍对中且按时释放。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	var world := preload("res://scenes/Game.tscn").instantiate()
	add_child(world)
	var player := world.get_node("Entities/Player") as Node2D
	Fx.damage_number(get_tree(), player, {"damage": 9876543210, "critical": true})
	await get_tree().process_frame
	await get_tree().process_frame
	var layer := world.get_node("DamageNumbers") as Node2D
	assert(layer.z_index > 3500, "飘字必须处于深度排序的角色与地图物件上方")
	assert(layer.get_child_count() == 1, "真实入口应生成一条飘字")
	var label := layer.get_child(0).get_node("Label") as Label
	assert(label.text == "9876543210" and label.size.x > 88, "长伤害数值应完整撑开文字区域")
	assert(label.get_theme_constant("outline_size") > 0, "伤害字应保留对亮地形的描边")
	assert((label.position + label.pivot_offset).is_equal_approx(Vector2(0, -20)), "长伤害字的中心应固定")
	GameState.settings["mapScale"] = 2.0
	SettingsRuntime.apply_world_text_scale_to(label)
	assert(label.pivot_offset == label.size * 0.5 and is_equal_approx(label.scale.x, SettingsRuntime.world_text_scale_value()))
	await get_tree().create_timer(1.0).timeout
	assert(layer.get_child_count() == 0, "飘字淡出后应释放")
	print("[DamageNumberReadabilityTest] PASS")
	get_tree().quit()
