class_name CarRecolor
extends RefCounted
## 车辆换色与自适应摆放工具。
##
## 换色支持两类模型：
## - 扁平材质（Kenney Racing Kit）：直接改写饱和度最高的材质的 albedo；
## - 调色板贴图（Kenney Car Kit）：定位车身 UV 指向的色板条纹，
##   按亮度比例替换为目标颜色，保留原有明暗渐变，车窗/轮胎不受影响。


## 将车辆车漆替换为目标颜色
static func apply(root: Node3D, target: Color) -> void:
	var meshes := collect_meshes(root)
	if meshes.is_empty():
		return
	var body := _find_body_mesh(meshes)
	var material: Material = null
	if body != null and body.mesh != null and body.mesh.get_surface_count() > 0:
		material = body.get_active_material(0)
	if material is StandardMaterial3D and material.albedo_texture != null:
		_recolor_palette(meshes, body, material, target)
	else:
		_recolor_flat(meshes, target)


## 缩放模型使车长（取水平面最长轴）等于 target_length，并居中、车底落到 y=0
static func autofit(model: Node3D, target_length := 3.0, yaw := 0.0) -> void:
	var aabb := compute_aabb(model)
	if aabb.size.is_zero_approx():
		return
	# 取 X/Z 中较长的轴作为车长（兼容车头朝 ±X 的模型）
	var s := target_length / maxf(aabb.size.x, aabb.size.z)
	model.scale = Vector3.ONE * s
	model.rotation.y = yaw
	# 旋转缩放后重新计算包围盒再居中
	aabb = compute_aabb(model)
	var center := aabb.get_center()
	model.position = Vector3(-center.x, -aabb.position.y, -center.z)


static func collect_meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			result.append(node)
		stack.append_array(node.get_children())
	return result


static func compute_aabb(root: Node3D) -> AABB:
	var acc := {
		"min": Vector3(INF, INF, INF),
		"max": Vector3(-INF, -INF, -INF),
	}
	_accumulate_aabb(root, Transform3D.IDENTITY, acc)
	var mn: Vector3 = acc["min"]
	var mx: Vector3 = acc["max"]
	if mn.x > mx.x:
		return AABB()
	return AABB(mn, mx - mn)


## 以 root 自身局部坐标系表示的子树 AABB（不应用 root 的 transform）
static func compute_local_aabb(root: Node3D) -> AABB:
	var acc := {
		"min": Vector3(INF, INF, INF),
		"max": Vector3(-INF, -INF, -INF),
	}
	_accumulate_aabb(root, root.transform.affine_inverse(), acc)
	var mn: Vector3 = acc["min"]
	var mx: Vector3 = acc["max"]
	if mn.x > mx.x:
		return AABB()
	return AABB(mn, mx - mn)


static func _accumulate_aabb(node: Node3D, xform: Transform3D, acc: Dictionary) -> void:
	var local: Transform3D = xform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var a: AABB = (node as MeshInstance3D).get_aabb()
		for i in 8:
			var corner: Vector3 = a.position + Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1) * a.size
			var p: Vector3 = local * corner
			acc["min"] = acc["min"].min(p)
			acc["max"] = acc["max"].max(p)
	for child in node.get_children():
		if child is Node3D:
			_accumulate_aabb(child, local, acc)


static func _find_body_mesh(meshes: Array[MeshInstance3D]) -> MeshInstance3D:
	for mi in meshes:
		if mi.name.to_lower().contains("body"):
			return mi
	# 无命名 body 时，取体积最大的网格（车身通常远大于轮子等部件）
	var best := meshes[0]
	var best_volume := -1.0
	for mi in meshes:
		if mi.mesh == null:
			continue
		var s: Vector3 = mi.get_aabb().size
		var volume := s.x * s.y * s.z
		if volume > best_volume:
			best_volume = volume
			best = mi
	return best


# ---- 扁平材质换色 ----

static func _recolor_flat(meshes: Array[MeshInstance3D], target: Color) -> void:
	var best: StandardMaterial3D = null
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is StandardMaterial3D and (best == null or m.albedo_color.s > best.albedo_color.s):
				best = m
	if best == null:
		return
	var painted := best.duplicate() as StandardMaterial3D
	painted.albedo_color = target
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			if mi.get_active_material(s) == best:
				mi.set_surface_override_material(s, painted)


# ---- 调色板贴图换色 ----

const _HUE_TOLERANCE := 0.06
const _MIN_SATURATION := 0.12 ## 条纹扩展时的最低饱和度
const _PAINT_SATURATION := 0.1 ## 车漆取样点的最低饱和度（排除纯灰黑白，允许灰蓝等低饱和车漆）


static func _recolor_palette(meshes: Array[MeshInstance3D], body: MeshInstance3D,
		material: StandardMaterial3D, target: Color) -> void:
	var arrays := body.mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if uvs == null or uvs.is_empty():
		return
	var source_image := material.albedo_texture.get_image()
	if source_image == null:
		return
	var image := source_image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	var w := image.get_width()
	var h := image.get_height()

	# 按三角形面积加权统计车身 UV 指向的像素点：
	# 车漆覆盖面积最大（车顶/引擎盖/车门），轮眉/车窗等小面积部件不会胜出
	var weights := {}
	var tri_count := indices.size() / 3 if not indices.is_empty() else verts.size() / 3
	for t in tri_count:
		var i0: int = indices[t * 3] if not indices.is_empty() else t * 3
		var i1: int = indices[t * 3 + 1] if not indices.is_empty() else t * 3 + 1
		var i2: int = indices[t * 3 + 2] if not indices.is_empty() else t * 3 + 2
		var area := 0.5 * (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]).length()
		var center_uv := (uvs[i0] + uvs[i1] + uvs[i2]) / 3.0
		var p := Vector2i(clampi(int(center_uv.x * w), 0, w - 1), clampi(int(center_uv.y * h), 0, h - 1))
		weights[p] = weights.get(p, 0.0) + area
	var points := weights.keys()
	points.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return weights[a] > weights[b])
	var paint_point := Vector2i(-1, -1)
	var paint := Color(1, 1, 1)
	for i in mini(20, points.size()):
		var c := image.get_pixelv(points[i])
		if c.s >= _PAINT_SATURATION:
			paint_point = points[i]
			paint = c
			break
	if paint_point.x < 0:
		return  # 取样点都不是彩色，放弃换色

	# 从取样点向四周扩展，找出整条色板条纹（同色相、有饱和度的连续区域）
	var x0 := paint_point.x
	var y0 := paint_point.y
	var rect := Rect2i(x0, y0, 1, 1)
	while rect.position.x > 0 and _similar_hue(image.get_pixel(rect.position.x - 1, y0), paint):
		rect.position.x -= 1
		rect.size.x += 1
	while rect.end.x < w - 1 and _similar_hue(image.get_pixel(rect.end.x + 1, y0), paint):
		rect.size.x += 1
	while rect.position.y > 0 and _similar_hue(image.get_pixel(x0, rect.position.y - 1), paint):
		rect.position.y -= 1
		rect.size.y += 1
	while rect.end.y < h - 1 and _similar_hue(image.get_pixel(x0, rect.end.y + 1), paint):
		rect.size.y += 1

	# 按亮度比例替换整条条纹，保留渐变明暗
	var paint_lum := maxf(paint.get_luminance(), 0.05)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var old := image.get_pixel(x, y)
			if not _similar_hue(old, paint):
				continue
			var ratio := old.get_luminance() / paint_lum
			image.set_pixel(x, y, Color(
				minf(target.r * ratio, 1.0),
				minf(target.g * ratio, 1.0),
				minf(target.b * ratio, 1.0),
				old.a
			))
	image.generate_mipmaps()

	var new_material := material.duplicate() as StandardMaterial3D
	new_material.albedo_texture = ImageTexture.create_from_image(image)
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			if mi.get_active_material(s) == material:
				mi.set_surface_override_material(s, new_material)


static func _similar_hue(c: Color, ref: Color) -> bool:
	if c.s < _MIN_SATURATION:
		return false
	var diff := absf(c.h - ref.h)
	return minf(diff, 1.0 - diff) < _HUE_TOLERANCE
