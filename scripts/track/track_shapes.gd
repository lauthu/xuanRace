class_name TrackShapes
extends RefCounted
## 赛道中心线形状库。所有形状都是平滑闭环，供赛道生成、
## 缩略图、赛道预览三处共用，保证各处看到的形状一致。

enum Shape {
	ELLIPSE,        ## 椭圆（沥青赛道）
	ROUNDED_SQUARE, ## 圆角矩形/超椭圆（砂石拉力）
	WOBBLE,         ## 波浪不规则环（颠簸越野）
	WILD,           ## 方形旷野，无赛道（野外区域，中央有河）
	GP_CIRCUIT,     ## GP 专业赛道（Road Generator 插件生成路面）
}

## GP 赛道控制点（Catmull-Rom 平滑闭环，x/z 米）
const GP_POINTS := [
	Vector2(-65, -25), # 发夹弯
	Vector2(-55, -55),
	Vector2(-10, -58), # 后直道
	Vector2(35, -62),
	Vector2(70, -35),  # 远端弯
	Vector2(62, 5),
	Vector2(35, -2),   # S 弯
	Vector2(18, 28),
	Vector2(-15, 55),
	Vector2(-58, 38),
]

## 河流参数（野外区域）：河道沿 X 轴自然弯曲横贯地图
const RIVER_HALF_WIDTH := 8.0 ## 涉水区半宽（米）
const RIVER_DEPTH := 1.4 ## 河床下切深度（米）
const WATER_LEVEL := -0.35 ## 水面高度
const WILD_HALF_SIZE := 320.0 ## 野外区域半边长（米，面积约为原 160 版的四倍）
const WILD_SPAWN := Vector2(0, -120) ## 出生点（河南岸）


## 河道中心线：双正弦叠加的自然蜿蜒
static func river_center(x: float) -> float:
	return 18.0 * sin(x * 0.012) + 9.0 * sin(x * 0.03 + 1.2)


## 中心线上 t 处的点（t ∈ [0, TAU)）；WILD 无赛道，返回原点
static func centerline_point(shape: Shape, radius_x: float, radius_z: float, t: float) -> Vector2:
	match shape:
		Shape.ELLIPSE:
			return Vector2(radius_x * cos(t), radius_z * sin(t))
		Shape.ROUNDED_SQUARE:
			# n=4 超椭圆：|x/a|^n + |z/b|^n = 1
			return Vector2(
				radius_x * _signed_pow(cos(t), 0.5),
				radius_z * _signed_pow(sin(t), 0.5)
			)
		Shape.WOBBLE:
			# 径向调制的不规则环线，幅度受控不会自交
			var r := 1.0 + 0.16 * sin(3.0 * t) + 0.07 * sin(7.0 * t + 1.3)
			return Vector2(radius_x * r * cos(t), radius_z * r * sin(t))
		Shape.GP_CIRCUIT:
			return _gp_point(t)
	return Vector2.ZERO


## GP 赛道：Catmull-Rom 样条插值（闭环）
static func _gp_point(t: float) -> Vector2:
	var n := GP_POINTS.size()
	var u := wrapf(t / TAU, 0.0, 1.0) * n
	var i := int(u) % n
	var s := u - int(u)
	var p0: Vector2 = GP_POINTS[(i - 1 + n) % n]
	var p1: Vector2 = GP_POINTS[i]
	var p2: Vector2 = GP_POINTS[(i + 1) % n]
	var p3: Vector2 = GP_POINTS[(i + 2) % n]
	return 0.5 * (
		2.0 * p1
		+ (-p0 + p2) * s
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * s * s
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * s * s * s
	)


## 中心线左法线（用于等宽偏移出路面内外边缘）
static func centerline_normal(shape: Shape, radius_x: float, radius_z: float, t: float) -> Vector2:
	const DT := 0.001
	var a := centerline_point(shape, radius_x, radius_z, t - DT)
	var b := centerline_point(shape, radius_x, radius_z, t + DT)
	var tangent := (b - a).normalized()
	return Vector2(-tangent.y, tangent.x)


## 沿法线偏移 offset 后的点（offset 为路面半宽等）
static func offset_point(shape: Shape, radius_x: float, radius_z: float, t: float, offset: float) -> Vector2:
	return centerline_point(shape, radius_x, radius_z, t) + centerline_normal(shape, radius_x, radius_z, t) * offset


## 地形高度：越野赛道有起伏，野外区域为缓坡+河道，其余平地
static func bump_height(shape: Shape, x: float, z: float) -> float:
	match shape:
		Shape.WOBBLE:
			return 0.5 * sin(x * 0.22) * sin(z * 0.2) + 0.25 * sin(x * 0.55 + 1.7) * sin(z * 0.5 + 0.4)
		Shape.WILD:
			return wild_height(x, z)
	return 0.0


## 野外区域地形：多八度缓坡丘陵 - 沿蜿蜒河道的高斯下切
static func wild_height(x: float, z: float) -> float:
	var h := 0.45 * sin(x * 0.08 + 0.5) * sin(z * 0.07 + 1.1) \
		+ 0.2 * sin(x * 0.2) * sin(z * 0.18) \
		+ 0.1 * sin(x * 0.45 + 2.0) * sin(z * 0.4 + 0.8)
	var d := (z - river_center(x)) / 5.0
	h -= RIVER_DEPTH * exp(-0.5 * d * d)
	return h


## 涉水判定：在河道范围内且车身低于水面附近
static func is_in_water(shape: Shape, pos: Vector3) -> bool:
	return shape == Shape.WILD \
		and absf(pos.z - river_center(pos.x)) < RIVER_HALF_WIDTH \
		and pos.y < WATER_LEVEL + 0.2


## 采样一整圈中心线（末点与起点重合，便于闭环绘制）
static func sample_centerline(shape: Shape, radius_x: float, radius_z: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count + 1:
		points.append(centerline_point(shape, radius_x, radius_z, TAU * i / count))
	return points


static func _signed_pow(value: float, exponent: float) -> float:
	return signf(value) * pow(absf(value), exponent)
