extends Node
## 地面砖族选择与道路索引契约：锁定 4 变体历史公式、9 变体加权表，以及道路索引与族变体数解耦。
## 目的：cave 扩到 9 变体不再挤占道路边缘槽位，同时 wild/ash/camp 的既有画面逐格保持不变。

var failures: Array[String] = []

## 统一断言入口；失败时记录并 push_error。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[GroundTileThemeTest] " + message)

## 改动前 ground.gd 的 4 变体原式，用于比对 4 变体分支未发生偏移。
func _legacy_pick(col: int, row: int) -> int:
	var variation := posmod(col * 73 + row * 37 + col * row * 11, 19)
	return 1 if variation < 4 else 2 if variation == 5 else 0

## 逐项核对变体数量、4 变体公式、9 变体加权与道路索引映射。
func _ready() -> void:
	var ground := IsoGround.new()
	check(IsoGround.CAVE_TILES.size() == 9, "cave 应扩到 9 变体")
	check(IsoGround.WILD_TILES.size() == 4 and IsoGround.ASH_TILES.size() == 4 and IsoGround.CAMP_TILES.size() == 4,
		"wild/ash/camp 仍保持 4 变体")
	for tex in IsoGround.CAVE_TILES:
		var image := (tex as Texture2D).get_image()
		check(image.get_size() == Vector2i(64, 32), "cave 砖必须 64×32，实际 %s" % image.get_size())

	# 4 变体分支必须与历史公式逐格一致，保证 wild/ash/camp 画面不变。
	var legacy_diff := 0
	for col in range(64):
		for row in range(64):
			if ground._pick_theme_tile(Vector2i(col, row), 4) != _legacy_pick(col, row):
				legacy_diff += 1
	check(legacy_diff == 0, "4 变体砖选择与历史公式不一致的格数应为 0，实际 %d" % legacy_diff)

	# 9 变体分支：九档全部出现，且占比接近 35 号 §8 加权表（容差 ±5 个百分点）。
	var targets := [38, 24, 10, 7, 6, 5, 4, 3, 3]
	var counts := [0, 0, 0, 0, 0, 0, 0, 0, 0]
	var out_of_range := 0
	var total := 0
	for col in range(200):
		for row in range(200):
			var tile := ground._pick_theme_tile(Vector2i(col, row), 9)
			if tile < 0 or tile > 8:
				out_of_range += 1
				continue
			counts[tile] += 1
			total += 1
	check(out_of_range == 0, "9 变体砖下标应全部落在 0..8，越界 %d 次" % out_of_range)
	for i in range(9):
		check(counts[i] > 0, "第 %d 档变体必须出现" % i)
		var percent := float(counts[i]) * 100.0 / float(total)
		check(absf(percent - float(targets[i])) <= 5.0,
			"第 %d 档占比 %.1f%% 应接近目标 %d%%" % [i, percent, targets[i]])

	# 道路索引映射：4 变体沿用历史（边缘落在 4..11），9 变体边缘顺延到族砖之后的 9..16。
	check(ground._road_atlas_index(3, 4) == 3 and ground._road_atlas_index(4, 4) == 4
		and ground._road_atlas_index(11, 4) == 11, "4 变体道路索引保持历史取值")
	check(ground._road_atlas_index(3, 9) == 3 and ground._road_atlas_index(4, 9) == 9
		and ground._road_atlas_index(11, 9) == 16, "9 变体道路边缘顺延到族砖之后")
	check(ground._road_atlas_index(11, 9) < 9 + 8, "道路索引不得越过图集末位")

	print("[GroundTileThemeTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
