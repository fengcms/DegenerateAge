extends Node
## 工程 115：UI 尺寸非法值防线（NaN / INF）。
##
## 背景：实机重铸后闪退，崩溃是 SIGSEGV（C++ 层空指针）。剥掉所有表象后有一条链：
## `viewport` 或 `uiScale` 变成 inf/nan → 守卫只写了 `<= 0.0`，而 `NAN <= 0.0` 恒为 false
## （浮点语义）⇒ 放行 → `control.size = nan` → 引擎报 `!isfinite(p_size)`
## → 子控件 `_draw` 里 `INF - INF = NaN` → 绘制层拿到 NaN 顶点 ⇒ 崩。
##
## 断言分工（每条咬住一个真实错法，负向注入后必须**红在这条上**）：
## A. `is_usable_layout_size()` 是唯一判据 —— 写成 `size.x <= 0.0` 就拦不住 NaN/INF。
## B. `ui_scale_value()` 对 NaN/INF 输入必须回落有限值 —— `clampf(NAN, ..)` 实测原样透传，
##    clamp 不能当兜底；它被 20+ 处用来算「逻辑视口」，透传会把整条尺寸链带崩。
## C. 端到端：倍率非法时控件尺寸仍必须是有限值（无论走「跳过」还是「兜底后重排」）。
## D. 正常倍率行为不变（防「一刀切成永不重排」式过修）。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[NanGuardTest] " + label)

func _ready() -> void:
	_test_guard_semantics()
	_test_usable_layout_size()
	await _test_scale_value_finite()
	await _test_apply_scale_end_to_end()
	await _test_normal_scale_unchanged()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[NanGuardTest] 全部通过 ✅")
		print("NanGuardTest: PASS")
	else:
		for failure in failures:
			push_error(failure)
		print("[NanGuardTest] 失败 %d 项" % failures.size())
		print("NanGuardTest: FAIL")

## 前置事实：整条分析成立的前提就是「NaN / INF 与 0 比较为 false」。
## 若某天换引擎或换浮点语义让这条不再成立，本用例先红，提示整份分析需重审。
func _test_guard_semantics() -> void:
	check(not (NAN <= 0.0), "NAN <= 0.0 必须为 false（否则原守卫本可拦住 NaN）")
	check(not (INF <= 0.0), "INF <= 0.0 必须为 false（否则原守卫本可拦住 INF）")
	check(not is_finite(NAN) and not is_finite(INF), "is_finite 必须能识别 NaN / INF")
	check(not is_finite(INF - INF), "INF - INF 必须为 NaN（这是边框法线算出的那一步）")
	check(not is_finite(1.0 / 0.0), "1.0 / 0.0 必须为 INF（视口除零后的形态）")

## A) 唯一判据：字面量入参，不复用生产常量，避免「判据写错也照绿」
func _test_usable_layout_size() -> void:
	check(not SettingsRuntime.is_usable_layout_size(Vector2(NAN, NAN)),
		"NaN 尺寸必须判为不可用")
	check(not SettingsRuntime.is_usable_layout_size(Vector2(NAN, 800.0)),
		"单轴 NaN 必须判为不可用")
	check(not SettingsRuntime.is_usable_layout_size(Vector2(INF, 800.0)),
		"INF 尺寸必须判为不可用")
	check(not SettingsRuntime.is_usable_layout_size(Vector2(1280.0, INF)),
		"单轴 INF 必须判为不可用")
	check(not SettingsRuntime.is_usable_layout_size(Vector2.ZERO),
		"零尺寸必须判为不可用")
	check(not SettingsRuntime.is_usable_layout_size(Vector2(-1280.0, 800.0)),
		"负尺寸必须判为不可用")
	check(SettingsRuntime.is_usable_layout_size(Vector2(1280.0, 800.0)),
		"正常尺寸必须判为可用（防一刀切全否）")
	check(SettingsRuntime.is_usable_layout_size(Vector2(0.5, 0.5)),
		"极小但正的尺寸必须判为可用")

## B) 倍率入口对非法输入兜底
func _test_scale_value_finite() -> void:
	var saved: Dictionary = GameState.settings.duplicate(true)
	GameState.settings["displayScaleMode"] = "auto"

	GameState.settings["uiScale"] = NAN
	var v_nan := SettingsRuntime.ui_scale_value()
	check(is_finite(v_nan), "uiScale 为 NaN 时倍率必须是有限值，实际 %s" % str(v_nan))
	check(is_equal_approx(v_nan, 1.0), "uiScale 为 NaN 时应回落 1.0，实际 %s" % str(v_nan))

	GameState.settings["uiScale"] = INF
	var v_inf := SettingsRuntime.ui_scale_value()
	check(is_finite(v_inf) and v_inf <= SettingsRuntime.UI_SCALE_MAX,
		"uiScale 为 INF 时必须夹到上限内，实际 %s" % str(v_inf))

	GameState.settings["uiScale"] = 1.0
	GameState.settings["displayScaleMode"] = "manual"
	GameState.settings["displayScale"] = NAN
	var v_disp := SettingsRuntime.ui_scale_value()
	check(is_finite(v_disp) and is_equal_approx(v_disp, 1.0),
		"手动显示倍率为 NaN 时必须回落 1.0，实际 %s" % str(v_disp))

	GameState.settings = saved
	await get_tree().process_frame

## C) 端到端：倍率非法时，控件尺寸与 transform 都必须保持有限
func _test_apply_scale_end_to_end() -> void:
	var saved: Dictionary = GameState.settings.duplicate(true)
	var ui := CanvasLayer.new()
	var probe := Control.new()
	ui.add_child(probe)
	add_child(ui)
	await get_tree().process_frame
	probe.size = Vector2(111, 222)

	for bad in [NAN, INF]:
		GameState.settings["uiScale"] = bad
		SettingsRuntime.apply_ui_scale_to(ui)
		check(is_finite(probe.size.x) and is_finite(probe.size.y),
			"倍率 %s 时控件尺寸仍必须有限，实际 %s" % [str(bad), str(probe.size)])
		check(is_finite(ui.transform.x.x) and is_finite(ui.transform.y.y),
			"倍率 %s 时 UI transform 仍必须有限，实际 %s" % [str(bad), str(ui.transform)])
		check(SettingsRuntime.is_usable_layout_size(probe.size),
			"倍率 %s 时控件尺寸必须是可用布局尺寸，实际 %s" % [str(bad), str(probe.size)])

	GameState.settings = saved
	ui.queue_free()
	await get_tree().process_frame

## D) 正常倍率回归：不得被「一刀切成永不重排」
func _test_normal_scale_unchanged() -> void:
	var saved: Dictionary = GameState.settings.duplicate(true)
	var ui := CanvasLayer.new()
	var probe := Control.new()
	ui.add_child(probe)
	add_child(ui)
	await get_tree().process_frame

	GameState.settings["displayScaleMode"] = "auto"
	GameState.settings["uiScale"] = 1.5
	SettingsRuntime.apply_ui_scale_to(ui)
	var expected := get_viewport().get_visible_rect().size / 1.5
	check(is_equal_approx(ui.transform.x.x, 1.5),
		"正常倍率应写入 UI transform，实际 %s" % str(ui.transform.x.x))
	check(probe.size.is_equal_approx(expected),
		"正常倍率下控件应为逻辑视口 %s，实际 %s" % [str(expected), str(probe.size)])

	GameState.settings = saved
	ui.queue_free()
	await get_tree().process_frame
