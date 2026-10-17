class_name MonsterAnimationCache
extends RefCounted
## 已审核怪物动画的地图级纹理缓存：只装载本图实际可能生成的正式外观。
## 纹理在装配阶段读取并由同 ID 实例共享；本类不处理帧推进、伤害或掉落。

static var _loaded: Dictionary = {}
static var _preview_loaded: Dictionary = {}
static var _failed: Dictionary = {}
static var _map_id := ""

## 地图生成怪物前预取刷新点、首领与其召唤物；同图重复调用不会重复解码。
static func prepare_for_map(map_id: String) -> void:
	if _map_id != map_id:
		_loaded.clear()
		_preview_loaded.clear()
		_failed.clear()
		_map_id = map_id
	var map_data: Variant = DataLoader.get_entry("maps", map_id)
	if not map_data is Dictionary:
		return
	var specs: Array = (map_data as Dictionary).get("spawnPoints", []).duplicate()
	var boss: Variant = (map_data as Dictionary).get("bossSpawn", null)
	if boss is Dictionary:
		specs.append(boss)
	var seen := {}
	for raw: Variant in specs:
		if raw is Dictionary:
			_prefetch_monster(String((raw as Dictionary).get("monsterId", "")), seen)

## 世界退出时移除缓存持有的引用；活着的实例会自行持有纹理直到退场。
static func release_for_map(map_id: String) -> void:
	if _map_id == map_id:
		_loaded.clear()
		_preview_loaded.clear()
		_failed.clear()
		_map_id = ""

## 供怪物装配读取包；隔离测试或脚本直接生怪时在装配点补加载。
static func get_pack(id: String) -> Dictionary:
	if _loaded.has(id):
		return _loaded[id]
	if _failed.has(id):
		return {}
	var raw: Variant = MonsterAnimationLibrary.PACKS.get(id)
	if not raw is Dictionary:
		return {}
	var pack: Dictionary = (raw as Dictionary).duplicate(true)
	for state: String in pack.states:
		var spec: Dictionary = pack.states[state]
		var resource_path := String(spec.get("texture", ""))
		if not ResourceLoader.exists(resource_path):
			_failed[id] = true
			push_error("[MonsterAnimationCache] 缺少图集：%s" % resource_path)
			return {}
		var image := load(resource_path) as Texture2D
		if image == null or image.get_width() != int(pack.frameSize[0]) * int(spec.frames) \
				or image.get_height() != int(pack.frameSize[1]) * 8:
			_failed[id] = true
			push_error("[MonsterAnimationCache] 图集尺寸错误：%s" % resource_path)
			return {}
		spec.texture = image
	_loaded[id] = pack
	return pack

## 八方向单帧试玩图按需加载；同地图同外观实例共用一张纹理。
static func get_preview_texture(id: String, resource_path: String) -> Texture2D:
	if _preview_loaded.has(id):
		return _preview_loaded[id] as Texture2D
	if resource_path.is_empty() or not ResourceLoader.exists(resource_path):
		push_error("[MonsterAnimationCache] 试玩图缺失：%s" % resource_path)
		return null
	var atlas := load(resource_path) as Texture2D
	if atlas == null or atlas.get_width() % 3 != 0 or atlas.get_height() != atlas.get_width() / 3 * 8:
		push_error("[MonsterAnimationCache] 试玩图尺寸错误：%s" % resource_path)
		return null
	_preview_loaded[id] = atlas
	return atlas

## 供缓存回归测试查看当前地图实际持有的包，不触发加载。
static func cached_ids() -> Array:
	return _loaded.keys()

static func cached_preview_ids() -> Array:
	return _preview_loaded.keys()

## 沿模板引用预取外观与召唤；避免首领技能或精英词缀首次召唤时现解码。
static func _prefetch_monster(monster_id: String, seen: Dictionary) -> void:
	if monster_id.is_empty() or seen.has(monster_id):
		return
	seen[monster_id] = true
	var monster: Variant = DataLoader.get_entry("monsters", monster_id)
	if not monster is Dictionary:
		return
	var entry: Dictionary = monster
	var appearance_id := String(entry.get("appearanceId", ""))
	var appearance: Variant = DataLoader.get_entry("monsterAppearances", appearance_id)
	if appearance is Dictionary and String((appearance as Dictionary).get("renderer", "")) == "animation_pack":
		get_pack(String((appearance as Dictionary).get("assetKey", "")))
	elif appearance is Dictionary and String((appearance as Dictionary).get("renderer", "")) == "directional_preview":
		get_preview_texture(appearance_id, String((appearance as Dictionary).get("texture", "")))
	if monster_id == "c2_boss_iron_foreman":
		_prefetch_monster("c2_broken_guard", seen)
	elif monster_id == "c2_boss_hundred_arm_extractor":
		_prefetch_monster("c2_spirit_larva", seen)
	var skill: Variant = entry.get("bossSkill", null)
	if skill is Dictionary:
		for phase: Variant in (skill as Dictionary).get("phases", []):
			if phase is Dictionary:
				_prefetch_monster(String((phase as Dictionary).get("summon", "")), seen)
	for affix_id: Variant in entry.get("affixPool", []):
		var affix: Variant = DataLoader.get_entry("affixes", String(affix_id))
		if affix is Dictionary:
			_prefetch_monster(String((affix as Dictionary).get("summonId", "")), seen)
