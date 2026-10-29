class_name PanelRouter
extends RefCounted
## M10-4（P-6）：`useType: "panel"` 杂项道具的唯一执行入口。
##
## 背景：`useType` 此前**只有校验与说明文案、没有执行分发**（工程 45 §2 F-2），
## 双击面板类道具会弹「该物品无法使用」。本表把「道具 → 面板」这条链接上。
##
## 三条约定（改这里之前先看完）：
## 1. `panelId` 必须先登记在 `PANELS`。`DataLoader._validate_misc_items` 查的是**同一张表**
##    ⇒ 脏 id 在启动期就报错，不会活到运行时；`open()` 里再查一次只是兜底。
## 2. `ready` 由各面板批次点亮。未点亮时 **明确失败**（返回原因交由调用方 toast），
##    绝不静默、绝不打开空壳面板（空商店比不开更糟）。
## 3. `useType: "panel"` 的道具**不消耗**（三件套是永久工具）。消耗逻辑不得写进本文件。

## panelId → {ready, title}。`title` 是本地化 key，说明文案与面板标题共用一份。
const PANELS := {
	# 随身车夫：M10-7 起面板走「随身模式」（七分组 + `travel_anywhere`）。
	# 打开方式是广播 `carter_panel_requested(title, true)`，当地车夫仍传 `false`。
	"carter": {"ready": true, "title": "ui.panel.portable_carter"},
	# 追猎令牌：面板随 M10-5 交付（`boss_token_panel.gd`）。
	"boss_token": {"ready": true, "title": "ui.panel.boss_token"},
	# 随身商队：面板随 M10-6 交付（复用 `ShopPanel` + `Shop.PORTABLE_SHOP_ID` 聚合货单）。
	"shop": {"ready": true, "title": "ui.panel.portable_shop"},
	# 随身铁匠（工程 108）：复用 `BlacksmithPanel`，只多一个 `portable` 模式 ——
	# 跳过问候卡直接进服务菜单，修理 1.5× / 成长服务 ×1.2。与当地铁匠同一个面板节点。
	"blacksmith": {"ready": true, "title": "ui.panel.portable_blacksmith"},
}

## 该 panelId 是否已登记（启动期校验与运行时共用的唯一判据）。
static func has(panel_id: String) -> bool:
	return PANELS.has(panel_id)

## 「这条登记项是否已到可打开的批次」的**唯一判定**（M10-6 抽成纯函数）。
## 抽出来的理由不是洁癖：三个面板全部点亮后，测试里已没有真实数据能触发「未点亮」分支，
## 只能靠合成 `{ready: false}` 覆盖。判定逻辑集中在这里，测试与运行时走的是同一段代码。
static func is_openable(entry: Variant) -> bool:
	return entry is Dictionary and bool((entry as Dictionary).get("ready", false))

## 该面板是否已到可打开的批次。
static func is_ready(panel_id: String) -> bool:
	return is_openable(PANELS.get(panel_id, null))

## 打开面板。返回 {ok, reason}；失败文案由 `GameState._use_fail` 统一 toast（单一出口）。
## ⚠ 只打开面板，不触碰背包 —— 道具不消耗。
static func open(panel_id: String) -> Dictionary:
	if not PANELS.has(panel_id):
		return {"ok": false, "reason": Localization.tr_key("msg.panel_router.p001") % panel_id}
	if not is_ready(panel_id):
		return {"ok": false, "reason": Localization.tr_key("msg.panel_router.p002")}
	match panel_id:
		"carter":
			# M10-7：第二参 `true` = 随身车夫（七分组全表 + travel_anywhere）。
			# 只传标题会让面板走当地模式，列出同集群几张图 —— 「点亮 ≠ 能用」（工程 48 C-1）。
			EventBus.carter_panel_requested.emit(title(panel_id), true)
			return {"ok": true, "reason": ""}
		"boss_token":
			EventBus.boss_token_panel_requested.emit(title(panel_id))
			return {"ok": true, "reason": ""}
		"shop":
			# 复用既有货郎面板：只是把店铺 id 换成合成 id，货单与价格由 `Shop` 聚合推导。
			# 交易会话（拉起背包并列、托盘退回）等语义全部沿用，面板侧零改造。
			EventBus.shop_open_requested.emit(Shop.PORTABLE_SHOP_ID)
			return {"ok": true, "reason": ""}
		"blacksmith":
			# 工程 108：第三参 `true` = 随身模式。`npc_name` / `greeting` 传空 ——
			# 面板在随身模式下自己取 `title()` 当标题、且不显示问候卡，
			# 传一个假 NPC 名会让标题变成「铁匠」而不是「随身铁匠」。
			EventBus.blacksmith_panel_requested.emit("", "", true)
			return {"ok": true, "reason": ""}
	# 已登记但尚无实现 = 配置超前（`ready` 被提前改成 true 却忘了写分支）。
	return {"ok": false, "reason": Localization.tr_key("msg.panel_router.p002")}

## 面板标题（本地化文本）。未登记的 id 返回空串，调用方据此回退到通用文案。
static func title(panel_id: String) -> String:
	var entry: Variant = PANELS.get(panel_id, null)
	if not entry is Dictionary:
		return ""
	return Localization.tr_key(String((entry as Dictionary).get("title", "")))
