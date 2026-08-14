class_name SpeedGauge
extends Control
## 速度表盘（HUD 右下角）：270° 扫掠的指针式仪表 + 数字时速。

@export var max_speed := 180.0 ## 表盘量程（km/h）
@export var redline := 140.0 ## 红区起点（km/h）

const START_ANGLE := 135.0 ## 0 速对应角度（屏幕坐标系，左下）
const SWEEP := 270.0

var _car: CarController
var _speed := 0.0 ## 平滑后的显示速度


func setup(car: CarController) -> void:
	_car = car


func _process(delta: float) -> void:
	if _car != null:
		var target := _car.get_speed_kmh()
		# 指针平滑追随，避免物理帧抖动
		_speed = lerpf(_speed, target, minf(delta * 8.0, 1.0))
	queue_redraw()


func _speed_angle(kmh: float) -> float:
	return deg_to_rad(START_ANGLE + SWEEP * clampf(kmh / max_speed, 0.0, 1.0))


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 4.0

	# 表盘底 + 外圈
	draw_circle(center, radius, UIStyle.PANEL_BG)
	draw_arc(center, radius, 0.0, TAU, 64, Color(UIStyle.LIME, 0.6), 2.0, true)

	# 红区
	if redline < max_speed:
		draw_arc(center, radius - 7.0, _speed_angle(redline), _speed_angle(max_speed),
			16, Color(0.9, 0.15, 0.15), 5.0, true)

	# 刻度与数字
	var font := get_theme_default_font()
	for v in range(0, int(max_speed) + 1, 10):
		var is_major := v % 30 == 0
		var angle := _speed_angle(v)
		var dir := Vector2(cos(angle), sin(angle))
		var tick_len := 12.0 if is_major else 6.0
		var tick_color := UIStyle.TEXT if is_major else Color(0.6, 0.65, 0.6)
		draw_line(center + dir * (radius - 6.0), center + dir * (radius - 6.0 - tick_len),
			tick_color, 2.5 if is_major else 1.5, true)
		if is_major:
			var label_pos := center + dir * (radius - 30.0)
			draw_string(font, label_pos + Vector2(-14, 5), str(v),
				HORIZONTAL_ALIGNMENT_CENTER, 28, 13, UIStyle.TEXT)

	# 指针
	var needle_angle := _speed_angle(_speed)
	var dir := Vector2(cos(needle_angle), sin(needle_angle))
	var perp := Vector2(-dir.y, dir.x)
	var tip := center + dir * (radius - 24.0)
	var tail := center - dir * 14.0
	draw_colored_polygon(
		[center + perp * 4.0, tip, center - perp * 4.0, tail],
		UIStyle.LIME
	)

	# 中心轴帽
	draw_circle(center, 8.0, UIStyle.LIME)
	draw_circle(center, 4.0, UIStyle.INK)

	# 数字时速
	var digital := "%d" % int(_speed)
	draw_string(font, center + Vector2(0, radius * 0.42), digital,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 26, UIStyle.LIME)
	draw_string(font, center + Vector2(0, radius * 0.42 + 16), "km/h",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 11, UIStyle.TEXT)
