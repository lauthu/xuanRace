extends SceneTree
## 野外驾驶性能 + 视觉验证：开车 3 秒测帧率并抓拍
var _f := 0
var _scene: Node
var _times: Array[float] = []

func _initialize() -> void:
	root.get_node("GameState").selected_track_index = 4
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)

func _process(delta: float) -> bool:
	_f += 1
	if _f == 2:
		Input.action_press("accelerate")
	if _f > 60:
		_times.append(delta)
	if _f == 240:
		var sum := 0.0
		var worst := 0.0
		for t in _times:
			sum += t
			worst = maxf(worst, t)
		print("平均帧耗时: %.1f ms (%.0f FPS) 最差: %.1f ms" % [sum / _times.size() * 1000, _times.size() / sum, worst * 1000])
		root.get_texture().get_image().save_png("/tmp/wild_drive.png")
		return true
	return false
