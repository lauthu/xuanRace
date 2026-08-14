extends AudioStreamPlayer
## 背景音乐播放器（Autoload）。
## 挂在自动加载上，跨场景（主菜单 → 选车 → 赛道）持续播放不中断。
## 音乐：Hyper Ultra-Racing（CC0，OpenGameArt），见 assets/audio/LICENSE.txt

const BGM_PATH := "res://assets/audio/racing_bgm.wav"
const DEFAULT_VOLUME_DB := -10.0


func _ready() -> void:
	if not ResourceLoader.exists(BGM_PATH):
		push_warning("BGM 文件不存在: " + BGM_PATH)
		return
	var audio := load(BGM_PATH)
	if audio is AudioStreamWAV:
		audio.loop_mode = AudioStreamWAV.LOOP_FORWARD  # 整曲循环
	stream = audio
	volume_db = DEFAULT_VOLUME_DB
	bus = &"Master"
	play()
