class_name TradeService
extends RefCounted
## 货郎交易服务：集中购买、出售和退回规则；GameState 保留稳定门面与状态，UI 不结算金币。
## 同步校验后提交并广播，交易规则与存档归属互相独立。

## 购买先校验价格和完整背包容量，成功后扣钱并广播。
static func shop_buy(shop_id: String, item_id: String) -> Dictionary:
	var price := Shop.buy_price(shop_id, item_id)
	if price < 0:
		return GameState._trade_fail(Localization.tr_key("msg.game_state.p047"))
	var item := Shop.make_item(item_id)
	if item.is_empty():
		return GameState._trade_fail(Localization.tr_key("msg.game_state.p048") % item_id)
	if not Inventory.has_space_for(GameState.inventory, item):
		return GameState._trade_fail(Localization.tr_key("msg.game_state.p049"))
	if GameState.gold < price:
		return GameState._trade_fail(Localization.tr_key("msg.game_state.p037") % [price, GameState.gold])
	GameState.add_gold(-price)
	# E-P3-1：预检与提交同为同步逻辑，单线程下不会失败；一旦将来插入 await（异步入包动画）
	# 便可能「扣钱不给货」，此处显式校验并退还金币，不静默。
	if not GameState.add_item(item):
		GameState.add_gold(price)
		return GameState._trade_fail(Localization.tr_key("msg.game_state.p049"))
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p050") % [ItemUtil.display_name(item), price], "pickup")
	EventBus.trade_done.emit("buy", item_id, price)
	return {"ok": true, "reason": "", "item": item, "price": price}


## 单格出售按实际金币入账结算，不因钱包封顶退回物品。
static func shop_sell(inv_index: int, silent: bool = false) -> Dictionary:
	if inv_index < 0 or inv_index >= GameState.inventory.size() or GameState.inventory[inv_index] == null:
		return GameState._trade_fail(Localization.tr_key("msg.game_state.p026"))
	var item: Dictionary = GameState.inventory[inv_index]
	if not Shop.can_sell(item):
		return GameState._trade_fail(Localization.tr_key("msg.game_state.p051"))
	var price := Shop.sell_price(item)
	var label := ItemUtil.display_name(item)
	GameState.remove_item_at(inv_index)
	var gained := GameState._gold_gain(price)
	if not silent:
		EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p052") % [label, gained], "pickup")
		GameState._notify_gold_gap(price, gained)
	EventBus.trade_done.emit("sell", String(item.get("itemId", "")), gained)
	return {"ok": true, "reason": "", "item": item, "price": gained, "capped": gained < price}


## 低层批量售金门面；物品所有权由调用者管理，正式托盘使用 commit_tray。
static func shop_sell_staged(items: Array) -> Dictionary:
	var total := 0
	var n := 0
	for it in items:
		if not it is Dictionary or not Shop.can_sell(it):
			return {"ok": false, "count": 0, "gold": 0, "reason": Localization.tr_key("ui.review.game_state.017")}
		total += Shop.sell_price(it)
		n += 1
	if n == 0:
		return {"ok": false, "count": 0, "gold": 0, "reason": Localization.tr_key("ui.review.game_state.018")}
	# 工程 56 / 口径 A：不再因金币上限整批拒绝。托盘内容由界面持有，本函数只算价与入账。
	var gained := GameState._gold_gain(total)
	EventBus.trade_done.emit("sell", "", gained)
	return {"ok": true, "count": n, "gold": gained, "reason": "", "capped": gained < total}


## 将尚未售出的物品完整退回背包，放不下的保留原数组。
static func shop_unstage(items: Array) -> int:
	var back := 0
	var i := items.size() - 1
	while i >= 0:
		var it = items[i]
		if it is Dictionary and GameState.add_item(it):
			items.remove_at(i)
			back += 1
		i -= 1
	return back


## 原子认领全局托盘后结算；先清理所有权，再广播金币事件，防止同步回调重复售出。
static func commit_tray() -> Dictionary:
	var items := GameState.trade_tray.values()
	if items.is_empty():
		return {"ok": false, "count": 0, "gold": 0}
	for item in items:
		if not item is Dictionary or not Shop.can_sell(item):
			return {"ok": false, "count": 0, "gold": 0}
	GameState.trade_tray.clear()
	GameState.set_trade_staged_count(0)
	return shop_sell_staged(items)
