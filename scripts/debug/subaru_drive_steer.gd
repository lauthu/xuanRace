extends SceneTree
## 行驶中打方向，从车头前方回看前轮转向表现
var _f := 0
var _car: VehicleBody3D
var _cam: Camera3D

func _initialize() -> void:
	root.get_node("GameState").selected_model_index = 4
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	_car = scene.get_node("Car")

func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		# 等 autoload 的 InputSetup._ready 在第 1 帧注册完动作再按
		Input.action_press("accelerate")
		Input.action_press("steer_left")
	if _f == 90:
		# 相机挂在赛道上空，从车头前方回看
		_cam = Camera3D.new()
		root.add_child(_cam)
		var ahead: Vector3 = _car.global_transform * Vector3(0, 0, 7.0)
		_cam.look_at_from_position(ahead + Vector3(2.5, 2.0, 0.0), _car.global_position + Vector3(0, 0.4, 0), Vector3.UP)
		_cam.make_current()
	elif _f == 100:
		root.get_texture().get_image().save_png("/tmp/subaru_driving_steer.png")
		return true
	return false
