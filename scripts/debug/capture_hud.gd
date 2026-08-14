extends SceneTree
## HUD 验证：全油门行驶 5 秒（中途带一点转向），
## 截图确认缩略图车点位移 + 速度表盘指针。

var _frame := 0


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		Input.action_press("accelerate")
	elif _frame == 1000:
		Input.action_press("steer_left")
	elif _frame == 1100:
		Input.action_release("steer_left")
	elif _frame == 150:
		root.get_texture().get_image().save_png("/tmp/hud_driving.png")
		return true
	return false
