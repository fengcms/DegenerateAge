class_name InventoryPanelTooltip
extends RefCounted

static func describe(item: Dictionary) -> String:
	var lines: Array[String] = [ItemUtil.display_name(item)]
	if item.has("baseAttrs"):
		for key in item.baseAttrs:
			lines.append("%s +%s" % [str(key), str(item.baseAttrs[key])])
	if item.has("affixes"):
		for affix in item.affixes:
			if affix is Dictionary:
				lines.append("%s +%s" % [str(affix.get("key", "词条")), str(affix.get("value", 0))])
	return "\n".join(lines)
