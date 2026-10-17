class_name MonsterDirectionalPreviewArt
extends SampleActorArt
## 八方向静态试玩稿：每行一个方向，三列为原姿、受击、死亡。
## 不把单帧候选伪装为正式五状态动画；战斗结算仍由 Monster 管理。

const ATLAS := preload("res://assets/sprites/monsters/c2_spirit_larva/directional_preview_atlas.png")

var _hit_remaining := 0.0

static func attach_preview(actor: Node2D) -> MonsterDirectionalPreviewArt:
	var art := MonsterDirectionalPreviewArt.new()
	art.name = "MonsterDirectionalPreviewArt"
	art.texture = ATLAS
	art.hframes = 3
	art.vframes = 8
	art.centered = false
	art.offset = Vector2(-40, -64)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.frame_coords = Vector2i(0, 7)
	art.facing = 7
	actor.add_child(art)
	return art

func attack(vector: Vector2, _interval: float) -> void:
	face(vector)

func hit() -> void:
	_hit_remaining = HIT_SECONDS

func _process(delta: float) -> void:
	var actor := get_parent() as Monster
	if actor == null:
		return
	actor.z_index = clampi(roundi(actor.global_position.y), -3500, 3500)
	if not actor.is_dead and actor.velocity.length_squared() > 1.0:
		face(actor.velocity)
	_hit_remaining = maxf(0.0, _hit_remaining - delta)
	frame_coords = Vector2i(2 if actor.is_dead else 1 if _hit_remaining > 0.0 else 0, facing)
	scale = Vector2.ONE * display_scale
