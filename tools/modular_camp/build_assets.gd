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
	var beetle := Image.load_from_file(root+"/art_source/actors/camp_pilot_v1/beetle.png")
	assert(beetle.detect_alpha()!=Image.ALPHA_NONE,"铜甲虫必须有透明背景")
	beetle = beetle.get_region(beetle.get_used_rect())
	beetle.resize(110,roundi(110.0*beetle.get_height()/beetle.get_width()),Image.INTERPOLATE_LANCZOS)
	assert(beetle.save_png(root+"/assets/art_pilot/beetle_v2.png")==OK)
	print("BEETLE_BUILT: ",beetle.get_size())
	_build_walk(root)
	_build_hero_attack(root)
	_build_hero_reactions(root)
	_build_monster_motion(root,"idle")
	_build_monster_motion(root,"attack")
	_build_supplies(root,manifest)
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

## 固定格、统一倍率打包姿态帧，不按各帧边界缩放或吸附脚底；输出只供隔离动作试装。
func _build_walk(root: String) -> void:
	var source := root+"/art_source/actors/hero_walk_pilot_v3/"
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source+"build.json"))
	var image := Image.load_from_file(source+"source.png")
	var source_size := Vector2i(spec.sourceFrame[0],spec.sourceFrame[1])
	assert(image.get_size()==source_size*Vector2i(spec.frames,1))
	assert(image.detect_alpha()!=Image.ALPHA_NONE)
	var size := Vector2i(spec.frameSize[0],spec.frameSize[1])
	var atlas := Image.create(size.x,size.y*int(spec.frames),false,Image.FORMAT_RGBA8)
	var scaled := Vector2i((Vector2(source_size)*float(spec.scale)).round())
	var offset := Vector2i(spec.pivot[0],spec.pivot[1])-Vector2i((Vector2(spec.sourcePivot[0],spec.sourcePivot[1])*float(spec.scale)).round())
	assert(Rect2i(Vector2i.ZERO,size).encloses(Rect2i(offset,scaled)))
	for index in range(spec.frames):
		var frame := image.get_region(Rect2i(Vector2i(index*source_size.x,0),source_size))
		frame.resize(scaled.x,scaled.y,Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(frame,Rect2i(Vector2i.ZERO,scaled),offset+Vector2i(0,index*size.y))
	assert(atlas.save_png(root+"/assets/art_pilot/hero_walk_se_v3.png")==OK)
	var walk_sources := {"ne":spec.rearWalkSource,"sw":spec.leftWalkSource,"nw":spec.leftRearWalkSource,"s":spec.frontWalkSource}
	var versions := {"ne":"v2","sw":"v1","nw":"v2","s":"v1"}
	for direction in spec.extraWalkSources:
		walk_sources[direction] = spec.extraWalkSources[direction]
		versions[direction] = "v1"
	for facing in walk_sources:
		var rear: Dictionary = walk_sources[facing]
		assert(rear.sourceFrame==spec.sourceFrame and rear.columns==spec.frames)
		var rear_image := Image.load_from_file(source+rear.path)
		assert(rear_image.get_size()==Vector2i(2048,768) and rear_image.detect_alpha()!=Image.ALPHA_NONE)
		var rear_scaled := Vector2i((Vector2(source_size)*float(rear.scale)).round())
		var rear_offset := Vector2i(spec.pivot[0],spec.pivot[1])-Vector2i((Vector2(rear.pivot[0],rear.pivot[1])*float(rear.scale)).round())
		assert(Rect2i(Vector2i.ZERO,size).encloses(Rect2i(rear_offset,rear_scaled)))
		var rear_atlas := Image.create(size.x,size.y*4,false,Image.FORMAT_RGBA8)
		for index in range(4):
			var frame := rear_image.get_region(Rect2i(Vector2i(index*source_size.x,0),source_size))
			if facing in ["s","n","e","w"]:
				_assert_frame_edges(frame)
			frame.resize(rear_scaled.x,rear_scaled.y,Image.INTERPOLATE_LANCZOS)
			rear_atlas.blit_rect(frame,Rect2i(Vector2i.ZERO,rear_scaled),rear_offset+Vector2i(0,index*size.y))
		assert(rear_atlas.save_png(root+"/assets/art_pilot/hero_walk_"+facing+"_"+versions[facing]+".png")==OK)
	var idle_sources := {"se":spec.idleSource,"ne":spec.rearIdleSource,"sw":spec.leftIdleSource,"nw":spec.leftRearIdleSource,"s":spec.frontIdleSource}
	for direction in spec.extraIdleSources:
		idle_sources[direction] = spec.extraIdleSources[direction]
	for direction in idle_sources:
		var idle_spec: Dictionary = idle_sources[direction]
		var idle_frame := _pack_idle(source,idle_spec,size,Vector2i(spec.pivot[0],spec.pivot[1]))
		assert(idle_frame.save_png(root+"/assets/art_pilot/hero_idle_"+direction+"_v3.png")==OK)
	var output := FileAccess.open(root+"/assets/art_pilot/hero_walk_se_v3.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(spec,"  "))
	print("HERO_WALK_BUILT: ",atlas.get_size()," / shared pivot / 4 source poses")

## 以源稿各自的统一标定缩放站姿，放入与行走共用的帧格；不镜像或改变武器持握。
func _pack_idle(source: String, spec: Dictionary, size: Vector2i, pivot: Vector2i) -> Image:
	var idle := Image.load_from_file(source+spec.path)
	assert(idle.get_size()==Vector2i(spec.size[0],spec.size[1]))
	assert(idle.detect_alpha()!=Image.ALPHA_NONE)
	var scaled := Vector2i((Vector2(idle.get_size())*float(spec.scale)).round())
	var offset := pivot-Vector2i((Vector2(spec.pivot[0],spec.pivot[1])*float(spec.scale)).round())
	assert(Rect2i(Vector2i.ZERO,size).encloses(Rect2i(offset,scaled)))
	idle.resize(scaled.x,scaled.y,Image.INTERPOLATE_LANCZOS)
	var frame := Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
	frame.blit_rect(idle,Rect2i(Vector2i.ZERO,scaled),offset)
	return frame

## 固定2×2源格统一倍率打包两类待机或攻击，保留帧间真实差异，不逐帧吸附足尖。
func _build_monster_motion(root: String, state: String) -> void:
	for kind in ["wolf","beetle"]:
		var folder: String = root+"/art_source/actors/"+kind+"_"+state+"_trial_v1/"
		var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder+"build.json"))
		var source := Image.load_from_file(folder+spec.source)
		var cell := Vector2i(spec.sourceFrame[0],spec.sourceFrame[1])
		var size := Vector2i(spec.frameSize[0],spec.frameSize[1])
		assert(source.get_size()==cell*2 and source.detect_alpha()!=Image.ALPHA_NONE)
		var scaled := Vector2i((Vector2(cell)*float(spec.scale)).round())
		var offset := Vector2i(spec.pivot[0],spec.pivot[1])-Vector2i((Vector2(spec.sourcePivot[0],spec.sourcePivot[1])*float(spec.scale)).round())
		assert(Rect2i(Vector2i.ZERO,size).encloses(Rect2i(offset,scaled)))
		var atlas := Image.create(size.x,size.y*4,false,Image.FORMAT_RGBA8)
		for index in range(4):
			var frame := source.get_region(Rect2i(Vector2i(index%2,index/2)*cell,cell))
			_assert_frame_edges(frame)
			frame.resize(scaled.x,scaled.y,Image.INTERPOLATE_LANCZOS)
			atlas.blit_rect(frame,Rect2i(Vector2i.ZERO,scaled),offset+Vector2i(0,index*size.y))
		var output: String = root+"/assets/art_pilot/"+kind+"_"+state+"_v1"
		assert(atlas.save_png(output+".png")==OK)
		FileAccess.open(output+".json",FileAccess.WRITE).store_string(JSON.stringify(spec,"  "))
	print("MONSTER_"+state.to_upper()+"_BUILT")

## 离线逐边检查帧格没有截断可见肢体或混入背景；低于5% alpha的残留仍需棋盘底人工复核。
func _assert_frame_edges(frame: Image) -> void:
	for x in range(frame.get_width()):
		assert(frame.get_pixel(x,0).a<0.05 and frame.get_pixel(x,frame.get_height()-1).a<0.05,"源帧上下边出现可见像素")
	for y in range(frame.get_height()):
		assert(frame.get_pixel(0,y).a<0.05 and frame.get_pixel(frame.get_width()-1,y).a<0.05,"源帧左右边出现可见像素")

## 离线裁切两件独立补给物件，源锚点记录地面接触区中心；输出尺寸与锚点写回生成清单。
func _build_supplies(root: String, manifest: Dictionary) -> void:
	var folder := root+"/art_source/environment/camp_supplies_v1/"
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder+"build.json"))
	var source := Image.load_from_file(folder+"source.png")
	assert(source.get_size()==Vector2i(spec.sourceSize[0],spec.sourceSize[1]))
	assert(source.detect_alpha()!=Image.ALPHA_NONE and source.get_pixel(0,0).a<0.01)
	for kind in spec.objects:
		var entry: Dictionary = spec.objects[kind]
		var rect := Rect2i(entry.crop[0],entry.crop[1],entry.crop[2],entry.crop[3])
		assert(Rect2i(Vector2i.ZERO,source.get_size()).encloses(rect))
		var frame := source.get_region(rect)
		var factor := float(entry.width)/rect.size.x
		var size := Vector2i(entry.width,roundi(rect.size.y*factor))
		var pivot := ((Vector2(entry.sourcePivot[0],entry.sourcePivot[1])-Vector2(rect.position))*factor).round()
		assert(Rect2(Vector2.ZERO,Vector2(size)).has_point(pivot))
		frame.resize(size.x,size.y,Image.INTERPOLATE_LANCZOS)
		assert(frame.save_png(root+"/assets/environment/camp_modular_v1/"+str(kind)+".png")==OK)
		manifest.objects[kind] = {"size":[size.x,size.y],"pivot":[pivot.x,pivot.y]}
	print("CAMP_SUPPLIES_BUILT")

## 按统一格与锚点打包四阶段挥剑；边缘alpha检查防止剑尖跨格截断，不修改像素内容。
func _build_hero_attack(root: String) -> void:
	for direction in ["se","ne","sw","nw","s","n","e","w"]:
		var folder: String = root+"/art_source/actors/hero_attack_"+direction+"_trial_v1/"
		var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder+"build.json"))
		var source := Image.load_from_file(folder+spec.source)
		var cell := Vector2i(spec.sourceFrame[0],spec.sourceFrame[1])
		assert(source.get_size()==cell*Vector2i(spec.columns,int(spec.frames)/int(spec.columns)) and source.detect_alpha()!=Image.ALPHA_NONE)
		var size := Vector2i(spec.frameSize[0],spec.frameSize[1])
		var scaled := Vector2i((Vector2(cell)*float(spec.scale)).round())
		var offset := Vector2i(spec.pivot[0],spec.pivot[1])-Vector2i((Vector2(spec.sourcePivot[0],spec.sourcePivot[1])*float(spec.scale)).round())
		assert(Rect2i(Vector2i.ZERO,size).encloses(Rect2i(offset,scaled)))
		var atlas := Image.create(size.x,size.y*int(spec.frames),false,Image.FORMAT_RGBA8)
		for index in range(spec.frames):
			var frame := source.get_region(Rect2i(Vector2i((index%int(spec.columns))*cell.x,(index/int(spec.columns))*cell.y),cell))
			for x in range(cell.x):
				assert(frame.get_pixel(x,0).a<0.05 and frame.get_pixel(x,cell.y-1).a<0.05,"挥剑上下边缘截断")
			for y in range(cell.y):
				assert(frame.get_pixel(0,y).a<0.05 and frame.get_pixel(cell.x-1,y).a<0.05,"挥剑左右边缘截断")
			frame.resize(scaled.x,scaled.y,Image.INTERPOLATE_LANCZOS)
			atlas.blit_rect(frame,Rect2i(Vector2i.ZERO,scaled),offset+Vector2i(0,index*size.y))
		assert(atlas.save_png(root+"/assets/art_pilot/hero_attack_"+direction+"_v1.png")==OK)
		var output := FileAccess.open(root+"/assets/art_pilot/hero_attack_"+direction+"_v1.json",FileAccess.WRITE)
		output.store_string(JSON.stringify(spec,"  "))
	print("HERO_ATTACK_BUILT")

## 按真实源格打包受击与死亡四阶段，统一缩放与锚点；所有源帧四边须通过透明检查。
func _build_hero_reactions(root: String) -> void:
	for state in ["hit","death"]:
		var folder: String = root+"/art_source/actors/hero_"+state+"_se_trial_v1/"
		var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder+"build.json"))
		var source := Image.load_from_file(folder+spec.source)
		var cell := Vector2i(spec.sourceFrame[0],spec.sourceFrame[1])
		assert(source.get_size()==cell*2 and source.detect_alpha()!=Image.ALPHA_NONE)
		var size := Vector2i(spec.frameSize[0],spec.frameSize[1])
		var scaled := Vector2i((Vector2(cell)*float(spec.scale)).round())
		var offset := Vector2i(spec.pivot[0],spec.pivot[1])-Vector2i((Vector2(spec.sourcePivot[0],spec.sourcePivot[1])*float(spec.scale)).round())
		assert(Rect2i(Vector2i.ZERO,size).encloses(Rect2i(offset,scaled)))
		var atlas := Image.create(size.x,size.y*4,false,Image.FORMAT_RGBA8)
		for index in range(4):
			var frame := source.get_region(Rect2i(Vector2i(index%2,index/2)*cell,cell))
			_assert_frame_edges(frame)
			frame.resize(scaled.x,scaled.y,Image.INTERPOLATE_LANCZOS)
			atlas.blit_rect(frame,Rect2i(Vector2i.ZERO,scaled),offset+Vector2i(0,index*size.y))
		var output: String = root+"/assets/art_pilot/hero_"+state+"_se_v1"
		assert(atlas.save_png(output+".png")==OK)
		FileAccess.open(output+".json",FileAccess.WRITE).store_string(JSON.stringify(spec,"  "))
	print("HERO_REACTIONS_BUILT")
