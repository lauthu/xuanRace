extends SceneTree
## GP 赛道验证：加载 GP 赛道，检查公路网格生成，俯视+追逐截图。

var _frame := 0
var _scene: Node

func _initialize() -> void:
	root.get_node("GameState").selected_track_index = 0  # GP 赛道
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		var container := _scene.get_node_or_null("Track/@GpRoad@2/GpRoadManager/RoadContainer")
		if container == null:
			print("错误：RoadContainer 不存在")
		else:
			var segs := 0
			for child in container.get_children():
				if child.get_class() == "Node3D" or child.has_method("is_road_segment"):
					segs += 1
			print("RoadContainer 子节点数: ", container.get_child_count())
	elif _frame == 10:
		var cam := Camera3D.new()
		cam.position = Vector3(0.0, 200.0, 0.01)
		cam.rotation.x = -PI * 0.5
		_scene.add_child(cam)
		cam.make_current()
	elif _frame == 90:
		root.get_texture().get_image().save_png("/tmp/gp_top.png")
		(_scene.get_node("ChaseCamera") as Camera3D).make_current()
	elif _frame == 150:
		root.get_texture().get_image().save_png("/tmp/gp_chase.png")
		return true
	return false
