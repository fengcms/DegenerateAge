extends ColorRect
## 主菜单专用静态背景，置于 HUD 上方、菜单和子面板下方。
## 依赖 GameState 的菜单模式；SceneTree 只保留本次启动的素材路径，场景节点持有一张纹理。
## 不接管存档、暂停或切图；进入游戏后释放纹理，重新回到主菜单仍选用同一素材。

const BACKGROUND_PATHS: Array[String] = [
	"res://assets/ui/menu_backgrounds/rift_gate.png",
	"res://assets/ui/menu_backgrounds/ember_refuge.png",
	"res://assets/ui/menu_backgrounds/guardian_expedition.png",
]
const SESSION_KEY := &"main_menu_background_path"

var _picture: TextureRect

## 构建等比铺满的图片层；不随菜单按钮隐藏，保证设置和存档页面保持相同背景。
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color("171a21")
	mouse_filter = Control.MOUSE_FILTER_STOP
	_picture = TextureRect.new()
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)
	set_active(GameState.menu_mode == "menu")

## 首次调用用独立随机源等概率选一张；路径保存在本次 SceneTree，不影响战斗随机序列或存档。
func session_background_path() -> String:
	var tree := get_tree()
	if not tree.has_meta(SESSION_KEY):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		tree.set_meta(SESSION_KEY, BACKGROUND_PATHS[rng.randi_range(0, BACKGROUND_PATHS.size() - 1)])
	return str(tree.get_meta(SESSION_KEY))

## 仅在菜单模式变更时加载/释放单张纹理；文件失效时保留不透底的深色背景。
func set_active(active: bool) -> void:
	visible = active
	if not active:
		_picture.texture = null
		return
	if _picture.texture != null:
		return
	var path := session_background_path()
	if ResourceLoader.exists(path):
		_picture.texture = load(path) as Texture2D
	else:
		push_warning("[MainMenuBackground] 主菜单背景缺失：" + path)
