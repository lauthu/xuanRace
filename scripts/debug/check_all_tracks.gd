extends SceneTree
var _frame := 0
var _scene: Node
var _errors := 0
func _initialize() -> void:
	_load(3)
func _load(i: int) -> void:
	root.get_node("GameState").selected_track_index = i
	if _scene: _scene.queue_free()
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 150: _load(0)
	elif _frame == 300: _load(2)
	elif _frame == 450:
		print("ALL TRACKS LOADED OK")
		return true
	return false
