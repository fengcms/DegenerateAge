extends SceneTree
## 确定性构建 cave 地砖：从已通过审阅的基础 4 块派生 5 个窄带变体，并对 9 块统一做横向明暗拉平。
## 依据 docs/素材设计/41-地砖族扩充cave脚本派生小样与验收.md（路线 39 号 §7「A + B」，决策点①②均获批）。
##
## 输入 res://art_source/environment/ground_tiles_v1/cave_base/tile_0..3.png 是基础砖的冻结快照，
## 字节等于接入前的 assets/tiles/cave/tile_0..3.png（即 _pack_tiles(cave_tiles_v2.png) 的产物）。
## 冻结快照只作派生输入，保证本脚本与 build_environment_art.gd 相互独立、且重复执行逐位可复现。
## 输出 res://assets/tiles/cave/tile_0..8.png（0..3 为拉平后的基础块，4..8 为派生并拉平的新块）。

const TILE_W := 64
const TILE_H := 32
const BASE := 4
const TOTAL := 9
const BASE_FMT := "res://art_source/environment/ground_tiles_v1/cave_base/tile_%d.png"
const OUT_FMT := "res://assets/tiles/cave/tile_%d.png"

## 三条窄轴：粗斑（混合场锐度 p / 场尺度 scale）、湿度（色调偏移 dr/dg/db + 对比 gain）、细点（speckles）。
## 全部落在 41 号划定的窄带内（色调 ≤ ±4/255、对比 ≤ ±4%），不引入任何新材质语义。
const AXES := [
	{"p": 8.0, "scale": 24.0, "dr": 2.0, "dg": 2.0, "db": 1.0, "gain": 1.00, "speckles": 18},
	{"p": 10.0, "scale": 16.0, "dr": 0.0, "dg": 0.0, "db": 0.0, "gain": 1.04, "speckles": 34},
	{"p": 6.0, "scale": 32.0, "dr": -4.0, "dg": -3.0, "db": -1.0, "gain": 0.97, "speckles": 10},
	{"p": 9.0, "scale": 20.0, "dr": -2.0, "dg": -1.0, "db": 1.0, "gain": 1.01, "speckles": 46},
	{"p": 7.0, "scale": 28.0, "dr": 3.0, "dg": 3.0, "db": 2.0, "gain": 1.03, "speckles": 26},
]

var _src: Array = []
var _bank := PackedColorArray()
var _family_mean := Color(0, 0, 0)

func _initialize() -> void:
	_load_base()
	_verify_mask_identity()
	_collect_bank()
	var derived: Array = []
	for v in range(BASE, TOTAL):
		derived.append(_synth(AXES[v - BASE], 20261017 + (v - BASE) * 7919))
	var tiles: Array = []
	for i in range(BASE):
		tiles.append(_flat_to_image(_src[i]))
	for image: Image in derived:
		tiles.append(image)
	var flattened: Array = []
	for image: Image in tiles:
		flattened.append(_flatten_ramp(image, 1.0))
	for i in range(TOTAL):
		_save(flattened[i], OUT_FMT % i)
	_report(flattened)
	print("[输出] %s/tile_0..8.png（拉平后 9 块）" % OUT_FMT.get_base_dir())
	quit()

## 载入基础 4 块，并确认它们的 alpha 掩码就是管线几何掩码（派生与拉平都建立在同一掩码上）。
func _load_base() -> void:
	for i in range(BASE):
		var image := Image.load_from_file(BASE_FMT % i)
		assert(image != null, "缺失 cave 基础砖：%s" % (BASE_FMT % i))
		image.convert(Image.FORMAT_RGBA8)
		assert(image.get_size() == Vector2i(TILE_W, TILE_H), "cave 基础砖尺寸必须是 64×32")
		var flat: Array = []
		for y in range(TILE_H):
			for x in range(TILE_W):
				flat.append(image.get_pixel(x, y))
		_src.append(flat)

func _verify_mask_identity() -> void:
	var mismatch := 0
	for i in range(BASE):
		for y in range(TILE_H):
			for x in range(TILE_W):
				var opaque: bool = (_src[i][y * TILE_W + x] as Color).a >= 0.5
				if opaque != _inside(x, y):
					mismatch += 1
	print("[掩码] 基础 4 块 alpha 与几何掩码不一致像素数 = %d（应为 0）" % mismatch)
	print("[掩码] 掩码包围盒 = %s" % _mask_bounds())

## 族调色板与基色全部取自基础 4 块的内部区（edge ≥ 0.30）。
func _collect_bank() -> void:
	var sum := Vector3.ZERO
	var count := 0
	for i in range(BASE):
		for y in range(TILE_H):
			for x in range(TILE_W):
				if _edge(x, y) < 0.30:
					continue
				var c: Color = _src[i][y * TILE_W + x]
				_bank.append(c)
				sum += Vector3(c.r, c.g, c.b)
				count += 1
	var mean := sum / float(count)
	_family_mean = Color(mean.x, mean.y, mean.z)
	print("[族] 内部样本 %d 色，基色 = (%.1f,%.1f,%.1f)" % [count, mean.x * 255.0, mean.y * 255.0, mean.z * 255.0])

## 派生：低频混合场（每源一个正弦场）→ 逐像素加权取源色 → 围绕基色窄带微调 → 细点叠加。
func _synth(axes: Dictionary, seed_value: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ks: Array = []
	var phases: Array = []
	for k in range(BASE):
		ks.append([
			float(rng.randi_range(1, 3)), float(rng.randi_range(1, 3)),
			float(rng.randi_range(2, 4)), float(rng.randi_range(2, 4)),
		])
		phases.append([rng.randf() * TAU, rng.randf() * TAU])
	# 场极值归一化用。
	var raw: Array = []
	var lo: Array = [INF, INF, INF, INF]
	var hi: Array = [-INF, -INF, -INF, -INF]
	for y in range(TILE_H):
		var row_fields: Array = []
		for x in range(TILE_W):
			var vals: Array = []
			for k in range(BASE):
				var value := _field(x, y, ks[k], phases[k], float(axes["scale"]))
				vals.append(value)
				lo[k] = minf(lo[k], value)
				hi[k] = maxf(hi[k], value)
			row_fields.append(vals)
		raw.append(row_fields)
	var image := Image.create(TILE_W, TILE_H, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var p := float(axes["p"])
	var gain := float(axes["gain"])
	var shift := Vector3(float(axes["dr"]), float(axes["dg"]), float(axes["db"])) / 255.0
	for y in range(TILE_H):
		for x in range(TILE_W):
			if not _inside(x, y):
				continue
			var weights: Array = []
			var total := 0.0
			for k in range(BASE):
				var value: float = raw[y][x][k]
				var norm: float = 0.0 if is_equal_approx(hi[k], lo[k]) else (value - lo[k]) / (hi[k] - lo[k])
				var w := pow(clampf(norm, 0.0, 1.0), p)
				weights.append(w)
				total += w
			var color := Vector3.ZERO
			for k in range(BASE):
				var source: Color = _src[k][y * TILE_W + x]
				var w: float = weights[k] / total
				color += Vector3(source.r, source.g, source.b) * w
			var base := Vector3(_family_mean.r, _family_mean.g, _family_mean.b)
			color = base + (color - base) * gain + shift
			image.set_pixel(x, y, Color(clampf(color.x, 0.0, 1.0), clampf(color.y, 0.0, 1.0), clampf(color.z, 0.0, 1.0), 1.0))
	_speckle(image, int(axes["speckles"]), rng)
	return image

func _field(x: int, y: int, k: Array, phase: Array, scale: float) -> float:
	var u := float(x) / float(TILE_W)
	var v := float(y) / float(TILE_H)
	var rate := float(TILE_W) / scale
	return sin(TAU * (k[0] * u + k[1] * v) * rate + phase[0]) \
		+ 0.6 * sin(TAU * (k[2] * u + k[3] * v) * rate + phase[1])

## 细点轴：从族调色板偏极值端取色，落点限制在内部区（edge ≥ 0.30），1–2px。
func _speckle(image: Image, count: int, rng: RandomNumberGenerator) -> void:
	var lum := _family_mean.r * 0.299 + _family_mean.g * 0.587 + _family_mean.b * 0.114
	for _i in range(count):
		var x := 0
		var y := 0
		for _t in range(64):
			x = rng.randi_range(4, TILE_W - 5)
			y = rng.randi_range(2, TILE_H - 3)
			if _edge(x, y) >= 0.30:
				break
		var pick: Color = _bank[rng.randi_range(0, _bank.size() - 1)]
		for _j in range(3):
			var other: Color = _bank[rng.randi_range(0, _bank.size() - 1)]
			var dl := absf(pick.r * 0.299 + pick.g * 0.587 + pick.b * 0.114 - lum)
			var do_ := absf(other.r * 0.299 + other.g * 0.587 + other.b * 0.114 - lum)
			if do_ > dl:
				pick = other
		image.set_pixel(x, y, pick)
		if rng.randf() < 0.45 and _inside(x + 1, y):
			image.set_pixel(x + 1, y, pick)
		if rng.randf() < 0.30 and _inside(x, y + 1):
			image.set_pixel(x, y + 1, pick)

## 横向明暗拉平：按每块掩码内逐列灰度均值反向补偿，用加法保证整体均值不变、色相不被比值扭曲。
func _flatten_ramp(image: Image, strength: float) -> Image:
	var profile: Array = []
	var valid: Array = []
	for x in range(TILE_W):
		var sum := 0.0
		var count := 0
		for y in range(TILE_H):
			if not _inside(x, y):
				continue
			sum += _luma(image.get_pixel(x, y))
			count += 1
		# 菱形左右尖端的列样本过少，其均值不可信，改用最近可信列外推。
		valid.append(count >= 8)
		profile.append(0.0 if count == 0 else sum / float(count))
	var total := 0.0
	var valid_count := 0
	for x in range(TILE_W):
		if valid[x]:
			total += profile[x]
			valid_count += 1
	var global_mean := total / float(maxi(1, valid_count))
	for x in range(TILE_W):
		if valid[x]:
			continue
		var left := x - 1
		while left >= 0 and not valid[left]:
			left -= 1
		var right := x + 1
		while right < TILE_W and not valid[right]:
			right += 1
		profile[x] = profile[left] if left >= 0 else (profile[right] if right < TILE_W else global_mean)
	var smooth: Array = []
	for x in range(TILE_W):
		var sum := 0.0
		var count := 0
		for d in range(-4, 5):
			var index := x + d
			if index < 0 or index >= TILE_W:
				continue
			sum += profile[index]
			count += 1
		smooth.append(sum / float(count))
	var out := Image.create(TILE_W, TILE_H, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in range(TILE_H):
		for x in range(TILE_W):
			if not _inside(x, y):
				continue
			var color := image.get_pixel(x, y)
			var delta: float = (float(smooth[x]) - global_mean) * strength / 255.0
			out.set_pixel(x, y, Color(clampf(color.r - delta, 0.0, 1.0), clampf(color.g - delta, 0.0, 1.0),
				clampf(color.b - delta, 0.0, 1.0), 1.0))
	return out

## 构建期自检：按 37/39/41 号同口径打印颗粒、均值、外圈与横向落差。
func _report(tiles: Array) -> void:
	print("[量测] 砖  内部std  内部均值RGB        外圈std  外圈均值RGB        左−右落差  掩码bbox")
	for i in range(tiles.size()):
		_line("%d" % i, tiles[i])
	var lo := INF
	var hi := -INF
	var std_lo := INF
	for image: Image in tiles:
		var m := _region_mean(image, 20, 10, 24, 12)
		lo = minf(lo, m.r * 255.0)
		hi = maxf(hi, m.r * 255.0)
		std_lo = minf(std_lo, _region_std(image, 20, 10, 24, 12))
	print("[自检] 内部 R 区间 %.1f–%.1f（极差 %.1f）；内部 std 下限 %.2f（判据 ≥ 15）" % [lo, hi, hi - lo, std_lo])

func _line(label: String, image: Image) -> void:
	var m := _region_mean(image, 20, 10, 24, 12)
	var om := _region_mean(image, 31, 1, 2, 6)
	print("%-4s  %.2f   (%3d,%3d,%3d)      %.2f   (%3d,%3d,%3d)     %+6.1f   %s" % [
		label, _region_std(image, 20, 10, 24, 12), int(m.r * 255), int(m.g * 255), int(m.b * 255),
		_region_std(image, 31, 1, 2, 6), int(om.r * 255), int(om.g * 255), int(om.b * 255),
		(_region_mean(image, 12, 10, 10, 12).r - _region_mean(image, 42, 10, 10, 12).r) * 255.0,
		_mask_bounds(),
	])

func _flat_to_image(flat: Array) -> Image:
	var image := Image.create(TILE_W, TILE_H, false, Image.FORMAT_RGBA8)
	for y in range(TILE_H):
		for x in range(TILE_W):
			image.set_pixel(x, y, flat[y * TILE_W + x])
	return image

func _region_mean(image: Image, x0: int, y0: int, w: int, h: int) -> Color:
	var sum := Vector3.ZERO
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var c := image.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
	var mean := sum / float(w * h)
	return Color(mean.x, mean.y, mean.z)

func _region_std(image: Image, x0: int, y0: int, w: int, h: int) -> float:
	var values: Array = []
	var sum := 0.0
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var value := _luma(image.get_pixel(x, y))
			values.append(value)
			sum += value
	var mean := sum / float(values.size())
	var acc := 0.0
	for value: float in values:
		acc += (value - mean) * (value - mean)
	return sqrt(acc / float(values.size()))

func _luma(color: Color) -> float:
	return (color.r * 0.299 + color.g * 0.587 + color.b * 0.114) * 255.0

## 与 build_environment_art.gd::_pack_tiles 完全同式的菱形掩码。
func _edge(x: int, y: int) -> float:
	return 1.0 - absf((x + 0.5 - 32.0) / 32.0) - absf((y + 0.5 - 16.0) / 16.0)

func _inside(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= TILE_W or y >= TILE_H:
		return false
	return _edge(x, y) >= 0.0

func _mask_bounds() -> String:
	var min_x := TILE_W
	var max_x := -1
	var min_y := TILE_H
	var max_y := -1
	for y in range(TILE_H):
		for x in range(TILE_W):
			if not _inside(x, y):
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	return "%dx%d+%d+%d" % [max_x - min_x + 1, max_y - min_y + 1, min_x, min_y]

func _save(image: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	assert(image.save_png(path) == OK, "写入失败：%s" % path)
