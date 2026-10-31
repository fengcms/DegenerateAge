extends Node
## 实际玩家普攻/多段群攻契约，固定无暴击无闪避以精确检查每段只乘一次跨级系数。
class Enemy extends Node2D:
	var level := 510
	var is_dead := false
	var hits: Array[int] = []
	## 仅登记可攻击目标，不执行AI与奖励。
	func _ready() -> void:
		add_to_group("enemies")
	## 返回独立固定防御，便于从外部推算伤害。
	func get_defense() -> float:
		return 100.0
	## 固定命中，避免随机闪避掩盖重复衰减。
	func get_dodge() -> float:
		return 0.0
	## 记录原生产入口实际交付的各段结果。
	func take_hit(result: Dictionary, _from: Node = null) -> void:
		hits.append(int(result.damage))
var failures: Array[String] = []

## 失败仍完成剩余检查并输出非零结果。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

## 等级夹具不伪造随机极品属性，仅让等级上下文与总攻独立。
func gear(level: int) -> void:
	for slot in Equipment.SLOT_DEFS:
		GameState.equipment[slot.id]={"kind":"equip","requiredLevel":level,"quality":"common","star":0}

## 普攻、换装恢复与混合等级AOE都通过真实PlayerCharacter入口。
func _ready() -> void:
	GameState.reset_to_defaults("mage")
	GameState.current_map="wild_trial"
	GameState.player.level=517
	GameState.player.attack=1000
	GameState.player.criticalChance=0.0
	GameState.player.mp=GameState.max_mp()
	GameState.skill_ranks.flame_burst=5
	gear(450)
	var player:=PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position=Vector2(1500,1500)
	var power:=player.effective_attack_power()
	var first:=Enemy.new()
	add_child(first)
	first.position=player.position+Vector2(40,0)
	var raw:=floori(power-50.0)
	var result:=player.perform_attack(first)
	check(result.damage==maxi(1,floori(raw*0.25)) and first.hits[0]==result.damage,"普攻最终伤害与事件/目标一致")
	gear(510)
	result=player.perform_attack(first)
	check(result.damage==raw,"换装立即解除，不等待装备信号")
	gear(450)
	first.level=60
	result=player.perform_attack(first)
	check(result.damage==raw,"前60级不改变伤害")
	first.level=510
	first.hits.clear()
	var lower:=Enemy.new()
	add_child(lower)
	lower.level=450
	lower.position=player.position+Vector2(60,20)
	var higher:=Enemy.new()
	add_child(higher)
	higher.level=517
	higher.position=player.position+Vector2(80,-20)
	var skill:=SkillProgression.current("flame_burst")
	check(player.cast_skill("flame_burst",first),"真实高阶群攻施放成功")
	var base:=floori(power*float(skill.coefficient)-50.0)
	for enemy in [first,lower,higher]:
		var factor:=pow(0.5,maxi(0,enemy.level-450-20)/20.0)
		check(enemy.hits.size()==3,"高阶多段每目标三次")
		for damage in enemy.hits:
			check(damage==maxi(1,floori(base*factor)),"AOE逐目标按实际等级，衰减只乘一次")
	var rng:=Combat.rng()
	rng.seed=913
	var state:=rng.state
	EquipmentGap.apply({"miss":false,"damage":1000,"critical":false},EquipmentGap.current_context(),517)
	check(rng.state==state,"新规则不消耗随机数")
	print("[EquipmentGapCombatTest] ","全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
