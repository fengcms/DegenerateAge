class_name CampModuleOccluder
extends Sprite2D
## 正式营地树冠/屋顶轮廓蒙版的局部淡出控制；只改材质，不改变通行、碰撞和脚底排序。
## 每对象缓存一次图像用于少量轮廓探测；人物位置不变时只推进尚未结束的淡入淡出。
const REVEAL_SHADER = preload("res://scripts/world/camp_module_reveal.gdshader")
var mask_texture: Texture2D
var target_reveal := false
var reveal_amount := 0.0
var mask_image: Image
var reveal_material: ShaderMaterial
var last_actor_position := Vector2.INF
var actor: Node2D

## 在物件建立后缓存轮廓蒙版，创建独立参数材质，共用同一shader资源。
func _ready() -> void:
	assert(mask_texture != null and mask_texture.get_size()==texture.get_size())
	mask_image = mask_texture.get_image()
	reveal_material = ShaderMaterial.new()
	reveal_material.shader = REVEAL_SHADER
	reveal_material.set_shader_parameter("reveal_mask",mask_texture)
	reveal_material.set_shader_parameter("radius_uv",Vector2(42,72)/scale/Vector2(texture.get_size()))
	material = reveal_material

## 仅人物在物件后方且头身采样点与允许淡出的轮廓区域重叠时触发，透明空洞不算遮挡。
func overlaps_actor(actor_position: Vector2) -> bool:
	if actor_position.y >= position.y:
		return false
	var rect := get_rect()
	for dx in [-18.0,0.0,18.0]:
		for dy in [-80.0,-58.0,-36.0]:
			var local := (actor_position+Vector2(dx,dy)-position)/scale
			var uv := (local-rect.position)/rect.size
			if uv.x>=0 and uv.x<1 and uv.y>=0 and uv.y<1:
				var point := Vector2i(uv*Vector2(mask_image.get_size()))
				if mask_image.get_pixelv(point).r>0.2:
					return true
	return false

## 由物件更新流程调用，位置变化才重算遮挡；0.2秒过渡，无新节点和纹理分配。
func update_reveal(actor_position: Vector2, delta: float) -> void:
	if actor_position != last_actor_position:
		last_actor_position = actor_position
		target_reveal = overlaps_actor(actor_position)
		var rect := get_rect()
		var focus := (actor_position+Vector2(0,-54)-position)/scale
		reveal_material.set_shader_parameter("focus_uv",(focus-rect.position)/rect.size)
	var next := move_toward(reveal_amount,1.0 if target_reveal else 0.0,delta*5.0)
	if not is_equal_approx(next,reveal_amount):
		reveal_amount = next
		reveal_material.set_shader_parameter("reveal_amount",reveal_amount)

## 缓存当前地图玩家引用；退出地图时随物件释放，不在热路径扫描所有实体。
func _process(delta: float) -> void:
	if not is_instance_valid(actor):
		actor = get_tree().get_first_node_in_group("player") as Node2D
	if actor != null:
		update_reveal(actor.global_position,delta)
