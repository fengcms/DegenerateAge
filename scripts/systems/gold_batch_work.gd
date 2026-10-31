class_name GoldBatchWork
extends RefCounted
## 分帧准备随机产物，只写本地候选；真实背包在最后一次终验后提交。
var groups: Array
var outputs: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var used_ids: Dictionary
var failed := false
func _init(input_groups: Array, seed_value: int, ids: Dictionary) -> void:
	groups = input_groups
	rng.seed = seed_value
	used_ids = ids.duplicate()
func advance(limit: int = 8) -> void:
	var kinds := Equipment.slot_kinds()
	var stop := mini(groups.size(), outputs.size() + limit)
	while outputs.size() < stop and not failed:
		var group: Array = groups[outputs.size()]
		var kind := String(kinds[rng.randi_range(0, kinds.size() - 1)])
		var output := EquipmentFusion.make_output(EquipmentFusion.tier_start(group[0]), kind, rng)
		if output.is_empty() or not SaveManager._valid_item(output) or used_ids.has(output.get("instanceId")):
			failed = true
			return
		used_ids[output.instanceId] = true
		outputs.append(output)
func done() -> bool:
	return failed or outputs.size() == groups.size()
