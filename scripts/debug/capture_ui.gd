extends SceneTree
## 界面风格验证：主菜单 → 选车（车型页）→ 选车（颜色页）分别截图。

var _frame := 0
var _ui: Control


func _initialize() -> void:
	_ui = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(_ui)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		60:
			root.get_texture().get_image().save_png("/tmp/ui_menu.png")
			# 切换到选车界面
			_ui.queue_free()
			_ui = load("res://scenes/ui/car_select.tscn").instantiate()
			root.add_child(_ui)
		120:
			root.get_texture().get_image().save_png("/tmp/ui_select_model.png")
			(_ui.get_node("Center/VBox/ActionButton") as Button).pressed.emit()
		180:
			root.get_texture().get_image().save_png("/tmp/ui_select_color.png")
			return true
	return false
