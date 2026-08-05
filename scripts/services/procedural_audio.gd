class_name ProceduralAudio
extends Node


const MIX_RATE := 22050

var _ambient: AudioStreamPlayer
var _cue: AudioStreamPlayer
var _volume := 0.65
var _muted := false


func _ready() -> void:
	# Headless test/export scans have no audible output and may terminate before
	# the dummy audio thread releases generated WAV playbacks.
	if DisplayServer.get_name() == "headless":
		return
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "RadioAmbience"
	add_child(_ambient)
	_cue = AudioStreamPlayer.new()
	_cue.name = "InterfaceCue"
	add_child(_cue)
	_ambient.stream = _build_stream("ambient", 2.0, true)
	_apply_volume()
	_ambient.play()


func _exit_tree() -> void:
	if is_instance_valid(_ambient):
		_ambient.stop()
		_ambient.stream = null
	if is_instance_valid(_cue):
		_cue.stop()
		_cue.stream = null


func configure(volume: float, muted: bool = false) -> void:
	_volume = clampf(volume, 0.0, 1.0)
	_muted = muted
	_apply_volume()


func play_cue(cue_name: String) -> void:
	if _muted or _volume <= 0.001 or not is_instance_valid(_cue):
		return
	var duration := 0.34 if cue_name in ["hazard", "failure"] else 0.22
	_cue.stream = _build_stream(cue_name, duration, false)
	_cue.play()


func _apply_volume() -> void:
	if not is_instance_valid(_ambient) or not is_instance_valid(_cue):
		return
	var linear := 0.0001 if _muted else maxf(_volume, 0.0001)
	_ambient.volume_db = linear_to_db(linear * 0.20)
	_cue.volume_db = linear_to_db(linear * 0.62)


func _build_stream(kind: String, duration: float, looped: bool) -> AudioStreamWAV:
	var sample_count := maxi(1, int(MIX_RATE * duration))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var phase := 0.0
	var frequency := _cue_frequency(kind)
	for index: int in range(sample_count):
		var time := float(index) / MIX_RATE
		var envelope := 1.0 if looped else sin(PI * clampf(time / duration, 0.0, 1.0))
		phase += TAU * frequency / MIX_RATE
		var radio_noise := sin(float(index * 17 % 101)) * 0.035
		var harmonic := sin(phase * 2.03) * 0.16
		var value := (sin(phase) * 0.52 + harmonic + radio_noise) * envelope
		if kind == "hazard" or kind == "failure":
			value += sin(TAU * (frequency * 0.5 + time * 130.0) * time) * envelope * 0.24
		elif kind == "success":
			value += sin(TAU * frequency * 1.5 * time) * envelope * 0.20
		var sample := clampi(int(value * 15000.0), -32768, 32767)
		bytes.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = sample_count
	return stream


func _cue_frequency(kind: String) -> float:
	match kind:
		"message": return 620.0
		"candidate": return 760.0
		"movement": return 180.0
		"inspection": return 420.0
		"puzzle", "success": return 880.0
		"hazard", "failure": return 118.0
		_: return 300.0
