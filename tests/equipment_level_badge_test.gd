extends Node
## 装备穿戴等级角标回归：核对实例等级、空格复用、装备槽继承、拖拽副本与缩放布局。
## 仅在隔离测试项目中创建 UI，不读取或写入玩家正式存档。

var _failures: Array[String] = []

## 使用真实动态装备检查可见数字，并确保非装备与错误等级清除旧角标。
func _ready() -> void:
	GameState.reset_to_defaults()
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var weapon_61 := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "rare", rng)
	var weapon_71 := ItemFactory.make_equip_dynamic("c6_equip_weapon", 71, "rare", rng)
	var helmet_64 := ItemFactory.make_equip_dynamic("c6_equip_helmet", 64, "rare", rng)
	_check(not weapon_61.is_empty() and not weapon_71.is_empty() and not helmet_64.is_empty(), "真实动态装备实例可生成")
	var bag := ItemSlot.new()
	bag.role = ItemSlot.ROLE_BAG
	bag.apply_grid_base(Vector2(52, 52))
	add_child(bag)
	bag.size = Vector2(52, 52)
	bag.item = weapon_61
	_check(bag._level_badge.visible and bag._level_badge_text == "61", "背包角标读取实例 61 级")
	bag.item = weapon_71
	_check(bag._level_badge_text == "71", "复用同一装备素材时显示新实例等级")
	bag.item = helmet_64
	_check(bag._level_badge_text == "64", "同档其他部位显示其穿戴等级 64")
	var worn := EquipmentSlot.new()
	worn.role = ItemSlot.ROLE_EQUIP
	worn.slot_id = "helmet"
	worn.custom_minimum_size = Vector2(52, 52)
	add_child(worn)
	worn.size = Vector2(52, 52)
	worn.item = helmet_64
	_check(worn._level_badge.visible and worn._level_badge_text == "64", "人物装备槽继承相同角标")
	var ghost := DragGhost.slot_copy(bag)
	add_child(ghost)
	ghost.size = Vector2(52, 52)
	_check(ghost._level_badge.visible and ghost._level_badge_text == "64", "拖拽副本保留等级角标")
	_check(bag._level_badge.mouse_filter == Control.MOUSE_FILTER_IGNORE, "角标不抢鼠标和拖放事件")
	var high := helmet_64.duplicate(true)
	high.requiredLevel = 9999
	bag.item = high
	for scales in [[1.0, 1.0], [1.5, 1.5], [2.0, 2.0], [1.0, 2.0]]:
		GameState.settings.uiScale = scales[0]
		GameState.settings.textScale = scales[1]
		EventBus.settings_changed.emit()
		var layout := bag._level_badge_layout()
		var rect: Rect2 = layout.get("rect", Rect2())
		_check(bag._level_badge_text == "9999" and rect.position.x >= 0.0 and rect.position.y >= 0.0
			and rect.end.x <= bag.size.x and rect.end.y <= bag.size.y,
			"四位数在界面/文字倍率 %s 内完整留在格子里" % str(scales))
	bag.item = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	_check(not bag._level_badge.visible and bag._level_badge_text.is_empty() and bag._count.text == "3",
		"药品保留数量角标且无等级数字")
	bag.item = {"kind": "equip", "requiredLevel": "无效"}
	_check(not bag._level_badge.visible, "非法等级不显示虚假的 1 级")
	bag.item = {}
	_check(not bag._level_badge.visible and bag._level_badge_text.is_empty(), "清空格子后不残留旧数字")

	# ---- 星级角标（工程 76）----
	_check(ItemUtil.star_badge_text(0) == "", "0 星不产生徽标文案")
	_check(ItemUtil.star_badge_text(3) == "★3" and ItemUtil.star_badge_text(11) == "★11",
		"非满星一律 ★N（不能用 ⭐，那是不可着色的彩色 emoji）")
	var sun := ItemUtil.star_badge_text(12)
	_check(sun.contains(String.chr(0x2600)) and sun.contains(String.chr(0xFE0F)),
		"满星必须是带 U+FE0F 的彩色 emoji 太阳，去掉 VS16 会渲染成灰白")
	_check(ItemUtil.star_badge_color(3) == ItemUtil.STAR_BADGE_COLOR["low"]
		and ItemUtil.star_badge_color(5) == ItemUtil.STAR_BADGE_COLOR["low"], "1—5 星亮蓝")
	_check(ItemUtil.star_badge_color(6) == ItemUtil.STAR_BADGE_COLOR["mid"]
		and ItemUtil.star_badge_color(8) == ItemUtil.STAR_BADGE_COLOR["mid"], "6—8 星亮绿（6 归绿不归蓝）")
	_check(ItemUtil.star_badge_color(9) == ItemUtil.STAR_BADGE_COLOR["high"]
		and ItemUtil.star_badge_color(11) == ItemUtil.STAR_BADGE_COLOR["high"], "9—11 星亮金")
	_check(ItemUtil.star_badge_color(3) != ItemUtil.star_badge_color(6)
		and ItemUtil.star_badge_color(6) != ItemUtil.star_badge_color(9),
		"星级三档颜色必须互不相同，否则分档形同虚设")
	_check(ItemUtil.star_badge_font_size(11) == 11 and ItemUtil.star_badge_font_size(12) == 13,
		"满星字号大 2px，emoji 太阳在小字号下会糊成一团")
	var mid6 := helmet_64.duplicate(true)
	mid6.star = 6
	bag.item = mid6
	_check(bag._star_marker.visible and bag._star_marker.text == "★6"
		and bag._star_marker.get_theme_color("font_color") == ItemUtil.STAR_BADGE_COLOR["mid"],
		"背包格 6 星显示亮绿 ★6")
	mid6.star = 0
	bag.item = mid6
	_check(not bag._star_marker.visible and bag._star_marker.text == "", "0 星完全不显示且不留旧文案")
	var max12 := helmet_64.duplicate(true)
	max12.star = 12
	bag.item = max12
	_check(bag._star_marker.text == sun and bag._star_marker.get_theme_font_size("font_size") == 13,
		"满星显示 13px 彩色太阳")
	worn.item = max12
	_check(worn._star_marker.visible and worn._star_marker.text == sun, "人物装备槽继承同一个星级徽标")
	var ghost2 := DragGhost.slot_copy(bag)
	add_child(ghost2)
	ghost2.size = Vector2(52, 52)
	_check(ghost2._star_marker.visible and ghost2._star_marker.text == sun, "拖拽副本保留星级徽标")
	_check(bag._star_marker.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"星级徽标不得抢鼠标与拖放事件")
	bag.item = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	_check(not bag._star_marker.visible and bag._star_marker.text.is_empty(), "药品格不显示星级")
	var fav6 := helmet_64.duplicate(true)
	fav6.star = 6
	fav6.favorite = true
	bag.item = fav6
	_check(bag._favorite_marker.text == "◆" and bag._star_marker.text == "★6",
		"收藏改用 ◆ 让出左上角，星级与收藏同格并存")
	_check(bag._favorite_marker.offset_left < 0.0,
		"收藏 ◆ 必须挂在右上（offset_left 为负）；搬回左上会与星级撞在一起")
	var font := bag.get_theme_font("font")
	var star_w := font.get_string_size("★11", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var dia_w := font.get_string_size("◆", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	_check(2.0 + star_w <= 26.0, "★11@11px 宽 %.1f 不得越过收藏 ◆ 的左边界 26" % star_w)
	_check(26.0 + dia_w <= 37.0, "收藏 ◆@10px 宽 %.1f 不得越过升级箭头 ↑ 的字符起点 37" % dia_w)
	var over := helmet_64.duplicate(true)
	over.star = 13
	bag.item = over
	_check(bag._star_marker.text == sun, "超上限的脏档按满星处理，不显示假数字也不崩")
	bag.item = {}
	_check(not bag._star_marker.visible and bag._favorite_marker.text.is_empty(),
		"清空后星级隐藏、收藏文本为空（收藏沿用「空文本即隐藏」的既有约定）")

	GameState.reset_to_defaults()
	if _failures.is_empty():
		print("[EquipmentLevelBadgeTest] 全部通过 ✅")
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

## 汇总失败项，确保单个错误不会掩盖后续的格子状态问题。
func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
