extends Node
## 不变地面几何缓存：点集同源、网格复用、预算上限及真实窗口原画法像素对照。
class Drawing extends Node2D:
	var modern := false
	## 同样的圆和小于/大于半圆扇形，左侧原画法、右侧正式缓存入口。
	func _draw() -> void:
		var fill := Color(0.8,0.15,0.05,0.3)
		var edge := Color(1.0,0.68,0.4)
		var center := Vector2(80,100)
		if modern:
			GroundFx.outline(self,center,65,edge,2.0,48)
		else:
			var points := Iso.ground_ellipse(center,65,48)
			points.append(points[0])
			draw_polyline(points,edge,2.0,true)
		center = Vector2(80,200)
		if modern:
			BossSkillVisual._shape(self,{"kind":"ring","center":Iso.to_ground(global_position+center),"inner":30.0,"radius":65.0},fill,edge,2.0)
		else:
			GroundFx.band(self,center,30,65,fill,48)
			var outer := Iso.ground_ellipse(center,65,48)
			outer.append(outer[0])
			draw_polyline(outer,edge,2.0,true)
			var inner := Iso.ground_ellipse(center,30,40)
			inner.append(inner[0])
			draw_polyline(inner,edge,2.0,true)
		for i in range(2):
			center = Vector2(240+i*180,130)
			var dir := Vector2(0.7,0.3) if i == 0 else Vector2(-0.5,0.4)
			var arc := 1.4 if i == 0 else 4.2
			if modern:
				GroundFx.sector(self,center,dir,70,arc,fill,24)
				GroundFx.sector_outline(self,center,dir,70,arc,edge,2.0,24)
			else:
				var points := GroundFx._sector_points(center,dir,70,arc,24)
				draw_colored_polygon(points,fill)
				points.append(points[0])
				draw_polyline(points,edge,2.0,true)

## 独立比较原点集；窗口模式另验证混合与线宽，headless只验证几何/预算。
func _ready() -> void:
	for segments in [12,24,48]:
		for dir in [Vector2.RIGHT,Vector2(0.3,0.9),Vector2(-0.8,0.1)]:
			for arc in [1.0,3.0,4.2]:
				var expected := GroundFx._sector_points(Vector2.ZERO,dir,100,arc,segments)
				expected.append(expected[0])
				var first := GroundFx.sector_geometry(dir,100,arc,segments)
				assert(first.outline == expected)
				assert(is_same(first.mesh,GroundFx.sector_geometry(dir,100,arc,segments).mesh))
	var ellipse := Iso.ground_ellipse(Vector2.ZERO,88,48)
	ellipse.append(ellipse[0])
	assert(GroundFx.ellipse_outline(88,48) == ellipse)
	for i in range(300):
		GroundFx.sector_geometry(Vector2.RIGHT,20+i,1.4,24)
		GroundFx.ellipse_outline(20+i,48)
	assert(GroundFx._ellipses.size() <= GroundFx.GEOMETRY_LIMIT)
	assert(GroundFx._sectors.size() <= GroundFx.GEOMETRY_LIMIT)
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1280,800)
		get_window().content_scale_size = Vector2i.ZERO
		var left := Drawing.new()
		left.position = Vector2(10,10)
		add_child(left)
		var right := Drawing.new()
		right.modern = true
		right.position = Vector2(650,10)
		add_child(right)
		for i in range(5):
			await get_tree().process_frame
		RenderingServer.force_draw(false)
		var image := get_viewport().get_texture().get_image()
		var bad := 0
		for y in range(260):
			for x in range(550):
				var a := image.get_pixel(x+10,y+10)
				var b := image.get_pixel(x+650,y+10)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.15:
					bad += 1
		print("[PERF] ground_geometry difference_pixels=",bad)
		assert(bad < 200,"缓存不能改变危险范围或线宽：差异%d" % bad)
		# 静态绘制命令必须在共享缓存淘汰后仍有效，不能只验证缓存上限。
		for i in range(40):
			BossSkillVisual.ring_mesh(20+i,80+i)
		for i in range(300):
			GroundFx.sector_geometry(Vector2.RIGHT,400+i,1.1,24)
		for i in range(3):
			await get_tree().process_frame
		RenderingServer.force_draw(false)
		var after_eviction := get_viewport().get_texture().get_image()
		var missing := 0
		for y in range(260):
			for x in range(550):
				var a := image.get_pixel(x+650,y+10)
				var b := after_eviction.get_pixel(x+650,y+10)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.15:
					missing += 1
		assert((right.get_meta("ground_fx_mesh_refs") as Array).size() <= 3, "节点仅保留当前绘制用量")
		assert(missing == 0,"淘汰共享缓存不能丢失仍在显示的填充：差异%d" % missing)
		image.save_png("/tmp/high_speed_geometry.png")
	print("[GroundGeometryCacheTest] PASS")
	get_tree().quit()
