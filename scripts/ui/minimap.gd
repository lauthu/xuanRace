class_name Minimap
extends Control
## 赛道缩略图（HUD 左下角）：按赛道实际中心线绘制路线图，
## 实时显示车辆位置与朝向。支持任意闭环赛道形状。

const POINTS := 72
const MARGIN := 14.0

var _car: CarController
var _points := PackedVector2Array()
var _track_width := 16.0
var _bounds := Rect2()
var _open_area := false


func setup(track: TrackBuilder, car: CarController) -> void:
	_car = car
	_open_area = track.is_open_area()
	if _open_area:
		var half: float = track.WILD_HALF_SIZE
		_bounds = Rect2(-half, -half, half * 2, half * 2)
	else:
		_points = track.get_centerline_points(POINTS)
		_track_width = track.track_width
		_bounds = _compute_bounds(_points)


static func _compute_bounds(points: PackedVector2Array) -> Rect2:
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p in points:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	return Rect2(min_p, max_p - min_p)


## 世界坐标 → 地图坐标（在 _draw 时按当前控件尺寸计算）
func _make_transform() -> Dictionary:
	var half := _track_width * 0.5 + 1.0
	var sx := (size.x - MARGIN * 2.0) / (_bounds.size.x + half * 2.0)
	var sy := (size.y - MARGIN * 2.0) / (_bounds.size.y + half * 2.0)
	var s := minf(sx, sy)
	var center_world := _bounds.get_center()
	return { "scale": s, "center": center_world }


func _to_map(world: Vector2, transform: Dictionary) -> Vector2:
	return size * 0.5 + (world - transform["center"]) * transform["scale"]


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _points.is_empty() and not _open_area:
		return
	var transform := _make_transform()
	var s: float = transform["scale"]

	# 底板
	draw_rect(Rect2(Vector2.ZERO, size), UIStyle.PANEL_BG, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(UIStyle.LIME, 0.5), false, 2.0)

	if _open_area:
		_draw_open_area(transform)
	else:
		_draw_track(transform, s)

	# 车辆位置与朝向
	if _car == null:
		return
	var car_pos := _car.global_position
	var pos := _to_map(Vector2(car_pos.x, car_pos.z), transform)
	var fwd3 := _car.global_transform.basis.z
	var fwd := Vector2(fwd3.x, fwd3.z).normalized()
	draw_line(pos, pos + fwd * 12.0, UIStyle.LIME, 2.0, true)
	draw_circle(pos, 5.5, UIStyle.LIME)
	draw_arc(pos, 5.5, 0.0, TAU, 16, UIStyle.INK, 1.5, true)


## 赛道地图：中心线 + 路缘发光 + 起点线
func _draw_track(transform: Dictionary, s: float) -> void:
	var pts := PackedVector2Array()
	for p in _points:
		pts.append(_to_map(p, transform))
	var road_px := _track_width * s
	draw_polyline(pts, UIStyle.LIME.darkened(0.35), road_px + 2.5, true)
	draw_polyline(pts, UIStyle.INK.lightened(0.12), road_px, true)

	var half_world := _track_width * 0.5
	var start := _points[0]
	var tangent := (_points[1] - _points[0]).normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	draw_line(
		_to_map(start - normal * half_world, transform),
		_to_map(start + normal * half_world, transform),
		Color.WHITE, 2.5, true
	)


## 开放区域地图：方形边界 + 蜿蜒河流
func _draw_open_area(transform: Dictionary) -> void:
	var half := _bounds.size.x * 0.5
	var s: float = transform["scale"]
	# 蜿蜒河流（沿河道中心线采样）
	var river := PackedVector2Array()
	var x := -half
	while x <= half:
		river.append(_to_map(Vector2(x, TrackShapes.river_center(x)), transform))
		x += 8.0
	draw_polyline(river, Color(0.25, 0.5, 0.75),
		TrackShapes.RIVER_HALF_WIDTH * 2.0 * s, true)
	# 方形边界
	var tl := _to_map(Vector2(-half, -half), transform)
	var br := _to_map(Vector2(half, half), transform)
	draw_rect(Rect2(tl, br - tl), UIStyle.LIME.darkened(0.2), false, 3.0)
