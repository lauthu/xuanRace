extends SceneTree
## 渲染斯巴鲁 GC8 正侧视图（透明背景），供主菜单背景图合成使用。
## 用法：Godot --path <project> -s res://scripts/debug/render_subaru_side.gd

var _frame := 0


func _initialize() -> void:
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	root.transparent_bg = true

	var world := Node3D.new()
	root.add_child(world)

	var model: Node3D = load("res://assets/vehicles/subaru_gc8_driver.glb").instantiate()
	CarRecolor.autofit(model, 4.4, 0.0)
	world.add_child(model)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	world.add_child(camera)
	camera.look_at_from_position(Vector3(6.0, 0.6, 0.0), Vector3(0.0, 0.6, 0.0), Vector3.UP)
	camera.make_current()

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.9, 0.0)
	sun.light_energy = 1.4
	world.add_child(sun)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.88, 0.95)
	environment.ambient_light_energy = 0.9
	env.environment = environment
	world.add_child(env)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 30:
		root.get_texture().get_image().save_png("/tmp/subaru_side.png")
		return true
	return false
