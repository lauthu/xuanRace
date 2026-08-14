extends SceneTree

var _frame := 0

func _initialize() -> void:
	var scene: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(scene)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 60:
		root.get_texture().get_image().save_png("/tmp/ui_menu2.png")
		return true
	return false
