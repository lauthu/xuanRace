extends Control
## 选车界面（三步）：
## 第 1 步选择车型 → 第 2 步选择颜色 → 第 3 步选择赛道 → 开始比赛。

enum Step { MODEL, COLOR, TRACK }

@onready var _pivot: Node3D = %PreviewPivot
@onready var _name_label: Label = %CarName
@onready var _camera: Camera3D = %PreviewCamera

var _game_state: Node
var _current_model: Node3D
var _step := Step.MODEL


func _ready() -> void:
	# -s 自定义主循环调试时不加载 Autoload，这里做兜底
	_game_state = get_node_or_null("/root/GameState")
	if _game_state == null:
		_game_state = load("res://scripts/core/game_state.gd").new()

	%PrevButton.pressed.connect(_on_prev_pressed)
	%NextButton.pressed.connect(_on_next_pressed)
	%ActionButton.pressed.connect(_on_action_pressed)
	%BackButton.pressed.connect(_on_back_pressed)
	%DestructibleToggle.toggled.connect(
		func(on: bool) -> void: _game_state.destructible_enabled = on)
	%DestructibleToggle.add_theme_color_override("font_color", UIStyle.TEXT)
	UIStyle.style_title(%Title)
	UIStyle.style_label(%CarName)
	UIStyle.style_ghost(%PrevButton)
	UIStyle.style_ghost(%NextButton)
	UIStyle.style_primary(%ActionButton)
	UIStyle.style_ghost(%BackButton)
	_camera.look_at(Vector3(0.0, 0.25, 0.0), Vector3.UP)
	_build_color_swatches()
	_show_step(Step.MODEL)


func _process(delta: float) -> void:
	_pivot.rotation.y += delta * 0.8


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_on_prev_pressed()
	elif event.is_action_pressed("ui_right"):
		_on_next_pressed()


func _build_color_swatches() -> void:
	for i in _game_state.color_count():
		var color: Color = _game_state.COLORS[i]["color"]
		var button := Button.new()
		button.custom_minimum_size = Vector2(52, 52)
		button.tooltip_text = _game_state.COLORS[i]["name"]
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 12
		style.border_width_bottom = 3
		style.border_color = color.darkened(0.4)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.pressed.connect(_on_color_selected.bind(i))
		%ColorRow.add_child(button)


func _show_step(step: Step) -> void:
	_step = step
	%ColorRow.visible = step == Step.COLOR
	%DestructibleToggle.visible = step == Step.TRACK and _is_wild_selected()
	%PreviewContainer.visible = step != Step.TRACK
	%TrackPreview.visible = step == Step.TRACK
	match step:
		Step.MODEL:
			%Title.text = "第 1 步：选择车型"
			%ActionButton.text = "下一步：选择颜色"
			%BackButton.text = "返回主菜单"
		Step.COLOR:
			%Title.text = "第 2 步：选择颜色"
			%ActionButton.text = "下一步：选择赛道"
			%BackButton.text = "上一步"
		Step.TRACK:
			%Title.text = "第 3 步：选择赛道"
			%ActionButton.text = "开始比赛"
			%BackButton.text = "上一步"
	_refresh_preview()


func _refresh_preview() -> void:
	if _step == Step.TRACK:
		var track_cfg: Dictionary = _game_state.get_selected_track()
		%TrackPreview.show_track(track_cfg["shape"], track_cfg["preview"])
		%DestructibleToggle.visible = _is_wild_selected()
		%DestructibleToggle.button_pressed = _game_state.destructible_enabled
		_update_label()
		return
	if _current_model != null:
		_current_model.queue_free()
	var model_cfg: Dictionary = _game_state.get_selected_model()
	_current_model = load(model_cfg["path"]).instantiate()
	CarRecolor.autofit(_current_model, 2.2, model_cfg.get("yaw", 0.0))
	_current_model.position.y += 0.1
	_pivot.add_child(_current_model)
	CarRecolor.apply(_current_model, _game_state.get_selected_color()["color"])
	_update_label()


func _is_wild_selected() -> bool:
	return _game_state.get_selected_track()["shape"] == TrackShapes.Shape.WILD


func _update_label() -> void:
	var text: String
	match _step:
		Step.MODEL:
			text = _game_state.get_selected_model()["name"]
		Step.COLOR:
			text = _game_state.get_selected_model()["name"] + " · " + _game_state.get_selected_color()["name"]
		Step.TRACK:
			text = _game_state.get_selected_track()["name"]
	_name_label.text = text


func _switch(step: int) -> void:
	match _step:
		Step.MODEL:
			_game_state.selected_model_index = wrapi(
				_game_state.selected_model_index + step, 0, _game_state.model_count())
		Step.COLOR:
			_game_state.selected_color_index = wrapi(
				_game_state.selected_color_index + step, 0, _game_state.color_count())
		Step.TRACK:
			_game_state.selected_track_index = wrapi(
				_game_state.selected_track_index + step, 0, _game_state.track_count())
	_refresh_preview()


func _on_color_selected(index: int) -> void:
	_game_state.selected_color_index = index
	_refresh_preview()


func _on_prev_pressed() -> void:
	_switch(-1)


func _on_next_pressed() -> void:
	_switch(1)


func _on_action_pressed() -> void:
	match _step:
		Step.MODEL:
			_show_step(Step.COLOR)
		Step.COLOR:
			_show_step(Step.TRACK)
		Step.TRACK:
			get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_back_pressed() -> void:
	match _step:
		Step.TRACK:
			_show_step(Step.COLOR)
		Step.COLOR:
			_show_step(Step.MODEL)
		Step.MODEL:
			get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
