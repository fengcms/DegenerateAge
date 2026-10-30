extends Node
## 工程 111 如意边框分色（方案 A：复用装备品质色）。
##
## 为什么值得单独一支测试：四张如意图标的平均色明度差不到 10%，格内文字又被
## `SampleArt.decorate()` 在有图标时清成空串 ⇒ **边框色是这个界面唯一真实可见的区分**。
## 所以「四档必须四色」不是审美偏好，是可用性底线。
##
## 第二件要守的是「四处消费点同源」：背包 / 仓库 / 货郎托盘 / 地面掉落原先各写了一份
## 「装备看品质、其余看品类」。若只在背包加一个 `if kind == "rune"`，同一只钻石如意
## 在背包是紫框、在仓库是青框 —— 比统一青色更让人困惑。

const RUNE_IDS := ["rune_iron", "rune_jade", "rune_gold", "rune_diamond"]

## 期望 accent 键（与 `runes.json` 对应）。写死在这里是**独立判据**：
## 若数据与配色表一起被改错，这条仍会红。
const EXPECT_ACCENT := {
	"rune_iron": "steel",
	"rune_jade": "jade",
	"rune_gold": "gold",
	"rune_diamond": "diamond",
}

## 方案 A 的口径：四个 accent 色 == 装备品质色 uncommon/rare/epic/legendary。
## 这条同时是「将来改了 QUALITY_COLOR 却忘了同步 ACCENT_COLOR」的唯一警报。
const EXPECT_QUALITY := {
	"rune_iron": "uncommon",
	"rune_jade": "rare",
	"rune_gold": "epic",
	"rune_diamond": "legendary",
}

## 必须走唯一入口的四个消费点（工程 111 §2.1）。
const CONSUMERS := [
	"res://scripts/ui/inventory_panel.gd",
	"res://scripts/ui/warehouse_panel.gd",
	"res://scripts/ui/shop_panel.gd",
	"res://scripts/entities/ground_item.gd",
]

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[RuneAccentTest] " + label)

func _ready() -> void:
	_test_data_contract()
	_test_four_colors_distinct()
	_test_colors_match_quality()
	_test_unconfigured_falls_back()
	_test_equip_still_uses_quality()
	_test_other_kinds_unaffected()
	_test_single_entry_point()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[RuneAccentTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[RuneAccentTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 用例 1：数据契约 ----

func _test_data_contract() -> void:
	var seen := {}
	for rune_id in RUNE_IDS:
		var tpl = DataLoader.get_entry("runes", rune_id)
		check(tpl is Dictionary, "%s 应存在于 runes.json" % rune_id)
		if not tpl is Dictionary:
			continue
		var accent := String((tpl as Dictionary).get("accent", ""))
		check(accent == String(EXPECT_ACCENT[rune_id]),
			"%s 的 accent 应为「%s」，实际「%s」" % [rune_id, EXPECT_ACCENT[rune_id], accent])
		check(ItemUtil.ACCENT_COLOR.has(accent),
			"%s 的 accent「%s」必须在 ItemUtil.ACCENT_COLOR 内" % [rune_id, accent])
		check(not seen.has(accent),
			"%s 的 accent「%s」与 %s 重复 —— 玩家会看到两档一模一样的如意" % [
				rune_id, accent, String(seen.get(accent, ""))])
		seen[accent] = rune_id

# ---- 用例 2：四档颜色互不相同 ----

func _test_four_colors_distinct() -> void:
	for i in range(RUNE_IDS.size()):
		for j in range(i + 1, RUNE_IDS.size()):
			var a := ItemUtil.rune_accent_color(String(RUNE_IDS[i]))
			var b := ItemUtil.rune_accent_color(String(RUNE_IDS[j]))
			check(a != b, "%s 与 %s 的边框色不得相同（都是 %s）" % [
				String(RUNE_IDS[i]), String(RUNE_IDS[j]), a.to_html(false)])

# ---- 用例 3：色值逐个对表（方案 A = 复用装备品质色） ----

func _test_colors_match_quality() -> void:
	for rune_id in RUNE_IDS:
		var want := ItemUtil.quality_color(String(EXPECT_QUALITY[rune_id]))
		var got := ItemUtil.rune_accent_color(String(rune_id))
		# 用 html 串断言，失败时能直接看出差在哪个色号，不必翻十六进制。
		check(got.to_html(false) == want.to_html(false),
			"%s 应为 %s 的装备品质色 %s，实际 %s" % [
				String(rune_id), String(EXPECT_QUALITY[rune_id]),
				want.to_html(false), got.to_html(false)])

# ---- 用例 4：未配置回落品类青绿，而不是白框 ----

func _test_unconfigured_falls_back() -> void:
	var fallback: Color = ItemUtil.KIND_COLOR["rune"]
	check(ItemUtil.rune_accent_color("rune_not_configured") == fallback,
		"未登记的如意应回落 KIND_COLOR[rune]，实际 %s"
			% ItemUtil.rune_accent_color("rune_not_configured").to_html(false))
	check(ItemUtil.rune_accent_color("") == fallback, "空 id 也应回落，不得崩")
	# 回落目标本身不能是白色 —— 白色在深底上是空格子的颜色，等于没上色。
	check(fallback != Color.WHITE, "回落色不得为纯白（与空格子同色）")

# ---- 用例 5：装备仍走品质色，且兜底口径与 Shop 一致 ----

func _test_equip_still_uses_quality() -> void:
	var explicit_item := {"kind": "equip", "itemId": "", "quality": "rare"}
	check(ItemUtil.item_accent_color(explicit_item) == ItemUtil.quality_color("rare"),
		"带 quality 的装备应按实例品质上色")
	check(Shop.item_quality(explicit_item) == "rare", "Shop 口径应与之一致（委托后仍成立）")

	# 缺 quality 时回退模板 defaultQuality —— 这条兜底原先只在 Shop 里，
	# 背包与地面掉落根本没走，同一件装备会「托盘按模板品质、地上按白色」。
	# 临时注入探针模板，验证后还原表与索引（与 smoke_test 同法）。
	var backup: Array = DataLoader.tables["equipments"]
	var temp: Array = backup.duplicate(true)
	temp.append({
		"id": "__probe_rune_accent_equip__", "name": "探针", "slot": "weapon", "price": 50,
		"defaultQuality": "epic", "tierBases": {"1": {"atk": 1}},
		"affixPool": ["atk", "def", "hp", "mp"], "requiredLevel": 1,
	})
	DataLoader.tables["equipments"] = temp
	DataLoader._build_index()
	var probe := {"kind": "equip", "itemId": "__probe_rune_accent_equip__"}
	check(ItemUtil.item_accent_color(probe).to_html(false)
			== ItemUtil.quality_color("epic").to_html(false),
		"实例缺 quality 时应回退模板 defaultQuality（epic），实际 %s"
			% ItemUtil.item_accent_color(probe).to_html(false))
	DataLoader.tables["equipments"] = backup
	DataLoader._build_index()

# ---- 用例 6：非如意不受影响 ----

func _test_other_kinds_unaffected() -> void:
	var potion := {"kind": "potion", "itemId": "potion_red_small", "count": 1}
	check(ItemUtil.item_accent_color(potion) == ItemUtil.kind_color("potion"),
		"药水应仍走品类色（红），不得被如意分档波及")
	var misc := {"kind": "misc", "itemId": "misc_firework", "count": 1}
	check(ItemUtil.item_accent_color(misc) == ItemUtil.kind_color("misc"),
		"杂项应仍走品类色（土黄）")
	var coin := {"kind": "coin", "gold": 100}
	check(ItemUtil.item_accent_color(coin) == ItemUtil.kind_color("coin"),
		"金币应仍走品类色")
	# 缺 kind 的兜底是 misc（四处消费点原本三处这么写），不是空串落到灰。
	check(ItemUtil.item_accent_color({}) == ItemUtil.kind_color("misc"),
		"缺 kind 时应按 misc 兜底，不得落到 #cccccc")

# ---- 用例 7：四个消费点确实同源 ----

func _test_single_entry_point() -> void:
	for path in CONSUMERS:
		var text := FileAccess.get_file_as_string(String(path))
		check(not text.is_empty(), "%s 应可读取（源码级断言失败多半是路径写错）" % String(path))
		check(text.contains("ItemUtil.item_accent_color("),
			"%s 必须调用 ItemUtil.item_accent_color()（唯一入口）" % String(path))
		# 防回退：谁再写一份「装备看品质、其余看品类」，这里就红。
		check(not text.contains("ItemUtil.kind_color("),
			"%s 不得再直接调 ItemUtil.kind_color()，应走 item_accent_color()" % String(path))
		check(not text.contains("ItemUtil.quality_color("),
			"%s 不得再直接调 ItemUtil.quality_color()，应走 item_accent_color()" % String(path))
