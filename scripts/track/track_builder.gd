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
const BANNER_RED := preload("res://assets/kenney_racing_kit/models/bannerTowerRed.glb")
const BANNER_GREEN := preload("res://assets/kenney_racing_kit/models/bannerTowerGreen.glb")
const FLAG_CHECKERS := preload("res://assets/kenney_racing_kit/models/flagCheckers.glb")

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
const WILD_CLUSTER_COUNT := 20 ## 密林团数量
const WILD_CLUSTER_TREES := 12 ## 每个密林团的树数（均值）
const WILD_SPARSE_TREES := 32 ## 稀疏散树数量

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
	plane.material = _make_material(_profile["ground"])
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

	# 视觉：细分网格
	var half := _ground_size * 0.5
	var cell := _ground_size / _ground_grid
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for gz in _ground_grid + 1:
		for gx in _ground_grid + 1:
			var x := -half + gx * cell
			var z := -half + gz * cell
			vertices.append(Vector3(x, TrackShapes.bump_height(_shape, x, z), z))
			normals.append(_surface_normal(x, z))
	for gz in _ground_grid:
		for gx in _ground_grid:
			var a := gz * (_ground_grid + 1) + gx
			var b := a + _ground_grid + 1
			# Godot 从法线方向看顺时针为正面（+offset 朝内侧，注意环绕方向）
			indices.append_array([a, a + 1, b, a + 1, b + 1, b])

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _make_strip_mesh(vertices, normals, indices, _profile["ground"])
	body.add_child(mesh_instance)


func _build_infield() -> void:
	var vertices := PackedVector3Array([Vector3.UP * 0.01])
	var normals := PackedVector3Array([Vector3.UP])
	var indices := PackedInt32Array()
	var inner := track_width * 0.5 + (CURB_WIDTH if _profile["has_curbs"] else 0.0)
	for i in ROAD_SEGMENTS + 1:
		vertices.append(_point3(TAU * i / ROAD_SEGMENTS, inner) + Vector3.UP * 0.01)
		normals.append(Vector3.UP)
	for i in ROAD_SEGMENTS:
		indices.append_array([0, i + 2, i + 1])
	var infield := MeshInstance3D.new()
	infield.name = "Infield"
	infield.mesh = _make_strip_mesh(vertices, normals, indices, _profile["infield"])
	add_child(infield)


func _make_strip_mesh(vertices: PackedVector3Array, normals: PackedVector3Array,
		indices: PackedInt32Array, color: Color) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _make_material(color))
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
	_build_water()
	_build_square_walls()
	_build_wild_trees()
	_build_wild_start()


func _build_water() -> void:
	# 沿蜿蜒河道生成水面条带网格
	var water := MeshInstance3D.new()
	water.name = "Water"
	var half_width := TrackShapes.RIVER_HALF_WIDTH * 1.1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var step := 4.0
	var count := int(_ground_size / step)
	for i in count + 1:
		var x := -_ground_size * 0.5 + i * step
		var zc := TrackShapes.river_center(x)
		vertices.append(Vector3(x, TrackShapes.WATER_LEVEL, zc - half_width))
		vertices.append(Vector3(x, TrackShapes.WATER_LEVEL, zc + half_width))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	for i in count:
		var a := i * 2
		# 从上方看顺时针为正面
		indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.45, 0.65, 0.65)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.1
	mesh.surface_set_material(0, material)
	water.mesh = mesh
	add_child(water)


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
	# 密林团：团中心附近高斯散布，形成有密有疏的分布
	for c in WILD_CLUSTER_COUNT:
		var center := _random_land_pos(rng)
		if center == Vector2.INF:
			continue
		var tree_count := WILD_CLUSTER_TREES + rng.randi_range(-2, 3)
		for i in tree_count:
			var pos := center + Vector2(
				rng.randfn(0.0, 12.0), rng.randfn(0.0, 12.0))
			_try_place_tree(pos, rng)
	# 稀疏散树
	for i in WILD_SPARSE_TREES:
		_try_place_tree(_random_land_pos(rng), rng)


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


func _try_place_tree(pos: Vector2, rng: RandomNumberGenerator) -> void:
	if pos == Vector2.INF:
		return
	if absf(pos.x) > WILD_HALF_SIZE - 4 or absf(pos.y) > WILD_HALF_SIZE - 4:
		return
	if absf(pos.y - TrackShapes.river_center(pos.x)) < TrackShapes.RIVER_HALF_WIDTH + 2.0:
		return  # 不长在水里
	_place_tree(
		Vector3(pos.x, TrackShapes.wild_height(pos.x, pos.y), pos.y),
		rng.randi_range(0, TREE_MODELS.size() - 1),
		rng.randf_range(5.5, 9.0), rng.randf_range(0.0, TAU))


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


## 放置一棵带碰撞、可被撞倒的树（type_idx 选树种，height 为目标高度米数）
func _place_tree(pos: Vector3, type_idx: int, height: float, yaw: float) -> void:
	var tree := DestructibleTree.new()
	tree.position = pos
	tree.rotation.y = yaw

	var model := _instantiate_fitted_tree(type_idx, height)
	tree.add_child(model)

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
