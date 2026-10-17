extends Node
## 坐骑快捷键与骑乘状态回归；只操作内存状态，不写入玩家存档。

var failures: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	SettingsRuntime.apply_all()
	check(SettingsRuntime.default_key("mount_toggle") == KEY_R and SettingsRuntime.ACTIONS.has("mount_toggle"),
		"R 已注册为可改键的骑乘动作")
	check(_mapped_key("mount_toggle") == KEY_R, "运行时 InputMap 包含默认 R 键")
	check(not GameState.toggle_mount() and GameState.active_mount.is_empty(), "未收藏坐骑时不改变骑乘状态")
	check(GameState.collect_mount("mount_corrupted_wing"), "可收藏第一章坐骑")
	var mount_icon := SampleArt.ground_for({"kind": "mount", "itemId": "mount_corrupted_wing"})
	check(mount_icon != null and mount_icon.get_size() == Vector2(48, 48)
		and mount_icon.resource_path == String(DataLoader.get_entry("mounts", "mount_corrupted_wing").get("icon", "")),
		"腐化之翼的地面掉落与收藏界面使用同一张正式图标")
	check(SampleArt.ground_for({"kind": "mount", "itemId": "mount_furnace_beast"}) == null,
		"尚无设计稿的第二章坐骑保留地面回退图形")
	var mount_panel := preload("res://scripts/ui/mount_panel.gd").new()
	add_child(mount_panel)
	mount_panel._selected_mount = "mount_corrupted_wing"
	mount_panel.visible = true
	mount_panel._refresh()
	check(mount_panel._image.texture == mount_icon
		and mount_panel._image.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"坐骑收藏预览加载正式图标并保持像素边缘")
	mount_panel.queue_free()
	GameState.player.level = 19
	check(not GameState.toggle_mount() and GameState.active_mount.is_empty(), "等级不足时快捷键不可越级骑乘")
	GameState.player.level = 20
	check(GameState.toggle_mount() and GameState.active_mount == "mount_corrupted_wing"
		and is_equal_approx(GameState.mount_speed_multiplier(), 1.3), "R 可直接骑乘并获得移速加成")
	check(GameState.toggle_mount() and GameState.active_mount.is_empty()
		and is_equal_approx(GameState.mount_speed_multiplier(), 1.0), "再次按 R 可下马并恢复速度")
	check(GameState.toggle_mount() and GameState.active_mount == "mount_corrupted_wing", "下马后可重新骑乘")
	check(GameState.collect_mount("mount_furnace_beast"), "可收藏第二章坐骑")
	GameState.ride_mount("mount_furnace_beast")
	GameState.dismount()
	check(GameState.toggle_mount() and GameState.active_mount == "mount_furnace_beast", "优先重新骑最近使用的坐骑")
	var saved := SaveManager._collect()
	check(SaveManager._is_valid_save(saved), "快捷骑乘沿用现有坐骑存档字段")
	var panel_key := SettingsRuntime.key_for("panel_mount")
	check(SettingsRuntime.set_binding("mount_toggle", panel_key), "骑乘键可在设置中重映射")
	check(_mapped_key("mount_toggle") == panel_key and _mapped_key("panel_mount") == KEY_R,
		"与面板快捷键冲突时按现有规则交换键位")
	GameState.reset_to_defaults()
	SettingsRuntime.apply_all()
	GameState.collect_mount("mount_corrupted_wing")
	GameState.player.level = 20
	var game := preload("res://scenes/Game.tscn").instantiate()
	add_child(game)
	var player := game.get_node("Entities/Player") as PlayerCharacter
	var art := player.sample_art
	var wing: Dictionary = CharacterLook.definition("look_01").mounts.mount_corrupted_wing
	check(art.texture == CharacterLook.definition("look_01").animations.idle.texture,
		"上马前使用普通待机动作")
	var press := InputEventKey.new()
	press.physical_keycode = KEY_R
	press.pressed = true
	GameState.set_panel_open("inventory", true)
	game._unhandled_input(press)
	check(GameState.active_mount == "mount_corrupted_wing", "面板打开时 R 仍可直接骑乘")
	check(art.texture == wing.idle and art.vframes == 4 and art.offset == -wing.pivot,
		"骑乘后立即使用双翼待机图集与脚底锚点")
	player.velocity = Vector2(100, 0)
	art._process(0.11)
	check(art.texture == wing.walk and art.pose == "walk" and art.facing == 6,
		"骑乘移动使用八向双翼行走图集")
	player.velocity = Vector2.ZERO
	game._unhandled_input(press)
	check(GameState.active_mount.is_empty(), "游戏场景第二次接收 R 时直接下马")
	check(art.texture == CharacterLook.definition("look_01").animations.walk.texture or
		art.texture == CharacterLook.definition("look_01").animations.idle.texture,
		"下马立即回到普通角色图集")
	GameState.set_panel_open("inventory", false)
	game.queue_free()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[MountShortcutTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("[MountShortcutTest] " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _mapped_key(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return int((event as InputEventKey).physical_keycode)
	return 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
