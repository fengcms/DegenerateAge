class_name BossSpacing
extends RefCounted
## Boss 对 Boss 的软站位规则：只修正本实例速度，不推动玩家、小怪或其他节点。
## 使用地面空间占位（屏幕纵向压缩一半）；技能锁定期间维持原位，不改预警几何与命中时序。
## 无持久节点引用，每次移动决策扫描当前 enemies；死亡/退场立即不再占位，切图无需释放缓存。

## Boss 主体占地横向半径64px、纵向32px；独立于36px点击半径和武器/光效图集宽度。
## 允许轮廓遮挡，但防止主体中心堆叠；不扩大攻击距离。当前各章统一占地，后续按实机美术校准。
const RADIUS := 64.0
const MARGIN := 12.0
const CORRECTION_SPEED := 48.0
const RESPONSE := 4.0

## 三代技能均将整段施法视为锚点；包括共享组件段间和后摇，不能只检查可见预警。
static func locked(actor: Monster) -> bool:
	return actor._stomp_pending or not actor._chapter_boss_warn.is_empty() \
		or (actor.boss_action != null and actor.boss_action.is_busy())

## 输入世界像素/秒期望速度，返回有界速度；只有调用者自身可移动时使用。
## 近邻法线约束先预防驶入已占位置，再修正已有重叠；同点使用成对相反方向消除对称死锁。
static func steer(actor: Monster, desired: Vector2) -> Vector2:
	if actor.is_dead or not actor.ai_enabled or locked(actor) or actor.move_speed_px <= 0.0:
		return Vector2.ZERO
	var wish := Iso.to_ground(desired)
	var correction := Vector2.ZERO
	var normals: Array[Vector2] = []
	var tangent := Vector2.ZERO
	for node in actor.get_tree().get_nodes_in_group("enemies"):
		var other := node as Monster
		if other == null or other == actor or other.is_dead or other.is_queued_for_deletion() or other._kind() != "boss":
			continue
		var offset := Iso.to_ground(actor.global_position - other.global_position)
		var distance := offset.length()
		if distance >= RADIUS * 2.0 + MARGIN:
			continue
		var normal := offset / distance if distance > 0.001 else _pair_direction(actor, other)
		normals.append(normal)
		correction += normal * maxf(0.0, RADIUS * 2.0 - distance) * RESPONSE
		if wish.dot(normal) < 0.0:
			var side := normal.orthogonal()
			if side.dot(wish) < -0.001:
				side = -side
			tangent += side * wish.length() * 0.6
	# 保留沿邻居切线的接近分量，避免一字队列只减速后永久顶住。
	var result := wish + tangent
	for normal in normals:
		var inward := result.dot(normal)
		if inward < 0.0:
			result -= normal * inward
	result += correction.limit_length(CORRECTION_SPEED * 2.0)
	var limit := minf(actor.current_move_speed(), maxf(desired.length(), CORRECTION_SPEED))
	return Iso.from_ground(result).limit_length(limit)

## 无随机数调用；同一对实例始终获得相反方向，生命周期内方向稳定。
static func _pair_direction(a: Monster, b: Monster) -> Vector2:
	var low := mini(a.get_instance_id(), b.get_instance_id())
	var high := maxi(a.get_instance_id(), b.get_instance_id())
	var angle := float((low * 31 + high * 17) % 360) * PI / 180.0
	var direction := Vector2.from_angle(angle)
	return direction if a.get_instance_id() == low else -direction
