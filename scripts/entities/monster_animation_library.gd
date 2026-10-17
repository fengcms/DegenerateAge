class_name MonsterAnimationLibrary
extends RefCounted
## 由 tools/build_monster_animation_assets.mjs 生成；只保存已审核图集的路径和帧元数据。
## 纹理由 MonsterAnimationCache 按当前地图载入，不在脚本初始化时全局预载。
const PACKS := {
	"elite_wolf_king": {"pivot": [56,88], "frameSize": [112,112], "states": {
		"idle": {"texture": "res://assets/sprites/monsters/elite_wolf_king/idle_atlas.png", "frames": 7, "fps": 8, "loop": true, "contact": 0},
		"walk": {"texture": "res://assets/sprites/monsters/elite_wolf_king/walk_atlas.png", "frames": 7, "fps": 10, "loop": true, "contact": 0},
		"attack": {"texture": "res://assets/sprites/monsters/elite_wolf_king/attack_atlas.png", "frames": 7, "fps": 12, "loop": false, "contact": 3},
		"hit": {"texture": "res://assets/sprites/monsters/elite_wolf_king/hit_atlas.png", "frames": 7, "fps": 24, "loop": false, "contact": 0},
		"death": {"texture": "res://assets/sprites/monsters/elite_wolf_king/death_atlas.png", "frames": 7, "fps": 10, "loop": false, "contact": 0},
	}},
	"elite_ash_wraith": {"pivot": [56,88], "frameSize": [112,112], "states": {
		"idle": {"texture": "res://assets/sprites/monsters/elite_ash_wraith/idle_atlas.png", "frames": 7, "fps": 8, "loop": true, "contact": 0},
		"walk": {"texture": "res://assets/sprites/monsters/elite_ash_wraith/walk_atlas.png", "frames": 7, "fps": 10, "loop": true, "contact": 0},
		"attack": {"texture": "res://assets/sprites/monsters/elite_ash_wraith/attack_atlas.png", "frames": 7, "fps": 12, "loop": false, "contact": 3},
		"hit": {"texture": "res://assets/sprites/monsters/elite_ash_wraith/hit_atlas.png", "frames": 7, "fps": 24, "loop": false, "contact": 0},
		"death": {"texture": "res://assets/sprites/monsters/elite_ash_wraith/death_atlas.png", "frames": 7, "fps": 10, "loop": false, "contact": 0},
	}},
	"elite_shellback_bug": {"pivot": [56,88], "frameSize": [112,112], "states": {
		"idle": {"texture": "res://assets/sprites/monsters/elite_shellback_bug/idle_atlas.png", "frames": 8, "fps": 8, "loop": true, "contact": 0},
		"walk": {"texture": "res://assets/sprites/monsters/elite_shellback_bug/walk_atlas.png", "frames": 8, "fps": 10, "loop": true, "contact": 0},
		"attack": {"texture": "res://assets/sprites/monsters/elite_shellback_bug/attack_atlas.png", "frames": 8, "fps": 12, "loop": false, "contact": 3},
		"hit": {"texture": "res://assets/sprites/monsters/elite_shellback_bug/hit_atlas.png", "frames": 8, "fps": 24, "loop": false, "contact": 0},
		"death": {"texture": "res://assets/sprites/monsters/elite_shellback_bug/death_atlas.png", "frames": 7, "fps": 10, "loop": false, "contact": 0},
	}},
	"boss_corrupted_beast": {"pivot": [96,152], "frameSize": [192,192], "states": {
		"idle": {"texture": "res://assets/sprites/monsters/boss_corrupted_beast/idle_atlas.png", "frames": 7, "fps": 8, "loop": true, "contact": 0},
		"walk": {"texture": "res://assets/sprites/monsters/boss_corrupted_beast/walk_atlas.png", "frames": 7, "fps": 10, "loop": true, "contact": 0},
		"attack": {"texture": "res://assets/sprites/monsters/boss_corrupted_beast/attack_atlas.png", "frames": 7, "fps": 12, "loop": false, "contact": 3},
		"hit": {"texture": "res://assets/sprites/monsters/boss_corrupted_beast/hit_atlas.png", "frames": 7, "fps": 24, "loop": false, "contact": 0},
		"death": {"texture": "res://assets/sprites/monsters/boss_corrupted_beast/death_atlas.png", "frames": 7, "fps": 10, "loop": false, "contact": 0},
		"stomp": {"texture": "res://assets/sprites/monsters/boss_corrupted_beast/stomp_atlas.png", "frames": 7, "fps": 12, "loop": false, "contact": 4},
		"enrage_summon": {"texture": "res://assets/sprites/monsters/boss_corrupted_beast/enrage_summon_atlas.png", "frames": 8, "fps": 12, "loop": false, "contact": 3},
	}},
}
