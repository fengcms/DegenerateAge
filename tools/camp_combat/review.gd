extends Node2D
## 八向五状态原尺寸联系表：读取战斗场同一图集缓存渲染，供检查造型、锚点与透明边缘。
## 只用于隔离截图，不参与战斗；每种角色输出四张阶段页，不放大或加工源稿。
const Art = preload("res://tools/camp_combat/art.gd")
const STATES := ["idle","walk","attack","hit","death"]

## 构造三套缓存后依次渲染方向×状态矩阵，所有截图成功才输出完成标记。
func _ready() -> void:
	assert(OS.get_environment("DEGENERATE_CAMP_ISOLATED")=="1")
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			output = arg.trim_prefix("--capture=")
	assert(not output.is_empty())
	for kind: String in ["hero","wolf","beetle"]:
		var holder := CharacterBody2D.new()
		add_child(holder)
		var art := Art.new()
		holder.add_child(art)
		art.setup(holder,kind)
		art.set_process(false)
		art.hide()
		assert(art.clips.size()==8,"八方向未齐，不能生成完整审查表")
		for phase_index in range(4):
			var page := Node2D.new()
			add_child(page)
			_label(page,kind+" · 八方向/五状态 · 阶段 "+str(phase_index+1),Vector2(20,15))
			for column in range(8):
				var direction: String = Art.DIRECTIONS[column]
				_label(page,direction,Vector2(145+column*138,48))
				for row in range(5):
					if column==0:
						_label(page,STATES[row],Vector2(15,120+row*130))
					var frames: Array = art.clips[direction][STATES[row]]
					var sprite := Sprite2D.new()
					sprite.centered = false
					sprite.texture = frames[mini(phase_index,frames.size()-1)]
					sprite.offset = art.offset
					sprite.position = Vector2(160+column*138,185+row*130)
					page.add_child(sprite)
			await get_tree().process_frame
			RenderingServer.force_draw(false)
			assert(get_viewport().get_texture().get_image().save_png(output+"/"+kind+"_phase_"+str(phase_index)+".png")==OK)
			page.free()
		holder.free()
	print("CAMP_ART_REVIEW_OK: 3 actors / 8 directions / 5 states / 4 phases")
	get_tree().quit()

## 添加矩阵标题与方向说明，位置单位为固定1280×800画布像素。
func _label(parent: Node, text: String, point: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	parent.add_child(label)
