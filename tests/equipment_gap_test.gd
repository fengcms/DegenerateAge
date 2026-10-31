extends Node
## 装备跨级独立契约：缓冲边界、混装/武器绕过、空槽、缓存与伤害元信息。
var failures: Array[String] = []

## 聚合错误，完成全部契约后才退出。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

## 只构造等级上下文，不制造极品属性或触碰存档。
func ctx(level: int) -> Dictionary:
	var levels := PackedInt32Array()
	levels.resize(14)
	levels.fill(level)
	return EquipmentGap.context(levels)

## 逐个验证业务边界，随机状态断言保护现有技能的随机流。
func _ready() -> void:
	check(EquipmentGap.validate_config(DataLoader.get_table("equipmentGap")).is_empty(),"正式规则合法")
	for gap in [0,20,21,30,40,60,67]:
		var factor := float(EquipmentGap.summary(ctx(500-gap),500).factor)
		check(is_equal_approx(factor,pow(0.5,maxi(0,gap-20)/20.0)),"差距边界 "+str(gap))
	check(EquipmentGap.summary(ctx(0),60).factor==1.0,"60级及以下逐位保持原规则")
	var trial := ctx(517)
	trial.levels[12]=450
	check(is_equal_approx(EquipmentGap.summary(trial,517).factor,pow(0.5,47*0.04/20.0)),"单枚戒指只按半类权重")
	trial=ctx(517)
	trial.levels[0]=450
	check(is_equal_approx(EquipmentGap.summary(trial,517).factor,pow(0.5,47/20.0)),"旧武器不能被新防具掩盖")
	trial=ctx(450)
	trial.levels[0]=517
	check(EquipmentGap.summary(trial,517).factor<0.30,"只换武器不解除整套过旧")
	trial=ctx(517)
	trial.levels[0]=0
	check(EquipmentGap.summary(trial,517).factor<0.01,"脱掉武器不规避")
	var result: Dictionary={"miss":false,"damage":1000,"critical":true}
	var adjusted := EquipmentGap.apply(result,ctx(450),510)
	check(adjusted.damage==250 and adjusted.critical and result.damage==1000,"最终伤害缩放一次且不改原结果")
	check(EquipmentGap.apply({"miss":true,"damage":0},ctx(0),517).damage==0,"闪避仍零伤害")
	check(EquipmentGap.apply({"miss":false,"damage":1},ctx(0),517).damage==1,"伤害最低一点")
	var bad: Dictionary=DataLoader.get_table("equipmentGap").duplicate(true)
	bad.halfDamageEveryExtraLevels=0
	check(not EquipmentGap.validate_config(bad).is_empty(),"拒绝除零")
	bad.minMonsterLevel={}
	check(not EquipmentGap.validate_config(bad).is_empty(),"异常类型由校验报告而不是转换崩溃")
	bad.minMonsterLevel=1e30
	check(not EquipmentGap.validate_config(bad).is_empty(),"拒绝整数溢出的配置")
	trial=ctx(450)
	for level in range(61,300):EquipmentGap.summary(trial,level)
	check(trial.memo.size()<=64,"目标等级缓存有界")
	GameState.reset_to_defaults()
	var before:=EquipmentGap.current_context()
	GameState.equipment.weapon={"kind":"equip","requiredLevel":450}
	var after:=EquipmentGap.current_context()
	check(before.levels!=after.levels,"直接读档替换也识别等级变化，不依赖信号先后")
	check(is_same(after,EquipmentGap.current_context()),"同签名复用上下文")
	benchmark()
	print("[EquipmentGapTest] ","全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 固定100目标×3段比较新增层CPU成本；真实攻击上限更低，此样本不代表整帧性能。
func benchmark() -> void:
	for slot in Equipment.SLOT_DEFS:
		GameState.equipment[slot.id]={"kind":"equip","requiredLevel":450}
	var states: Array[int]=[]
	for enabled in [false,true]:
		var rng:=RandomNumberGenerator.new()
		rng.seed=8811
		var samples: Array[float]=[]
		for sample in range(120):
			var start:=Time.get_ticks_usec()
			var captured:=EquipmentGap.current_context() if enabled else {}
			for i in range(300):
				var result:=Combat.resolve(1000000.0,50000.0,1.4,0.07,2.1,4.0,rng)
				if enabled:EquipmentGap.apply(result,captured,510+i%3)
			samples.append((Time.get_ticks_usec()-start)/1000.0)
		samples.sort()
		states.append(rng.state)
		print("[PERF] equipment_gap enabled=",enabled," targets100_hits3_ms=",[samples[60],samples[114],samples[118],samples[-1]])
	check(states[0]==states[1],"新增层不改变真实Combat随机消耗")
