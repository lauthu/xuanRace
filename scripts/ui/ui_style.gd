class_name UIStyle
extends RefCounted
## 全局 UI 样式库：霓虹荧光绿 × 近黑 的赛车主题。
## 参考风格：Forza Horizon 等主流赛车游戏 —— 大号斜体标题、
## 切角按钮、暗角渐变、荧光绿点缀。
## 展示字体用 Rajdhani（OFL，见 assets/ui/fonts/LICENSE.txt），中文回退系统字体。

const LIME := Color(0.78, 0.96, 0.02) ## 荧光黄绿主色
const LIME_HOVER := Color(0.88, 1.0, 0.25)
const LIME_PRESSED := Color(0.6, 0.76, 0.0)
const INK := Color(0.03, 0.04, 0.02) ## 近黑底色
const PANEL_BG := Color(0.04, 0.055, 0.03, 0.85) ## 半透明面板底
const TEXT := Color(0.94, 0.97, 0.9) ## 主文字（微绿白）
const TEXT_DIM := Color(0.55, 0.6, 0.52) ## 弱化文字

static var _font_bold: FontFile
static var _font_semibold: FontFile


## 展示字体（拉丁/数字为 Rajdhani，中文回退系统字体）
static func display_font(bold := true) -> FontFile:
	if bold:
		if _font_bold == null:
			_font_bold = load("res://assets/ui/fonts/Rajdhani-Bold.ttf")
			_font_bold.fallbacks.append(SystemFont.new())
		return _font_bold
	if _font_semibold == null:
		_font_semibold = load("res://assets/ui/fonts/Rajdhani-SemiBold.ttf")
		_font_semibold.fallbacks.append(SystemFont.new())
	return _font_semibold


static func apply_display_font(control: Control, bold := true) -> void:
	control.add_theme_font_override("font", display_font(bold))


## 斜切展示字体：FontVariation 对字形施加剪切，营造斜体速度感
static func apply_slanted_font(control: Control, shear := 0.18) -> void:
	var fv := FontVariation.new()
	fv.base_font = display_font()
	fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(-shear, 1), Vector2.ZERO)
	control.add_theme_font_override("font", fv)


## 全屏暗角（径向渐变：中心透明 → 边缘压暗）
static func make_vignette() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0), Color(0, 0, 0, 0.14), Color(0, 0, 0, 0.72)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 1024
	tex.height = 1024
	return tex


## 左侧压暗渐变（主菜单：让文字区从背景图上托起来，右侧保留画面）
static func make_side_fade() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	grad.colors = PackedColorArray([
		Color(INK, 0.96), Color(INK, 0.55), Color(INK, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(0.75, 0.5)
	tex.width = 1024
	tex.height = 64
	return tex


## 主按钮：荧光绿填充 + 黑字（开始比赛 / 下一步）
static func style_primary(button: Button) -> void:
	_apply_button(
		button,
		LIME, LIME_HOVER, LIME_PRESSED,
		INK, INK, INK,
		0, LIME_PRESSED
	)


## 次按钮：黑底 + 荧光绿描边 + 荧光绿字（返回 / 上一步 / 切换箭头）
static func style_ghost(button: Button) -> void:
	_apply_button(
		button,
		Color(PANEL_BG, 0.85), Color(LIME, 0.18), Color(LIME, 0.32),
		LIME, LIME_HOVER, LIME,
		2, LIME
	)


## 主菜单大按钮：左侧荧光绿能量条 + 黑底，悬停整条点亮（配滑移动画）
static func style_menu(button: Button, primary := false) -> void:
	if primary:
		button.add_theme_stylebox_override("normal", _make_menu_box(Color(LIME, 0.96), LIME, 5))
		button.add_theme_stylebox_override("hover", _make_menu_box(LIME_HOVER, LIME_HOVER, 5))
		button.add_theme_stylebox_override("pressed", _make_menu_box(LIME_PRESSED, LIME_PRESSED, 5))
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", INK)
		button.add_theme_color_override("font_pressed_color", INK)
	else:
		button.add_theme_stylebox_override("normal", _make_menu_box(Color(INK, 0.72), LIME, 5))
		button.add_theme_stylebox_override("hover", _make_menu_box(Color(LIME, 0.22), LIME_HOVER, 5))
		button.add_theme_stylebox_override("pressed", _make_menu_box(Color(LIME, 0.38), LIME, 5))
		button.add_theme_color_override("font_color", TEXT)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("focus", _make_focus_box())
	button.add_theme_color_override("font_focus_color", button.get_theme_color("font_color"))


static func _make_menu_box(fill: Color, bar_color: Color, bar_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_right = 2
	sb.corner_radius_top_left = 2
	sb.corner_radius_bottom_left = 2
	sb.border_width_left = bar_width
	sb.border_color = bar_color
	sb.content_margin_left = 26
	sb.content_margin_right = 20
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## 步骤指示芯片（选车页顶部）：激活 = 荧光绿底黑字，未激活 = 暗底灰字
static func chip_box(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = LIME if active else Color(INK, 0.66)
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	if not active:
		sb.border_width_bottom = 2
		sb.border_color = Color(LIME, 0.35)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func _apply_button(button: Button,
		normal: Color, hover: Color, pressed: Color,
		font_normal: Color, font_hover: Color, font_pressed: Color,
		border_width: int, border_color: Color) -> void:
	button.add_theme_stylebox_override("normal", _make_box(normal, border_width, border_color))
	button.add_theme_stylebox_override("hover", _make_box(hover, border_width, border_color))
	button.add_theme_stylebox_override("pressed", _make_box(pressed, border_width, border_color))
	button.add_theme_stylebox_override("disabled", _make_box(normal.darkened(0.5), border_width, border_color))
	button.add_theme_stylebox_override("focus", _make_focus_box())
	button.add_theme_color_override("font_color", font_normal)
	button.add_theme_color_override("font_hover_color", font_hover)
	button.add_theme_color_override("font_pressed_color", font_pressed)
	button.add_theme_color_override("font_focus_color", font_normal)
	button.add_theme_color_override("font_disabled_color", font_normal.darkened(0.4))


static func _make_box(fill: Color, border_width: int, border_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	# 对角圆角：制造锐利的速度感切角
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 16
	if border_width > 0:
		sb.set_border_width_all(border_width)
		sb.border_color = border_color
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func _make_focus_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.7)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 16
	return sb


## 大标题：荧光绿 + 黑色投影
static func style_title(label: Label) -> void:
	label.add_theme_color_override("font_color", LIME)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 4)
	label.add_theme_constant_override("shadow_offset_y", 4)


## 副标题/名称文字
static func style_label(label: Label, color := TEXT) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)


## 信息面板（HUD）：半透明黑底 + 左侧荧光绿描边
static func style_panel(panel: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_right = 12
	sb.border_width_left = 4
	sb.border_color = LIME
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)


## 文字衬底面板：把标题/内容从花哨背景上托起来
static func style_backdrop(panel: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK, 0.78)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 24
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 24
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(LIME, 0.55)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)
