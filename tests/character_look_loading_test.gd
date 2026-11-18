extends Node
## 独立进程验证阶段形象按需加载，防止低级角色恢复为全档位预载；不写存档。

## 使用初始形象后高级纹理仍未载入，首次换高级档位才加载，重复查询复用纹理实例。
func _ready() -> void:
	var future := "res://assets/sprites/player/stage_looks/look_06/look_06_idle_atlas.png"
	assert(not ResourceLoader.has_cached(future),"初始进程不应预载未使用形象")
	var initial := CharacterLook.definition("look_01")
	assert(initial.animations.idle.texture is Texture2D)
	assert(not ResourceLoader.has_cached(future),"初始形象不应加载高级纹理")
	var advanced := CharacterLook.definition("look_06")
	assert(ResourceLoader.has_cached(future),"首次换装应加载所需形象")
	assert(advanced.main == CharacterLook.definition("look_06").main,"同形象应复用纹理")
	assert(CharacterLook.definition("look_missing").main == initial.main,"缺失形象沿用默认回退")
	print("[CharacterLookLoadingTest] PASS")
	get_tree().quit()
