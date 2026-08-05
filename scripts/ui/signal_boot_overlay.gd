class_name SignalBootOverlay
extends Control


signal intro_finished(skipped: bool)


const DURATION := 4.05
const CYAN := Color("67c7c1")
const GREEN := Color("70c5a0")
const AMBER := Color("d3a354")
const RED := Color("df6159")
const MUTED := Color("789398")
const INK := Color("020609")

static var _played_this_process := false

var _screen_layer: Control
var _original_position := Vector2.ZERO
var _original_modulate := Color.WHITE
var _elapsed := 0.0
var _phase := "idle"
var _active := false
var _completed := false
var _skipped := false


func configure(screen_layer: Control) -> void:
	_screen_layer = screen_layer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 500
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	if _screen_layer == null:
		_phase = "missing_screen_layer"
		_completed = true
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	_original_position = _screen_layer.position
	_original_modulate = _screen_layer.modulate
	if _played_this_process:
		_phase = "already_played"
		_completed = true
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)
		set_process_input(false)
		return
	_played_this_process = true
	_active = true
	_phase = "cold_start"
	set_process(true)
	set_process_input(true)
	grab_focus()
	_update_screen_layer()
	queue_redraw()


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed = minf(DURATION, _elapsed + delta)
	_update_phase()
	_update_screen_layer()
	queue_redraw()
	if _elapsed >= DURATION:
		_finish(false)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	var should_skip := false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			should_skip = key_event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]
	elif event is InputEventMouseButton:
		should_skip = (event as InputEventMouseButton).pressed
	if should_skip:
		skip_intro()
	# No input may leak through to the game while the boot layer is active.
	get_viewport().set_input_as_handled()


func skip_intro() -> void:
	if _active:
		_finish(true)


func get_intro_debug_state() -> Dictionary:
	var screen_position := _original_position
	var screen_modulate := _original_modulate
	if is_instance_valid(_screen_layer):
		screen_position = _screen_layer.position
		screen_modulate = _screen_layer.modulate
	return {
		"active": _active,
		"completed": _completed,
		"skipped": _skipped,
		"phase": _phase,
		"elapsed": _elapsed,
		"duration": DURATION,
		"visible": visible,
		"input_blocked": _active and mouse_filter == Control.MOUSE_FILTER_STOP,
		"screen_position": screen_position,
		"screen_modulate": screen_modulate,
		"original_position": _original_position,
		"original_modulate": _original_modulate,
		"screen_restored": screen_position.is_equal_approx(_original_position)
			and screen_modulate.is_equal_approx(_original_modulate),
	}


func _finish(was_skipped: bool) -> void:
	if _completed:
		return
	_active = false
	_completed = true
	_skipped = was_skipped
	_phase = "skipped" if was_skipped else "locked"
	_restore_screen_layer()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	release_focus()
	set_process(false)
	set_process_input(false)
	visible = false
	intro_finished.emit(was_skipped)


func _restore_screen_layer() -> void:
	if not is_instance_valid(_screen_layer):
		return
	_screen_layer.position = _original_position
	_screen_layer.modulate = _original_modulate


func _update_phase() -> void:
	if _elapsed < 0.45:
		_phase = "cold_start"
	elif _elapsed < 1.30:
		_phase = "seeking"
	elif _elapsed < 2.15:
		_phase = "lost_retry"
	elif _elapsed < 3.35:
		_phase = "acquiring"
	else:
		_phase = "locking"


func _update_screen_layer() -> void:
	if not is_instance_valid(_screen_layer):
		return
	var reveal := 0.0
	var tint := Color(0.55, 0.86, 0.84, 1.0)
	var shake_strength := 0.0
	if _elapsed < 0.45:
		reveal = 0.0
	elif _elapsed < 1.30:
		var pulse := int(floor(_elapsed * 19.0)) % 7
		reveal = 0.58 if pulse in [1, 2] else 0.12
		shake_strength = 2.5
	elif _elapsed < 2.15:
		var lost_pulse := int(floor(_elapsed * 24.0)) % 9
		reveal = 0.34 if lost_pulse in [2, 6] else 0.06
		tint = Color(0.82, 0.46, 0.42, 1.0)
		shake_strength = 4.0
	elif _elapsed < 3.35:
		var acquire_t := inverse_lerp(2.15, 3.35, _elapsed)
		reveal = lerpf(0.35, 0.88, acquire_t)
		if int(floor(_elapsed * 17.0)) % 8 == 0:
			reveal *= 0.35
		shake_strength = lerpf(3.0, 0.8, acquire_t)
	else:
		var lock_t := clampf(inverse_lerp(3.35, DURATION, _elapsed), 0.0, 1.0)
		reveal = lerpf(0.88, 1.0, lock_t)
		tint = Color.WHITE.lerp(GREEN, 0.05 * (1.0 - lock_t))
		shake_strength = lerpf(0.8, 0.0, lock_t)
	var frame := int(floor(_elapsed * 30.0))
	var jitter := Vector2(
		round((_hash01(frame * 2.0 + 3.0) * 2.0 - 1.0) * shake_strength),
		round((_hash01(frame * 2.0 + 11.0) * 2.0 - 1.0) * shake_strength * 0.55)
	)
	_screen_layer.position = _original_position + jitter
	_screen_layer.modulate = Color(tint.r, tint.g, tint.b, reveal)


func _draw() -> void:
	if not _active:
		return
	var cover_alpha := _cover_alpha()
	draw_rect(Rect2(Vector2.ZERO, size), Color(INK, cover_alpha))
	_draw_scanlines()
	_draw_noise_bands()
	_draw_boot_copy()


func _cover_alpha() -> float:
	if _elapsed < 0.45:
		return 1.0
	if _elapsed < 1.30:
		return 0.90 if int(floor(_elapsed * 19.0)) % 7 in [1, 2] else 0.98
	if _elapsed < 2.15:
		return 0.91
	if _elapsed < 3.35:
		var acquire_t := inverse_lerp(2.15, 3.35, _elapsed)
		return lerpf(0.82, 0.28, acquire_t)
	return lerpf(0.24, 0.0, clampf(inverse_lerp(3.35, DURATION, _elapsed), 0.0, 1.0))


func _draw_scanlines() -> void:
	for y: int in range(0, int(size.y), 4):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.02, 0.10, 0.11, 0.16), 1.0)
	var sweep_y := fmod(_elapsed * 148.0, maxf(1.0, size.y))
	draw_rect(Rect2(0, sweep_y, size.x, 2), Color(CYAN, 0.12))


func _draw_noise_bands() -> void:
	var frame := int(floor(_elapsed * 24.0))
	var intensity := 1.0 if _phase in ["seeking", "lost_retry"] else 0.52 if _phase == "acquiring" else 0.16
	for index: int in range(15):
		var seed := float(frame * 31 + index * 13)
		var y := _hash01(seed + 1.0) * size.y
		var height := 1.0 + _hash01(seed + 7.0) * 7.0 * intensity
		var start_x := _hash01(seed + 4.0) * size.x * 0.38
		var width := size.x * (0.18 + _hash01(seed + 9.0) * 0.72)
		var band_color := RED if _phase == "lost_retry" and index % 5 == 0 else CYAN
		draw_rect(
			Rect2(start_x, y, minf(width, size.x - start_x), height),
			Color(band_color, (0.025 + _hash01(seed + 2.0) * 0.11) * intensity)
		)
	if _phase == "lost_retry" and int(floor(_elapsed * 12.0)) % 5 == 0:
		var cut_y := size.y * (0.28 + _hash01(frame + 40.0) * 0.42)
		draw_rect(Rect2(0, cut_y, size.x, 16), Color(0.32, 0.03, 0.025, 0.38))


func _draw_boot_copy() -> void:
	var font := ThemeDB.fallback_font
	var top_color := RED if _phase == "lost_retry" else GREEN if _phase == "locking" else CYAN
	draw_string(font, Vector2(28, 34), "BR//07  RELAY HANDSHAKE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(top_color, 0.90))
	draw_string(font, Vector2(size.x - 196, 34), "K-17 / CH 02", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(MUTED, 0.88))

	var title := "COLD START"
	var subtitle := "ROUTING EMERGENCY CARRIER"
	match _phase:
		"seeking":
			title = "SEEKING SIGNAL"
			subtitle = "HANDSHAKE  07-A  //  NO VISUAL"
		"lost_retry":
			title = "SIGNAL LOST"
			subtitle = "RETRY 01 FAILED  //  RETRY 02"
		"acquiring":
			title = "CARRIER FOUND"
			subtitle = "DECODING VISUAL FEED  //  K-17"
		"locking":
			title = "SIGNAL LOCKED"
			subtitle = "REMOTE CHANNEL STABLE"
	var title_color := RED if _phase == "lost_retry" else GREEN if _phase == "locking" else CYAN
	var title_y := size.y * 0.46
	draw_string(font, Vector2(0, title_y), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 29, Color(title_color, 0.96))
	draw_string(font, Vector2(0, title_y + 30), subtitle, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(MUTED, 0.92))

	var progress := clampf(_elapsed / DURATION, 0.0, 1.0)
	var block_count := 24
	var block_width := 11.0
	var gap := 4.0
	var total_width := block_count * block_width + (block_count - 1) * gap
	var start_x := (size.x - total_width) * 0.5
	var progress_y := title_y + 58.0
	for index: int in range(block_count):
		var filled := float(index + 1) / float(block_count) <= progress
		var color := title_color if filled else Color(0.18, 0.29, 0.31, 0.65)
		draw_rect(Rect2(start_x + index * (block_width + gap), progress_y, block_width, 3), color)

	var skip_hint_alpha := 0.68 if _elapsed > 0.28 else _elapsed / 0.28 * 0.68
	draw_string(
		font,
		Vector2(0, size.y - 26),
		"ENTER / SPACE / ESC / CLICK  TO SKIP",
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x,
		10,
		Color(MUTED, skip_hint_alpha)
	)


func _hash01(seed: float) -> float:
	return fposmod(sin(seed * 12.9898) * 43758.5453, 1.0)
