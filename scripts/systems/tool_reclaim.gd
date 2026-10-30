class_name ToolReclaim
extends RefCounted
## 工程 79：永久工具（`data/miscItems.json` 中 `useType == "panel"` 的道具）缺失补领。
##
## 判据（唯一，纯函数，运行态与测试共用）：
##   `unlocks` 中该 id 为 true（任务链说「发过」）**且** 背包与仓库都没有该 itemId ⇒ 判为缺失，补发一件。
##
## 🔴 为什么这个判据是安全的：这些工具在**正常游戏里丢不掉** ——
## 死亡惩罚只掉 `kind == "equip"`（`death_penalty.gd`）、商店拒收 `questItem: true`（`shop.gd`）、
## **拖到地面丢弃被 `GameState.can_drop_item()` 挡下（工程 89，且工具判定排在最前、
## 早于 `questItem` 那条）**、`panel` 类双击只开面板不消耗（`GameState._use_misc`）。
## ⇒ 「解锁键说发过、物品却不在」只可能是**发放链路断了**（造档工具只置状态不发物品、旧档导入异常），
## 补的正是该有的那件，不存在反复刷取的面。
##
## 🔴 反向约束：若将来这些工具变成可消耗 / 可交易 / **可丢弃**，本判据会立刻变成无限刷。
## 届时**必须先收紧判据**（例如改为一次性标记字段），不能只靠「先加个冷却」糊过去。
## 工程 89 就是踩着这条线做的：丢弃功能上线时，工具的「不可丢」必须写在 `can_drop_item` 里，
## 不能靠 UI 不给入口。
##
## 触发点：读档自愈（`SaveManager.apply_to_game_state` 末尾），玩家零操作。

const PANEL_USE_TYPE := "panel"
const RECLAIM_COUNT := 1

## 全库 `useType == "panel"` 的道具 id。
## 当前四条：随身车夫 / 随身商队 / 追猎令牌（工程 79）+ 随身铁匠（工程 108）。
## 🔑 这里是**数据驱动**的：新增 panel 类道具不需要改本文件，白名单不在这里 ——
## 也不要手工加一份「名单」到别处，那样从此有两处真相（工程 108 R5）。
## 需要跟着改的只有测试里的业务期望清单（`tool_reclaim_test.gd` 的 `EXPECTED_TOOLS`）。
static func panel_tool_ids() -> Array[String]:
	var out: Array[String] = []
	var rows: Variant = DataLoader.get_table("miscItems")
	if not rows is Array:
		return out
	for row in (rows as Array):
		if not row is Dictionary:
			continue
		var entry := row as Dictionary
		if String(entry.get("useType", "")) != PANEL_USE_TYPE:
			continue
		var item_id := String(entry.get("id", ""))
		if not item_id.is_empty() and not out.has(item_id):
			out.append(item_id)
	return out

## 容器里是否已持有该 itemId（null 空位跳过；count 与堆叠无关，只看有无）。
static func holds(container: Array, item_id: String) -> bool:
	for entry in container:
		if entry is Dictionary and String((entry as Dictionary).get("itemId", "")) == item_id:
			return true
	return false

## 缺失清单（纯函数）。`unlocks` 未置 true 的一律不算缺失 —— 那是「还没领」，不是「发了又没了」。
static func missing_tools(unlocks: Dictionary, inventory: Array, warehouse: Array) -> Array[String]:
	var out: Array[String] = []
	var retired: Array = []
	for quest in DataLoader.get_table("quests"):
		if quest is Dictionary:
			for granted in quest.get("reward", {}).get("unlocks", []):
				if bool(unlocks.get(String(granted), false)):
					retired.append_array(quest.get("exchangeTools", []))
	for item_id in panel_tool_ids():
		if retired.has(item_id):
			continue
		if not bool(unlocks.get(item_id, false)):
			continue
		if holds(inventory, item_id) or holds(warehouse, item_id):
			continue
		out.append(item_id)
	return out

## 补发：背包优先（工具要双击用），背包满走仓库，两者都满计 failed（不静默丢弃）。
## 就地修改传入的两个容器（与 `Inventory.add` 语义一致）。
## 返回 {given: Array[String], to_warehouse: Array[String], failed: Array[String]}。
static func reclaim(unlocks: Dictionary, inventory: Array, warehouse: Array) -> Dictionary:
	var given: Array[String] = []
	var to_warehouse: Array[String] = []
	var failed: Array[String] = []
	for item_id in missing_tools(unlocks, inventory, warehouse):
		var item := ItemFactory.make_any(item_id, RECLAIM_COUNT)
		if item.is_empty():
			failed.append(item_id)
			continue
		if Inventory.add(inventory, item):
			given.append(item_id)
		elif Inventory.add(warehouse, item):
			given.append(item_id)
			to_warehouse.append(item_id)
		else:
			failed.append(item_id)
	return {"given": given, "to_warehouse": to_warehouse, "failed": failed}

## 运行态门面：就地补发 `GameState` 的背包 / 仓库，并广播变更（让自动存档把结果带走）。
## 只在真补发了东西时广播，避免每次读档都白刷一次 UI。
static func reclaim_into_game() -> Dictionary:
	var result := reclaim(GameState.unlocks, GameState.inventory, GameState.warehouse)
	var given := result.get("given", []) as Array
	if not given.is_empty():
		EventBus.inventory_changed.emit()
	var to_warehouse := result.get("to_warehouse", []) as Array
	if not to_warehouse.is_empty():
		EventBus.warehouse_changed.emit()
	return result
