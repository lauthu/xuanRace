extends SceneTree
## 调试用：加载比赛场景，运行若干帧后截图保存并退出。
## 用法：Godot --path <project> -s res://scripts/debug/screenshot_capture.gd

var _frame := 0


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 120:
		var image := root.get_texture().get_image()
		image.save_png("/tmp/race_screenshot.png")
		return true
	return false
