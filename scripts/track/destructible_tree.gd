class_name DestructibleTree
extends Node3D
## 野外区域的树：自带树干碰撞体（硬障碍）。
## GameState.destructible_enabled 开启时，车辆以足够速度撞击会
## 把树朝撞击方向撞倒，倒下的树不再阻挡车辆。

@export var min_hit_speed := 3.0 ## 触发撞倒的最低车速（m/s）
@export var fall_duration := 0.9 ## 倒伏动画时长（秒）

var _falling := false


func _ready() -> void:
	$HitArea.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _falling or body is not VehicleBody3D:
		return
	var game_state := get_node_or_null("/root/GameState")
	if game_state == null or not game_state.destructible_enabled:
		return
	if body.linear_velocity.length() < min_hit_speed:
		return
	_knock_down(body)


func _knock_down(car: VehicleBody3D) -> void:
	_falling = true
	# 撞倒后树干不再阻挡车辆
	$Trunk.set_deferred("collision_layer", 0)
	$Trunk.set_deferred("collision_mask", 0)
	$HitArea.set_deferred("monitoring", false)

	# 倒伏方向：远离撞击车辆；绕水平轴（垂直于倒伏方向）旋转
	var fall_dir := global_position - car.global_position
	fall_dir.y = 0.0
	if fall_dir.length_squared() < 0.01:
		fall_dir = -car.global_transform.basis.z
	fall_dir = fall_dir.normalized()
	var axis := Vector3.UP.cross(fall_dir).normalized()

	var initial_basis := transform.basis
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_method(
		func(angle: float) -> void: transform.basis = initial_basis.rotated(axis, angle),
		0.0, 1.45, fall_duration
	)
