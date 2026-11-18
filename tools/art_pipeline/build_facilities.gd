extends SceneTree
## 将审核后的单体设施透明源稿打包为运行图与遮挡蒙版；不生成造型、不修改碰撞。
## 在最小Godot项目运行，唯一参数是仓库绝对路径；按固定宽度缩放并记录脚锚。

## 编译已审核设施，验证透明背景，输出可重复构建的PNG与规格清单。
func _initialize() -> void:
	var root := OS.get_cmdline_user_args()[0]
	var manifest := {}
	for kind in ["warehouse"]:
		var source := Image.load_from_file(root+"/art_source/environment/camp_facilities_v1/"+kind+".png")
		assert(source != null and source.get_pixel(0,0).a<0.01,"设施源稿背景不透明")
		var bounds := _visible_bounds(source)
		var piece := source.get_region(bounds)
		var width := 384 if kind=="warehouse" else 320
		var height := roundi(float(piece.get_height())/piece.get_width()*width)
		assert(height<=320,"设施高度超过运行预算")
		piece.resize(width,height,Image.INTERPOLATE_LANCZOS)
		var mask := Image.create(width,height,false,Image.FORMAT_RGBA8)
		for y in range(height):
			for x in range(width):
				var allowed := piece.get_pixel(x,y).a if y<height*0.75 else 0.0
				mask.set_pixel(x,y,Color(allowed,allowed,allowed,1))
		var output := root+"/assets/environment/camp_facilities_v1/"
		assert(piece.save_png(output+kind+".png")==OK)
		assert(mask.save_png(output+kind+"_reveal_mask.png")==OK)
		manifest[kind] = {"size":[width,height],"pivot":[width/2,height-4]}
	FileAccess.open(root+"/assets/environment/camp_facilities_v1/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(manifest,"  ")+"\n")
	print("FACILITIES_BUILD_OK")
	quit()

## 忽略近透明噪点确定裁切框，保留框内原始透明度，不做色键或背景编辑。
func _visible_bounds(image: Image) -> Rect2i:
	var minimum := image.get_size()
	var maximum := Vector2i(-1,-1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x,y).a>0.1:
				minimum = minimum.min(Vector2i(x,y))
				maximum = maximum.max(Vector2i(x,y))
	assert(maximum.x>=0,"设施源稿为空")
	return Rect2i(minimum,maximum-minimum+Vector2i.ONE)
