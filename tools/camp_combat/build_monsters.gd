extends SceneTree
## 战斗样板怪物方向图集离线构建：只做确定性分格、等比缩放和打包，保留生成alpha。
## 每源页4列5行，对应待机/行走/攻击/受击/倒地各四帧；源图不进入运行依赖。
const STATES := ["idle","walk","attack","hit","death"]
const DIRECTIONS := ["ne","nw","e","w","n","s","se"]

## 从命令行唯一仓库路径读取源清单；边缘污染、尺寸或裁切不合法立即失败，不发布残缺清单。
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size()==1)
	var root: String = args[0]
	var output := root+"/assets/art_pilot/combat_monsters_v1"
	DirAccess.make_dir_recursive_absolute(output)
	var catalog: Dictionary = {}
	for kind: String in ["wolf","beetle"]:
		catalog[kind] = {}
		for direction: String in DIRECTIONS:
			var folder := root+"/art_source/actors/"+kind+"_"+direction+"_combat_v1"
			if not FileAccess.file_exists(folder+"/build.json"):
				continue
			var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder+"/build.json"))
			assert(spec.columns==4 and spec.rows==5 and Vector2i(spec.frameSize[0],spec.frameSize[1])==Vector2i(128,96) and Vector2i(spec.pivot[0],spec.pivot[1])==Vector2i(64,80))
			assert(float(spec.scale)>0)
			var source := Image.load_from_file(folder+"/"+String(spec.source))
			assert(source.get_size()==Vector2i(spec.sourceSize[0],spec.sourceSize[1]))
			catalog[kind][direction] = {}
			for row in range(5):
				var atlas := Image.create(128,384,false,Image.FORMAT_RGBA8)
				for column in range(4):
					var origin := Vector2i(floori(column*source.get_width()/4.0),floori(row*source.get_height()/5.0))
					var size := Vector2i(source.get_width()/4,source.get_height()/5)
					var tile := source.get_region(Rect2i(origin,size))
					if not _edges_clean(tile):
						push_error("源帧边缘污染："+kind+"/"+direction+"/"+str(row)+"/"+str(column))
						quit(1)
						return
					var scale_factor := float(spec.scale)
					var resized := Vector2i(roundi(size.x*scale_factor),roundi(size.y*scale_factor))
					tile.resize(resized.x,resized.y,Image.INTERPOLATE_LANCZOS)
					var anchor := Vector2(float(size.x)*0.5,float(size.y)*0.96)*scale_factor
					var destination := Vector2i(64-roundi(anchor.x),column*96+80-roundi(anchor.y))
					assert(destination.x>=0 and destination.x+resized.x<=128)
					assert(destination.y>=column*96 and destination.y+resized.y<=(column+1)*96)
					atlas.blit_rect(tile,Rect2i(Vector2i.ZERO,resized),destination)
				var filename: String = kind+"_"+STATES[row]+"_"+direction+".png"
				assert(atlas.save_png(output+"/"+filename)==OK)
				catalog[kind][direction][STATES[row]] = filename
	var file := FileAccess.open(output+"/manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frameSize":[128,96],"pivot":[64,80],"frames":4,"packs":catalog},"  "))
	print("COMBAT_MONSTERS_BUILT: ",catalog)
	quit()

## 每格四边alpha不得超过0.05，避免格线、背景和相邻角色进入运行帧；不以程序抠图掩盖坏稿。
func _edges_clean(tile: Image) -> bool:
	for x in range(tile.get_width()):
		if maxf(tile.get_pixel(x,0).a,tile.get_pixel(x,tile.get_height()-1).a)>0.05:
			return false
	for y in range(tile.get_height()):
		if maxf(tile.get_pixel(0,y).a,tile.get_pixel(tile.get_width()-1,y).a)>0.05:
			return false
	return true
