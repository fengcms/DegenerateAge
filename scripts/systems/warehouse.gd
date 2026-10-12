class_name Warehouse
extends RefCounted
## 仓库容量与价格来自 warehouse.json。道具移动由 GameState 保证原子性。

static func config() -> Dictionary:
	var loaded = DataLoader.get_table("warehouse")
	if loaded is Dictionary:
		return loaded
	# GameState 先于 DataLoader 初始化；开新游戏时直接读取同一份配置。
	var file := FileAccess.open("res://data/warehouse.json", FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			return parsed
	return {}

static func base_slots() -> int:
	return int(config().get("baseSlots", 40))

static func expand_slots() -> int:
	return int(config().get("expandSlots", 10))

static func cap() -> int:
	return int(config().get("cap", 200))

static func max_expansions() -> int:
	return int(ceili(float(cap() - base_slots()) / float(maxi(1, expand_slots()))))

static func capacity(expansions: int) -> int:
	return mini(cap(), base_slots() + maxi(0, expansions) * expand_slots())

static func next_cost(expansions: int) -> int:
	if capacity(expansions) >= cap():
		return -1
	var params := config()
	return int(round(float(params.get("expandBase", 0)) * pow(float(params.get("expandRate", 1.0)), expansions)))

static func create(expansions: int = 0) -> Array:
	return Inventory.create(capacity(expansions))

## 装备沿用实例 ID；可堆叠物品快照全部字段，防止整理或使用后旧拖拽误操作。
static func item_token(item: Dictionary) -> String:
	if String(item.get("kind", "")) == "equip":
		return String(item.get("instanceId", ""))
	return "stack:" + JSON.stringify(item)

static func token_matches(item: Dictionary, token: String) -> bool:
	return not token.is_empty() and item_token(item) == token

static func validate_config() -> Array[String]:
	var issues: Array[String] = []
	var data := config()
	if base_slots() <= 0 or expand_slots() <= 0 or cap() < base_slots():
		issues.append("[warehouse] baseSlots / expandSlots / cap 需为有效正数且 cap ≥ baseSlots")
	if float(data.get("expandBase", 0)) <= 0 or float(data.get("expandRate", 0)) < 1.0:
		issues.append("[warehouse] expandBase 应大于 0，expandRate 应不小于 1")
	return issues
