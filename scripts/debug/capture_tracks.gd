extends SceneTree
## 赛道验证：依次加载 3 条赛道，俯视图截图验证形状；
## 最后一张追逐视角验证越野赛道的起伏地形。

var _frame := 0
var _scene: Node


func _initialize() -> void:
	_load_track(0)


func _load_track(index: int) -> void:
	root.get_node("GameState").selected_track_index = index
	if _scene != null:
		_scene.queue_free()
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	# 俯视调试相机
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 150.0, 0.01)
	cam.rotation.x = -PI * 0.5
	_scene.add_child(cam)
	cam.make_current()


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		90:
			root.get_texture().get_image().save_png("/tmp/track_0_top.png")
			_load_track(1)
		180:
			root.get_texture().get_image().save_png("/tmp/track_1_top.png")
			_load_track(2)
		270:
			root.get_texture().get_image().save_png("/tmp/track_2_top.png")
			# 切回追逐相机看越野起伏
			_scene.get_node("ChaseCamera").make_current()
		330:
			root.get_texture().get_image().save_png("/tmp/track_2_chase.png")
			return true
	return false
