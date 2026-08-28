class_name CarController
extends VehicleBody3D
## 街机风格的车辆物理控制。
## 基于 Godot 内置 VehicleBody3D：前轮转向、后轮驱动，支持刹车与倒车。
## 手感参数均以 @export 暴露，可在编辑器中直接调节。

@export var max_engine_force := 3000.0 ## 最大驱动力
@export var max_brake_force := 90.0 ## 最大刹车力
@export var max_steer_angle := 0.55 ## 低速时前轮最大转角（弧度）
@export var max_yaw_rate := 0.8 ## 最大横摆角速度（弧度/秒），限制车身旋转速度，防止"天旋地转"
@export var steer_speed := 4.0 ## 转向响应速度（越大越灵敏）
@export var reverse_ratio := 0.5 ## 倒车动力相对前进动力的比例
@export var upright_strength := 800.0 ## 扶正力矩（N·m），阻止翻滚并缓慢扶正侧翻车辆
@export var yaw_damp_strength := 1200.0 ## 超速横摆阻尼（N·s·m），轮胎打滑后抑制旋转失控
@export var rescue_delay := 1.5 ## 翻车多少秒后自动扶正
@export var downforce_factor := 2.5 ## 下压力系数（N·s²/m²），速度越快越"吸地"，提升高速稳定性
@export var water_drag := 150.0 ## 涉水阻力系数（N·s/m）
@export var water_engine_factor := 0.6 ## 涉水时动力保留比例

const WHEELBASE := 3.2 ## 轴距（米），用于横摆角速度换算转角

const VISUAL_Y_OFFSET := 0.4 ## 模型视觉下沉量：补偿悬挂静止高度，让轮胎贴地

const FIT_LENGTH := 4.5 ## 模型车长对齐目标（米）

const DEFAULT_MODEL := { "name": "F1 赛车", "path": "res://assets/kenney_racing_kit/models/raceCarRed.glb", "yaw": 0.0 }

## 翻车被自动扶正时发出（HUD 用于提示）
signal car_rescued

var _steer_target := 0.0
var _inverted_time := 0.0
var _shape := TrackShapes.Shape.ELLIPSE
var _wheels: Array[Dictionary] = [] ## {pivot, front, radius} 自动识别的车轮
var _wheel_angle := 0.0 ## 车轮累计滚动角度


func _ready() -> void:
	# 按 GameState 中的选择加载车身模型并换色（调试环境无 Autoload 时用默认配置）
	var model_cfg: Dictionary = DEFAULT_MODEL
	var paint := Color(0.91, 0.33, 0.33)
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		model_cfg = game_state.get_selected_model()
		paint = game_state.get_selected_color()["color"]
		_shape = game_state.get_selected_track()["shape"]
	var model: Node3D = load(model_cfg["path"]).instantiate()
	_strip_embedded_vehicle_wheels(model)
	# 自动缩放到碰撞体尺寸并居中（车长对齐 FIT_LENGTH）
	CarRecolor.autofit(model, FIT_LENGTH, model_cfg.get("yaw", 0.0))
	model.position.y -= VISUAL_Y_OFFSET
	$Model.add_child(model)
	if model_cfg.get("parts", false):
		# 分件模型（Generate in Parts，无贴图）：按部件角色配色
		CarRecolor.colorize_parts(model, paint)
	elif model_cfg.get("recolor", true):
		# 贴图模型（如 AI 生成）不换色，保留原生材质
		CarRecolor.apply(model, paint)
	# 玻璃补丁：AI 模型有些车窗融合在车壳里，按车身比例贴一块玻璃
	for patch: Dictionary in model_cfg.get("glass_patches", []):
		_add_glass_patch(model, patch)
	_setup_wheels(model)


## 剥离模型自带的 VehicleWheel3D 节点（替换为普通 Node3D），
## 避免它们作为本车额外的物理车轮参与模拟（如某些车模文件内嵌的情况）
func _strip_embedded_vehicle_wheels(model: Node3D) -> void:
	for node in model.find_children("*", "VehicleWheel3D", true, false):
		var plain := Node3D.new()
		plain.name = node.name
		plain.transform = node.transform
		var parent := node.get_parent()
		parent.add_child(plain)
		parent.move_child(plain, node.get_index())
		for child in node.get_children():
			node.remove_child(child)
			plain.add_child(child)
		node.queue_free()


## 自动识别模型中的车轮节点，包一层轴心枢轴以便滚动/转向动画。
## 兼容：Quaternius（FrontWheel_L/R、BackWheels）、
##       Kenney Car Kit（wheel-front-left 等）、Racing Kit（wheelBackLeft 等）
func _setup_wheels(model: Node3D) -> void:
	var meshes := CarRecolor.collect_meshes(model)
	# 车身（最大网格）体积作为参照，轮子是小得多的圆饼形部件
	var body := CarRecolor._find_body_mesh(meshes)
	var body_volume := 1.0
	if body != null and body.mesh != null:
		var bs: Vector3 = body.get_aabb().size
		body_volume = maxf(bs.x * bs.y * bs.z, 0.001)

	var wheel_nodes: Array[MeshInstance3D] = []
	for mi in meshes:
		var lower := mi.name.to_lower()
		if "wheel" in lower or "tire" in lower:
			wheel_nodes.append(mi)
		elif _looks_like_wheel(mi, body_volume):
			wheel_nodes.append(mi)
	for wheel in wheel_nodes:
		# 用网格在轮子局部坐标系下的包围盒中心作为轮轴心
		# （compute_local_aabb 不应用轮子自身变换，全局变换只乘一次）
		var aabb := CarRecolor.compute_local_aabb(wheel)
		if aabb.size.is_zero_approx():
			continue
		var center := wheel.global_transform * aabb.get_center()
		var pivot := Node3D.new()
		model.add_child(pivot)
		# 枢轴与车体对齐（无旋转），轮子重挂到枢轴下且保持全局变换不变
		pivot.global_transform = Transform3D(Basis(), center)
		var global := wheel.global_transform
		wheel.get_parent().remove_child(wheel)
		pivot.add_child(wheel)
		wheel.global_transform = global
		# 前后轮按在车体 Z 轴上的位置区分（车头为 +Z）；高位部件（后视镜等）排除
		var local_pos := to_local(center)
		if local_pos.y > 0.7:
			pivot.queue_free()
			continue
		# 半径换算到世界尺寸（局部 AABB 未含节点缩放）
		var world_radius := wheel.global_transform.basis.get_scale().y * aabb.size.y * 0.5
		_wheels.append({
			"pivot": pivot,
			"front": local_pos.z > 0.0 if not "back" in wheel.name.to_lower() else false,
			"radius": maxf(world_radius, 0.1),
		})


func _looks_like_wheel(mi: MeshInstance3D, body_volume: float) -> bool:
	return CarRecolor.looks_like_wheel(mi, body_volume)


## 玻璃补丁：在车身指定面的比例区域内贴一块蓝灰玻璃薄板。
## x_range/y_range 为车身包围盒的比例区间（0~1），face 支持 rear/front
## 坐标在车体系计算，补丁挂在未变换的 $Model 包装节点下
func _add_glass_patch(model: Node3D, patch: Dictionary) -> void:
	var body := CarRecolor._find_body_mesh(CarRecolor.collect_meshes(model))
	if body == null:
		return
	# 此时车未摆位，global 即车体系
	var model_aabb := CarRecolor.compute_aabb(model)  # 车体系（含缩放/旋转后）
	var body_aabb := CarRecolor.compute_local_aabb(body)
	var xr: Array = patch["x_range"]
	var yr: Array = patch["y_range"]
	var center := body.global_transform * Vector3(
		body_aabb.position.x + body_aabb.size.x * (xr[0] + xr[1]) * 0.5,
		body_aabb.position.y + body_aabb.size.y * (yr[0] + yr[1]) * 0.5,
		0.0
	)
	var face: String = patch.get("face", "rear")
	# 贴在车身壳体最外侧面外 1cm（用车壳包围盒，避免被备胎等外挂件顶出去）
	var body_rear_z: float = (body.global_transform * Vector3(0, 0, body_aabb.position.z)).z
	var body_front_z: float = (body.global_transform * Vector3(0, 0, body_aabb.position.z + body_aabb.size.z)).z
	center.z = body_rear_z - 0.01 if face == "rear" else body_front_z + 0.01

	var pane := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(
		body_aabb.size.x * (xr[1] - xr[0]) * absf(model.scale.x),
		body_aabb.size.y * (yr[1] - yr[0]) * absf(model.scale.y),
		0.02
	)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.18, 0.28, 0.38, 0.92)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	box.material = glass
	pane.mesh = box
	pane.position = center
	$Model.add_child(pane)


func _animate_wheels(delta: float, forward_speed: float) -> void:
	if _wheels.is_empty():
		return
	# 平均半径估算滚动角速度（视觉近似即可）
	var radius: float = _wheels[0]["radius"]
	_wheel_angle += forward_speed / maxf(radius, 0.1) * delta
	for wheel in _wheels:
		var pivot: Node3D = wheel["pivot"]
		pivot.rotation.x = _wheel_angle
		if wheel["front"]:
			pivot.rotation.y = steering


func _physics_process(delta: float) -> void:
	var throttle := Input.get_action_strength("accelerate")
	var braking := Input.get_action_strength("brake")
	var steer_input := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")

	# 沿车头方向（+Z，本工程中 VehicleBody3D 的前进方向）的速度，用于区分刹车与倒车
	var forward_speed := transform.basis.z.dot(linear_velocity)

	if braking > 0.0 and forward_speed > 1.0:
		engine_force = 0.0
		brake = braking * max_brake_force
	elif braking > 0.0:
		brake = 0.0
		engine_force = -braking * max_engine_force * reverse_ratio
	else:
		brake = 0.0
		engine_force = throttle * max_engine_force

	# 横摆角速度限制：由目标过弯转速反推允许的前轮转角（δ = atan(ω·L/v)），
	# 保证任何车速下满打方向，车身转速都不超过 max_yaw_rate
	var speed := absf(forward_speed)
	var steer_limit := max_steer_angle
	if speed > 2.0:
		steer_limit = minf(max_steer_angle, atan(max_yaw_rate * WHEELBASE / speed))
	_steer_target = steer_input * steer_limit
	steering = move_toward(steering, _steer_target, steer_speed * delta)

	# 车轮动画：随速度滚动，前轮随方向盘偏转
	_animate_wheels(delta, forward_speed)

	# 空气下压力：随速度平方增长，高速时把车"按"在路面上
	apply_central_force(Vector3.DOWN * downforce_factor * forward_speed * forward_speed)

	# 涉水：水流阻力 + 动力衰减
	if TrackShapes.is_in_water(_shape, global_position):
		engine_force *= water_engine_factor
		apply_central_force(-linear_velocity * water_drag)
		apply_torque(-angular_velocity * 300.0)

	_apply_stability_assists(delta)


## 稳定性辅助：扶正力矩 + 横摆阻尼 + 翻车自动救援
func _apply_stability_assists(delta: float) -> void:
	var up := transform.basis.y

	# 扶正力矩：把车体"上"方向拉向世界上方。
	# 侧倾时回正，完全翻车（up.y<0）时也持续施加，配合阻尼缓慢翻回
	var correction := up.cross(Vector3.UP)
	apply_torque(correction * upright_strength)

	# 横摆阻尼：角速度超过目标转速上限时施加反向力矩。
	# 转向角受限只能预防"输入过快"，轮胎打滑后的自旋需要阻尼兜底
	var yaw := angular_velocity.y
	var yaw_cap := max_yaw_rate * 1.3
	if absf(yaw) > yaw_cap:
		apply_torque(Vector3.UP * (-signf(yaw) * (absf(yaw) - yaw_cap) * yaw_damp_strength))

	# 翻车检测：基本底朝天且持续一段时间 → 原地扶正（防止卡死）
	if up.y < 0.2:
		_inverted_time += delta
		if _inverted_time >= rescue_delay:
			_rescue_upright()
	else:
		_inverted_time = 0.0


## 原地扶正车辆（保留朝向，清空速度）
func _rescue_upright() -> void:
	var t := global_transform
	var flat_forward := Vector3(t.basis.z.x, 0.0, t.basis.z.z)
	if flat_forward.length_squared() < 0.01:
		flat_forward = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	flat_forward = flat_forward.normalized()
	# 本车前进方向为 +Z，Basis.looking_at 使 -Z 朝向目标，故取反
	var new_basis := Basis.looking_at(-flat_forward, Vector3.UP)
	global_transform = Transform3D(new_basis, t.origin + Vector3.UP * 0.5)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_inverted_time = 0.0
	car_rescued.emit()


func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6
