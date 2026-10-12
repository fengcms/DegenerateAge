class_name InventoryPanelTooltip
extends RefCounted

static func describe(item: Dictionary) -> String:
	var lines: Array[String] = [ItemUtil.display_name(item)]
	lines.append_array(ItemUtil.attr_lines(item))
	return "\n".join(PackedStringArray(lines))
