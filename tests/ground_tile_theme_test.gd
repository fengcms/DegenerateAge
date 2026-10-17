extends Node
## 地面砖族选择与道路索引契约：锁定 4 变体历史公式、8/9 变体加权表，以及道路中心与族变体数解耦。
## 目的：wild 扩到 9、ash 扩到 8 变体不再挤占道路槽位，同时 camp 的既有画面逐格保持不变。

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

## 核对某变体数下各档占比是否接近目标表（容差 ±5 个百分点），并保证下标不越界。
func _check_weights(ground: IsoGround, variant: int, targets: Array) -> void:
	var counts := []
	counts.resize(variant)
	counts.fill(0)
	var out_of_range := 0
	var total := 0
	for col in range(200):
		for row in range(200):
			var tile := ground._pick_theme_tile(Vector2i(col, row), variant)
			if tile < 0 or tile >= variant:
				out_of_range += 1
				continue
			counts[tile] += 1
			total += 1
	check(out_of_range == 0, "%d 变体砖下标应全部落在 0..%d，越界 %d 次" % [variant, variant - 1, out_of_range])
	for i in range(variant):
		check(counts[i] > 0, "%d 变体第 %d 档必须出现" % [variant, i])
		var percent := float(counts[i]) * 100.0 / float(total)
		check(absf(percent - float(targets[i])) <= 5.0,
			"%d 变体第 %d 档占比 %.1f%% 应接近目标 %d%%" % [variant, i, percent, targets[i]])

## 逐项核对变体数量、砖尺寸、道路砖独立性、4 变体公式、8/9 变体加权与道路索引映射。
func _ready() -> void:
	var ground := IsoGround.new()
	check(IsoGround.CAVE_TILES.size() == 9, "cave 应扩到 9 变体")
	check(IsoGround.WILD_TILES.size() == 9, "wild 应扩到 9 变体")
	check(IsoGround.ASH_TILES.size() == 8, "ash 应扩到 8 变体")
	check(IsoGround.CAMP_TILES.size() == 4, "camp 仍保持 4 变体")
	for theme in [IsoGround.WILD_TILES, IsoGround.ASH_TILES, IsoGround.CAVE_TILES]:
		for tex in theme:
			var image := (tex as Texture2D).get_image()
			check(image.get_size() == Vector2i(64, 32), "族砖必须 64×32，实际 %s" % image.get_size())

	# 道路中心砖必须是独立资源，且不得混入族砖数组（否则扩变体就会顶掉道路）。
	check(IsoGround.CAMP_ROAD != null and IsoGround.WILD_ROAD != null
		and IsoGround.ASH_ROAD != null and IsoGround.CAVE_ROAD != null, "四图道路中心砖必须各自存在")
	check(not IsoGround.WILD_TILES.has(IsoGround.WILD_ROAD), "wild 道路中心砖不得混入族砖数组")
	check(not IsoGround.ASH_TILES.has(IsoGround.ASH_ROAD), "ash 道路中心砖不得混入族砖数组")

	# 4 变体分支必须与历史公式逐格一致，保证 camp 画面不变。
	var legacy_diff := 0
	for col in range(64):
		for row in range(64):
			if ground._pick_theme_tile(Vector2i(col, row), 4) != _legacy_pick(col, row):
				legacy_diff += 1
	check(legacy_diff == 0, "4 变体砖选择与历史公式不一致的格数应为 0，实际 %d" % legacy_diff)

	# 9 变体与 8 变体两套加权：9 档取 35 号 §8 表；8 档把末档 3% 并入第 7 档得 6%。
	_check_weights(ground, 9, [38, 24, 10, 7, 6, 5, 4, 3, 3])
	_check_weights(ground, 8, [38, 24, 10, 7, 6, 5, 4, 6])

	# 道路索引映射：中心固定在族砖之后第 1 槽，八张边缘紧随其后，与族变体数完全解耦。
	check(ground._road_atlas_index(3, 4) == 4 and ground._road_atlas_index(4, 4) == 5
		and ground._road_atlas_index(11, 4) == 12, "4 变体道路索引应落在 4..12")
	check(ground._road_atlas_index(3, 8) == 8 and ground._road_atlas_index(4, 8) == 9
		and ground._road_atlas_index(11, 8) == 16, "8 变体道路索引应落在 8..16")
	check(ground._road_atlas_index(3, 9) == 9 and ground._road_atlas_index(4, 9) == 10
		and ground._road_atlas_index(11, 9) == 17, "9 变体道路索引应落在 9..17")
	for size in [4, 8, 9]:
		check(ground._road_atlas_index(11, size) < size + 9, "%d 变体下道路索引不得越过图集末位" % size)

	print("[GroundTileThemeTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
