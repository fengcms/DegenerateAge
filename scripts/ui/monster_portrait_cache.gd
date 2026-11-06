class_name MonsterPortraitCache
extends RefCounted
## 界面拥有的怪物头像缓存：从真实外观精灵取得稳定待机帧，复用原纹理，只缓存AtlasTexture裁切。
## 按外观与数据revision失效，不持有怪物节点；宿主切图/退出时clear，缺图不缓存以便稍后恢复。
var _revision := -1
var _portraits: Dictionary = {}

## 清除本界面持有的裁切资源，不干预地图动画缓存的所有权。
func clear() -> void:
	_portraits.clear()

## 从存活或死亡中的真实实例取得头像，缺失美术返回null交由界面绘制统一回退。
func get_portrait(monster: Monster) -> AtlasTexture:
	if _revision != DataLoader.revision:
		clear()
		_revision = DataLoader.revision
	var appearance := String(monster.template.get("appearanceId", ""))
	if _portraits.has(appearance):
		return _portraits[appearance]
	var sprite := monster.sample_art as Sprite2D if monster.sample_art != null else monster.dummy_art
	if sprite == null or sprite.texture == null:
		return null
	var source := sprite.texture
	var columns := maxi(1, sprite.hframes)
	var rows := maxi(1, sprite.vframes)
	# 正式动画始终取待机首帧，不能让首次登记时的受击/死亡姿态成为永久头像。
	if sprite is MonsterActorArt:
		source = (sprite as MonsterActorArt)._textures.get("idle", source)
		columns = int((sprite as MonsterActorArt).definitions.get("idle", {}).get("frames", columns))
	var frame := Rect2i(0, (rows - 1) * (source.get_height() / rows), source.get_width() / columns, source.get_height() / rows)
	var image := source.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	var used := image.get_region(frame).get_used_rect()
	if not used.has_area():
		return null
	var portrait := AtlasTexture.new()
	portrait.atlas = source
	var side := mini(used.size.x, used.size.y)
	var crop := Rect2i(used.position + frame.position + Vector2i((used.size.x-side)/2, 0), Vector2i(side, side))
	portrait.region = Rect2(crop)
	portrait.filter_clip = true
	_portraits[appearance] = portrait
	return portrait

## 返回当前界面的裁切数量，供缓存生命周期验收使用。
func cached_count() -> int:
	return _portraits.size()
