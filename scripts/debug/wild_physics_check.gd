extends SceneTree
## 野外物理验证：极速上限、触地状态、车高与地形贴合度
var _f := 0
var _car: VehicleBody3D
var _max_speed := 0.0
var _max_height_err := 0.0

func _initialize() -> void:
	root.get_node("GameState").selected_track_index = 4
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	_car = scene.get_node("Car")

func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		Input.action_press("accelerate")
	if _f > 60:
		_max_speed = maxf(_max_speed, _car.get_speed_kmh())
		var gy := TrackShapes.bump_height(TrackShapes.Shape.WILD,
			_car.global_position.x, _car.global_position.z)
		_max_height_err = maxf(_max_height_err, absf(_car.global_position.y - gy))
	if _f % 60 == 0:
		print("f=%d 速度=%.0f km/h 车高-地形=%.2f m" % [
			_f, _car.get_speed_kmh(),
			_car.global_position.y - TrackShapes.bump_height(
				TrackShapes.Shape.WILD, _car.global_position.x, _car.global_position.z)])
	if _f == 1200:
		print("极速: %.0f km/h | 最大车高偏差: %.2f m" % [_max_speed, _max_height_err])
		root.get_texture().get_image().save_png("/tmp/wild_physics.png")
		return true
	return false
