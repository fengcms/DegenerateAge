class_name QuestInlineText
extends RefCounted
## 任务文案：普通文本原样编辑，少量 {类型:ID} 标记生成行内链接。
## 追踪栏与任务官面板共用此显示规则；点击后的导航权限由 Quest 校验。

## 依据任务状态选择目标、交付或下一主线文案；未配置时回退到普通描述。
static func description(entry: Dictionary) -> String:
	var state := String(entry.get("state", ""))
	if state == Quest.STATE_AVAILABLE and entry.has("leadText"):
		return String(entry.get("leadText", ""))
	if state == Quest.STATE_COMPLETED:
		return String(entry.get("turnInText", entry.get("desc", "")))
	if state == Quest.STATE_ACTIVE:
		return String(entry.get("trackerText", entry.get("desc", "")))
	return String(entry.get("desc", ""))

static func markup(entry: Dictionary) -> String:
	var source := description(entry)
	var pattern := RegEx.new()
	pattern.compile("\\{(count|current|(?:map|monster|npc|item):[a-zA-Z0-9_]+)\\}")
	var result := ""
	var last := 0
	for match_data in pattern.search_all(source):
		result += _escape(source.substr(last, match_data.get_start() - last))
		var token := match_data.get_string(1)
		if token == "count":
			result += str(entry.get("need", 0))
		elif token == "current":
			result += str(entry.get("cur", 0))
		else:
			var parts := token.split(":", false, 1)
			var kind := String(parts[0])
			var target_id := String(parts[1])
			var name := _display_name(kind, target_id)
			if name.is_empty():
				result += _escape(match_data.get_string())
			elif kind == "item":
				result += _escape(name)
			else:
				result += "[url=%s:%s][color=#70d9eb][u]%s[/u][/color][/url]" % [kind, target_id, _escape(name)]
		last = match_data.get_end()
	result += _escape(source.substr(last))
	return result

static func _display_name(kind: String, target_id: String) -> String:
	match kind:
		"map":
			return MapService.display_name(target_id) if MapService.exists(target_id) else ""
		"monster":
			var monster = DataLoader.get_entry("monsters", target_id)
			return String(monster.get("name", "")) if monster is Dictionary else ""
		"npc":
			return MapService.npc_name(target_id) if not MapService.map_for_npc(target_id).is_empty() else ""
		"item":
			var item = DataLoader.get_entry("miscItems", target_id)
			return String(item.get("name", "")) if item is Dictionary else ""
	return ""

static func _escape(value: String) -> String:
	return value.replace("[", "[lb]")

static func link_target(meta: Variant) -> PackedStringArray:
	var parts := String(meta).split(":", false, 1)
	return parts if parts.size() == 2 else PackedStringArray()
