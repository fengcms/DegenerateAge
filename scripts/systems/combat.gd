class_name Combat
extends RefCounted
## 战斗结算（产品文档 3.1 流程 / 3.2 伤害公式 / 3.5 概率 Miss / 3.8 上限）。
##
## 纯函数、不持有状态，攻防双方共用同一套公式（敌我对等），便于单测。

const DODGE_K := 50.0              # 3.5：missChance = dodge / (dodge + K)
const MAX_MISS := 0.75             # 3.8：闪避(Miss) 上限
const MAX_CRIT_CHANCE := 0.75      # 3.8：暴击率上限
const MAX_CRIT_MULT := 5.0         # 3.8：暴击伤害倍率上限
const MIN_ATTACK_INTERVAL := 0.2   # 3.8：攻击间隔下限(s)

## 怪物侧暴击参数约定（3.2 / B-P3-1）：怪物不暴击。集中常量避免调用点留白式硬编码，
## 与玩家侧读 `GameState.player` 的数据驱动策略区分清楚；将来若要给怪物开暴击，只需改这里。
const ENEMY_CRIT_CHANCE := 0.0
const ENEMY_CRIT_MULT := 1.0

static var _rng: RandomNumberGenerator = null

## 默认随机源（延迟初始化并随机化种子）。
static func rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng

## 概率 Miss：防御方闪避越高，越可能完全免伤；封顶 75%（3.5）。
static func miss_chance(defender_dodge: float) -> float:
	if defender_dodge <= 0.0:
		return 0.0
	return clampf(defender_dodge / (defender_dodge + DODGE_K), 0.0, MAX_MISS)

## 结算一次攻击。返回 { miss: bool, damage: int, critical: bool }。
## 注：传入 use_rng 可复现随机（测试用）；crit_chance=0/1 时结果确定。
static func resolve(attacker_attack: float, defender_defense: float, multiplier: float,
		crit_chance: float, crit_mult: float, defender_dodge: float = 0.0,
		use_rng: RandomNumberGenerator = null) -> Dictionary:
	var r: RandomNumberGenerator = use_rng if use_rng != null else rng()

	# ① 命中判定（概率 Miss）
	if r.randf() < miss_chance(defender_dodge):
		return {"miss": true, "damage": 0, "critical": false}

	# ② 基础伤害：max(1, floor(攻×系数 − 防×0.5))
	var base := maxf(1.0, floorf(attacker_attack * multiplier - defender_defense * 0.5))

	# ③ 暴击判定
	var critical := r.randf() < clampf(crit_chance, 0.0, MAX_CRIT_CHANCE)
	var damage := base
	if critical:
		damage = floorf(base * clampf(crit_mult, 1.0, MAX_CRIT_MULT))

	# ④ 约束：伤害 ≥1
	return {"miss": false, "damage": maxi(1, int(damage)), "critical": critical}
