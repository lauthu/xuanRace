extends Control
## 选车界面（三步）：
## 第 1 步选择车型 → 第 2 步选择颜色 → 第 3 步选择赛道 → 开始比赛。
## 展厅式呈现：发光展台 + 聚光灯 + 顶部步骤条，切换带旋转冲刺与滑入动画。

enum Step { MODEL, COLOR, TRACK }

## 赛道材质 → 展示标签
const SURFACE_NAMES := {
	"asphalt": "沥青路面", "gravel": "砂石拉力",
	"offroad": "泥地越野", "wild": "开放区域",
}
const BASE_TURN_SPEED := 0.8 ## 展台常态转速（弧度/秒）

@onready var _pivot: Node3D = %PreviewPivot
@onready var _name_label: Label = %CarName
@onready var _camera: Camera3D = %PreviewCamera

var _game_state: Node
var _current_model: Node3D
var _step := Step.MODEL
var _spin_boost := 0.0 ## 切换车辆时的旋转冲刺量
var _name_base_pos := Vector2.ZERO


func _ready() -> void:
	# -s 自定义主循环调试时不加载 Autoload，这里做兜底
	_game_state = get_node_or_null("/root/GameState")
	if _game_state == null:
		_game_state = load("res://scripts/core/game_state.gd").new()

	%Vignette.texture = UIStyle.make_vignette()
	%PageBackground.texture = UIStyle.make_backdrop_glow()
	%SpotLight.look_at(Vector3(0.0, 0.4, 0.0), Vector3.UP)

	%PrevButton.pressed.connect(_on_prev_pressed)
	%NextButton.pressed.connect(_on_next_pressed)
	%ActionButton.pressed.connect(_on_action_pressed)
	%BackButton.pressed.connect(_on_back_pressed)
	%DestructibleToggle.toggled.connect(
		func(on: bool) -> void: _game_state.destructible_enabled = on)

	_apply_styles()
	_camera.look_at(Vector3(0.0, 0.35, 0.0), Vector3.UP)
	# 预览视口跟随窗口大小，保证全屏时 3D 不模糊
	_sync_preview_size()
	get_viewport().size_changed.connect(_sync_preview_size)
	_name_base_pos = _name_label.position
	_build_color_swatches()
	_show_step(Step.MODEL)


func _apply_styles() -> void:
	UIStyle.apply_slanted_font(%CarName, 0.12)
	UIStyle.style_label(%CarName)
	UIStyle.apply_display_font(%Counter, false)
	UIStyle.style_label(%Counter, UIStyle.LIME)
	UIStyle.apply_display_font(%SurfaceTag, false)
	UIStyle.style_label(%HintFooter, UIStyle.TEXT_DIM)
	%DestructibleToggle.add_theme_color_override("font_color", UIStyle.TEXT)
	for chip: Label in [%StepModel, %StepColor, %StepTrack]:
		UIStyle.apply_display_font(chip, false)
	UIStyle.apply_display_font(%ActionButton, false)
	UIStyle.style_ghost(%PrevButton)
	UIStyle.style_ghost(%NextButton)
	UIStyle.style_primary(%ActionButton)
	UIStyle.style_ghost(%BackButton)


func _process(delta: float) -> void:
	_pivot.rotation.y += delta * (BASE_TURN_SPEED + _spin_boost)
	_spin_boost = move_toward(_spin_boost, 0.0, delta * 16.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_on_prev_pressed()
	elif event.is_action_pressed("ui_right"):
		_on_next_pressed()
	elif event.is_action_pressed("ui_accept"):
		_on_action_pressed()
	elif event.is_action_pressed("ui_cancel"):
		_on_back_pressed()


func _build_color_swatches() -> void:
	for i in _game_state.color_count():
		var color: Color = _game_state.COLORS[i]["color"]
		var button := Button.new()
		button.custom_minimum_size = Vector2(64, 46)
		button.tooltip_text = _game_state.COLORS[i]["name"]
		button.pivot_offset = Vector2(32, 23)
		button.add_theme_stylebox_override("normal", _swatch_box(color, false))
		button.add_theme_stylebox_override("hover", _swatch_box(color, true))
		button.add_theme_stylebox_override("pressed", _swatch_box(color, true))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.pressed.connect(_on_color_selected.bind(i))
		%ColorRow.add_child(button)


## 色板：切角色块；选中/悬停加白色描边
func _swatch_box(color: Color, highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 15
	style.corner_radius_bottom_right = 5
	style.corner_radius_bottom_left = 15
	style.border_width_bottom = 3
	style.border_color = color.darkened(0.4)
	if highlighted:
		style.set_border_width_all(3)
		style.border_color = Color.WHITE
	return style


func _show_step(step: Step) -> void:
	_step = step
	%ColorRow.visible = step == Step.COLOR
	%DestructibleToggle.visible = step == Step.TRACK and _is_wild_selected()
	%PreviewContainer.visible = step != Step.TRACK
	%TrackPreview.visible = step == Step.TRACK
	%SurfaceTag.visible = step == Step.TRACK
	%Counter.visible = step != Step.TRACK
	_update_step_bar()
	match step:
		Step.MODEL:
			%ActionButton.text = "下一步：选择颜色  ▶"
			%BackButton.text = "◀ 返回主菜单"
		Step.COLOR:
			%ActionButton.text = "下一步：选择赛道  ▶"
			%BackButton.text = "◀ 上一步"
		Step.TRACK:
			%ActionButton.text = "开始比赛  ▶"
			%BackButton.text = "◀ 上一步"
	_refresh_preview()
	if step == Step.COLOR:
		_mark_selected_swatch()
	_animate_step_in()


## 顶部步骤条：当前步骤点亮
func _update_step_bar() -> void:
	var chips: Array[Label] = [%StepModel, %StepColor, %StepTrack]
	for i in chips.size():
		var active := i == _step
		chips[i].add_theme_stylebox_override("normal", UIStyle.chip_box(active))
		chips[i].add_theme_color_override("font_color",
			UIStyle.INK if active else (UIStyle.TEXT if i < _step else UIStyle.TEXT_DIM))


## 步骤切换动画：标题滑入 + 色板淡入
func _animate_step_in() -> void:
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_name_label.position = _name_base_pos + Vector2(-36, 0)
	_name_label.modulate.a = 0.0
	tw.tween_property(_name_label, "position", _name_base_pos, 0.3)
	tw.tween_property(_name_label, "modulate:a", 1.0, 0.25)
	if _step == Step.COLOR:
		%ColorRow.modulate.a = 0.0
		tw.tween_property(%ColorRow, "modulate:a", 1.0, 0.35)


func _refresh_preview() -> void:
	if _step == Step.TRACK:
		var track_cfg: Dictionary = _game_state.get_selected_track()
		%TrackPreview.show_track(track_cfg["shape"], track_cfg["preview"])
		%SurfaceTag.text = SURFACE_NAMES.get(
			_game_state.get_selected_track()["surface"], "")
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
	# 分件模型按部件角色配色；贴图模型（如 AI 生成）不换色，保留原生材质
	if model_cfg.get("parts", false):
		CarRecolor.colorize_parts(_current_model, _game_state.get_selected_color()["color"])
	elif model_cfg.get("recolor", true):
		CarRecolor.apply(_current_model, _game_state.get_selected_color()["color"])
	_update_label()


func _is_wild_selected() -> bool:
	return _game_state.get_selected_track()["shape"] == TrackShapes.Shape.WILD


## 预览视口分辨率跟随窗口（SubViewport 固定尺寸拉伸会糊）
func _sync_preview_size() -> void:
	var sv := get_node("PreviewContainer/SubViewport") as SubViewport
	var window_size := Vector2i(get_viewport().get_visible_rect().size)
	if window_size.x > 0:
		sv.size = window_size


func _update_label() -> void:
	match _step:
		Step.MODEL:
			_name_label.text = _game_state.get_selected_model()["name"]
			%Counter.text = "%02d / %02d" % [
				_game_state.selected_model_index + 1, _game_state.model_count()]
		Step.COLOR:
			_name_label.text = _game_state.get_selected_model()["name"] \
				+ " · " + _game_state.get_selected_color()["name"]
			%Counter.text = "%02d / %02d" % [
				_game_state.selected_color_index + 1, _game_state.color_count()]
		Step.TRACK:
			_name_label.text = _game_state.get_selected_track()["name"]
			%Counter.text = "%02d / %02d" % [
				_game_state.selected_track_index + 1, _game_state.track_count()]


func _switch(step: int) -> void:
	match _step:
		Step.MODEL:
			_game_state.selected_model_index = wrapi(
				_game_state.selected_model_index + step, 0, _game_state.model_count())
			_spin_boost = 11.0 * sign(step)
		Step.COLOR:
			_game_state.selected_color_index = wrapi(
				_game_state.selected_color_index + step, 0, _game_state.color_count())
			_mark_selected_swatch()
		Step.TRACK:
			_game_state.selected_track_index = wrapi(
				_game_state.selected_track_index + step, 0, _game_state.track_count())
	_refresh_preview()


## 高亮当前选中的色板
func _mark_selected_swatch() -> void:
	var selected: int = _game_state.selected_color_index
	for i in %ColorRow.get_child_count():
		var button := %ColorRow.get_child(i) as Button
		var color: Color = _game_state.COLORS[i]["color"]
		button.add_theme_stylebox_override("normal", _swatch_box(color, i == selected))


func _on_color_selected(index: int) -> void:
	_game_state.selected_color_index = index
	_mark_selected_swatch()
	# 选中色板弹跳反馈
	var button := %ColorRow.get_child(index) as Button
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	button.scale = Vector2(0.82, 0.82)
	tw.tween_property(button, "scale", Vector2.ONE, 0.28)
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
