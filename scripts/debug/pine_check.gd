extends SceneTree
var _f := 0
func _initialize() -> void:
	var m: Node3D = load("res://assets/trees/pine.glb").instantiate()
	root.add_child(m)
	var aabb := CarRecolor.compute_local_aabb(m)
	var h := aabb.size.y
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(h * 0.55, h * 0.45, h * 0.55), Vector3(0, h * 0.45, 0), Vector3.UP)
	cam.make_current()
func _process(_d: float) -> bool:
	_f += 1
	if _f == 30:
		root.get_texture().get_image().save_png("/tmp/pine_closeup.png")
		return true
	return false
