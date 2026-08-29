extends SceneTree
var _f := 0

func _initialize() -> void:
	var model: Node3D = load("res://assets/vehicles/subaru_gc8_parts.glb").instantiate()
	root.add_child(model)
	var meshes: Array[MeshInstance3D] = []
	_collect(model, meshes)
	print("MeshInstance3D 总数: ", meshes.size())
	for mi in meshes:
		var aabb := mi.get_aabb()
		var s: Vector3 = aabb.size
		print("%s | size=(%.2f, %.2f, %.2f) center=(%.2f, %.2f, %.2f) verts=%d" % [
			mi.name, s.x, s.y, s.z,
			aabb.position.x + s.x / 2, aabb.position.y + s.y / 2, aabb.position.z + s.z / 2,
			mi.mesh.get_faces().size() if mi.mesh else 0,
		])
	# 静态相机看整车
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(1.35, 0.75, 1.85)

func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)

func _process(_d: float) -> bool:
	_f += 1
	if _f == 3:
		var cam := root.get_children().back() as Camera3D
		cam.look_at_from_position(Vector3(1.35, 0.75, 1.85), Vector3(0, 0.5, 0), Vector3.UP)
		cam.make_current()
	elif _f == 30:
		root.get_texture().get_image().save_png("/tmp/subaru_static.png")
		return true
	return false
