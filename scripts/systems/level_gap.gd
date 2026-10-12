class_name LevelGap
extends RefCounted
## M3-6：怪物击杀经验的等级差。任务经验不经过这里。

static func experience_multiplier(player_level: int, monster_level: int) -> float:
	return clampf(1.0 - float(player_level - monster_level) * 0.04, 0.2, 1.5)

static func kill_xp(base_xp: int, player_level: int, monster_level: int) -> int:
	return roundi(maxi(0, base_xp) * experience_multiplier(player_level, monster_level))
