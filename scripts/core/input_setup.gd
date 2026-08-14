extends Node
## 运行时注册自定义输入动作，避免手写 project.godot 中冗长的 InputEvent 序列化。
## 键位：W/S 或 ↑/↓ 油门刹车，A/D 或 ←/→ 转向，R 重置车辆，Esc 返回主菜单。

const ACTIONS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"reset_car": [KEY_R],
}


func _ready() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode: int in ACTIONS[action]:
			if not _has_key_event(action, keycode):
				var event := InputEventKey.new()
				event.physical_keycode = keycode
				InputMap.action_add_event(action, event)


func _has_key_event(action: String, keycode: int) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false
