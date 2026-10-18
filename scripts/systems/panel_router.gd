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
	# 随身车夫：面板本身已能独立打开（`carter_panel_requested` 只设标题 + 刷新）。
	# M10-7 只把可达范围扩成「去任何走过的地图」，面板不需要重写。
	"carter": {"ready": true, "title": "ui.panel.portable_carter"},
	# 追猎令牌：面板随 M10-5 交付。
	"boss_token": {"ready": false, "title": "ui.panel.boss_token"},
	# 随身商队：面板随 M10-6 交付；现在打开会是空店铺，故不点亮。
	"shop": {"ready": false, "title": "ui.panel.portable_shop"},
}

## 该 panelId 是否已登记（启动期校验与运行时共用的唯一判据）。
static func has(panel_id: String) -> bool:
	return PANELS.has(panel_id)

## 该面板是否已到可打开的批次。
static func is_ready(panel_id: String) -> bool:
	var entry: Variant = PANELS.get(panel_id, null)
	return entry is Dictionary and bool((entry as Dictionary).get("ready", false))

## 打开面板。返回 {ok, reason}；失败文案由 `GameState._use_fail` 统一 toast（单一出口）。
## ⚠ 只打开面板，不触碰背包 —— 道具不消耗。
static func open(panel_id: String) -> Dictionary:
	if not PANELS.has(panel_id):
		return {"ok": false, "reason": Localization.tr_key("msg.panel_router.p001") % panel_id}
	if not is_ready(panel_id):
		return {"ok": false, "reason": Localization.tr_key("msg.panel_router.p002")}
	match panel_id:
		"carter":
			EventBus.carter_panel_requested.emit(title(panel_id))
			return {"ok": true, "reason": ""}
	# 已登记但尚无实现 = 配置超前（`ready` 被提前改成 true 却忘了写分支）。
	return {"ok": false, "reason": Localization.tr_key("msg.panel_router.p002")}

## 面板标题（本地化文本）。未登记的 id 返回空串，调用方据此回退到通用文案。
static func title(panel_id: String) -> String:
	var entry: Variant = PANELS.get(panel_id, null)
	if not entry is Dictionary:
		return ""
	return Localization.tr_key(String((entry as Dictionary).get("title", "")))
