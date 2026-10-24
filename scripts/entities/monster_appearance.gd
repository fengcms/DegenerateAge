class_name MonsterAppearance
extends RefCounted
## 怪物表现装配入口：通过外观 ID 选择已有图集、方向动画或程序占位图。
## 仅创建视觉节点和设置渲染元数据，不改变怪物身份、碰撞、战斗或奖励。

## 在怪物创建时装配一次表现节点；无美术/资源缺失时返回 null，怪物继续原有分档绘制。
## 贴图由 Godot 资源缓存共享，返回节点属于 actor，由 actor 生命周期负责释放。
static func attach(actor: Node2D, appearance_id: String) -> CanvasItem:
	var raw: Variant = DataLoader.get_entry("monsterAppearances", appearance_id)
	if not (raw is Dictionary):
		push_warning("[MonsterAppearance] 未登记外观：%s" % appearance_id)
		return null
	var spec: Dictionary = raw
	var renderer := String(spec.get("renderer", "procedural"))
	var art: CanvasItem = null
	match renderer:
		"procedural":
			return null
		"animation_pack":
			art = MonsterActorArt.attach_monster(actor, String(spec.get("assetKey", "")))
		"directional_preview":
			# 逐方向单帧试玩；同 ID 实例复用地图级缓存，与正式动画包分开登记。
			var point: Array = spec.get("offset", [0, 0])
			art = MonsterDirectionalPreviewArt.attach_preview(actor, appearance_id,
				String(spec.get("texture", "")), Vector2(float(point[0]), float(point[1])))
		"chapter2_manifest":
			art = ChapterTwoArt.attach(actor, String(spec.get("assetKey", "")))
		"sample_atlas":
			var main := String(spec.get("main", ""))
			if ResourceLoader.exists(main):
				var point: Array = spec.get("pivot", [0, 0])
				art = SampleActorArt.attach(actor, main, Vector2(float(point[0]), float(point[1])),
					String(spec.get("extra", "")), String(spec.get("walk", "")))
		"static_atlas":
			var path := String(spec.get("texture", ""))
			if ResourceLoader.exists(path):
				# 临时怪物图在导出包中显式预载；旧木桩等静态档案仍按路径读取。
				var image := SimplifiedMonsterLibrary.TEXTURES.get(appearance_id) as Texture2D
				if image == null:
					image = load(path) as Texture2D
				if image != null:
					var sprite := Sprite2D.new()
					sprite.name = "MonsterStaticArt"
					sprite.texture = image
					sprite.hframes = int(spec.get("hframes", 1))
					sprite.centered = false
					var point: Array = spec.get("offset", [0, 0])
					sprite.offset = Vector2(float(point[0]), float(point[1]))
					sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					actor.add_child(sprite)
					art = sprite
		_:
			push_warning("[MonsterAppearance] 不支持的渲染类型：%s" % renderer)
	if art != null and spec.has("displayScale") and art is SampleActorArt:
		(art as SampleActorArt).display_scale = float(spec.displayScale)
	return art

## 工程 103-b（怪物重叠第二轮）：按外观推导**画面可见半宽**（px）。
## `radius` 是点击命中与程序占位圆的玩法参数，和美术帧尺寸无关 —— 打金图怪物可见体宽 69px，
## 玩法半径却只有 13px，按玩法半径分离画面上仍然叠成一坨（见工程文档 103 §9）。
## 这里量第 0 张图集所有帧的 alpha 包围盒最大宽度；取不到（程序占位、纹理缺失）返回 0，
## 由调用方回退玩法半径。结果按 appearanceId 缓存，只有首次装配时解码一次。
static var _body_half_width_cache: Dictionary = {}

static func body_half_width(appearance_id: String, art: CanvasItem) -> float:
	if _body_half_width_cache.has(appearance_id):
		return float(_body_half_width_cache[appearance_id])
	var measured := _measure_body_half_width(art)
	_body_half_width_cache[appearance_id] = measured
	return measured

static func _measure_body_half_width(art: CanvasItem) -> float:
	var sprite := art as Sprite2D
	if sprite == null or sprite.texture == null:
		return 0.0
	var image := sprite.texture.get_image()
	if image == null or image.is_empty():
		return 0.0
	if image.is_compressed():
		image.decompress()
	var hframes := maxi(sprite.hframes, 1)
	var vframes := maxi(sprite.vframes, 1)
	var frame := Vector2i(image.get_width() / hframes, image.get_height() / vframes)
	if frame.x <= 0 or frame.y <= 0:
		return 0.0
	var widest := 0
	# 八向图集里侧身帧比正面帧窄，取所有帧的最大宽度，避免按侧面帧低估体型。
	for row in range(vframes):
		for col in range(hframes):
			var region := Rect2i(col * frame.x, row * frame.y, frame.x, frame.y)
			widest = maxi(widest, image.get_region(region).get_used_rect().size.x)
	if widest <= 0:
		return 0.0
	var scale_x := absf(sprite.scale.x)
	if sprite is SampleActorArt:
		# SampleActorArt 每帧会把 scale 乘上呼吸/行走倍率，取登记倍率才稳定。
		scale_x = absf((sprite as SampleActorArt).display_scale)
	return float(widest) * scale_x * 0.5
