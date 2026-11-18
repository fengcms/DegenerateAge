extends SceneTree
## 将样板主角五状态八方向无损重排为正式角色横方向、纵帧图集；不重绘、不镜像。
## 参数为仓库绝对路径，--check只读逐像素比对源包与运行包；打坐和骑乘保留既有资产。
const DIRECTIONS := ["s","sw","w","nw","n","ne","e","se"]

## 独立最小项目执行，避免导入完整游戏；输出可复核源稿和正式运行资源。
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size()>0)
	var root := args[0]
	var check_only := "--check" in args
	var source_folder := root+"/art_source/actors/hero_formal_v1/"
	var runtime_folder := root+"/assets/sprites/player/guardian_modular_v1/"
	for folder in [source_folder,runtime_folder]:
		if not check_only:
			DirAccess.make_dir_recursive_absolute(folder)
	for state: String in ["idle","walk","attack","hit","death"]:
		var count := 1 if state=="idle" else 4
		var packed := Image.create(896,128*count,false,Image.FORMAT_RGBA8)
		for direction in range(8):
			var suffix: String = DIRECTIONS[direction]
			var version := "v3" if state=="idle" or (state=="walk" and suffix=="se") else "v2" if state=="walk" and suffix in ["ne","nw"] else "v1"
			var input := root+"/assets/art_pilot/hero_"+state+"_"+suffix+"_"+version+".png"
			var source := Image.load_from_file(input)
			assert(source.get_size()==Vector2i(112,128*count))
			packed.blit_rect(source,Rect2i(0,0,112,128*count),Vector2i(direction*112,0))
		for folder in [source_folder,runtime_folder]:
			var output: String = folder+state+"_atlas.png"
			if check_only:
				assert(Image.load_from_file(output).get_data()==packed.get_data(),"主角图集像素不一致："+output)
			else:
				assert(packed.save_png(output)==OK)
	print("FORMAL_HERO_PACKED_OK: 8 directions / 5 states / lossless")
	quit()
