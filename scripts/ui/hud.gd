class_name HUD
extends CanvasLayer
## 比赛 HUD：速度、圈数、本圈时间、上一圈、最快圈速、提示信息。

@onready var _speed_label: Label = %SpeedLabel
@onready var _lap_label: Label = %LapLabel
@onready var _time_label: Label = %TimeLabel
@onready var _last_label: Label = %LastLabel
@onready var _best_label: Label = %BestLabel
@onready var _message_label: Label = %MessageLabel

var _car: CarController
var _lap_manager: LapManager


func _ready() -> void:
	UIStyle.style_panel($Panel)
	UIStyle.style_label(_speed_label, UIStyle.LIME)
	UIStyle.style_label(_lap_label)
	UIStyle.style_label(_time_label)
	UIStyle.style_label(_last_label)
	UIStyle.style_label(_best_label)
	UIStyle.style_label(_message_label, UIStyle.LIME)


func setup(car: CarController, lap_manager: LapManager, track: TrackBuilder) -> void:
	_car = car
	_lap_manager = lap_manager
	_lap_manager.lap_completed.connect(_on_lap_completed)
	%Minimap.setup(track, car)
	%SpeedGauge.setup(car)
	if not _lap_manager.race_enabled:
		# 开放地图：隐藏圈数信息，显示探索时间
		_lap_label.hide()
		_last_label.hide()
		_best_label.hide()


func _process(_delta: float) -> void:
	if _car == null or _lap_manager == null:
		return
	_speed_label.text = "速度: %d km/h" % int(_car.get_speed_kmh())
	if _lap_manager.race_enabled:
		_lap_label.text = "圈数: %d / %d" % [
			mini(_lap_manager.current_lap, _lap_manager.total_laps),
			_lap_manager.total_laps,
		]
		_time_label.text = "本圈: " + format_time(_lap_manager.get_current_lap_time())
	else:
		_time_label.text = "探索: " + format_time(_lap_manager.get_current_lap_time())


func _on_lap_completed(lap_time: float, _lap_number: int) -> void:
	_last_label.text = "上一圈: " + format_time(lap_time)
	_best_label.text = "最快: " + format_time(_lap_manager.best_lap_time)
	if _lap_manager.race_finished:
		_show_message("🏁 比赛结束！按 R 重新开始")
	else:
		_show_message("圈速 " + format_time(lap_time))


func _on_car_rescued() -> void:
	_show_message("🔧 车辆已自动扶正")


func _show_message(text: String) -> void:
	_message_label.text = text
	_message_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(_message_label, "modulate:a", 0.0, 1.0)


static func format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "--:--.--"
	var minutes := int(seconds) / 60
	var rest := seconds - minutes * 60
	return "%02d:%05.2f" % [minutes, rest]
