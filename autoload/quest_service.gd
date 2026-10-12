extends Node
## QuestService — 任务推进接线（单例 / Autoload，M2；工程文档 11 §4.2）。
##
## 职责**单一**：把「战斗 / 拾取」事件桥接到 `scripts/systems/quest.gd`。
## 任务规则（状态机 / 计数 / 地图范围 / 奖励）全部在 `Quest` 静态层，本节点不含业务逻辑——
## 与 `EventBus` 同构的"薄接线"，便于单测与解耦。
##
## 复用现成信号，**不新增采集点**：
##   - `EventBus.monster_died`（monster.gd 死亡时已发）→ 击杀类任务
##   - `EventBus.item_picked`（ground_item.gd 认领当帧已发）→ 收集类任务

func _ready() -> void:
	EventBus.monster_died.connect(_on_monster_died)
	EventBus.item_picked.connect(_on_item_picked)

## 3.1 死亡结算 → 击杀类任务计数。
func _on_monster_died(monster_id: String) -> void:
	Quest.on_event("monster_died", monster_id)

## 掉落认领 → 收集类任务计数（方案 C 后为「掉落生成当帧入包」即发，见 9.9）。
func _on_item_picked(item_id: String) -> void:
	Quest.on_event("item_picked", item_id)
