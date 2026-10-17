extends Node
## 正式怪物动画按地图加载回归：验证预取、共享、切图释放和直接生怪补加载。
## 不改真实存档；测试仅使用 Godot 隔离项目中的静态数据和贴图。

var failures: Array[String] = []

## 收集失败后继续检查其余缓存行为，最后以退出码标记测试结果。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[MonsterAnimationCacheTest] " + message)

## 对照已知的第一章地图分布，检查缓存只保留当前地图所需包。
func _ready() -> void:
	MonsterAnimationCache.prepare_for_map("wild_trial")
	check(MonsterAnimationCache.cached_ids().has("elite_wolf_king"), "试炼地图预取狼王")
	check(not MonsterAnimationCache.cached_ids().has("boss_corrupted_beast"), "试炼地图不预取源头首领")
	var wolf := MonsterAnimationCache.get_pack("elite_wolf_king")
	check(not wolf.is_empty() and wolf.states.idle.texture is Texture2D, "共享包持有已解码纹理")
	check(MonsterAnimationCache.get_pack("elite_wolf_king").states.idle.texture == wolf.states.idle.texture, "同 ID 重用纹理")
	MonsterAnimationCache.prepare_for_map("corruption_source")
	var loaded := MonsterAnimationCache.cached_ids()
	check(loaded.has("boss_corrupted_beast") and loaded.has("elite_ash_wraith") and loaded.has("elite_shellback_bug"), "源头地图预取首领和精英")
	check(not loaded.has("elite_wolf_king"), "切图清除旧图引用")
	MonsterAnimationCache.release_for_map("corruption_source")
	check(MonsterAnimationCache.cached_ids().is_empty(), "世界退出释放缓存")
	check(not MonsterAnimationCache.get_pack("elite_wolf_king").is_empty(), "隔离场景直接生怪可补加载")
	MonsterAnimationCache.prepare_for_map("wild_trial")
	MonsterAnimationCache.release_for_map("wild_trial")
	MonsterAnimationCache.prepare_for_map("c2_pipe_slope")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_spirit_larva"), "断管坡预取汲灵幼虫试玩图")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_copper_worm"), "断管坡预取铜壳蠕虫试玩图")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_broken_guard"), "断管坡预取断链守卫试玩图")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_elite_copper_matriarch"), "断管坡预取铜壳母虫试玩图")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_elite_broken_inspector"), "断管坡预取断链巡检长试玩图")
	var larva := MonsterAnimationCache.get_preview_texture("c2_spirit_larva", "res://assets/sprites/monsters/c2_spirit_larva/directional_preview_atlas.png")
	check(larva != null and larva.get_size() == Vector2(240, 640), "试玩图集由地图缓存共享")
	MonsterAnimationCache.release_for_map("c2_pipe_slope")
	check(MonsterAnimationCache.cached_preview_ids().is_empty(), "切图释放试玩图缓存")
	MonsterAnimationCache.prepare_for_map("c2_old_well")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_slag_leech"), "旧汲灵井预取喷渣蛭试玩图")
	MonsterAnimationCache.release_for_map("c2_old_well")
	MonsterAnimationCache.prepare_for_map("c2_lower_works")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_badge_wraith"), "工坊下层预取工牌游魂试玩图")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_spirit_attendant"), "工坊下层预取汲灵侍虫试玩图")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_elite_gray_scribe"), "工坊下层预取灰印书记试玩图")
	MonsterAnimationCache.release_for_map("c2_lower_works")
	MonsterAnimationCache.prepare_for_map("c2_ember_furnace")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_ash_beast"), "余烬炉房预取煤灰兽试玩图")
	MonsterAnimationCache.release_for_map("c2_ember_furnace")
	MonsterAnimationCache.prepare_for_map("c2_well_core")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_purple_parasite"), "井核预取紫脉寄生体试玩图")
	check(MonsterAnimationCache.cached_preview_ids().has("c2_elite_spirit_guard"), "井核预取汲灵护卫试玩图")
	MonsterAnimationCache.release_for_map("c2_well_core")
	print("[MonsterAnimationCacheTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
