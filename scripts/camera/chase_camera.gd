class_name ChaseCamera
extends Camera3D
## 平滑追逐相机：跟随在车辆后上方（带侧向偏移，能看见车轮），
## 位置弹簧插值 + look_at 注视，颠簸时画面更稳。
## 按住鼠标右键拖拽可环绕观察车辆，松开后自动回正。

@export var target: Node3D
@export var offset := Vector3(2.9, 1.9, -6.5) ## 相对车辆的相机偏移（x 侧偏 / y 高度 / z 后方）
@export var look_height := 0.4 ## 注视点高度（车身上方）
@export var follow_speed := 14.0 ## 跟随弹簧速度（越大越跟手）
@export var orbit_sensitivity := 0.008 ## 环绕拖拽灵敏度（弧度/像素）
@export var orbit_return_delay := 1.5 ## 松开后多少秒开始回正
@export var orbit_return_speed := 3.0 ## 回正速度（弧度/秒）

var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _orbiting := false
var _last_orbit_time := 0.0


func _ready() -> void:
	if target != null:
		global_position = target.global_transform * offset
		make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_orbiting = event.pressed
		if event.pressed:
			_last_orbit_time = Time.get_ticks_msec() / 1000.0
	elif event is InputEventMouseMotion and _orbiting:
		_orbit_yaw -= event.relative.x * orbit_sensitivity
		_orbit_pitch = clampf(
			_orbit_pitch + event.relative.y * orbit_sensitivity, -0.5, 0.6)
		_last_orbit_time = Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	if target == null:
		return
	# 松开一段时间后视角自动回正
	if not _orbiting and (_orbit_yaw != 0.0 or _orbit_pitch != 0.0):
		var idle := Time.get_ticks_msec() / 1000.0 - _last_orbit_time
		if idle > orbit_return_delay:
			_orbit_yaw = move_toward(_orbit_yaw, 0.0, orbit_return_speed * delta)
			_orbit_pitch = move_toward(_orbit_pitch, 0.0, orbit_return_speed * delta)

	# 环绕偏移：先俯仰再偏航，围绕车辆旋转
	var orbit_basis := Basis(Vector3.UP, _orbit_yaw) * Basis(Vector3.RIGHT, _orbit_pitch)
	var desired := target.global_transform * (orbit_basis * offset)
	var t := minf(delta * follow_speed, 1.0)
	global_position = global_position.lerp(desired, t)
	look_at(target.global_position + Vector3.UP * look_height, Vector3.UP)
