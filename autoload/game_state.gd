extends Node
## GameState — 全局运行时状态（单例 / Autoload）。
##
## 持有角色、经济、进度、设置的运行时数据；启动时赋予初始参数
## （数值来源：docs/产品文档/04 角色成长系统 4.4 初始值）。
## 不持久化运行时节点对象——存档由 SaveManager 负责序列化这里的数据。

const SCHEMA_VERSION := 1

var player: Dictionary = {}
var gold: int = 0
var current_map: String = "camp"
var quest_states: Dictionary = {}   # quest_id -> state 字符串
var first_clear: Dictionary = {}    # boss_id -> bool（首通标记）
var settings: Dictionary = {}

func _ready() -> void:
	reset_to_defaults()

## 重置为初始状态（新建角色 / 初始化时调用）。
func reset_to_defaults() -> void:
	player = {
		"name": "守护者",
		"level": 1,
		"xp": 0,
		"hp": 102,          # 派生：见 4.3，L1（攻12/防5）=> 102
		"mp": 35,           # 派生：BASE_MP30 + L1×5 => 35
		"attack": 12,
		"defense": 5,
		"criticalChance": 0.05,
		"criticalMultiplier": 1.5,
		"attackInterval": 0.8,
		"movementSpeed": 4.0,
		"dodge": 0,
		"block": 0,         # 首版不做（保留字段）
		"cdr": 0.0,
	}
	gold = 0
	current_map = "camp"
	quest_states = {}
	first_clear = {}
	settings = {
		"autoBattleDefault": false,   # 10.3：重启后自动战斗默认关闭
		"autoPickupDefault": false,
		"potionThreshold": 0.35,      # 3.14 喝药血量阈值
		"searchRadius": 12,           # 3.14 搜索半径（格）
		"allowBoss": false,           # 3.14 自动战斗是否允许 Boss
		"masterVolume": 1.0,
		"sfxVolume": 1.0,
		"uiScale": 1.0,
	}

## 经验升级所需（4.4 公式：round(100 × L^1.6)）。
func xp_to_next(level: int) -> int:
	return int(round(100.0 * pow(float(level), 1.6)))

## 派生的最大生命（4.3 公式，无装备时）。
func max_hp() -> int:
	return int(round(50.0 + player.level * 8.0 + player.attack * 2.0 + player.defense * 4.0))

## 派生的最大法力（4.3 公式，无装备时）。
func max_mp() -> int:
	return int(round(30.0 + player.level * 5.0))
