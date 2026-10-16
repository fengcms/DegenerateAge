extends Node
## 怪物表现复用验收：两个不同怪物 ID 可共享图集，而数值、掉落与身份仍独立。
## 在隔离测试项目运行；临时修改的内存模板会在测试结束前还原。

var failures: Array[String] = []

## 记录独立断言失败，避免一次错误掩盖后续资源或身份问题。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[MonsterAppearanceReuseTest] " + message)

## 装配同外观的两个不同怪物，并核对视觉资源共享与战斗模板隔离。
func _ready() -> void:
	var wolf_data: Dictionary = DataLoader.get_entry("monsters", "wolf_corrupted")
	var shell_data: Dictionary = DataLoader.get_entry("monsters", "shellback_bug")
	var previous: Variant = shell_data.get("appearanceId")
	shell_data["appearanceId"] = String(wolf_data.get("appearanceId", ""))
	var scene := load("res://scenes/entities/Monster.tscn") as PackedScene
	var wolf := scene.instantiate() as Monster
	wolf.monster_id = "wolf_corrupted"
	add_child(wolf)
	wolf.set_physics_process(false)
	var shell := scene.instantiate() as Monster
	shell.monster_id = "shellback_bug"
	add_child(shell)
	shell.set_physics_process(false)
	shell_data["appearanceId"] = previous
	check(wolf.sample_art != null and shell.sample_art != null, "不同怪物都装配外观")
	if wolf.sample_art != null and shell.sample_art != null:
		check(wolf.sample_art.texture == shell.sample_art.texture, "同外观复用同一纹理资源")
	check(wolf.monster_id != shell.monster_id and wolf.display_name != shell.display_name, "怪物身份独立")
	check(wolf.max_hp != shell.max_hp and wolf.attack_power != shell.attack_power, "血量与攻击仍按各自模板计算")
	check(String(wolf.template.get("dropTableId", "")) != String(shell.template.get("dropTableId", "")), "掉落表仍按各自模板")
	check(wolf.sample_art != shell.sample_art, "动画状态节点属于各自实例")
	check(DataLoader.validate_all().is_empty(), "还原模板后配置引用有效")
	print("[MonsterAppearanceReuseTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
