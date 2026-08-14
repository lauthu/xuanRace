extends SceneTree
var _frame := 0
var _ui: Control

func _initialize() -> void:
	_ui = load("res://scenes/ui/car_select.tscn").instantiate()
	root.add_child(_ui)

func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		30: (_ui.get_node("Center/VBox/ActionButton") as Button).pressed.emit()
		60: (_ui.get_node("Center/VBox/ActionButton") as Button).pressed.emit()
		90:
			# 切到野外区域（第 4 条）
			for i in 3:
				(_ui.get_node("Center/VBox/HBox/NextButton") as Button).pressed.emit()
		120:
			(_ui.get_node("Center/VBox/DestructibleToggle") as CheckButton).button_pressed = true
		150:
			root.get_texture().get_image().save_png("/tmp/select_wild_toggle.png")
			print("开关状态: ", root.get_node("GameState").destructible_enabled)
			return true
	return false
