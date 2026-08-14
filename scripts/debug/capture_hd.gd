extends SceneTree

var _frame := 0
var _scene: Node
var _car: VehicleBody3D

func _initialize() -> void:
	root.get_node("GameState").selected_model_index = 2
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	_car = _scene.get_node("Car")

func _process(_delta: float) -> bool:
	_frame += 1
	_car.engine_force = 3000.0
	if _frame == 130:
		root.get_texture().get_image().save_png("/tmp/hd_race.png")
		return true
	return false
