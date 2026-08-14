extends SceneTree
## 稳定性测试：全油门直行 2 秒，然后 W+A 全油门满转向 8 秒。
## 期望：up 始终保持 (0,1,0) 附近（不翻车），yaw 角速度收敛（不自旋加速）。
## 注意：-s 自定义主循环不会加载 Autoload，这里手动补注册输入动作。

var _frame := 0
var _car: VehicleBody3D


func _initialize() -> void:
	for action in ["accelerate", "steer_left", "steer_right", "brake"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	_car = scene.get_node("Car")
	Input.action_press("accelerate")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 120:
		Input.action_press("steer_right")
		print("--- 开始满转向 ---")
	if _frame % 60 == 0:
		var up := _car.global_transform.basis.y
		print("f=", _frame,
			" speed=%d km/h" % int(_car.linear_velocity.length() * 3.6),
			" angular.y=%.2f" % _car.angular_velocity.y,
			" up=(%.2f %.2f %.2f)" % [up.x, up.y, up.z],
			" steering=%.3f" % _car.steering)
	if _frame == 600:
		root.get_texture().get_image().save_png("/tmp/race_stability.png")
		return true
	return false
