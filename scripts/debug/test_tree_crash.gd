extends SceneTree
## 撞树测试：
## 阶段A（不可破坏）：车撞树应被树干挡住，树不倒；
## 阶段B（允许破坏）：车撞树应把树撞倒并通过。

var _frame := 0
var _phase := 0
var _scene: Node
var _car: VehicleBody3D
var _tree: Node3D


func _initialize() -> void:
	root.get_node("GameState").selected_track_index = 3  # 野外区域
	root.get_node("GameState").destructible_enabled = false
	_load_scene()


func _load_scene() -> void:
	if _scene != null:
		_scene.queue_free()
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)


func _setup_crash() -> void:
	_car = _scene.get_node("Car")
	# 找离出生点最近的一棵树
	var best_dist := INF
	for child in _scene.get_node("Track").get_children():
		if child is DestructibleTree:
			var d: float = child.global_position.distance_to(_car.global_position)
			if d < best_dist:
				best_dist = d
				_tree = child
	if _tree == null:
		print("错误：没有找到树")
		return
	# 把车放到树南侧 15 米，正对树
	var tp := _tree.global_position
	_car.global_transform = Transform3D(
		Basis(), Vector3(tp.x, TrackShapes.wild_height(tp.x, tp.z - 15.0) + 0.6, tp.z - 15.0))
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
	print("阶段", "A（不可破坏）" if _phase == 0 else "B（允许破坏）",
		"：目标树位置 z=%.1f，撞击测试开始" % tp.z)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_setup_crash()
		return false
	if _frame == 3:
		Input.action_press("accelerate")
	if _frame > 3 and _frame % 60 == 0:
		var tree_up: float = _tree.transform.basis.y.y
		print("  f=", _frame, " speed=%d" % int(_car.linear_velocity.length() * 3.6),
			" car_z=%.1f" % _car.global_position.z, " 树直立度=%.2f" % tree_up)
	if _frame == 420:
		var tree_up: float = _tree.transform.basis.y.y
		var passed: bool = _car.global_position.z > _tree.global_position.z + 2.0
		print("阶段结果: 树直立度=%.2f（%s），车辆%s通过" % [
			tree_up, "倒下" if tree_up < 0.5 else "直立", "已" if passed else "未"])
		if _phase == 0:
			_phase = 1
			_frame = 0
			Input.action_release("accelerate")
			root.get_node("GameState").destructible_enabled = true
			_load_scene()
		else:
			return true
	return false
