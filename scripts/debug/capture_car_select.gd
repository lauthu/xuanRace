extends SceneTree
## 验证两步选车流程：
## 1. 车型页截图（F1）→ 2. 切到拉力赛车截图 → 3. 进入颜色页选"深海蓝"截图。

var _frame := 0
var _ui: Control


func _initialize() -> void:
	_ui = load("res://scenes/ui/car_select.tscn").instantiate()
	root.add_child(_ui)


func _press(path: String) -> void:
	(_ui.get_node(path) as Button).pressed.emit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		60:
			root.get_texture().get_image().save_png("/tmp/select_model_f1.png")
			_press("Center/VBox/HBox/NextButton")  # 下一台车
		90:
			root.get_texture().get_image().save_png("/tmp/select_model_rally.png")
			_press("Center/VBox/ActionButton")  # 下一步：选颜色
		120:
			# 点第 5 个色板（深海蓝）
			(_ui.get_node("Center/VBox/ColorRow").get_child(4) as Button).pressed.emit()
		150:
			root.get_texture().get_image().save_png("/tmp/select_color_blue.png")
			return true
	return false
