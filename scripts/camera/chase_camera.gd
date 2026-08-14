class_name ChaseCamera
extends Camera3D
## 平滑追逐相机：跟随在车辆后上方（带侧向偏移，能看见车轮），
## 位置弹簧插值 + look_at 注视，颠簸时画面更稳。

@export var target: Node3D
@export var offset := Vector3(2.9, 1.9, -6.5) ## 相对车辆的相机偏移（x 侧偏 / y 高度 / z 后方）
@export var look_height := 0.4 ## 注视点高度（车身上方）
@export var follow_speed := 14.0 ## 跟随弹簧速度（越大越跟手）


func _ready() -> void:
	if target != null:
		global_position = target.global_transform * offset
		make_current()


func _process(delta: float) -> void:
	if target == null:
		return
	var desired := target.global_transform * offset
	var t := minf(delta * follow_speed, 1.0)
	global_position = global_position.lerp(desired, t)
	look_at(target.global_position + Vector3.UP * look_height, Vector3.UP)
