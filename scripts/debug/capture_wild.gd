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
		# 高空俯瞰时关雾，否则 620m 外全被雾吞掉
		var env := _scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if env != null:
			env.environment.fog_enabled = false
		var cam := Camera3D.new()
		cam.far = 2000.0
		cam.position = Vector3(0.0, 620.0, 0.01)
		cam.rotation.x = -PI * 0.5
		_scene.add_child(cam)
		cam.make_current()
	elif _frame == 90:
		root.get_texture().get_image().save_png("/tmp/wild_top.png")
		# 地面近景：河岸滩涂视角（岩石/灌木/水面）
		var cam2 := Camera3D.new()
		_scene.add_child(cam2)
		cam2.look_at_from_position(Vector3(14, 2.2, -14), Vector3(-22, 0.6, 12), Vector3.UP)
		cam2.make_current()
	elif _frame == 100:
		root.get_texture().get_image().save_png("/tmp/wild_ground.png")
		return true
	return false
