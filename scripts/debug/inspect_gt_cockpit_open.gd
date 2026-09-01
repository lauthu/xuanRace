extends SceneTree
## 隐藏 GT 跑车车顶以上部件，俯视验证座舱内是否有驾驶员（窗口模式）。

var _frame := 0


func _initialize() -> void:
	RenderingServer.set_default_clear_color(Color(0.15, 0.16, 0.18))
	var world := Node3D.new()
	root.add_child(world)

	var model: Node3D = load("res://assets/vehicles/gt_racer_driver.glb").instantiate()
	CarRecolor.autofit(model, 4.4, 0.0)
	world.add_child(model)

	# 反选：只显示车顶以上部件，确认其中是否含驾驶员（排除误隐藏）
	var aabb := CarRecolor.compute_local_aabb(model)
	var roof_y := aabb.position.y + aabb.size.y * 0.72
	for mi in CarRecolor.collect_meshes(model):
		var box: AABB = mi.get_aabb()
		var center := mi.global_transform * box.get_center()
		mi.visible = center.y > roof_y

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.2, 0.3, 0.0)
	sun.light_energy = 2.5
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.15, 0.16, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 1.0, 1.0)
	environment.ambient_light_energy = 1.0
	env.environment = environment
	world.add_child(env)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 4.2, 1.6), Vector3(0.0, 0.3, 0.5), Vector3.UP)
	cam.make_current()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 30:
		root.get_texture().get_image().save_png("/tmp/gt_cockpit_open.png")
		return true
	return false
