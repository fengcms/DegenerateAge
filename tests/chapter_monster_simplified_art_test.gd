extends Node
## 第二至六章临时怪物外观集成测试：逐 ID 装配真实实体，核对独立图集与三档脚底规格。
## 另验证汲灵幼虫的八方向单帧试玩稿；不把它误判为正式五状态动画。

const MONSTER_SCENE := preload("res://scenes/entities/Monster.tscn")
const SIZES := {"normal": [80, 64], "elite": [112, 88], "boss": [192, 152]}

var failures: Array[String] = []

## 收集外观与图集契约失败，继续检查其余 ID，避免首个坏资源掩盖整批问题。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterMonsterSimplifiedArtTest] " + message)

## 实际创建 79 只怪物并装配外观；每只立即释放，避免在测试里制造无关战斗负载。
func _ready() -> void:
	var count := 0
	for raw: Variant in DataLoader.get_table("monsters"):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var id := String(entry.get("id", ""))
		if not id.begins_with("c2_") and not id.begins_with("c3_") and not id.begins_with("c4_") and not id.begins_with("c5_") and not id.begins_with("c6_"):
			continue
		count += 1
		var monster := MONSTER_SCENE.instantiate() as Monster
		monster.monster_id = id
		add_child(monster)
		monster.set_physics_process(false)
		if id in ["c2_spirit_larva", "c2_copper_worm", "c2_broken_guard", "c2_slag_leech"]:
			var preview := monster.sample_art as MonsterDirectionalPreviewArt
			check(preview != null, "%s 装配八方向试玩外观" % id)
			if preview != null:
				check(preview.texture.get_size() == Vector2(240, 640), "试玩图集为 3 列 8 行，每格 80 像素")
				check(preview.offset == Vector2(-40, -64), "试玩图保持原脚底锚点")
				preview.face(Vector2.DOWN)
				preview._process(0.0)
				check(preview.frame_coords == Vector2i(0, 0), "向南显示正面")
				monster.velocity = Vector2.LEFT * 40.0
				preview._process(0.016)
				check(preview.frame_coords == Vector2i(0, 2), "移动向西显示左侧面")
				monster.velocity = Vector2.ZERO
				preview.attack(Vector2.UP, 0.4)
				preview._process(0.0)
				check(preview.frame_coords == Vector2i(0, 4), "向北攻击显示背面，不改变伤害时序")
				preview.hit()
				preview._process(0.01)
				check(preview.frame_coords == Vector2i(1, 4), "受击保持当前方向")
				monster.is_dead = true
				preview._process(0.01)
				check(preview.frame_coords == Vector2i(2, 4), "死亡保持当前方向")
			remove_child(monster)
			monster.free()
			continue
		var art := monster.dummy_art
		check(art != null, "%s 装配临时外观" % id)
		if art != null:
			var dimensions: Array = SIZES[String(entry.get("kind", "normal"))]
			check(art.hframes == 3, "%s 保留原姿/受击/死亡三格" % id)
			check(art.texture == SimplifiedMonsterLibrary.TEXTURES.get(id), "%s 使用预载的独立运行图" % id)
			if art.texture != null:
				check(art.texture.get_size() == Vector2(int(dimensions[0]) * 3, int(dimensions[0])), "%s 图集帧尺寸" % id)
			check(art.offset == Vector2(-int(dimensions[0]) / 2.0, -int(dimensions[1])), "%s 脚底锚点" % id)
		remove_child(monster)
		monster.free()
	check(count == 79, "覆盖 79 个第二至六章怪物 ID")
	check(DataLoader.validate_all().is_empty(), "全表外观资源与跨表引用合法")
	print("[ChapterMonsterSimplifiedArtTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
