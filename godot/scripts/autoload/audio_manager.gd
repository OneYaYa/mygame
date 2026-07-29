extends Node

const MIX_RATE: float = 22050.0

var enabled: bool = true
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _tones: Array[Dictionary] = []
var _ambient_elapsed: float = 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.4
	_player = AudioStreamPlayer.new()
	_player.name = "ProceduralAudio"
	_player.stream = generator
	_player.volume_db = -3.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	set_process(true)


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	set_process(false)
	_tones.clear()
	if is_instance_valid(_player):
		_player.stop()
	_playback = null
	if is_instance_valid(_player):
		_player.stream = null


func _process(_delta: float) -> void:
	if not enabled or _playback == null:
		return
	var frames: int = mini(_playback.get_frames_available(), 2048)
	for _frame: int in range(frames):
		var sample: float = 0.0
		for tone: Dictionary in _tones:
			if float(tone["delay"]) > 0.0:
				tone["delay"] = float(tone["delay"]) - 1.0 / MIX_RATE
				continue
			var phase: float = float(tone["phase"])
			var wave: float = sin(phase)
			if str(tone["wave"]) == "square":
				wave = 1.0 if wave >= 0.0 else -1.0
			elif str(tone["wave"]) == "triangle":
				wave = asin(sin(phase)) * 2.0 / PI
			var life: float = maxf(0.0, float(tone["remaining"]) / maxf(0.001, float(tone["duration"])))
			sample += wave * float(tone["volume"]) * minf(1.0, life * 4.0)
			tone["phase"] = fmod(phase + TAU * float(tone["frequency"]) / MIX_RATE, TAU)
			tone["remaining"] = float(tone["remaining"]) - 1.0 / MIX_RATE
		_playback.push_frame(Vector2.ONE * clampf(sample, -0.8, 0.8))
	_tones = _tones.filter(func(tone: Dictionary) -> bool:
		return float(tone["remaining"]) > 0.0 or float(tone["delay"]) > 0.0
	)


func play(cue: String) -> void:
	if not enabled or _playback == null:
		return
	match cue:
		"reset":
			_sequence([196.0, 147.0, 98.0, 73.0], 0.9, "sine", 0.04, 0.16)
		"bell":
			_add_tone(196.0, 1.25, "sine", 0.05)
			_add_tone(392.0, 0.8, "sine", 0.02, 0.03)
			_add_tone(587.0, 0.55, "sine", 0.012, 0.05)
		"step":
			_add_tone(116.0, 0.035, "square", 0.012)
		"talk":
			_sequence([330.0, 440.0], 0.07, "square", 0.025, 0.045)
		"choice":
			_sequence([262.0, 392.0], 0.14, "triangle", 0.035, 0.08)
		"event":
			_sequence([196.0, 247.0, 330.0], 0.32, "triangle", 0.035, 0.1)
		"travel":
			_sequence([392.0, 330.0, 262.0], 0.12, "square", 0.025, 0.07)
		"save":
			_sequence([523.0, 659.0], 0.12, "square", 0.025, 0.06)
		"ending":
			_sequence([220.0, 277.0, 330.0, 440.0, 554.0], 0.6, "triangle", 0.03, 0.17)
		_:
			_add_tone(220.0, 0.05, "square", 0.018)


func update_ambience(scene_id: String, state: Dictionary, delta: float) -> void:
	if not enabled or _playback == null:
		return
	_ambient_elapsed += delta
	if _ambient_elapsed < 4.8:
		return
	_ambient_elapsed = 0.0
	var palettes: Dictionary = {
		"harbor": [196.0, 247.0, 294.0, 370.0],
		"chapel": [220.0, 330.0, 392.0, 494.0],
		"inn": [196.0, 262.0, 330.0, 392.0],
		"archive": [175.0, 220.0, 262.0, 330.0],
		"darkroom": [147.0, 185.0, 220.0, 277.0],
		"town": [220.0, 277.0, 330.0, 440.0],
	}
	var key: String = "town"
	for candidate: String in palettes.keys():
		if candidate in scene_id:
			key = candidate
			break
	var notes: Array = palettes[key] as Array
	var offset: int = (int(float(state.get("loopElapsed", 0.0)) / 120.0) + int(state.get("loopCount", 0))) % notes.size()
	for index: int in range(3):
		_add_tone(float(notes[(offset + [0, 2, 1][index]) % notes.size()]), 0.62, "triangle", 0.007, index * 0.34)


func set_enabled(value: bool) -> bool:
	enabled = value
	if is_instance_valid(_player):
		_player.stream_paused = not enabled
	if enabled:
		play("choice")
	return enabled


func _sequence(notes: Array, duration: float, wave: String, volume: float, spacing: float) -> void:
	for index: int in range(notes.size()):
		_add_tone(notes[index], duration, wave, volume, index * spacing)


func _add_tone(frequency: float, duration: float, wave: String, volume: float, delay: float = 0.0) -> void:
	_tones.append({
		"frequency": frequency,
		"duration": duration,
		"remaining": duration,
		"wave": wave,
		"volume": volume,
		"delay": delay,
		"phase": 0.0,
	})
