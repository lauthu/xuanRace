extends SceneTree
var _f := 0
var _car: VehicleBody3D

func _initialize() -> void:
	root.get_node("GameState").selected_model_index = 2
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	_car = scene.get_node("Car")

func _process(_d: float) -> bool:
	_f += 1
	_car.engine_force = 3000.0
	if _f == 5:
		var fronts := 0
		for w in _car._wheels:
			if w["front"]: fronts += 1
		print("轮子: ", _car._wheels.size(), " 前轮: ", fronts)
	elif _f == 140:
		root.get_texture().get_image().save_png("/tmp/tex_charger.png")
		return true
	return false
