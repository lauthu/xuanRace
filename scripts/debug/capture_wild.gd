extends SceneTree
var _frame := 0
var _scene: Node

func _initialize() -> void:
	root.get_node("GameState").selected_track_index = 3
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var cam := Camera3D.new()
		cam.position = Vector3(0.0, 260.0, 0.01)
		cam.rotation.x = -PI * 0.5
		_scene.add_child(cam)
		cam.make_current()
	elif _frame == 90:
		root.get_texture().get_image().save_png("/tmp/wild_big_top.png")
		return true
	return false
