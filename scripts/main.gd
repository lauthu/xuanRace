extends Node3D
## 比赛主场景：负责把车辆、赛道、计时系统、HUD 串联起来。

@onready var _car: CarController = $Car
@onready var _track: TrackBuilder = $Track
@onready var _lap_manager: LapManager = $LapManager
@onready var _hud: HUD = $HUD


func _ready() -> void:
	_reset_car()
	_hud.setup(_car, _lap_manager, _track)
	_car.car_rescued.connect(_hud._on_car_rescued)
	($ChaseCamera as ChaseCamera).target = _car
	($ChaseCamera as ChaseCamera)._ready()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_car"):
		if _lap_manager.race_finished:
			_lap_manager.reset_race()
		_reset_car()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/ui/car_select.tscn")


func _reset_car() -> void:
	var start := _track.get_node_or_null("StartPosition") as Marker3D
	if start == null:
		return
	_car.global_transform = start.global_transform
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
