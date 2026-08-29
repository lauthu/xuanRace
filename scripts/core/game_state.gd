extends Node
## 全局游戏状态（Autoload）：保存玩家选择的车型与颜色，跨场景传递。

const CAR_MODELS := [
	{ "name": "极速跑车", "path": "res://assets/vehicles/sports_car.glb", "yaw": 0.0 },
	{ "name": "Camaro ZL1", "path": "res://assets/vehicles/camaro_parts_textured.glb", "yaw": 0.0, "recolor": false },
	{ "name": "道奇 Charger", "path": "res://assets/vehicles/charger_parts.glb", "yaw": 0.0, "recolor": false },
	{ "name": "坦克300", "path": "res://assets/vehicles/tank300_parts_textured.glb", "yaw": 0.0, "recolor": false },
	{ "name": "F1 赛车", "path": "res://assets/kenney_racing_kit/models/raceCarRed.glb", "yaw": 0.0 },
	{ "name": "拉力赛车", "path": "res://assets/kenney_racing_kit/models/hatchback-sports.glb", "yaw": 0.0 },
	{ "name": "吉普越野车", "path": "res://assets/kenney_racing_kit/models/suv.glb", "yaw": 0.0 },
	{ "name": "未来赛车", "path": "res://assets/kenney_racing_kit/models/race.glb", "yaw": 0.0 },
]

const COLORS := [
	{ "name": "烈焰红", "color": Color(0.91, 0.33, 0.33) },
	{ "name": "活力橙", "color": Color(0.95, 0.55, 0.15) },
	{ "name": "闪电黄", "color": Color(0.93, 0.82, 0.2) },
	{ "name": "疾风绿", "color": Color(0.25, 0.72, 0.35) },
	{ "name": "深海蓝", "color": Color(0.2, 0.45, 0.9) },
	{ "name": "幻影紫", "color": Color(0.58, 0.3, 0.85) },
	{ "name": "极地白", "color": Color(0.93, 0.93, 0.95) },
	{ "name": "暗夜黑", "color": Color(0.16, 0.16, 0.19) },
]

const TRACKS := [
	{ "name": "GP 赛道", "shape": TrackShapes.Shape.GP_CIRCUIT, "surface": "asphalt", "preview": Color(0.3, 0.3, 0.35) },
	{ "name": "沥青赛道", "shape": TrackShapes.Shape.ELLIPSE, "surface": "asphalt", "preview": Color(0.3, 0.3, 0.35) },
	{ "name": "砂石拉力", "shape": TrackShapes.Shape.ROUNDED_SQUARE, "surface": "gravel", "preview": Color(0.6, 0.5, 0.35) },
	{ "name": "颠簸越野", "shape": TrackShapes.Shape.WOBBLE, "surface": "offroad", "preview": Color(0.45, 0.36, 0.25) },
	{ "name": "野外区域", "shape": TrackShapes.Shape.WILD, "surface": "wild", "preview": Color(0.3, 0.45, 0.2) },
]

var selected_model_index := 0
var selected_color_index := 0
var selected_track_index := 0
var destructible_enabled := false ## 允许破坏：撞倒树木（野外区域）


func get_selected_model() -> Dictionary:
	return CAR_MODELS[selected_model_index]


func get_selected_color() -> Dictionary:
	return COLORS[selected_color_index]


func get_selected_track() -> Dictionary:
	return TRACKS[selected_track_index]


func model_count() -> int:
	return CAR_MODELS.size()


func color_count() -> int:
	return COLORS.size()


func track_count() -> int:
	return TRACKS.size()
