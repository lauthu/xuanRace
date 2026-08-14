extends SceneTree
## 车轮动画验证：选极速跑车，直行+转向，两帧截图对比轮子转动。

var _frame := 0
var _scene: Node
var _car: VehicleBody3D

func _initialize() -> void:
	root.get_node("GameState").selected_model_index = 0  # 极速跑车
	root.get_node("GameState").selected_track_index = 0  # GP 赛道
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_car = _scene.get_node("Car")
		print("识别到的车轮数: ", _car._wheels.size())
		for w in _car._wheels:
			print("  front=", w["front"], " radius=%.2f" % w["radius"])
	elif _frame > 1:
		_car.engine_force = 1500.0
	if _frame == 90:
		root.get_texture().get_image().save_png("/tmp/wheels_f90.png")
		_car.steering = 0.3  # 打一点转向，看前轮偏转
	elif _frame == 120:
		root.get_texture().get_image().save_png("/tmp/wheels_f120.png")
		print("车轮累计角度: %.2f rad" % _car._wheel_angle)
		return true
	return false
