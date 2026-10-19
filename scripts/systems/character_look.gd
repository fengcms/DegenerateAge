class_name CharacterLook
extends RefCounted
## 角色阶段形象（look）解析入口。
##
## 依据 docs/素材设计/15-角色形象与素材方案（阶段形象·八向单层）.md：
## 保留真八向、放弃分层，一个 look 就是一套整体精灵（武器、衣物、头饰全部烘焙在图内）。
## 装备不再驱动素材叠加，而是驱动「整体换成哪一套形象」。
##
## 职责与边界：
##   - 单一事实源是武器模板的 look 字段（data/equipments.json），本模块是唯一解析入口。
##   - 只决定「当前该显示哪套形象」，不做装备语义、不结算属性、不写存档。
##   - 头像不在此处理：头像固定一张，见 HUD。
## 资源全部用 preload 登记，保证进入导出包；新增 look 只需在此补纹理与帧格，
## 世界渲染与人物面板不需要为每档改动代码；换装测试校验所有已登记档位。

## 武器未标注 look、空手、或标注了尚未登记的 look 时统一回退到该形象。
const DEFAULT_LOOK := "look_01"

## look 表：look_id → 世界图集与帧格参数。
## main 关键姿态（列＝方向，行＝姿势帧）、extra 受击/打坐、walk 行走；
## frame 为单帧尺寸（像素），pivot 为帧内脚底锚点（像素）。
## 玩家各 look 使用同一帧格与锚点；人物面板另用独立高清图。
const LOOKS := {
	"look_01": {
		"main": preload("res://assets/sprites/player/guardian/guardian_atlas.png"),
		"extra": preload("res://assets/sprites/player/guardian/guardian_hit_sit_atlas.png"),
		"walk": preload("res://assets/sprites/player/guardian/guardian_walk_atlas.png"),
		"frame": Vector2i(64, 80),
		"pivot": Vector2(32, 64),
		"panel": preload("res://assets/ui/portraits/guardian_panel.png"),
		"animations": {
			"idle": {"texture": preload("res://assets/sprites/player/guardian/animations/guardian_idle_atlas.png"), "frames": 4},
			"walk": {"texture": preload("res://assets/sprites/player/guardian/animations/guardian_walk_atlas.png"), "frames": 8},
			"attack": {"texture": preload("res://assets/sprites/player/guardian/animations/guardian_attack_atlas.png"), "frames": 6},
			"hit": {"texture": preload("res://assets/sprites/player/guardian/animations/guardian_hit_atlas.png"), "frames": 2},
			"death": {"texture": preload("res://assets/sprites/player/guardian/animations/guardian_death_atlas.png"), "frames": 6},
			"sit": {"texture": preload("res://assets/sprites/player/guardian/animations/guardian_sit_atlas.png"), "frames": 4},
		},
		"mounts": {
			"mount_corrupted_wing": {
				"idle": preload("res://assets/sprites/player/guardian/mounts/corrupted_wing_idle_atlas.png"),
				"walk": preload("res://assets/sprites/player/guardian/mounts/corrupted_wing_walk_atlas.png"),
				"frame": Vector2i(128, 128),
				"pivot": Vector2(64, 104),
			},
		},
	},
	"look_02": {
		"main": preload("res://assets/sprites/player/stage_looks/look_02/look_02_idle_atlas.png"),
		"walk": preload("res://assets/sprites/player/stage_looks/look_02/look_02_walk_atlas.png"),
		"frame": Vector2i(64, 80),
		"pivot": Vector2(32, 64),
		"panel": preload("res://assets/ui/portraits/look_02_panel.png"),
		"animations": {
			"idle": {"texture": preload("res://assets/sprites/player/stage_looks/look_02/look_02_idle_atlas.png"), "frames": 4},
			"walk": {"texture": preload("res://assets/sprites/player/stage_looks/look_02/look_02_walk_atlas.png"), "frames": 8},
			"attack": {"texture": preload("res://assets/sprites/player/stage_looks/look_02/look_02_attack_atlas.png"), "frames": 6},
			"hit": {"texture": preload("res://assets/sprites/player/stage_looks/look_02/look_02_hit_atlas.png"), "frames": 2},
			"death": {"texture": preload("res://assets/sprites/player/stage_looks/look_02/look_02_death_atlas.png"), "frames": 6},
			"sit": {"texture": preload("res://assets/sprites/player/stage_looks/look_02/look_02_sit_atlas.png"), "frames": 4},
		},
	},
	"look_03": {
		"main": preload("res://assets/sprites/player/stage_looks/look_03/look_03_idle_atlas.png"),
		"walk": preload("res://assets/sprites/player/stage_looks/look_03/look_03_walk_atlas.png"),
		"frame": Vector2i(64, 80),
		"pivot": Vector2(32, 64),
		"panel": preload("res://assets/ui/portraits/look_03_panel.png"),
		"animations": {
			"idle": {"texture": preload("res://assets/sprites/player/stage_looks/look_03/look_03_idle_atlas.png"), "frames": 4},
			"walk": {"texture": preload("res://assets/sprites/player/stage_looks/look_03/look_03_walk_atlas.png"), "frames": 8},
			"attack": {"texture": preload("res://assets/sprites/player/stage_looks/look_03/look_03_attack_atlas.png"), "frames": 6},
			"hit": {"texture": preload("res://assets/sprites/player/stage_looks/look_03/look_03_hit_atlas.png"), "frames": 2},
			"death": {"texture": preload("res://assets/sprites/player/stage_looks/look_03/look_03_death_atlas.png"), "frames": 6},
			"sit": {"texture": preload("res://assets/sprites/player/stage_looks/look_03/look_03_sit_atlas.png"), "frames": 4},
		},
	},
	"look_04": {
		"main": preload("res://assets/sprites/player/stage_looks/look_04/look_04_idle_atlas.png"),
		"walk": preload("res://assets/sprites/player/stage_looks/look_04/look_04_walk_atlas.png"),
		"frame": Vector2i(64, 80),
		"pivot": Vector2(32, 64),
		"panel": preload("res://assets/ui/portraits/look_04_panel.png"),
		"animations": {
			"idle": {"texture": preload("res://assets/sprites/player/stage_looks/look_04/look_04_idle_atlas.png"), "frames": 4},
			"walk": {"texture": preload("res://assets/sprites/player/stage_looks/look_04/look_04_walk_atlas.png"), "frames": 8},
			"attack": {"texture": preload("res://assets/sprites/player/stage_looks/look_04/look_04_attack_atlas.png"), "frames": 6},
			"hit": {"texture": preload("res://assets/sprites/player/stage_looks/look_04/look_04_hit_atlas.png"), "frames": 2},
			"death": {"texture": preload("res://assets/sprites/player/stage_looks/look_04/look_04_death_atlas.png"), "frames": 6},
			"sit": {"texture": preload("res://assets/sprites/player/stage_looks/look_04/look_04_sit_atlas.png"), "frames": 4},
		},
	},
	"look_05": {
		"main": preload("res://assets/sprites/player/stage_looks/look_05/look_05_idle_atlas.png"),
		"walk": preload("res://assets/sprites/player/stage_looks/look_05/look_05_walk_atlas.png"),
		"frame": Vector2i(64, 80),
		"pivot": Vector2(32, 64),
		"panel": preload("res://assets/ui/portraits/look_05_panel.png"),
		"animations": {
			"idle": {"texture": preload("res://assets/sprites/player/stage_looks/look_05/look_05_idle_atlas.png"), "frames": 4},
			"walk": {"texture": preload("res://assets/sprites/player/stage_looks/look_05/look_05_walk_atlas.png"), "frames": 8},
			"attack": {"texture": preload("res://assets/sprites/player/stage_looks/look_05/look_05_attack_atlas.png"), "frames": 6},
			"hit": {"texture": preload("res://assets/sprites/player/stage_looks/look_05/look_05_hit_atlas.png"), "frames": 2},
			"death": {"texture": preload("res://assets/sprites/player/stage_looks/look_05/look_05_death_atlas.png"), "frames": 6},
			"sit": {"texture": preload("res://assets/sprites/player/stage_looks/look_05/look_05_sit_atlas.png"), "frames": 4},
		},
	},
	"look_06": {
		"main": preload("res://assets/sprites/player/stage_looks/look_06/look_06_idle_atlas.png"),
		"walk": preload("res://assets/sprites/player/stage_looks/look_06/look_06_walk_atlas.png"),
		"frame": Vector2i(64, 80),
		"pivot": Vector2(32, 64),
		"panel": preload("res://assets/ui/portraits/look_06_panel.png"),
		"animations": {
			"idle": {"texture": preload("res://assets/sprites/player/stage_looks/look_06/look_06_idle_atlas.png"), "frames": 4},
			"walk": {"texture": preload("res://assets/sprites/player/stage_looks/look_06/look_06_walk_atlas.png"), "frames": 8},
			"attack": {"texture": preload("res://assets/sprites/player/stage_looks/look_06/look_06_attack_atlas.png"), "frames": 6},
			"hit": {"texture": preload("res://assets/sprites/player/stage_looks/look_06/look_06_hit_atlas.png"), "frames": 2},
			"death": {"texture": preload("res://assets/sprites/player/stage_looks/look_06/look_06_death_atlas.png"), "frames": 6},
			"sit": {"texture": preload("res://assets/sprites/player/stage_looks/look_06/look_06_sit_atlas.png"), "frames": 4},
		},
		"mounts": {
			"mount_corrupted_wing": {
				"idle": preload("res://assets/sprites/player/stage_looks/look_06/mounts/corrupted_wing_idle_atlas.png"),
				"walk": preload("res://assets/sprites/player/stage_looks/look_06/mounts/corrupted_wing_walk_atlas.png"),
				"frame": Vector2i(128, 128),
				"pivot": Vector2(64, 104),
			},
		},
	},
}

## 已提示过「形象素材未到」的 look_id，避免每次换装重复刷日志。
static var _pending_logged: Array[String] = []

## 解析当前穿戴（槽 id → 装备实例）应使用的 look_id：以武器模板的 look 字段为准。
## 空手或武器未标注 look 时回退 DEFAULT_LOOK；标注了但素材尚未到货只影响取图，不改变形象 id。
static func look_id_for(slots: Dictionary) -> String:
	var weapon: Variant = slots.get("weapon")
	if not weapon is Dictionary:
		return DEFAULT_LOOK
	var declared := String(Equipment.template_of(weapon).get("look", ""))
	return declared if not declared.is_empty() else DEFAULT_LOOK

## 取某 look 的图集定义；素材未登记时回退默认 look，保证换装链路不因素材未到而中断。
static func definition(look_id: String) -> Dictionary:
	if LOOKS.has(look_id):
		return LOOKS[look_id]
	_log_pending(look_id)
	return LOOKS[DEFAULT_LOOK]

## 该 look 是否已在 look 表中登记（供校验与测试判断是否需要回退）。
static func is_declared(look_id: String) -> bool:
	return LOOKS.has(look_id)

## 人物面板优先使用独立高清展示图；尚未制作展示图的形象沿用主图集首帧。
## 只在形象变化时调用，不在每帧或每次数值刷新路径上创建裁切资源。
static func panel_texture(look_id: String) -> Texture2D:
	var entry := definition(look_id)
	if entry.has("panel"):
		return entry.panel
	var frame: Vector2i = entry.frame
	var atlas := AtlasTexture.new()
	atlas.atlas = entry.main
	atlas.region = Rect2(0, 0, frame.x, frame.y)
	return atlas

## 记录一次「武器标注了未登记的形象」，提示美术素材尚未到货；同一 look 只提示一次。
static func _log_pending(look_id: String) -> void:
	if _pending_logged.has(look_id):
		return
	_pending_logged.append(look_id)
	push_warning("形象素材未到，%s 暂沿用 %s" % [look_id, DEFAULT_LOOK])
