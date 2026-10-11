class_name Fx
extends RefCounted
## 视觉反馈工具（产品文档 9.5）：伤害飘字的统一生成入口，玩家与怪物共用。

const DAMAGE_NUMBER_SCENE := preload("res://scenes/ui/DamageNumber.tscn")

## 在目标上方生成一个伤害飘字（普通白 / 暴击黄 / Miss 灰）。
## 飘字层 = 场景树中分组 "damage_numbers" 的节点（DamageNumbers）。
static func damage_number(tree: SceneTree, target: Node2D, result: Dictionary) -> void:
	if tree == null or target == null:
		return
	var layer := tree.get_first_node_in_group("damage_numbers")
	if layer == null:
		return
	var dn: Node2D = DAMAGE_NUMBER_SCENE.instantiate()
	# 连续命中时错位堆叠，避免飘字互相覆盖（9.5）
	var stagger := 14.0 * float(layer.get_child_count() % 3)
	dn.position = target.global_position + Vector2(0.0, -28.0 - stagger)
	dn.setup(int(result.get("damage", 0)), bool(result.get("critical", false)), bool(result.get("miss", false)))
	layer.add_child(dn)
