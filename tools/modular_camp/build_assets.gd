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
	var shapes: Array = Rules.shapes()
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
					var color := (soils if shape==0 else roads).get_pixel(sx,sy)
					color.a = 1.0 if shape==0 else Rules.coverage(shapes[shape-1],u,v)
					tile.set_pixel(x,y,color)
			atlas.blit_rect(tile,Rect2i(0,0,64,32),Vector2i(variant*64,shape*32))
	atlas.save_png(output+"terrain_atlas.png")
	var manifest := {"terrain":{"size":[1024,1536],"tile":[64,32],"period":4,"shapes":shapes},"objects":{}}
	for id in ["wall","tree","shelter"]:
		var image := Image.load_from_file(source+("wall_short" if id=="wall" else id)+".png")
		assert(image.detect_alpha()!=Image.ALPHA_NONE,"物件缺少透明通道")
		image = image.get_region(image.get_used_rect())
		var height := 230 if id=="tree" else (200 if id=="shelter" else 56)
		var width := roundi(float(image.get_width())/image.get_height()*height)
		image.resize(width,height,Image.INTERPOLATE_LANCZOS)
		image.save_png(output+id+".png")
		manifest.objects[id] = {"size":[width,height],"pivot":[width*0.5,height-4]}
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
