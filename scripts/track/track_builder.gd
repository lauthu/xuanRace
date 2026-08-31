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
const HEIGHTMAP_RES := 401 ## 越野地形高度图分辨率（覆盖整个地面）
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
	_build_wild_trees()
	_build_wild_start()


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
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.08
	material.metallic = 0.15
	mesh.surface_set_material(0, material)
	water.mesh = mesh
	add_child(water)


## 河岸滩涂带：贴地形的沙土带铺满河床并延伸到两岸，
## 中心湿泥深色（透过水面可见河床），向外过渡到湿沙、干沙、草地
func _build_riverbanks() -> void:
	var hw := TrackShapes.RIVER_HALF_WIDTH
	var cols := [-20.0, -12.0, -hw - 0.5, 0.0, hw + 0.5, 12.0, 20.0]
	var col_colors := [
		Color(0.42, 0.45, 0.27),  # 外缘：沙草过渡
		Color(0.60, 0.52, 0.38),  # 干沙
		Color(0.48, 0.41, 0.30),  # 湿沙
		Color(0.34, 0.29, 0.21),  # 河底湿泥
		Color(0.48, 0.41, 0.30),
		Color(0.60, 0.52, 0.38),
		Color(0.42, 0.45, 0.27),
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
		[Vector3(0, 0, -WILD_HALF_SIZE), Vector3(WILD_HALF_SIZE * 2, wall_height + 0.5, 0.4)],
		[Vector3(0, 0, WILD_HALF_SIZE), Vector3(WILD_HALF_SIZE * 2, wall_height + 0.5, 0.4)],
		[Vector3(-WILD_HALF_SIZE, 0, 0), Vector3(0.4, wall_height + 0.5, WILD_HALF_SIZE * 2)],
		[Vector3(WILD_HALF_SIZE, 0, 0), Vector3(0.4, wall_height + 0.5, WILD_HALF_SIZE * 2)],
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
## AI 树模型面数高（约 14 万三角形），限制可视距离控制渲染开销
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
	return model


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
