extends SceneTree
## GP 赛道行驶测试：全油门 4 秒，验证公路碰撞与行驶。

var _frame := 0
var _car: VehicleBody3D

func _initialize() -> void:
	root.get_node("GameState").selected_track_index = 0
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	_car = scene.get_node("Car")

func _process(_delta: float) -> bool:
	_frame += 1
	_car.engine_force = 2000.0
	if _frame % 60 == 0:
		var up := _car.global_transform.basis.y
		print("f=", _frame, " speed=%d km/h" % int(_car.linear_velocity.length() * 3.6),
			" y=%.3f" % _car.global_position.y, " up.y=%.2f" % up.y)
	if _frame == 240:
		return true
	return false
