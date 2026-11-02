extends SceneTree
## 工程 115（崩溃取证）：确认 `settings_runtime.apply_ui_scale_to` 的
## `if viewport_size.x <= 0.0` 守卫对 NaN / INF 是否失效。
## 结论：NAN/INF 与 0.0 比较恒为 false ⇒ 守卫放行；`clampf(NAN)` 原样返回 nan。
## 只打印，不改任何文件、不碰存档。复核命令：
##   Godot --headless --script res://tools/nan_guard_probe.gd
## 见 docs/审阅报告/重铸闪退崩溃分析（SIGSEGV·UI尺寸NaN）.md §5.1

func _init() -> void:
	var nan: float = NAN
	var inf: float = INF
	print("--- 守卫有效性 ---")
	print("NAN  <= 0.0        = ", nan <= 0.0, "   （true 才拦得住）")
	print("INF  <= 0.0        = ", inf <= 0.0, "   （true 才拦得住）")
	print("-INF <= 0.0        = ", -inf <= 0.0)
	print("is_finite(NAN)     = ", is_finite(nan))
	print("is_finite(INF)     = ", is_finite(inf))
	print("--- 传播链 ---")
	print("INF / 1.0          = ", inf / 1.0)
	print("NAN / 1.0          = ", nan / 1.0)
	print("clampf(NAN,0.8,2)  = ", clampf(nan, 0.8, 2.0))
	print("clampf(INF,0.8,2)  = ", clampf(inf, 0.8, 2.0))
	print("--- 与崩溃报错同形的判定 ---")
	var size := Vector2(inf, inf)
	print("!isfinite(size.x)  = ", not is_finite(size.x), "   （即引擎 set_size 的报错条件）")
	print("size.x - 2.0       = ", size.x - 2.0)
	print("INF - INF          = ", inf - inf, "   （即 draw_rect 边框算出的 NaN）")
	quit()
