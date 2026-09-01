extends SceneTree
## 逐个渲染斯巴鲁座舱候选部件，定位驾驶员部件（窗口模式）。

var _frame := 0
var _all: Array[MeshInstance3D] = []
const NAMES := ["tripo_part_21", "tripo_part_18", "tripo_part_14",
	"tripo_part_12", "tripo_part_6"]


func _initialize() -> void:
	RenderingServer.set_default_clear_color(Color(0.15, 0.16, 0.18))
	var world := Node3D.new()
	root.add_child(world)

	var model: Node3D = load("res://assets/vehicles/subaru_gc8_driver.glb").instantiate()
	CarRecolor.autofit(model, 4.4, 0.0)
	world.add_child(model)
	_all = CarRecolor.collect_meshes(model)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0.0)
	sun.light_energy = 2.0
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.15, 0.16, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.9
	env.environment = environment
	world.add_child(env)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(1.2, 1.0, 1.4), Vector3(0.05, 0.2, 0.0), Vector3.UP)
	cam.make_current()


func _process(_delta: float) -> bool:
	_frame += 1
	var idx := (_frame - 10) / 5  # 每个部件停 5 帧
	if _frame < 10 or idx >= NAMES.size():
		return idx >= NAMES.size()
	for mi in _all:
		mi.visible = mi.name == NAMES[idx]
	if _frame % 5 == 4:
		root.get_texture().get_image().save_png("/tmp/gc8_part_%s.png" % NAMES[idx])
		print("saved ", NAMES[idx])
	return false
