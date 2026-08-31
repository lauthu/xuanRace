extends SceneTree
## 野外区域验证：高空全景 + 地面近景
var _frame := 0
var _scene: Node

func _initialize() -> void:
	root.get_node("GameState").selected_track_index = 4
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var cam := Camera3D.new()
		cam.far = 2000.0
		cam.position = Vector3(0.0, 620.0, 0.01)
		cam.rotation.x = -PI * 0.5
		_scene.add_child(cam)
		cam.make_current()
	elif _frame == 90:
		root.get_texture().get_image().save_png("/tmp/wild_top.png")
		# 地面近景：出生点北侧河边看树
		var cam2 := Camera3D.new()
		_scene.add_child(cam2)
		cam2.look_at_from_position(Vector3(-20, 3.5, -95), Vector3(20, 6, -40), Vector3.UP)
		cam2.make_current()
	elif _frame == 100:
		root.get_texture().get_image().save_png("/tmp/wild_ground.png")
		return true
	return false
