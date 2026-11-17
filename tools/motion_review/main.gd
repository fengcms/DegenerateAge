extends Node2D
## 动作候选审片器：共享图集在原尺寸、三倍和逐帧条带中显示，供人工判断步态与身份漂移。
## 依赖review.json与独立透明候选源稿；无物理、战斗、存档或正式动画资源注册。
var background_mode := 0
var guide_visible := false
var guide_regions: Array[AtlasTexture] = []
var strip_previews: Array[Sprite2D] = []
var strip_caption: Label
var spec: Dictionary
var atlas: Texture2D
var regions: Array[AtlasTexture] = []
var previews: Array[Sprite2D] = []
var status: Label
var frame := 0
var elapsed := 0.0
var playing := true
var playback_rate := 1.0
var verifying := false

## 启动时一次性创建共享区域资源与固定对照面板；不在播放期间加载图片。
func _ready() -> void:
	spec = JSON.parse_string(FileAccess.get_file_as_string("res://review.json"))
	atlas = load("res://candidate.png")
	var size := Vector2(spec.frameSize[0],spec.frameSize[1])
	assert(atlas.get_size()==Vector2(size.x*spec.columns,size.y*ceili(float(spec.frames)/spec.columns)))
	for index in range(spec.frames):
		var region := AtlasTexture.new()
		region.atlas = atlas
		region.region = Rect2(Vector2(index%int(spec.columns),index/int(spec.columns))*size,size)
		region.filter_clip = true
		regions.append(region)
	if spec.has("guide"):
		var guide: Texture2D = load("res://"+spec.guide)
		assert(guide.get_size()==atlas.get_size())
		for region in regions:
			var copy: AtlasTexture = region.duplicate()
			copy.atlas = guide
			guide_regions.append(copy)
	_text("守护者 · 单方向动作审片",Vector2(30,20),24)
	_text(spec.issues,Vector2(30,58),17,Color(1,0.7,0.45))
	_text("空格 播放/暂停   ← → 单帧检查   1 正常速度   2 慢放   R 回到首帧   B 底色   G 姿态参照",Vector2(30,88),16)
	_text("已认可静态主角",Vector2(55,190),18)
	_text("候选 · 原尺寸",Vector2(265,190),18)
	_text("候选 · 3倍（与原尺寸同步）",Vector2(680,125),18)
	var reference := Sprite2D.new()
	reference.texture = load("res://reference.png")
	reference.position = Vector2(120,370)
	reference.offset.y = -reference.texture.get_height()*0.5
	add_child(reference)
	previews.append(_sprite(0,Vector2(330,370),1))
	previews.append(_sprite(0,Vector2(850,470),3))
	strip_caption = _text("固定坐标逐帧对照 · 不逐帧裁边或缩放对齐",Vector2(30,530),18)
	for index in range(spec.frames):
		var origin := Vector2(180+index*285,715)
		strip_previews.append(_sprite(index,origin,1.5))
		_text("帧 %d"%(index+1),origin+Vector2(-22,20),16)
	status = _text("",Vector2(30,770),16)
	_select(0)
	verifying = "--verify" in OS.get_cmdline_user_args()
	if verifying:
		_verify.call_deferred()

## 创建固定锚点的共享图集精灵；倍率仅用于审片，不生成新帧或改变姿态。
func _sprite(index: int, origin: Vector2, zoom: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = regions[index]
	sprite.centered = false
	sprite.offset = -Vector2(spec.pivot[0],spec.pivot[1])
	sprite.position = origin
	sprite.scale = Vector2.ONE*float(spec.scale)*zoom
	add_child(sprite)
	return sprite

## 建立不拦截键盘或鼠标的说明文字，返回Label供状态栏更新。
func _text(value: String, origin: Vector2, size: int, tint := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = value
	label.position = origin
	label.add_theme_font_size_override("font_size",size)
	label.modulate = tint
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

## 绘制固定屏幕标尺，供判断角色抖动；线条不是游戏地面或伤害区域。
func _draw() -> void:
	draw_rect(Rect2(0,0,1280,800),Color(0.17,0.18,0.19) if background_mode==0 else Color(0.64,0.66,0.68))
	if background_mode==2:
		for y in range(7,24):
			for x in range(40):
				if (x+y)%2==0:
					draw_rect(Rect2(x*32,y*32,32,32),Color(0.4,0.42,0.44))
	for line in [Rect2(50,370,400,0),Rect2(620,470,460,0),Rect2(60,715,1150,0)]:
		draw_line(line.position,line.end,Color(0.45,0.5,0.52),1)

## 同步两个预览的帧；不改变精灵位置、比例或锚点，允许检测原稿本身的漂移。
func _select(index: int) -> void:
	frame = posmod(index,int(spec.frames))
	for preview in previews:
		preview.texture = regions[frame]
	status.text = "帧 %d / %d · %.1f 帧/秒 · %s · 仅审片，未接入营地" % [frame+1,spec.frames,float(spec.fps)*playback_rate,"播放" if playing else "暂停"]

## 按秒推进循环，低帧率时直接跳至正确相位；仅帧变化时切换纹理引用。
func _advance(delta: float) -> void:
	if not playing:
		return
	var period := 1.0/(float(spec.fps)*playback_rate)
	elapsed += delta
	var steps := floori(elapsed/period)
	if steps>0:
		elapsed = fmod(elapsed,period)
		_select(frame+steps)

## 普通播放逐帧推进；自动验收改为显式时间步进，避免窗口调度造成随机结果。
func _process(delta: float) -> void:
	if not verifying:
		_advance(delta)

## 共用输入入口供键盘与验证调用；手动切帧自动暂停并清空时间余量。
func _command(key: int) -> void:
	if key==KEY_B:
		background_mode = (background_mode+1)%3
		queue_redraw()
	elif key==KEY_G and not guide_regions.is_empty():
		guide_visible = not guide_visible
		for index in range(strip_previews.size()):
			strip_previews[index].texture = guide_regions[index] if guide_visible else regions[index]
		strip_caption.text = "姿态参照 · 蓝色左肢 / 红色右肢（仅替换下方条带）" if guide_visible else "固定坐标逐帧对照 · 不逐帧裁边或缩放对齐"
	elif key==KEY_SPACE:
		playing = not playing
	elif key in [KEY_LEFT,KEY_RIGHT]:
		playing = false
		elapsed = 0
		_select(frame+(-1 if key==KEY_LEFT else 1))
	elif key in [KEY_1,KEY_2]:
		playback_rate = 1.0 if key==KEY_1 else 0.5
		elapsed = 0
	elif key==KEY_R:
		elapsed = 0
		_select(0)
	_select(frame)

## 将无重复按键传至同一播放控制入口，不拦截其他窗口事件。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_command(event.keycode)

## 验证审片工具而非美术质量：真实共享资源、边缘透明、同步、暂停、循环与倍率。
func _verify() -> void:
	assert(spec.status=="rejected_for_runtime")
	var pixels := atlas.get_image()
	assert(pixels.detect_alpha()!=Image.ALPHA_NONE)
	for region in regions:
		assert(region.atlas==atlas)
		print("FRAME_BOUNDS: ",region.region.position," ",region.get_image().get_used_rect())
		var origin := Vector2i(region.region.position)
		assert(pixels.get_pixelv(origin).a<0.01,"帧角存在背景污染")
	for point in spec.get("background_probes",[]):
		print("BACKGROUND_ALPHA_PROBE: ",point," alpha=",pixels.get_pixel(point[0],point[1]).a)
	_command(KEY_B)
	assert(background_mode==1)
	_command(KEY_B)
	assert(background_mode==2)
	if not guide_regions.is_empty():
		_command(KEY_G)
		assert(guide_visible and strip_previews[0].texture.atlas==guide_regions[0].atlas)
		assert(previews[0].texture.atlas==atlas,"姿态条带不应替换角色预览")
		_command(KEY_G)
		assert(not guide_visible and strip_previews[0].texture.atlas==atlas)
	var original_position := previews[0].position
	var original_offset := previews[0].offset
	_advance(1.01/float(spec.fps))
	assert(frame==1 and previews[0].texture==previews[1].texture)
	_command(KEY_SPACE)
	_advance(1)
	assert(frame==1)
	_command(KEY_RIGHT)
	assert(frame==2 and not playing)
	_command(KEY_LEFT)
	assert(frame==1)
	_command(KEY_R)
	_command(KEY_2)
	_command(KEY_SPACE)
	_advance(2.01/float(spec.fps))
	assert(frame==1)
	_command(KEY_1)
	_advance(3.01/float(spec.fps))
	assert(frame==0)
	assert(previews[0].position==original_position and previews[0].offset==original_offset)
	assert(previews[1].scale.is_equal_approx(previews[0].scale*3))
	playing = false
	var captures := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			captures = argument.trim_prefix("--capture=")
	if not captures.is_empty():
		queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		for index in range(spec.frames):
			_select(index)
			await RenderingServer.frame_post_draw
			var shot := get_viewport().get_texture().get_image()
			assert(shot.get_pixel(50,400)!=shot.get_pixel(80,400),"棋盘底未渲染")
			shot.save_png(captures+"/frame_%d.png"%index)
		if not guide_regions.is_empty():
			_command(KEY_G)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(captures+"/pose_guide.png")
	print("MOTION_REVIEW_VERIFY_OK: shared atlas / sync / pause / stepping / slow playback / wrap; ART_NOT_APPROVED")
	get_tree().quit()
