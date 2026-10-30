class_name ServiceFee
extends RefCounted
## 铁匠服务费率：随身通道与回城通道的唯一口径（工程 108 / 产品 13 §5.6）。
##
## 🔴 这个文件存在的唯一理由：本项目的费用是「显示」与「扣费」**两处独立算的** ——
##    `upgrade_panel.gd` 显示时调一次 `Upgrade.cost()`，`game_state.upgrade_equipment()`
##    扣费时又调一次。重铸同理。两边只要有一处取整方式不同，按钮价与实际扣款就差 1 金。
##    这种差在逐值断言里很难覆盖，但玩家一对账就能发现（工程 108 §11.3）。
##    **显示与扣费必须都走这里。**
##
## 两条费率是**产品决策**，不是调参：
##   ① 修理 1.5×（与随身商店同价，工程 77 / 108 Q3）—— 两条远程通道不能一条贵一条便宜；
##   ② 成长服务 1.2×（108 Q4）—— 若随身完全不加价，回城铁匠在 80 级后永久失业，
##      「回城」从此少一条理由。+20% 把回城保留成「省两成换一趟路」的**有意义选择**。

## 随身通道的成长服务费率（升星 / 重铸 / 保星升级）。
## 只作用于**有金币费用**的三项；四金合紫 / 四紫定向 / 四紫升星 / 献祭只耗材料，不受影响。
const PORTABLE_RATE := 1.2

## 随身通道的修理费率。与 `ShopPanel` 的随身修理同价（两处都读这里，不要各写 1.5）。
const REPAIR_PORTABLE_RATE := 1.5

## 成长服务的唯一取整口径：**向上取整**。
## 向上而不是四舍五入：宁可玩家多付 1 金，也不要出现「标价 100 实扣 99」这种对不上账的写法。
static func apply(base: int, rate: float) -> int:
	if rate <= 1.0 or base <= 0:
		return base
	return int(ceil(float(base) * rate))

## 成长服务费率。`portable = false` 返回 1.0（回城原价）。
static func rate_for(portable: bool) -> float:
	return PORTABLE_RATE if portable else 1.0

## 修理费费率。`portable = false` 返回 1.0（回城原价）。
static func repair_rate_for(portable: bool) -> float:
	return REPAIR_PORTABLE_RATE if portable else 1.0

## 修理费的唯一取整口径。
## 🔴 **必须与 `GameState.repair_equipment()` 里的 `round(total * maxf(1.0, rate))` 逐位一致**。
##    这里若换成 `apply()` 的 ceil，显示就会比实扣多 1—N 金 —— 两处看似都「加了价」，
##    但取整方向不同，是 108 里最隐蔽的一类不一致。
static func apply_repair(base: int, rate: float) -> int:
	if rate <= 1.0 or base <= 0:
		return base
	return maxi(1, int(round(float(base) * rate)))
