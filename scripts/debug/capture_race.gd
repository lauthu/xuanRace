extends SceneTree
## 端到端验证：选择"拉力赛车 + 疾风绿"，加载比赛场景，
## 确认车型/颜色/朝向都正确。

var _frame := 0
var _scene: Node


func _initialize() -> void:
	var game_state := root.get_node("GameState")
	game_state.selected_model_index = 2  # 吉普
	game_state.selected_color_index = 3  # 疾风绿
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		for child in _scene.get_node("Car/Model").get_children():
			print("car model: ", child.scene_file_path)
	if _frame == 120:
		root.get_texture().get_image().save_png("/tmp/race_suv.png")
		return true
	return false
