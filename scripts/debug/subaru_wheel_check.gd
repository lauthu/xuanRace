extends SceneTree
## 冻结车身，前轮定点旋转 4 角度 + 转向角各截图，排除车动干扰
var _f := 0
var _car: VehicleBody3D
var _cam: Camera3D
var _angles := [0.0, PI / 2, PI, PI * 1.5]

func _initialize() -> void:
	root.get_node("GameState").selected_model_index = 4
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	_car = scene.get_node("Car")

func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		_car.freeze = true  # 悬架不再沉降，车身固定
		_cam = Camera3D.new()
		_car.add_child(_cam)  # 相机挂在车上，随车局部坐标固定
		_cam.look_at_from_position(
			_car.global_transform * Vector3(-1.9, 0.75, 2.4),
			_car.global_transform * Vector3(-0.83, 0.1, 1.33), Vector3.UP)
		_cam.make_current()
		_spin(0.0, 0.0)
	elif _f >= 20 and (_f - 20) % 12 == 0 and _f < 20 + 4 * 12:
		var i := (_f - 20) / 12
		_spin(_angles[i], 0.0)
	elif _f >= 21 and (_f - 21) % 12 == 0 and _f < 20 + 4 * 12:
		root.get_texture().get_image().save_png("/tmp/subaru_spin_%d.png" % ((_f - 21) / 12))
	elif _f == 20 + 4 * 12 + 2:
		_spin(0.0, 0.4)  # 纯转向角
	elif _f == 20 + 4 * 12 + 10:
		root.get_texture().get_image().save_png("/tmp/subaru_steer.png")
		return true
	return false

func _spin(spin: float, steer: float) -> void:
	for w in _car._wheels:
		if w["front"]:
			(w["pivot"] as Node3D).rotation = Vector3(spin, steer, 0.0)
