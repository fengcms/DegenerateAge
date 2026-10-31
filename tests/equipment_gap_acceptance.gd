extends Node
## 武士/法师真实AutoPilot单Boss击杀对照：同旧装关闭新层、同旧装启用、同品质星级升级投影。
## 固定60Hz游戏步长加速执行，只用于逻辑与游戏时间，不代表GPU帧率或真人装备骰子。
var failures: Array[String] = []
var rules: Dictionary

## 记录真实击杀和换装改善，超时不冒充胜利。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

## 生成一次旧装快照，后两轮复制它，不在各轮重新骰不同品质/词条。
func make_gear() -> Dictionary:
	var gear:=Equipment.create()
	for i in range(Equipment.SLOT_DEFS.size()):
		var slot: Dictionary=Equipment.SLOT_DEFS[i]
		var rng:=RandomNumberGenerator.new()
		rng.seed=45200+i
		var item:=ItemFactory.make_equip_exact(EquipmentFusion.template_for(441,slot.kind),440,"legendary",rng)
		item.star=12
		gear[slot.id]=item
	return gear

## 受控新装投影，仅重标基底与固定词条；百分比、星级、词条种类不变。
func uplift(gear: Dictionary) -> Dictionary:
	var result:=gear.duplicate(true)
	var ratio:=Balance.scale(500-60)/Balance.scale(440-60)
	for item in result.values():
		for stat in item.rawBaseAttrs:item.rawBaseAttrs[stat]=roundi(float(item.rawBaseAttrs[stat])*ratio)
		for entry in item.affixes:entry.value=roundi(float(entry.value)*ratio)
		item.level=500
		item.requiredLevel=500
	return result

## 每轮实例化真实Game，Boss关闭AI以排除承伤/走位变量，玩家保留实际自动技能和冷却。
func fight(class_id: String, gear: Dictionary, enabled: bool) -> float:
	DataLoader.tables.equipmentGap=rules.duplicate(true)
	if not enabled:DataLoader.tables.equipmentGap.minMonsterLevel=9999
	DataLoader.revision+=1
	GameState.reset_to_defaults(class_id)
	GameState.player.level=500
	GameState.player.attack=Balance.base_attack(500)
	GameState.player.defense=Balance.base_defense(500)
	GameState.equipment=gear.duplicate(true)
	GameState.player.hp=GameState.max_hp()
	GameState.player.mp=GameState.max_mp()
	GameState.current_map="c7_boss_field"
	GameState.settings.allowBoss=true
	for id in PlayerClass.active_skills():GameState.skill_ranks[id]=SkillProgression.max_rank(id)
	GameState.hotbar=HotbarConfig.defaults(class_id)
	Combat.rng().seed=5199
	var world:=preload("res://scenes/Game.tscn").instantiate()
	add_child(world)
	world.get_node("Spawner").set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var player:=world.get_node("Entities/Player") as PlayerCharacter
	var boss:=preload("res://scenes/entities/Monster.tscn").instantiate() as Monster
	boss.monster_id="c6_boss03"
	boss.spawn_level=500
	boss.stat_norm=Endgame.norm(boss.monster_id)
	boss.hp_multiplier=2.0
	boss.atk_multiplier=3.0
	boss.ai_enabled=false
	boss.position=player.position+Vector2(48,0)
	world.get_node("Entities").add_child(boss)
	GameState.set_auto_battle(true)
	GameState.set_auto_pickup(false)
	var elapsed:=0.0
	for tick in range(18000):
		await get_tree().physics_frame
		elapsed=(tick+1)/60.0
		if not is_instance_valid(boss) or boss.is_dead:break
	check(not is_instance_valid(boss) or boss.is_dead,"300游戏秒内确实击杀")
	GameState.set_auto_battle(false)
	world.queue_free()
	await get_tree().process_frame
	return elapsed

## 六轮同源对照完成后恢复配置；不改变真实角色或发布配置。
func _ready() -> void:
	rules=DataLoader.get_table("equipmentGap").duplicate(true)
	var gear:=make_gear()
	for class_id in ["warrior","mage"]:
		var legacy: float=await fight(class_id,gear,false)
		var stale: float=await fight(class_id,gear,true)
		var fresh: float=await fight(class_id,uplift(gear),true)
		check(stale>legacy*3.0,"跨60级实际自动战斗明显变慢 "+class_id)
		check(fresh<stale*0.7,"同品质星级换装明显恢复 "+class_id)
		print("[PERF] ",class_id," game_seconds legacy=",legacy," stale=",stale," fresh=",fresh)
	DataLoader.tables.equipmentGap=rules
	DataLoader.revision+=1
	print("[EquipmentGapAcceptance] ","全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
