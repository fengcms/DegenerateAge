extends SceneTree
## 将独立母版编译为4×4周期地砖、47形状道路图集和紧裁切物件。
## 仅裁切、等距投影、共边处理和图集打包，不生成整图；源稿保留不覆盖。
const Rules = preload("road_rules.gd")

## 通过显式仓库路径读取源稿并输出运行素材，失败时停止构建。
func _initialize() -> void:
	var root := OS.get_cmdline_user_args()[0]
	var source := root+"/art_source/environment/camp_modular_v1/"
	var output := root+"/assets/environment/camp_modular_v1/"
	var soils := _material(source+"soil.png")
	var roads := _material(source+"road.png")
	var grass := _material(source+"grass.png")
	var shapes: Array = Rules.shapes()
	for kind in ["terrain","grass"]:
		var atlas := Image.create(1024,1536,false,Image.FORMAT_RGBA8)
		for variant in range(16):
			for shape in range(48):
				var tile := Image.create(64,32,false,Image.FORMAT_RGBA8)
				for y in range(32):
					for x in range(64):
						var a := (x+0.5-32.0)/32.0
						var b := -(y+0.5-16.0)/16.0
						var u := (a+b)*0.5
						var v := (b-a)*0.5
						if absf(u)>0.5 or absf(v)>0.5:
							continue
						var sx := posmod(floori((variant%4+u+0.5)*64),256)
						var sy := posmod(floori((floori(float(variant)/4.0)+v+0.5)*64),256)
						var color := (soils if shape==0 else (roads if kind=="terrain" else grass)).get_pixel(sx,sy)
						color.a = 1.0 if shape==0 else Rules.coverage(shapes[shape-1],u,v,0.08 if kind=="grass" else 0.25,0.49 if kind=="grass" else 0.38)
						tile.set_pixel(x,y,color)
				atlas.blit_rect(tile,Rect2i(0,0,64,32),Vector2i(variant*64,shape*32))
		atlas.save_png(output+kind+"_atlas.png")
	var manifest := {"terrain":{"size":[1024,1536],"tile":[64,32],"period":4,"shapes":shapes},"grass":{"size":[1024,1536],"tile":[64,32],"period":4},"objects":{}}
	for id in ["wall","wall_other","wall_corner","tree","shelter"]:
		var image := Image.load_from_file(source+("wall_short" if id=="wall" else id)+".png")
		assert(image.detect_alpha()!=Image.ALPHA_NONE,"物件缺少透明通道")
		image = image.get_region(image.get_used_rect())
		var height := 230 if id=="tree" else (200 if id=="shelter" else 56)
		var width := roundi(float(image.get_width())/image.get_height()*height)
		image.resize(width,height,Image.INTERPOLATE_LANCZOS)
		image.save_png(output+id+".png")
		manifest.objects[id] = {"size":[width,height],"pivot":[width*0.5,height-4]}
	var decals := Image.create(256,64,false,Image.FORMAT_RGBA8)
	for index in range(2):
		var id := "roots" if index==0 else "gravel"
		var detail := Image.load_from_file(source+id+".png")
		assert(detail.detect_alpha()!=Image.ALPHA_NONE)
		detail = detail.get_region(detail.get_used_rect())
		var factor := minf(96.0/detail.get_width(),48.0/detail.get_height())
		detail.resize(roundi(detail.get_width()*factor),roundi(detail.get_height()*factor),Image.INTERPOLATE_LANCZOS)
		var offset := Vector2i(index*128+(128-detail.get_width())/2,(64-detail.get_height())/2)
		decals.blit_rect(detail,Rect2i(Vector2i.ZERO,detail.get_size()),offset)
	decals.save_png(output+"decals_atlas.png")
	manifest["decals"] = {"size":[256,64],"slot":[128,64],"ids":["roots","gravel"]}
	var regions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root+"/tools/modular_camp/occlusion_regions.json"))
	for id in regions:
		var mask := _reveal_mask(Image.load_from_file(output+id+".png"),regions[id])
		mask.save_png(output+id+"_reveal_mask.png")
		manifest.objects[id]["reveal_mask"] = id+"_reveal_mask.png"
	var file := FileAccess.open(output+"manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"  "))
	print("MODULAR_ASSETS_BUILT: ",manifest)
	quit()

## 缩至256方形周期母版；对向边8像素共同收口，避免生成母版边界亮度跳变。
func _material(path: String) -> Image:
	var image := Image.load_from_file(path)
	image.resize(256,256,Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	for axis in range(2):
		for i in range(8):
			var weight := (1.0-float(i)/8.0)*0.5
			for p in range(256):
				var first := Vector2i(i,p) if axis==0 else Vector2i(p,i)
				var last := Vector2i(255-i,p) if axis==0 else Vector2i(p,255-i)
				var a := image.get_pixelv(first)
				var b := image.get_pixelv(last)
				image.set_pixelv(first,a.lerp(b,weight))
				image.set_pixelv(last,b.lerp(a,weight))
	return image

## 将人工标注的轮廓区域编译为显示蒙版；保护区与透明像素始终为黑色，不改原画。
func _reveal_mask(source: Image, spec: Dictionary) -> Image:
	assert(source.get_size()==Vector2i(spec.size[0],spec.size[1]),"图片尺寸变化后必须重审轮廓")
	var mask := Image.create(source.get_width(),source.get_height(),false,Image.FORMAT_RGBA8)
	mask.fill(Color.BLACK)
	var includes := _polygons(spec.include)
	var protects := _polygons(spec.protect)
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			if source.get_pixel(x,y).a<0.02:
				continue
			var point := Vector2(x+0.5,y+0.5)
			var selected := false
			for polygon in includes:
				selected = selected or Geometry2D.is_point_in_polygon(point,polygon)
			for polygon in protects:
				if Geometry2D.is_point_in_polygon(point,polygon):
					selected = false
			if selected:
				mask.set_pixel(x,y,Color.WHITE)
	for raw in spec.protected_samples:
		var point := Vector2i(raw[0],raw[1])
		assert(source.get_pixelv(point).a>0.2,"保护验证点必须位于可见树干或墙体")
		assert(mask.get_pixelv(point).r==0,"保护区错误淡出")
	for raw in spec.reveal_samples:
		var point := Vector2i(raw[0],raw[1])
		assert(source.get_pixelv(point).a>0.2 and mask.get_pixelv(point).r==1,"冠层或屋顶验证点不在蒙版内")
	return mask

## 将配置中的像素顶点转换成Godot多边形，构建期执行，不进入帧循环。
func _polygons(raw: Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for values in raw:
		var polygon := PackedVector2Array()
		for point in values:
			polygon.append(Vector2(point[0],point[1]))
		result.append(polygon)
	return result
