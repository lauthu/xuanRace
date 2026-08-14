extends Control
## 主菜单：开始比赛（进入选车）/ 退出游戏。


func _ready() -> void:
	UIStyle.style_backdrop(%Backdrop)
	UIStyle.style_title(%Title)
	UIStyle.style_label(%Subtitle, UIStyle.TEXT)
	UIStyle.style_primary(%StartButton)
	UIStyle.style_ghost(%QuitButton)
	%StartButton.pressed.connect(_on_start_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%StartButton.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/car_select.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
