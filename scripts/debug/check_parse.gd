extends SceneTree
func _initialize() -> void:
	var s = load("res://scripts/car/car_recolor.gd")
	print("car_recolor 加载: ", "OK" if s != null and s.can_instantiate() else "失败")
	quit()
