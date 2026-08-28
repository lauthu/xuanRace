class_name TrackPreview
extends Control
## 选车界面的赛道 2D 预览：绘制赛道俯视轮廓，路面颜色随材质变化。

const POINTS := 96
const MARGIN := 30.0

var _points := PackedVector2Array()
var _road_color := Color(0.3, 0.3, 0.35)
var _wild := false


func show_track(shape: TrackShapes.Shape, road_color: Color) -> void:
	_wild = shape == TrackShapes.Shape.WILD
	_road_color = road_color
	if _wild:
		_points = PackedVector2Array()
	else:
		_points = TrackShapes.sample_centerline(shape, 60.0, 40.0, POINTS)
	queue_redraw()


func _draw() -> void:
	# 全屏悬浮布局：不画底板，赛道图占窗口中央
	if _wild:
		_draw_wild()
		return
	if _points.is_empty():
		return

	var bounds := Minimap._compute_bounds(_points)
	var s := minf(
		(size.x - size.x * 0.3) / bounds.size.x,
		(size.y - size.y * 0.3) / bounds.size.y
	)
	var center_world := bounds.get_center()

	var pts := PackedVector2Array()
	for p in _points:
		pts.append(size * 0.5 + (p - center_world) * s)

	# 荧光绿描边 + 材质色路面
	draw_polyline(pts, UIStyle.LIME.darkened(0.35), 19.0, true)
	draw_polyline(pts, _road_color, 16.0, true)

	# 起点线
	var start := pts[0]
	var tangent := (pts[1] - pts[0]).normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	draw_line(start - normal * 12.0, start + normal * 12.0, Color.WHITE, 3.0, true)


## 野外区域预览：方形边界 + 蜿蜒河流（全屏悬浮布局，无底板）
func _draw_wild() -> void:
	var map_half := TrackShapes.WILD_HALF_SIZE
	var s := minf(size.x, size.y) * 0.6 / (map_half * 2.0)
	var center := size * 0.5
	var half := map_half * s
	# 草地
	draw_rect(Rect2(center - Vector2(half, half), Vector2(half, half) * 2), _road_color, true)
	# 蜿蜒河流
	var river := PackedVector2Array()
	var x := -map_half
	while x <= map_half:
		river.append(center + Vector2(x, TrackShapes.river_center(x)) * s)
		x += 8.0
	draw_polyline(river, Color(0.25, 0.5, 0.75),
		TrackShapes.RIVER_HALF_WIDTH * 2.0 * s + 2.0, true)
	# 方形边界
	draw_rect(Rect2(center - Vector2(half, half), Vector2(half, half) * 2),
		UIStyle.LIME.darkened(0.2), false, 3.0)
