class_name LootRetryState
extends RefCounted
## 自动拾取失败的共享失效版本；只订阅一次，不为每件地面物创建信号或定时器。
static var _revision := 0
static var _connected := false
static var _capacity_frame := -1
static var _inventory: Array = []
static var _empty_slot := -2
static var _gold_capped := false

## 首次使用时连接影响入包/出售的事件，常态只返回整数。
static func revision() -> int:
	if not _connected:
		_connected = true
		_gold_capped = GameState.gold_is_capped()
		EventBus.inventory_changed.connect(_invalidate)
		EventBus.equipment_changed.connect(_invalidate)
		EventBus.settings_changed.connect(_invalidate)
		EventBus.data_loaded.connect(_invalidate)
		EventBus.gold_changed.connect(_on_gold)
		EventBus.player_leveled.connect(_on_level)
	# 兼容读档整体替换及旧调用直接腾格：每物理帧共享一次空位检查，而非每件物品扫描。
	if not is_same(_inventory,GameState.inventory):
		_inventory = GameState.inventory
		_capacity_frame = -1
		_invalidate()
	var frame := Engine.get_physics_frames()
	if frame != _capacity_frame:
		_capacity_frame = frame
		var empty := _inventory.find(null)
		if empty != _empty_slot:
			_empty_slot = empty
			_invalidate()
	return _revision

## 容器、装备、策略或读档变化后允许失败物品重新尝试。
static func _invalidate() -> void:
	_revision += 1

## 只在金币封顶状态切换时失效；普通金币入账不应让满包积压全体重试。
static func _on_gold(_amount: int) -> void:
	var capped := GameState.gold_is_capped()
	if capped != _gold_capped:
		_gold_capped = capped
		_invalidate()

## 升级可能改变装备升级候选保护，重新计算出售决策。
static func _on_level(_level: int) -> void:
	_invalidate()
