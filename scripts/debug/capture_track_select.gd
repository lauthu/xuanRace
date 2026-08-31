extends SceneTree

var _frame := 0
var _ui: Control

func _initialize() -> void:
	_ui = load("res://scenes/ui/car_select.tscn").instantiate()
	root.add_child(_ui)

func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		30:
			(_ui.get_node("%ActionButton") as Button).pressed.emit()  # → 颜色
		60:
			(_ui.get_node("%ActionButton") as Button).pressed.emit()  # → 赛道
		90:
			root.get_texture().get_image().save_png("/tmp/select_track_rally.png")
			(_ui.get_node("%NextButton") as Button).pressed.emit()  # 下一条赛道
		120:
			root.get_texture().get_image().save_png("/tmp/select_track_offroad.png")
		150:
			(_ui.get_node("%NextButton") as Button).pressed.emit()  # 下一条赛道
			(_ui.get_node("%NextButton") as Button).pressed.emit()  # → 野外区域
		180:
			root.get_texture().get_image().save_png("/tmp/select_track_wild.png")
			return true
	return false
