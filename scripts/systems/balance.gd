class_name Balance
extends RefCounted
## M10-0：满级后数值地基（产品 13 §2）。三条曲线 + 两个基线推导，全部纯静态、无状态。
##
## 口径约束：L ≤ 60 时必须与既有实现**逐位一致**（经验 round(100·L^1.6)、
## 升级攻 +2 / 防 +1），任何改动都要过 tests/BalanceTest 的 1–60 全量比对。
## 本类**不引用 GameState**：`--check-only` 单脚本检查时 autoload 不可见会出假阳性，
## 上限截断交给调用方。
##
## ⚠ 离线估算工具 `tools/balance_check.py` 与本类**同源但不是权威**：权威只有本类，
##   改一边必须同步另一边（否则下一个人会按错表算数值）。

## 60 级及以下沿用 4.4 的逐级成长；> 60 改走曲线。
const SOFTCAP_LEVEL := 60
## L60 的基线值（= 12 + 59×2 / 5 + 59×1），是曲线的锚点。
const BASE_ATTACK_60 := 130
const BASE_DEFENSE_60 := 64

## 缩放曲线 S(d) = 1 + 0.12·d + 0.0022·max(0, d−12)²，d = level − 60。
## 线性段即既有 M_HP_PER_LV = 0.12；二次段从 d = 13 起，故存量（最大 d = 9）不受影响。
static func scale(delta_level: int) -> float:
	var d := maxi(0, delta_level)
	var quadratic := 0.0022 * pow(float(maxi(0, d - 12)), 2.0)
	return 1.0 + 0.12 * float(d) + quadratic

## 经验曲线 E(L) = round(100·L^1.6·(1 + 0.03·max(0, L−60)))。
## L ≤ 60 时 boost 恒 1.0 —— 与旧的 round(100·L^1.6) 完全等价（IEEE754 下 x×1.0 == x）。
static func xp_to_next(level: int) -> int:
	var l := maxi(1, level)
	var boost := 1.0 + 0.03 * float(maxi(0, l - SOFTCAP_LEVEL))
	return int(round(100.0 * pow(float(l), 1.6) * boost))

## 难度旋钮：每级期望击杀循环 Boss 数 K(L) = 12 + 0.18·max(0, L−60)。
static func kills_per_level(level: int) -> float:
	return 12.0 + 0.18 * float(maxi(0, level - SOFTCAP_LEVEL))

## 循环 Boss 的单只经验 = E / K（掉落表不再手填经验，改由此反推，保证「打 K 只升一级」）。
static func boss_xp(level: int) -> int:
	return int(round(float(xp_to_next(level)) / maxf(1.0, kills_per_level(level))))

## 基线攻击：L ≤ 60 = 12 + 2(L−1)；L > 60 = round(130 · S(L−60))。
static func base_attack(level: int) -> int:
	var l := maxi(1, level)
	if l <= SOFTCAP_LEVEL:
		return 12 + (l - 1) * 2
	return int(round(float(BASE_ATTACK_60) * scale(l - SOFTCAP_LEVEL)))

## 基线防御：L ≤ 60 = 5 + (L−1)；L > 60 = round(64 · S(L−60))。
static func base_defense(level: int) -> int:
	var l := maxi(1, level)
	if l <= SOFTCAP_LEVEL:
		return 5 + (l - 1)
	return int(round(float(BASE_DEFENSE_60) * scale(l - SOFTCAP_LEVEL)))
