extends SceneTree
## 编译已审核的透明八向转面源图为横向游戏图集；只做确定性分格、透明边裁切、缩放和脚锚对齐。
## 参数：仓库绝对路径、规格JSON相对路径，可加--check逐像素核对已有运行图；不生成或镜像造型。

## 读取显式规格并逐图检查透明背景、帧边界与输出预算，失败不得视为构建成功。
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size()>=2)
	var root := args[0]
	var specs: Array = JSON.parse_string(FileAccess.get_file_as_string(root+"/"+args[1]))
	for spec: Dictionary in specs:
		var source := Image.load_from_file(root+"/"+String(spec.source))
		assert(source != null and source.get_pixel(0,0).a<0.01,"源图不是透明背景")
		var frame := Vector2i(spec.frame[0],spec.frame[1])
		var pivot := Vector2i(spec.pivot[0],spec.pivot[1])
		var poses := int(spec.get("poses",1))
		var output := Image.create(frame.x*8,frame.y*poses,false,Image.FORMAT_RGBA8)
		for pose_index in range(poses):
			for direction in range(8):
				var col := direction%4
				var row := direction/4+pose_index*2
				var start := Vector2i(floori(col*source.get_width()/4.0),floori(row*source.get_height()/(2.0*poses)))
				var end := Vector2i(floori((col+1)*source.get_width()/4.0),floori((row+1)*source.get_height()/(2.0*poses)))
				var cell := source.get_region(Rect2i(start,end-start))
				var used := _visible_bounds(cell)
				assert(used.has_area(),"源图方向为空")
				assert(used.position.x>1 and used.position.y>1 and used.end.x<cell.get_width()-1 and used.end.y<cell.get_height()-1,"角色触及分格边界，需修正源图")
				var piece := cell.get_region(used)
				var height := int(spec.height)
				var width := roundi(float(piece.get_width())/piece.get_height()*height)
				assert(width<=frame.x-8 and height<=pivot.y,"运行角色超出帧预算")
				piece.resize(width,height,Image.INTERPOLATE_LANCZOS)
				output.blit_rect(piece,Rect2i(Vector2i.ZERO,piece.get_size()),Vector2i(direction*frame.x+pivot.x-width/2,pose_index*frame.y+pivot.y-height))
		var path := root+"/"+String(spec.output)
		if "--check" in args:
			assert(Image.load_from_file(path).get_data()==output.get_data(),"运行图集未与源稿同步："+path)
		else:
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			assert(output.save_png(path)==OK)
	print("TURNTABLE_BUILD_OK: ",specs.size()," sheets / 8 directions / alpha preserved")
	quit()

## 以10%透明度检测主体边界，忽略生成器近透明背景噪点；裁切内部仍保留原始alpha。
func _visible_bounds(image: Image) -> Rect2i:
	var minimum := image.get_size()
	var maximum := Vector2i(-1,-1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x,y).a>0.1:
				minimum = minimum.min(Vector2i(x,y))
				maximum = maximum.max(Vector2i(x,y))
	return Rect2i(minimum,maximum-minimum+Vector2i.ONE) if maximum.x>=0 else Rect2i()
