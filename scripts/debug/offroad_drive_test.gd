extends SceneTree

var _frame := 0
var _car: VehicleBody3D

func _initialize() -> void:
	root.get_node("GameState").selected_track_index = 2
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	_car = scene.get_node("Car")

func _process(_delta: float) -> bool:
	_frame += 1
	_car.engine_force = 2000.0
	if _frame % 60 == 0:
		var up := _car.global_transform.basis.y
		print("f=", _frame, " speed=%d km/h" % int(_car.linear_velocity.length() * 3.6),
			" y=%.2f" % _car.global_position.y, " up.y=%.2f" % up.y)
	if _frame == 240:
		root.get_texture().get_image().save_png("/tmp/offroad_drive.png")
		return true
	return false
