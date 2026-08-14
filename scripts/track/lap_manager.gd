class_name LapManager
extends Node
## 计时与计圈系统。
## 车辆按顺序通过检查点（1 → N-1 → 0）记为一圈，
## 通过信号向外广播圈速，HUD 负责显示。

signal lap_completed(lap_time: float, lap_number: int)

@export var total_laps := 3 ## 比赛总圈数

var current_lap := 1
var last_lap_time := 0.0
var best_lap_time := 0.0
var race_finished := false
var race_enabled := false ## 无检查点的开放地图（野外区域）为 false，HUD 显示探索时间

var _checkpoints: Array[Checkpoint] = []
var _next_index := 1
var _lap_start_time := 0.0


func _ready() -> void:
	_lap_start_time = Time.get_ticks_msec() / 1000.0
	# Track 节点在场景中排在本节点之前，其 _ready 已生成检查点
	var container := get_parent().get_node_or_null("Track/Checkpoints")
	if container == null:
		return  # 开放地图（野外区域）无检查点，自由探索
	for child: Node in container.get_children():
		if child is Checkpoint:
			_checkpoints.append(child)
	if _checkpoints.is_empty():
		return
	race_enabled = true
	_checkpoints.sort_custom(func(a: Checkpoint, b: Checkpoint) -> bool: return a.index < b.index)
	for checkpoint: Checkpoint in _checkpoints:
		checkpoint.car_entered.connect(_on_checkpoint_entered)


func _on_checkpoint_entered(checkpoint: Checkpoint) -> void:
	if race_finished or checkpoint.index != _next_index:
		return
	if checkpoint.index == 0:
		_complete_lap()
	else:
		_next_index += 1
		if _next_index >= _checkpoints.size():
			_next_index = 0


func _complete_lap() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var lap_time := now - _lap_start_time
	last_lap_time = lap_time
	if best_lap_time <= 0.0 or lap_time < best_lap_time:
		best_lap_time = lap_time
	lap_completed.emit(lap_time, current_lap)
	current_lap += 1
	if current_lap > total_laps:
		race_finished = true
	_lap_start_time = now
	_next_index = 1


func get_current_lap_time() -> float:
	if race_finished:
		return last_lap_time
	return Time.get_ticks_msec() / 1000.0 - _lap_start_time


func reset_race() -> void:
	current_lap = 1
	last_lap_time = 0.0
	best_lap_time = 0.0
	race_finished = false
	_next_index = 1
	_lap_start_time = Time.get_ticks_msec() / 1000.0
