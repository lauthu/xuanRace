extends SceneTree
## 检查 GT 跑车 v2 座舱内是否有驾驶员：前上风挡视角 + 俯视视角各一张。
## 用法：Godot --path <project> -s res://scripts/debug/inspect_gt_cockpit.gd（窗口模式）

var _frame := 0
var _world: Node3D


func _initialize() -> void:
	RenderingServer.set_default_clear_color(Color(0.15, 0.16, 0.18))
	_world = Node3D.new()
	root.add_child(_world)

	var model: Node3D = load("res://assets/vehicles/gt_racer_driver.glb").instantiate()
	CarRecolor.autofit(model, 4.4, 0.0)
	_world.add_child(model)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.4, 0.0)
	sun.light_energy = 2.0
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.4, -2.2, 0.0)
	fill.light_energy = 0.8
	_world.add_child(fill)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.15, 0.16, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.92, 0.95)
	environment.ambient_light_energy = 0.8
	env.environment = environment
	_world.add_child(env)


func _make_cam(pos: Vector3, target: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	_world.add_child(cam)
	cam.look_at_from_position(pos, target, Vector3.UP)
	cam.make_current()
	return cam


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 20:
		# 前上视角：透过风挡看驾驶座
		_make_cam(Vector3(0.6, 2.2, 3.2), Vector3(0.0, 0.7, 0.3))
	elif _frame == 40:
		root.get_texture().get_image().save_png("/tmp/gt_cockpit_front.png")
		# 俯视：正上方看座舱
		_make_cam(Vector3(0.0, 4.5, 0.8), Vector3(0.0, 0.0, 0.3))
	elif _frame == 60:
		root.get_texture().get_image().save_png("/tmp/gt_cockpit_top.png")
		return true
	return false
