extends IsoGround
## 隔离战斗场的导航门面：复用样板同源CaveLayout和正式IsoGround路线接口，不另绘地面。

## 场景在入树前注入布局，避免正式地图加载覆盖样板掩码。
func _ready() -> void:
	assert(cave != null)
	grid_size = cave.size
	add_to_group("map_ground")
	cave.prepare_connectivity()

## 地面由模块化样板合批绘制，此门面只服务正式玩家和怪物的导航。
func _draw() -> void:
	pass
