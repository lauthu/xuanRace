extends SceneTree
## 综合回归：
## 阶段1 高速甩尾撞墙（旋转抑制）→ 阶段2 底朝天卡死（自动救援）。

var _frame := 0
var _phase := 0
var _scene: Node
var _car: VehicleBody3D
var _spin_frames := 0
var _rescued := false


func _initialize() -> void:
	_load_scene()


func _load_scene() -> void:
	if _scene != null:
		_scene.queue_free()
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_car = _scene.get_node("Car")
		_car.car_rescued.connect(func() -> void: _rescued = true)
		return false

	if _phase == 0:
		# 甩尾测试
		Input.action_press("accelerate")
		if _frame >= 240:
			if (_frame / 30) % 2 == 0:
				Input.action_press("steer_left")
				Input.action_release("steer_right")
			else:
				Input.action_press("steer_right")
				Input.action_release("steer_left")
		if absf(_car.angular_velocity.y) > 1.04:
			_spin_frames += 1
		if _frame == 480:
			print("阶段1 甩尾: 失控旋转 %d 帧（%.2f 秒）, up.y=%.2f" % [
				_spin_frames, _spin_frames / 60.0, _car.global_transform.basis.y.y])
			Input.action_release("accelerate")
			Input.action_release("steer_left")
			Input.action_release("steer_right")
			_phase = 1
			_frame = 0
			_load_scene()
	elif _phase == 1:
		# 底朝天卡死测试
		if _frame == 10:
			var t := _car.global_transform
			_car.global_transform = Transform3D(
				t.basis.rotated(t.basis.z, PI), t.origin + Vector3.UP * 0.3)
			_car.linear_velocity = Vector3.ZERO
			_car.angular_velocity = Vector3.ZERO
		if _frame == 300:
			print("阶段2 卡死: 救援触发=%s, up.y=%.2f" % [
				"是" if _rescued else "否", _car.global_transform.basis.y.y])
			return true
	return false
