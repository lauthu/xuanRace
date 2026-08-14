extends SceneTree
## 全部车型车轮识别回归

var _frame := 0
var _scene: Node
var _model := 0

func _initialize() -> void:
	_load(0)

func _load(i: int) -> void:
	root.get_node("GameState").selected_model_index = i
	if _scene: _scene.queue_free()
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		var car: VehicleBody3D = _scene.get_node("Car")
		var gs := root.get_node("GameState")
		var fronts := 0
		for w in car._wheels:
			if w["front"]: fronts += 1
		print(gs.CAR_MODELS[_model]["name"], ": 轮子=", car._wheels.size(), " 前轮=", fronts)
		_model += 1
		if _model >= gs.model_count():
			return true
		_load(_model)
		_frame = 0
	return false
