class_name BossSkillCanvas
extends Node2D
## 地面层不随Boss实体深度压住玩家。无_process/物理或碰撞，仅按宿主事件重绘。
## 固定在地形之上、所有实体之下，避免预警遮住玩家。
func _ready() -> void:
	z_as_relative = false
	z_index = -3501
## 委托宿主绘制锁定几何，不持有战斗状态。
func _draw() -> void:
	var host := get_parent()
	if host != null:
		host.draw_boss_skill_ground(self)

var _was_active := false
## 活动时刷新，结束后额外刷新一次以清除缓存命令。
func sync(active: bool) -> void:
	if active or _was_active:
		queue_redraw()
	_was_active = active
