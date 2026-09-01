class_name TrackBuilder
extends Node3D
## 程序化赛道生成器。形状与材质由 GameState 中选中的赛道决定：
## - 沥青赛道：椭圆，平地，红白路缘 + 中央虚线
## - 砂石拉力：圆角矩形，沙石路面，无路缘
## - 颠簸越野：波浪环线，泥土路面 + 真实起伏地形（视觉与碰撞一致）
## 调整 @export 参数可改变赛道尺寸。

@export var track_radius_x := 60.0 ## 中心线 X 半径
@export var track_radius_z := 40.0 ## 中心线 Z 半径
@export var track_width := 16.0 ## 路面宽度
@export var wall_height := 2.0 ## 围墙高度
@export var checkpoint_count := 8 ## 检查点数量（含起点线）

const WALL_SEGMENTS := 96
const ROAD_SEGMENTS := 128
const CURB_WIDTH := 1.0 ## 路缘石宽度
const DASH_WIDTH := 0.3 ## 中央虚线宽度
const GROUND_SIZE := 400.0 ## 地面边长
const WILD_GROUND_SIZE := 700.0 ## 野外区域地面边长（覆盖 320 半边长 + 余量）
const HEIGHTMAP_RES := 601 ## 越野地形高度图分辨率（覆盖整个地面）
const GROUND_GRID := 160 ## 越野地面网格细分
const WILD_GROUND_GRID := 280 ## 野外地面网格细分（保持约 2.5 米/格）

## AI 生成的树种库（Tripo 管线：文生图 → HD Model 带贴图，见 assets/vehicles/LICENSE.txt）
const TREE_MODELS: Array[PackedScene] = [
	preload("res://assets/trees/pine.glb"),
	preload("res://assets/trees/oak.glb"),
	preload("res://assets/trees/birch.glb"),
	preload("res://assets/trees/dead_tree.glb"),
]
## 树种索引（对应 TREE_MODELS）
const TREE_PINE := 0
const TREE_OAK := 1
const TREE_BIRCH := 2
const TREE_DEAD := 3
## AI 生成的小件库：花岗岩巨石 / 层状岩 / 绿篱灌木 / 蕨类
const PROP_MODELS: Array[PackedScene] = [
	preload("res://assets/props/boulder.glb"),
	preload("res://assets/props/rock_ledge.glb"),
	preload("res://assets/props/bush.glb"),
	preload("res://assets/props/fern.glb"),
]
const PROP_BOULDER := 0
const PROP_ROCK_LEDGE := 1
const PROP_BUSH := 2
const PROP_FERN := 3
const BANNER_RED := preload("res://assets/kenney_racing_kit/models/bannerTowerRed.glb")
const BANNER_GREEN := preload("res://assets/kenney_racing_kit/models/bannerTowerGreen.glb")
const FLAG_CHECKERS := preload("res://assets/kenney_racing_kit/models/flagCheckers.glb")

## 草地纹理（Poly Haven leafy_grass，CC0，见 assets/ground/LICENSE.txt）
const GRASS_DIFFUSE := preload("res://assets/ground/leafy_grass_diff_1k.jpg")
const GRASS_NORMAL := preload("res://assets/ground/leafy_grass_nor_gl_1k.jpg")
const GRASS_ROUGHNESS := preload("res://assets/ground/leafy_grass_rough_1k.jpg")
const GROUND_UV_TILE := 8.0 ## 草地纹理平铺尺寸（米/张）
## 地面色调向白色靠拢的比例：albedo 与纹理是相乘关系，纯色档案色太暗会压黑纹理
const GROUND_TINT_BLEND := 0.65

## 路面材质档案
const SURFACE_PROFILES := {
	"asphalt": {
		"road": Color(0.22, 0.22, 0.26), "ground": Color(0.2, 0.42, 0.18),
		"infield": Color(0.3, 0.55, 0.24), "wall": Color(0.75, 0.75, 0.78),
		"curb_red": Color(0.85, 0.12, 0.12), "curb_white": Color(0.92, 0.92, 0.92),
		"has_curbs": true, "has_dashes": true, "bumpy": false,
	},
	"gravel": {
		"road": Color(0.6, 0.5, 0.35), "ground": Color(0.42, 0.46, 0.2),
		"infield": Color(0.5, 0.55, 0.26), "wall": Color(0.5, 0.38, 0.26),
		"curb_red": Color(0.85, 0.12, 0.12), "curb_white": Color(0.92, 0.92, 0.92),
		"has_curbs": false, "has_dashes": false, "bumpy": false,
	},
	"offroad": {
		"road": Color(0.52, 0.42, 0.29), "ground": Color(0.35, 0.43, 0.2),
		"infield": Color(0.35, 0.43, 0.18), "wall": Color(0.5, 0.38, 0.26),
		"curb_red": Color(0.85, 0.12, 0.12), "curb_white": Color(0.92, 0.92, 0.92),
		"has_curbs": false, "has_dashes": false, "bumpy": true,
	},
	"wild": {
		"road": Color(0.3, 0.45, 0.2), "ground": Color(0.3, 0.45, 0.2),
		"infield": Color(0.3, 0.45, 0.2), "wall": Color(0.45, 0.33, 0.2),
		"curb_red": Color(0.85, 0.12, 0.12), "curb_white": Color(0.92, 0.92, 0.92),
		"has_curbs": false, "has_dashes": false, "bumpy": true,
	},
}

const WILD_HALF_SIZE := TrackShapes.WILD_HALF_SIZE ## 野外区域半边长（米）

var _shape := TrackShapes.Shape.ELLIPSE
var _profile: Dictionary = SURFACE_PROFILES["asphalt"]
var _ground_size := GROUND_SIZE ## 当前地面边长（野外区域更大）
var _ground_grid := GROUND_GRID ## 当前地面网格细分
var _water_material: StandardMaterial3D = null ## 水面材质（_process 中滚动 UV 模拟流动）


func _ready() -> void:
	_load_config()
	if _shape == TrackShapes.Shape.WILD:
		_build_wild()
		return
	_build_ground()
	if _shape == TrackShapes.Shape.GP_CIRCUIT:
		_build_gp_road()  # Road Generator 插件生成路面（含车道线与碰撞）
	else:
		_build_road()
		if _profile["has_curbs"]:
			_build_curbs_and_lines()
	_build_walls()
	_build_checkpoints()
	_build_start_position()
	_build_decorations()


func _process(delta: float) -> void:
	# 水面 UV 滚动模拟河流流动（沿 X 即河道走向）
	if _water_material != null:
		_water_material.uv1_offset.x += delta * 0.06
		_water_material.uv1_offset.y = sin(Time.get_ticks_msec() / 1600.0) * 0.02


## GP 赛道：用 Road Generator 沿中心线生成公路
func _build_gp_road() -> void:
	var pts := TrackShapes.sample_centerline(_shape, track_radius_x, track_radius_z, GpRoad.SAMPLE_COUNT)
	pts.remove_at(pts.size() - 1)  # 去掉闭环重复终点，由插件自行闭环
	var gp_road := GpRoad.new()
	add_child(gp_road)
	gp_road.build(pts)


## 是否开放区域（无赛道的自由探索地图）
func is_open_area() -> bool:
	return _shape == TrackShapes.Shape.WILD


func _load_config() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state == null:
		return
	var cfg: Dictionary = game_state.get_selected_track()
	_shape = cfg["shape"]
	_profile = SURFACE_PROFILES[cfg["surface"]]


## 中心线点（含地形高度）
func _point3(t: float, offset := 0.0) -> Vector3:
	var p := TrackShapes.offset_point(_shape, track_radius_x, track_radius_z, t, offset)
	return Vector3(p.x, TrackShapes.bump_height(_shape, p.x, p.y), p.y)


## 供缩略图等使用：采样中心线（x, z）
func get_centerline_points(count: int) -> PackedVector2Array:
	return TrackShapes.sample_centerline(_shape, track_radius_x, track_radius_z, count)


## 让节点局部 +X 轴对齐 dir 所需的偏航角
func _yaw_toward(dir: Vector3) -> float:
	return atan2(-dir.z, dir.x)


## 地形表面法线（平地恒为向上；越野按高度函数梯度计算，让起伏有明暗）
func _surface_normal(x: float, z: float) -> Vector3:
	if not _profile["bumpy"]:
		return Vector3.UP
	const E := 0.5
	var hx := TrackShapes.bump_height(_shape, x + E, z) - TrackShapes.bump_height(_shape, x - E, z)
	var hz := TrackShapes.bump_height(_shape, x, z + E) - TrackShapes.bump_height(_shape, x, z - E)
	return Vector3(-hx, 2.0 * E, -hz).normalized()


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


## 草地纹理材质：纹理提供细节，档案色调浅染保留各赛道的地表色彩倾向
func _make_ground_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.lerp(Color.WHITE, GROUND_TINT_BLEND)
	material.albedo_texture = GRASS_DIFFUSE
	material.normal_enabled = true
	material.normal_texture = GRASS_NORMAL
	material.roughness_texture = GRASS_ROUGHNESS
	return material


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	add_child(body)

	if _profile["bumpy"]:
		_build_bumpy_ground(body)
	else:
		_build_flat_ground(body)

	# 内场（越野赛道地面本身起伏、GP 赛道为非凸多边形，均跳过内场贴面）
	if not _profile["bumpy"] and _shape != TrackShapes.Shape.GP_CIRCUIT:
		_build_infield()


func _build_flat_ground(body: StaticBody3D) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_ground_size, 1.0, _ground_size)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(_ground_size, _ground_size)
	# PlaneMesh 的 UV 覆盖 0..1，按地面边长放大 UV 实现平铺
	var material := _make_ground_material(_profile["ground"])
	var tiling := _ground_size / GROUND_UV_TILE
	material.uv1_scale = Vector3(tiling, tiling, 1.0)
	plane.material = material
	mesh_instance.mesh = plane
	body.add_child(mesh_instance)


func _build_bumpy_ground(body: StaticBody3D) -> void:
	# 物理：高度图碰撞，与视觉网格共用同一高度函数
	var shape := CollisionShape3D.new()
	var heightmap := HeightMapShape3D.new()
	heightmap.map_width = HEIGHTMAP_RES
	heightmap.map_depth = HEIGHTMAP_RES
	var data := PackedFloat32Array()
	data.resize(HEIGHTMAP_RES * HEIGHTMAP_RES)
	var step := _ground_size / (HEIGHTMAP_RES - 1)
	for gz in HEIGHTMAP_RES:
		for gx in HEIGHTMAP_RES:
			var x := -_ground_size * 0.5 + gx * step
			var z := -_ground_size * 0.5 + gz * step
			data[gz * HEIGHTMAP_RES + gx] = TrackShapes.bump_height(_shape, x, z)
	heightmap.map_data = data
	shape.shape = heightmap
	body.add_child(shape)

	# 视觉：细分网格（UV 取世界坐标 xz，按 GROUND_UV_TILE 平铺）
	var half := _ground_size * 0.5
	var cell := _ground_size / _ground_grid
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var moisture_tint := _shape == TrackShapes.Shape.WILD
	var indices := PackedInt32Array()
	for gz in _ground_grid + 1:
		for gx in _ground_grid + 1:
			var x := -half + gx * cell
			var z := -half + gz * cell
			vertices.append(Vector3(x, TrackShapes.bump_height(_shape, x, z), z))
			normals.append(_surface_normal(x, z))
			uvs.append(Vector2(x, z) / GROUND_UV_TILE)
			if moisture_tint:
				# 近河葱郁、远河偏干黄，叠加低频噪声避免均质（顶点色与草地纹理相乘）
				var dist := absf(z - TrackShapes.river_center(x))
				var moisture := clampf(1.0 - dist / 55.0, 0.0, 1.0)
				var n := 0.94 + 0.06 * sin(x * 0.31 + z * 0.17) * sin(x * 0.13 - z * 0.23)
				var c := Color(1.06, 1.02, 0.88).lerp(Color(0.72, 1.0, 0.66), moisture)
				colors.append(Color(c.r * n, c.g * n, c.b * n))
	for gz in _ground_grid:
		for gx in _ground_grid:
			var a := gz * (_ground_grid + 1) + gx
			var b := a + _ground_grid + 1
			# Godot 从法线方向看顺时针为正面（+offset 朝内侧，注意环绕方向）
			indices.append_array([a, a + 1, b, a + 1, b + 1, b])

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _make_strip_mesh(vertices, normals, indices, _profile["ground"], uvs, colors)
	body.add_child(mesh_instance)


func _build_infield() -> void:
	var vertices := PackedVector3Array([Vector3.UP * 0.01])
	var normals := PackedVector3Array([Vector3.UP])
	var uvs := PackedVector2Array([Vector2.ZERO])
	var indices := PackedInt32Array()
	var inner := track_width * 0.5 + (CURB_WIDTH if _profile["has_curbs"] else 0.0)
	for i in ROAD_SEGMENTS + 1:
		var p := _point3(TAU * i / ROAD_SEGMENTS, inner) + Vector3.UP * 0.01
		vertices.append(p)
		normals.append(Vector3.UP)
		uvs.append(Vector2(p.x, p.z) / GROUND_UV_TILE)
	for i in ROAD_SEGMENTS:
		indices.append_array([0, i + 2, i + 1])
	var infield := MeshInstance3D.new()
	infield.name = "Infield"
	infield.mesh = _make_strip_mesh(vertices, normals, indices, _profile["infield"], uvs)
	add_child(infield)


func _make_strip_mesh(vertices: PackedVector3Array, normals: PackedVector3Array,
		indices: PackedInt32Array, color: Color, uvs := PackedVector2Array(),
		colors := PackedColorArray()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := _make_ground_material(color) if not uvs.is_empty() else _make_material(color)
	if not colors.is_empty():
		material.vertex_color_use_as_albedo = true  # 顶点色作为乘算色调
	mesh.surface_set_material(0, material)
	return mesh


func _build_road() -> void:
	const CROSS := 4  # 横向细分，越野路面的起伏需要足够顶点表达
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var half := track_width * 0.5

	for i in ROAD_SEGMENTS + 1:
		var t := TAU * i / ROAD_SEGMENTS
		for j in CROSS + 1:
			var offset := lerpf(-half, half, float(j) / CROSS)
			var p := _point3(t, offset) + Vector3.UP * 0.04
			vertices.append(p)
			normals.append(_surface_normal(p.x, p.z))

	var stride := CROSS + 1
	for i in ROAD_SEGMENTS:
		for j in CROSS:
			var v00 := i * stride + j
			var v01 := v00 + 1
			var v10 := v00 + stride
			var v11 := v10 + 1
			# +offset 朝赛道内侧，此顺序保证从上方看为顺时针（正面）
			indices.append_array([v00, v10, v01, v01, v10, v11])

	var road := MeshInstance3D.new()
	road.name = "Road"
	road.mesh = _make_strip_mesh(vertices, normals, indices, _profile["road"])
	add_child(road)


## 在 offset 区间 [offset_a, offset_b] 生成一段路面贴条（计入目标顶点数组）
func _append_strip_segment(vertices: PackedVector3Array, normals: PackedVector3Array,
		indices: PackedInt32Array, i: int, offset_a: float, offset_b: float, y: float) -> void:
	var t0 := TAU * i / ROAD_SEGMENTS
	var t1 := TAU * (i + 1) / ROAD_SEGMENTS
	var base := vertices.size()
	vertices.append(_point3(t0, offset_a) + Vector3.UP * y)
	vertices.append(_point3(t0, offset_b) + Vector3.UP * y)
	vertices.append(_point3(t1, offset_a) + Vector3.UP * y)
	vertices.append(_point3(t1, offset_b) + Vector3.UP * y)
	for j in 4:
		normals.append(Vector3.UP)
	# +offset 朝赛道内侧，此顺序保证从上方看为顺时针（正面）
	indices.append_array([base, base + 2, base + 1, base + 1, base + 3, base + 2])


func _build_curbs_and_lines() -> void:
	var half := track_width * 0.5
	var red_v := PackedVector3Array()
	var red_n := PackedVector3Array()
	var red_i := PackedInt32Array()
	var white_v := PackedVector3Array()
	var white_n := PackedVector3Array()
	var white_i := PackedInt32Array()
	var dash_v := PackedVector3Array()
	var dash_n := PackedVector3Array()
	var dash_i := PackedInt32Array()

	for i in ROAD_SEGMENTS:
		var is_red := (i % 4) < 2
		var v: PackedVector3Array = red_v if is_red else white_v
		var n: PackedVector3Array = red_n if is_red else white_n
		var idx: PackedInt32Array = red_i if is_red else white_i
		_append_strip_segment(v, n, idx, i, -half - CURB_WIDTH, -half, 0.06)
		_append_strip_segment(v, n, idx, i, half, half + CURB_WIDTH, 0.06)
		if _profile["has_dashes"] and i % 2 == 0:
			_append_strip_segment(dash_v, dash_n, dash_i, i, -DASH_WIDTH * 0.5, DASH_WIDTH * 0.5, 0.05)

	var curbs_red := MeshInstance3D.new()
	curbs_red.name = "CurbsRed"
	curbs_red.mesh = _make_strip_mesh(red_v, red_n, red_i, _profile["curb_red"])
	add_child(curbs_red)

	var curbs_white := MeshInstance3D.new()
	curbs_white.name = "CurbsWhite"
	curbs_white.mesh = _make_strip_mesh(white_v, white_n, white_i, _profile["curb_white"])
	add_child(curbs_white)

	if not dash_v.is_empty():
		var dashes := MeshInstance3D.new()
		dashes.name = "CenterDashes"
		dashes.mesh = _make_strip_mesh(dash_v, dash_n, dash_i, Color(0.95, 0.95, 0.95))
		add_child(dashes)


func _build_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "WallBody"
	add_child(body)

	var mesh_container := Node3D.new()
	mesh_container.name = "WallMeshes"
	add_child(mesh_container)

	var unit_box := BoxMesh.new()
	unit_box.material = _make_material(_profile["wall"])

	var wall_offset_extra := (CURB_WIDTH if _profile["has_curbs"] else 0.0) + 0.4
	for side: float in [-1.0, 1.0]:
		var offset := side * (track_width * 0.5 + wall_offset_extra)
		for i in WALL_SEGMENTS:
			var p0 := _point3(TAU * i / WALL_SEGMENTS, offset)
			var p1 := _point3(TAU * (i + 1) / WALL_SEGMENTS, offset)
			var mid := (p0 + p1) * 0.5
			mid.y += wall_height * 0.5
			var dir := (p1 - p0).normalized()
			var length := p0.distance_to(p1) + 0.1
			var yaw := _yaw_toward(dir)

			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(length, wall_height, 0.4)
			shape.shape = box
			shape.position = mid
			shape.rotation.y = yaw
			body.add_child(shape)

			var wall_mesh := MeshInstance3D.new()
			wall_mesh.mesh = unit_box
			wall_mesh.position = mid
			wall_mesh.rotation.y = yaw
			wall_mesh.scale = Vector3(length, wall_height, 0.4)
			mesh_container.add_child(wall_mesh)


func _build_checkpoints() -> void:
	var container := Node3D.new()
	container.name = "Checkpoints"
	add_child(container)

	for i in checkpoint_count:
		var t := TAU * i / checkpoint_count
		var pos := _point3(t, 0.0)
		var dir := (_point3(t + 0.01, 0.0) - pos).normalized()

		var checkpoint := Checkpoint.new()
		checkpoint.name = "Checkpoint%d" % i
		checkpoint.index = i
		checkpoint.position = pos + Vector3.UP * 3.0
		checkpoint.rotation.y = _yaw_toward(dir)

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 8.0, track_width + 2.0)
		shape.shape = box
		checkpoint.add_child(shape)
		container.add_child(checkpoint)

		# 起点线可视化：横跨赛道的白色标线
		if i == 0:
			var line := MeshInstance3D.new()
			var line_mesh := BoxMesh.new()
			line_mesh.size = Vector3(1.2, 0.05, track_width)
			line_mesh.material = _make_material(Color(1, 1, 1))
			line.mesh = line_mesh
			line.position = pos + Vector3.UP * 0.08
			line.rotation.y = _yaw_toward(dir)
			container.add_child(line)


func _build_start_position() -> void:
	var t0 := -0.08
	var pos := _point3(t0, 0.0)
	var dir := (_point3(t0 + 0.01, 0.0) - pos).normalized()

	var marker := Marker3D.new()
	marker.name = "StartPosition"
	add_child(marker)
	marker.position = pos + Vector3.UP * 0.6
	# look_at 使 -Z 朝向目标，而本车前进方向为 +Z，故看向反方向
	marker.look_at(marker.global_position - dir, Vector3.UP)


func _place_model(scene: PackedScene, pos: Vector3, model_scale: float, yaw := 0.0) -> void:
	var model := scene.instantiate()
	model.position = pos
	model.rotation.y = yaw
	model.scale = Vector3.ONE * model_scale
	add_child(model)


func _build_decorations() -> void:
	var half := track_width * 0.5

	# 起点线两侧的红绿灯塔
	var start_pos := _point3(0.0, 0.0)
	var start_dir := (_point3(0.01, 0.0) - start_pos).normalized()
	_place_model(BANNER_RED, _point3(0.0, half + 2.5), 4.0, _yaw_toward(start_dir))
	_place_model(BANNER_GREEN, _point3(0.0, -half - 2.5), 4.0, _yaw_toward(start_dir))

	# 起点附近的方格旗
	_place_model(FLAG_CHECKERS, _point3(-0.04, half + 2.0), 3.0)
	_place_model(FLAG_CHECKERS, _point3(0.04, -half - 2.0), 3.0)

	# 赛道外围随机种树（固定种子，每次生成一致）
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 24:
		var t := TAU * i / 24.0 + rng.randf_range(-0.08, 0.08)
		# 法线正方向朝赛道内侧，负偏移 = 赛道外侧
		var offset := -(half + CURB_WIDTH + rng.randf_range(4.0, 14.0))
		var pos := _point3(t, offset)
		# 超出地面范围则跳过
		if absf(pos.x) > 190.0 or absf(pos.z) > 190.0:
			continue
		_place_fitted_tree(pos, rng.randi_range(0, TREE_MODELS.size() - 1),
			rng.randf_range(5.0, 8.0), rng.randf_range(0.0, TAU))


# ---- 野外区域（开放地图，无赛道） ----

func _build_wild() -> void:
	# 野外区域使用更大的地面与更细的网格（面积约四倍）
	_ground_size = WILD_GROUND_SIZE
	_ground_grid = WILD_GROUND_GRID
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	add_child(body)
	_build_bumpy_ground(body)  # bump_height 对 WILD 返回缓坡+河道地形
	_build_riverbanks()  # 沙土滩涂在草地与水面之间过渡
	_build_water()
	_build_square_walls()
	_build_perimeter_forest()  # 林缘树环 + 距离雾一起藏住围墙
	_build_wild_trees()
	_build_wild_props()
	_build_wild_ambience()
	_build_wild_start()


## 石头与灌木点缀：河岸滩涂岩石（部分半浸水）、高地岩石、林下灌木层
func _build_wild_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	# 河岸岩石
	for i in 26:
		var x := rng.randf_range(-WILD_HALF_SIZE + 10.0, WILD_HALF_SIZE - 10.0)
		var side := 1.0 if rng.randi() % 2 == 0 else -1.0
		var z := TrackShapes.river_center(x) \
			+ side * (TrackShapes.RIVER_HALF_WIDTH + rng.randf_range(-3.0, 9.0))
		_place_prop(rng.randi_range(PROP_BOULDER, PROP_ROCK_LEDGE),
			Vector3(x, TrackShapes.wild_height(x, z), z),
			rng.randf_range(0.5, 2.0), rng.randf_range(0.0, TAU), true)
	# 高地岩石
	for i in 14:
		var pos := _random_land_pos(rng)
		if pos == Vector2.INF or _dist_to_river(pos) < 40.0:
			continue
		_place_prop(rng.randi_range(PROP_BOULDER, PROP_ROCK_LEDGE),
			Vector3(pos.x, TrackShapes.wild_height(pos.x, pos.y), pos.y),
			rng.randf_range(0.6, 2.4), rng.randf_range(0.0, TAU), true)
	# 灌木层：70% 河岸林下，30% 任意散生
	for i in 90:
		var pos: Vector2
		if rng.randf() < 0.7:
			var x := rng.randf_range(-WILD_HALF_SIZE + 10.0, WILD_HALF_SIZE - 10.0)
			var side := 1.0 if rng.randi() % 2 == 0 else -1.0
			var z := TrackShapes.river_center(x) \
				+ side * (TrackShapes.RIVER_HALF_WIDTH + rng.randf_range(2.0, 42.0))
			pos = Vector2(x, z)
		else:
			pos = _random_land_pos(rng)
		if pos == Vector2.INF:
			continue
		if _dist_to_river(pos) < TrackShapes.RIVER_HALF_WIDTH + 2.0:
			continue
		_place_prop(PROP_BUSH + rng.randi_range(0, 1),
			Vector3(pos.x, TrackShapes.wild_height(pos.x, pos.y), pos.y),
			rng.randf_range(0.6, 1.6), rng.randf_range(0.0, TAU), false)


## 放置小件：按包围盒缩放到目标高度、底部微沉入地面贴合坡面；
## 岩石距离剔除 160m、灌木 90m；大石头（>1.4m）加球形碰撞体
func _place_prop(type_idx: int, pos: Vector3, height: float, yaw: float, is_rock: bool) -> void:
	var model: Node3D = PROP_MODELS[type_idx].instantiate()
	var aabb := CarRecolor.compute_local_aabb(model)
	var s := 1.0
	if aabb.size.y > 0.01:
		s = height / aabb.size.y
	model.scale = Vector3.ONE * s
	model.position = pos
	model.position.y += -aabb.position.y * s - 0.08
	model.rotation.y = yaw
	var cull := 160.0 if is_rock else 90.0
	for mi in CarRecolor.collect_meshes(model):
		mi.visibility_range_end = cull
		mi.visibility_range_end_margin = 16.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if not is_rock:
			# 灌木/蕨类随风轻摆（摆幅比树冠小）
			for surf in mi.mesh.get_surface_count():
				var src := mi.get_active_material(surf) as StandardMaterial3D
				if src != null:
					mi.set_surface_override_material(surf,
						_get_sway_material(100 + type_idx, src, aabb.size.y, 0.008))
	add_child(model)
	if is_rock and height > 1.4:
		var body := StaticBody3D.new()
		body.name = "RockBody"
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = height * 0.45
		shape.shape = sphere
		shape.position.y = height * 0.35
		body.add_child(shape)
		body.position = pos
		add_child(body)


## 沿围墙内侧种一圈密树，把人工边界藏进林缘（无碰撞纯装饰）
func _build_perimeter_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var inset := WILD_HALF_SIZE - 9.0
	var step := 7.0
	var side_len := WILD_HALF_SIZE * 2.0
	var count := int(side_len * 4.0 / step)
	for i in count:
		var d := i * step  # 从西南角沿周长展开
		var side := int(d / side_len)
		var seg := d - side * side_len - WILD_HALF_SIZE  # [-half, half]
		var pos := Vector2.ZERO
		match side:
			0: pos = Vector2(seg, -inset)  # 南边
			1: pos = Vector2(inset, seg)   # 东边
			2: pos = Vector2(-seg, inset)  # 北边（反向避免重叠角）
			3: pos = Vector2(-inset, -seg) # 西边
		pos += Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
		# 林缘以高大松树为主，遮挡效果最好
		var type_idx: int = TREE_PINE if rng.randf() < 0.7 else TREE_OAK
		var height := rng.randf_range(8.0, 12.0)
		var model := _instantiate_fitted_tree(type_idx, height)
		model.position = Vector3(pos.x, TrackShapes.wild_height(pos.x, pos.y) + model.position.y, pos.y)
		model.rotation.y = rng.randf_range(0.0, TAU)
		add_child(model)


## 环境音：全域风声 + 沿河分布式流水声（程序生成噪声，无需音频资源）
func _build_wild_ambience() -> void:
	var wind := AudioStreamPlayer.new()
	wind.name = "WindAmbience"
	wind.stream = _make_noise_stream(true, 0.13, 0.35)
	wind.volume_db = -20.0
	add_child(wind)
	wind.play()

	for i in 9:
		var x := -WILD_HALF_SIZE + 40.0 + i * (WILD_HALF_SIZE - 40.0) / 4.0
		var river := AudioStreamPlayer3D.new()
		river.name = "RiverAmbience%d" % i
		river.stream = _make_noise_stream(false, 2.7, 0.5)
		river.volume_db = -14.0
		river.unit_size = 12.0
		river.max_distance = 90.0
		river.position = Vector3(x, TrackShapes.WATER_LEVEL + 0.5, TrackShapes.river_center(x))
		add_child(river)
		river.play()


## 程序生成 4 秒循环噪声：brownian=true 为低频风声，false 为颗粒感水声
static func _make_noise_stream(brownian: bool, lfo_hz: float, lfo_depth: float) -> AudioStreamWAV:
	var sr := 22050
	var n := sr * 4
	var data := PackedByteArray()
	data.resize(n * 2)  # 16-bit 单声道
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 if brownian else 77
	var last := 0.0
	for i in n:
		var white := rng.randf_range(-1.0, 1.0)
		var s: float
		if brownian:
			last = clampf((last + 0.02 * white) / 1.02, -0.5, 0.5) * 3.5
			s = last
		else:
			last = last * 0.72 + white * 0.28
			s = last * 1.8
		var lfo := 1.0 + lfo_depth * sin(TAU * lfo_hz * i / sr)
		data.encode_s16(i * 2, int(clampf(s * lfo, -1.0, 1.0) * 32000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sr
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_PINGPONG  # 往返循环避免接缝爆音
	stream.loop_end = n
	return stream


func _build_water() -> void:
	# 沿蜿蜒河道生成水面条带网格（四列顶点：近岸浅透、河心深蓝不透）
	var water := MeshInstance3D.new()
	water.name = "Water"
	var hw := TrackShapes.RIVER_HALF_WIDTH * 1.1
	var cols := [-hw, -hw * 0.5, hw * 0.5, hw]
	var col_colors := [
		Color(0.38, 0.58, 0.72, 0.35), Color(0.14, 0.36, 0.55, 0.8),
		Color(0.14, 0.36, 0.55, 0.8), Color(0.38, 0.58, 0.72, 0.35)]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var step := 4.0
	var count := int(_ground_size / step)
	for i in count + 1:
		var x := -_ground_size * 0.5 + i * step
		var zc := TrackShapes.river_center(x)
		for j in cols.size():
			vertices.append(Vector3(x, TrackShapes.WATER_LEVEL, zc + cols[j]))
			normals.append(Vector3.UP)
			colors.append(col_colors[j])
			uvs.append(Vector2(x, zc + cols[j]) / 6.0)
	var w := cols.size()
	for i in count:
		for j in w - 1:
			var a := i * w + j
			# 从上方看顺时针为正面
			indices.append_array([a, a + w, a + 1, a + 1, a + w, a + w + 1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.08
	material.metallic = 0.15
	# 噪声法线贴图 + _process 中 UV 滚动 = 流动感
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.6
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	material.normal_enabled = true
	material.normal_texture = noise_tex
	material.normal_scale = 0.3
	mesh.surface_set_material(0, material)
	_water_material = material
	water.mesh = mesh
	add_child(water)


## 河岸滩涂带：贴地形的沙土带铺满河床并延伸到两岸，
## 中心湿泥深色（透过水面可见河床），向外过渡到湿沙、干沙、草地
func _build_riverbanks() -> void:
	var hw := TrackShapes.RIVER_HALF_WIDTH
	var cols := [-14.0, -10.0, -hw - 0.5, 0.0, hw + 0.5, 10.0, 14.0]
	var col_colors := [
		Color(0.30, 0.36, 0.20),  # 外缘：沙草过渡
		Color(0.42, 0.36, 0.25),  # 干沙
		Color(0.33, 0.28, 0.20),  # 湿沙
		Color(0.24, 0.21, 0.15),  # 河底湿泥
		Color(0.33, 0.28, 0.20),
		Color(0.42, 0.36, 0.25),
		Color(0.30, 0.36, 0.20),
	]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var step := 3.0
	var count := int(_ground_size / step)
	for i in count + 1:
		var x := -_ground_size * 0.5 + i * step
		var zc := TrackShapes.river_center(x)
		for j in cols.size():
			var z: float = zc + cols[j]
			# 全程贴地形（河床处自然没入水下），抬高 4cm 避免与地面 z-fighting
			var y: float = TrackShapes.wild_height(x, z) + 0.04
			vertices.append(Vector3(x, y, z))
			normals.append(Vector3.UP)
			colors.append(col_colors[j])
	var w := cols.size()
	for i in count:
		for j in w - 1:
			var a := i * w + j
			indices.append_array([a, a + w, a + 1, a + 1, a + w, a + w + 1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	mesh.surface_set_material(0, material)
	var banks := MeshInstance3D.new()
	banks.name = "Riverbanks"
	banks.mesh = mesh
	add_child(banks)


func _build_square_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "WallBody"
	add_child(body)
	var meshes := Node3D.new()
	meshes.name = "WallMeshes"
	add_child(meshes)

	var unit_box := BoxMesh.new()
	unit_box.material = _make_material(_profile["wall"])

	# 四面围墙（底边埋入地面 0.5 米以适应缓坡）
	var walls := [
		[Vector3(0, 0, -WILD_HALF_SIZE), Vector3(WILD_HALF_SIZE * 2, wall_height + 5.0, 0.4)],
		[Vector3(0, 0, WILD_HALF_SIZE), Vector3(WILD_HALF_SIZE * 2, wall_height + 5.0, 0.4)],
		[Vector3(-WILD_HALF_SIZE, 0, 0), Vector3(0.4, wall_height + 5.0, WILD_HALF_SIZE * 2)],
		[Vector3(WILD_HALF_SIZE, 0, 0), Vector3(0.4, wall_height + 5.0, WILD_HALF_SIZE * 2)],
	]
	for wall in walls:
		var center: Vector3 = wall[0]
		var extents: Vector3 = wall[1]
		center.y = (extents.y - 0.5) * 0.5

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = extents
		shape.shape = box
		shape.position = center
		body.add_child(shape)

		var wall_mesh := MeshInstance3D.new()
		wall_mesh.mesh = unit_box
		wall_mesh.position = center
		wall_mesh.scale = extents
		meshes.add_child(wall_mesh)


func _build_wild_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# 河岸林带：阔叶树亲水（橡树/白桦为主），沿河两岸 6~40 米内成团
	for c in 14:
		var cx := rng.randf_range(-WILD_HALF_SIZE + 20.0, WILD_HALF_SIZE - 20.0)
		var side := 1.0 if rng.randi() % 2 == 0 else -1.0
		var cz: float = TrackShapes.river_center(cx) \
			+ side * (TrackShapes.RIVER_HALF_WIDTH + rng.randf_range(6.0, 40.0))
		var tree_count := 12 + rng.randi_range(-3, 4)
		for i in tree_count:
			var pos := Vector2(cx, cz) + Vector2(
				rng.randfn(0.0, 10.0), rng.randfn(0.0, 10.0))
			_try_place_tree(pos, rng, _pick_species(rng, [45, 35, 15, 5]),
				rng.randf_range(6.0, 9.5))
	# 高地松林：远离河道（>55 米），松树为主
	for c in 10:
		var center := _random_land_pos(rng)
		if center == Vector2.INF or _dist_to_river(center) < 55.0:
			continue
		var tree_count := 10 + rng.randi_range(-2, 4)
		for i in tree_count:
			var pos := center + Vector2(
				rng.randfn(0.0, 12.0), rng.randfn(0.0, 12.0))
			_try_place_tree(pos, rng, _pick_species(rng, [20, 15, 60, 5]),
				rng.randf_range(6.5, 10.0))
	# 稀疏散树：混合分布，孤生枯树比例较高（自然枯立木）
	for i in 36:
		_try_place_tree(_random_land_pos(rng), rng, _pick_species(rng, [25, 25, 30, 20]),
			rng.randf_range(5.0, 8.5))


## 按权重抽树种，weights = [橡, 白桦, 松, 枯树]
func _pick_species(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0
	for w in weights:
		total += w
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	var order := [TREE_OAK, TREE_BIRCH, TREE_PINE, TREE_DEAD]
	for i in order.size():
		acc += weights[i]
		if roll < acc:
			return order[i]
	return TREE_OAK


func _dist_to_river(pos: Vector2) -> float:
	return absf(pos.y - TrackShapes.river_center(pos.x))


## 在允许区域（不压河道、不压出生点）内取一个随机点；失败返回 Vector2.INF
func _random_land_pos(rng: RandomNumberGenerator) -> Vector2:
	for attempt in 50:
		var pos := Vector2(
			rng.randf_range(-WILD_HALF_SIZE + 6, WILD_HALF_SIZE - 6),
			rng.randf_range(-WILD_HALF_SIZE + 6, WILD_HALF_SIZE - 6))
		if absf(pos.y - TrackShapes.river_center(pos.x)) > TrackShapes.RIVER_HALF_WIDTH + 5.0 \
				and pos.distance_to(TrackShapes.WILD_SPAWN) > 12.0:
			return pos
	return Vector2.INF


func _try_place_tree(pos: Vector2, rng: RandomNumberGenerator, type_idx: int, height: float) -> void:
	if pos == Vector2.INF:
		return
	if absf(pos.x) > WILD_HALF_SIZE - 4 or absf(pos.y) > WILD_HALF_SIZE - 4:
		return
	if absf(pos.y - TrackShapes.river_center(pos.x)) < TrackShapes.RIVER_HALF_WIDTH + 2.0:
		return  # 不长在水里
	_place_tree(
		Vector3(pos.x, TrackShapes.wild_height(pos.x, pos.y), pos.y),
		type_idx, height, rng.randf_range(0.0, TAU))


## 实例化树种并按包围盒缩放到目标高度，树根对齐模型原点（y=0）
## AI 树模型面数高（约 14 万三角形），限制可视距离控制渲染开销；
## 材质替换为带风摆的 ShaderMaterial（树冠高处摆幅大、根部不动）
func _instantiate_fitted_tree(type_idx: int, height: float) -> Node3D:
	var model: Node3D = TREE_MODELS[type_idx].instantiate()
	var aabb := CarRecolor.compute_local_aabb(model)
	if aabb.size.y > 0.01:
		var s := height / aabb.size.y
		model.scale = Vector3.ONE * s
		model.position.y = -aabb.position.y * s
	for mi in CarRecolor.collect_meshes(model):
		mi.visibility_range_end = 160.0
		mi.visibility_range_end_margin = 24.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		for surf in mi.mesh.get_surface_count():
			var src := mi.get_active_material(surf) as StandardMaterial3D
			if src != null:
				mi.set_surface_override_material(surf,
					_get_sway_material(type_idx, src, aabb.size.y))
	return model


const SWAY_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform float height_ref = 1.0;
uniform float sway = 0.02;
uniform vec4 modulate : source_color = vec4(1.0);
void vertex() {
	float mask = smoothstep(0.3, 0.95, VERTEX.y / height_ref);
	float phase = VERTEX.x * 1.7 + VERTEX.z * 1.3;
	VERTEX.x += sin(TIME * 1.4 + phase) * sway * mask;
	VERTEX.z += cos(TIME * 1.05 + phase * 1.7) * sway * 0.7 * mask;
}
void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * modulate.rgb;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = 0.9;
}
"""
static var _sway_shader: Shader = null
static var _sway_mats := {} ## type_idx+texture 指针 -> ShaderMaterial（共享缓存）

## 风摆材质：保留原贴图，仅在 vertex 阶段按高度加权摆动
static func _get_sway_material(type_idx: int, src: StandardMaterial3D,
		raw_height: float, sway := 0.02) -> ShaderMaterial:
	var key := "%d_%x_%.3f" % [type_idx, src.albedo_texture.get_instance_id() if src.albedo_texture else 0, sway]
	if _sway_mats.has(key):
		return _sway_mats[key]
	if _sway_shader == null:
		_sway_shader = Shader.new()
		_sway_shader.code = SWAY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _sway_shader
	if src.albedo_texture != null:
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
	if src.normal_texture != null:
		mat.set_shader_parameter("normal_tex", src.normal_texture)
	mat.set_shader_parameter("modulate", src.albedo_color)
	mat.set_shader_parameter("height_ref", maxf(raw_height, 0.01))
	mat.set_shader_parameter("sway", sway)
	_sway_mats[key] = mat
	return mat


## 赛道外围装饰树（无碰撞，纯装饰）
func _place_fitted_tree(pos: Vector3, type_idx: int, height: float, yaw: float) -> void:
	var model := _instantiate_fitted_tree(type_idx, height)
	model.position = pos + Vector3(0, model.position.y, 0)
	model.rotation.y = yaw
	add_child(model)


static var _mound_mesh: SphereMesh = null

## 树根泥土基座的共享网格（半径 1 的半球，使用时按树缩放）
static func _get_mound_mesh() -> SphereMesh:
	if _mound_mesh == null:
		_mound_mesh = SphereMesh.new()
		_mound_mesh.is_hemisphere = true
		_mound_mesh.radial_segments = 16
		_mound_mesh.rings = 4
		_mound_mesh.radius = 1.0
		_mound_mesh.height = 1.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.30, 0.23, 0.15)
		mat.roughness = 1.0
		_mound_mesh.material = mat
	return _mound_mesh


## 放置一棵带碰撞、可被撞倒的树（type_idx 选树种，height 为目标高度米数）
func _place_tree(pos: Vector3, type_idx: int, height: float, yaw: float) -> void:
	var tree := DestructibleTree.new()
	tree.position = pos
	tree.rotation.y = yaw

	var model := _instantiate_fitted_tree(type_idx, height)
	tree.add_child(model)

	# 树根泥土基座：压扁半球遮住树根与地面的接缝，交接更自然
	var mound := MeshInstance3D.new()
	mound.mesh = _get_mound_mesh()
	mound.scale = Vector3(clampf(0.09 * height, 0.7, 1.6), 0.3, clampf(0.09 * height, 0.7, 1.6))
	mound.position.y = 0.02
	tree.add_child(mound)

	# 树干碰撞体（不可破坏时是硬障碍），粗细随树高比例
	var trunk := StaticBody3D.new()
	trunk.name = "Trunk"
	var trunk_shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = clampf(0.022 * height, 0.12, 0.35)
	cylinder.height = 0.3 * height
	trunk_shape.shape = cylinder
	trunk_shape.position.y = 0.15 * height
	trunk.add_child(trunk_shape)
	tree.add_child(trunk)

	# 撞击检测区（比树干略大）
	var hit_area := Area3D.new()
	hit_area.name = "HitArea"
	var area_shape := CollisionShape3D.new()
	var area_cylinder := CylinderShape3D.new()
	area_cylinder.radius = cylinder.radius + 0.5
	area_cylinder.height = cylinder.height + 0.4
	area_shape.shape = area_cylinder
	area_shape.position.y = trunk_shape.position.y + 0.2
	hit_area.add_child(area_shape)
	tree.add_child(hit_area)

	# 子节点就绪后再挂到场景树，保证 DestructibleTree._ready 能找到 HitArea
	add_child(tree)


func _build_wild_start() -> void:
	# 出生在河南岸，面朝北方正对河流
	var spawn := TrackShapes.WILD_SPAWN
	var marker := Marker3D.new()
	marker.name = "StartPosition"
	add_child(marker)
	marker.position = Vector3(spawn.x, TrackShapes.wild_height(spawn.x, spawn.y) + 0.6, spawn.y)
	# look_at 使 -Z 朝向目标，本车前进方向为 +Z，故看向 -Z 方向
	marker.look_at(marker.global_position + Vector3(0, 0, -1), Vector3.UP)
