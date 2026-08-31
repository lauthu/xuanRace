extends Control
## 主菜单：开始比赛（进入选车）/ 退出游戏。
## 地平线式左对齐布局：左侧压暗渐变 + 超大斜切标题 + 能量条按钮，带入场与悬停动画。

const SLIDE_DISTANCE := 56.0


func _ready() -> void:
	%SideFade.texture = UIStyle.make_side_fade()
	%Vignette.texture = UIStyle.make_vignette()

	UIStyle.apply_slanted_font(%Title)
	UIStyle.style_title(%Title)
	UIStyle.apply_display_font(%Subtitle, false)
	UIStyle.style_label(%Subtitle, UIStyle.LIME)
	UIStyle.style_label(%Footer, UIStyle.TEXT_DIM)
	UIStyle.apply_display_font(%StartButton, false)
	UIStyle.apply_display_font(%QuitButton, false)
	UIStyle.style_menu(%StartButton, true)
	UIStyle.style_menu(%QuitButton)

	%StartButton.pressed.connect(_on_start_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	_hook_hover(%StartButton)
	_hook_hover(%QuitButton)

	_play_intro()
	_pulse_accent()
	%StartButton.grab_focus()


## 入场动画：标题与按钮依次从左侧滑入并淡入
func _play_intro() -> void:
	var delay := 0.0
	for node: Control in [%AccentBar, %Title, %Subtitle, %StartButton, %QuitButton]:
		_slide_in(node, delay)
		delay += 0.07


func _slide_in(node: Control, delay: float) -> void:
	var target := node.position
	node.position = target + Vector2(-SLIDE_DISTANCE, 0)
	node.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", target, 0.45).set_delay(delay)
	tw.tween_property(node, "modulate:a", 1.0, 0.35).set_delay(delay)


## 荧光条呼吸脉冲
func _pulse_accent() -> void:
	await get_tree().create_timer(0.5).timeout
	var tw := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(%AccentBar, "modulate:a", 0.45, 0.9)
	tw.tween_property(%AccentBar, "modulate:a", 1.0, 0.9)


## 悬停/聚焦时按钮向右滑出
func _hook_hover(button: Button) -> void:
	button.set_meta("base_x", button.position.x)
	button.mouse_entered.connect(_nudge.bind(button, 16.0))
	button.mouse_exited.connect(_nudge.bind(button, 0.0))
	button.focus_entered.connect(_nudge.bind(button, 16.0))
	button.focus_exited.connect(_nudge.bind(button, 0.0))


func _nudge(button: Button, offset: float) -> void:
	var old_tween := button.get_meta("tw") as Tween if button.has_meta("tw") else null
	if old_tween != null:
		old_tween.kill()
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(button, "position:x", button.get_meta("base_x") + offset, 0.18)
	button.set_meta("tw", tw)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/car_select.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
