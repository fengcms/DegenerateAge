class_name LevelGap
extends RefCounted
## M3-6：怪物击杀经验的等级差。任务经验不经过这里。
## A2：越级伤害倍率（产品 03 §3.13）也放在本类，与经验倍率同源、同为无状态纯函数。

static func experience_multiplier(player_level: int, monster_level: int) -> float:
	return clampf(1.0 - float(player_level - monster_level) * 0.04, 0.2, 1.5)

## A2 越级伤害（产品 03 §3.13）：`1 + (怪等级 − 玩家等级) × 0.02`，上限 1.3。
## 下限取 **1.0**（口径①「只奖不罚」）：玩家高于怪时不掉伤害——反刷由 `experience_multiplier`
## 承担（经验衰减到 0.2 倍），若此处再给负倍率会让回流低图变成「打不动」而非「收益低」。
## 双向对称：玩家打怪与怪打玩家共用本公式，调用时玩家等级恒在前。
static func damage_multiplier(player_level: int, monster_level: int) -> float:
	return clampf(1.0 + float(monster_level - player_level) * 0.02, 1.0, 1.3)

static func kill_xp(base_xp: int, player_level: int, monster_level: int) -> int:
	return roundi(maxi(0, base_xp) * experience_multiplier(player_level, monster_level))
