class_name EquipmentGap
extends RefCounted
## 装备跨级伤害规则：只约束玩家打61级以上目标，20级缓冲后逐件汇总并保留主武器约束。
## 上下文仅含14个穿戴等级及至多64个目标等级的系数；不读背包、属性、存档或驱动伤害。
const CACHE_LIMIT := 64
static var _current: Dictionary = {}

## 捕获穿戴等级签名，自动识别穿脱、保星、重置与读档；不依赖信号先后顺序。
## 返回上下文只读（除内部memo）；技能一次捕获，多段/多目标复用该快照。
static func current_context() -> Dictionary:
	var levels := levels_of(GameState.equipment)
	if _current.is_empty() or _current.revision != DataLoader.revision or _current.levels != levels:
		_current = context(levels)
	return _current

## 从唯一14槽定义读取实例需求等级，空槽记0，禁止通过脱装缩小分母。
static func levels_of(equipment: Dictionary) -> PackedInt32Array:
	var levels := PackedInt32Array()
	for slot in Equipment.SLOT_DEFS:
		var item: Variant = equipment.get(slot.id)
		levels.append(Equipment.level_req(item) if item is Dictionary and item.get("kind") == "equip" else 0)
	return levels

## 纯规则快照构造器；显式等级供边界测试和换装预览，配置随DataLoader修订替换。
static func context(levels: PackedInt32Array) -> Dictionary:
	return {"levels":levels.duplicate(), "rules":DataLoader.get_table("equipmentGap"), "revision":DataLoader.revision, "memo":{}}

## 逐件先扣20级缓冲后加权，主武器超额与综合超额取max，绝不重复乘惩罚。
static func summary(ctx: Dictionary, monster_level: int) -> Dictionary:
	var cfg: Variant = ctx.rules
	if not cfg is Dictionary or monster_level < int(cfg.get("minMonsterLevel", 61)):
		return {"factor":1.0, "excess":0.0, "weapon":int(ctx.levels[0]), "recommended":0}
	if ctx.memo.has(monster_level):
		return ctx.memo[monster_level]
	var excess := 0.0
	var weapon_excess := 0.0
	var grace := int(cfg.graceLevels)
	for i in range(Equipment.SLOT_DEFS.size()):
		var slot: String = Equipment.SLOT_DEFS[i].id
		var gap := maxf(0.0, monster_level - int(ctx.levels[i]) - grace)
		excess += float(cfg.weights[slot]) * gap
		if slot == "weapon":
			weapon_excess = gap
	excess = snappedf(maxf(excess, weapon_excess), 0.000001)
	var result := {"factor":pow(0.5, excess / float(cfg.halfDamageEveryExtraLevels)), "excess":excess, "weapon":int(ctx.levels[0]), "recommended":maxi(1,monster_level-grace)}
	if ctx.memo.size() >= CACHE_LIMIT:
		ctx.memo.clear()
	ctx.memo[monster_level] = result
	return result

## 无实际等级的练习桩/测试目标不套用人物等级，防止制造虚假的装备惩罚。
static func target_level(target: Node) -> int:
	var level: Variant = target.get("level")
	return maxi(0,int(level)) if level is int or level is float else 0

## 最终伤害仅缩放一次，闪避保持0、暴击标记与其他键原样保留；不消耗随机数。
static func apply(result: Dictionary, ctx: Dictionary, monster_level: int) -> Dictionary:
	var factor := float(summary(ctx, monster_level).factor)
	if factor >= 1.0 or bool(result.get("miss",false)):
		return result
	var adjusted := result.duplicate()
	adjusted.damage = maxi(1, floori(float(result.get("damage",0))*factor))
	return adjusted

## 在未穿装预览中替换指定槽，再按同一公式计算目标系数，不修改真实装备或快照。
static func preview(equipment: Dictionary, item: Dictionary, slot: String, monster_level: int) -> Dictionary:
	var trial := equipment.duplicate()
	trial[slot] = item
	return summary(context(levels_of(trial)),monster_level)

## 加载期拒绝非法阈值、权重、缺槽和NaN，避免战斗中出现除零或静默少算部位。
static func validate_config(cfg: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not cfg is Dictionary or not cfg.get("weights") is Dictionary:
		return ["[equipmentGap] 需要规则对象与weights"]
	for key in ["minMonsterLevel","graceLevels","halfDamageEveryExtraLevels"]:
		var n: Variant = cfg.get(key)
		if not (n is int or n is float) or not is_finite(float(n)) or float(n)!=floor(float(n)) or float(n)<(0.0 if key=="graceLevels" else 1.0):
			errors.append("[equipmentGap] 非法参数："+key)
	if int(cfg.get("minMonsterLevel", 0)) < 61:
		errors.append("[equipmentGap] 不得影响前60级主线")
	if cfg.weights.size()!=Equipment.SLOT_DEFS.size():
		errors.append("[equipmentGap] 权重必须覆盖14槽")
	var sum := 0.0
	for slot in Equipment.SLOT_DEFS:
		var w: Variant = cfg.weights.get(slot.id)
		if not (w is int or w is float) or not is_finite(float(w)) or float(w)<=0.0 or float(w)>1.0:
			errors.append("[equipmentGap] 非法槽权重："+String(slot.id))
		else:
			sum += float(w)
	if not is_equal_approx(sum,1.0):
		errors.append("[equipmentGap] 权重和必须为1")
	return errors
