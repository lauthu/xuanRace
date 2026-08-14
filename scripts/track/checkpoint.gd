class_name Checkpoint
extends Area3D
## 赛道检查点。index 0 为起点/终点线，其余按顺序编号。
## 车辆必须按 1 → N-1 → 0 的顺序通过，LapManager 才计一圈。

signal car_entered(checkpoint: Checkpoint)

@export var index := 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is VehicleBody3D:
		car_entered.emit(self)
