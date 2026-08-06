class_name NpcPortrait
extends Control


## A compact pixel-art scene renderer for Lin Lan's remote body-camera feed.
##
## `set_npc_state()` remains backwards compatible with the original portrait API,
## but it can now receive either the small NPC dictionary or the complete mission
## snapshot. When the complete snapshot is available, the room, resources, flags,
## pending action and ending state all affect the scene.

const MALE_PIXEL_PORTRAIT_PATH := "res://assets/portraits/lin_lan_male_pixel.png"
const FALLBACK_PORTRAIT: Texture2D = preload("res://assets/portraits/lin_lan_male_pixel.png")

const BG := Color("03080c")
const FRAME := Color("376a70")
const CYAN := Color("62b9b3")
const AMBER := Color("d3a354")
const RED := Color("d45e57")
const MUTED := Color("718d91")
const PIXEL := 4.0

var _state: Dictionary = {}
var _flags: Dictionary = {}
var _connection := "local"
var _room_id := "relay_control"
var _room_name := "中继控制室"
var _previous_room_id := ""
var _phase := 0.0
var _transition := 1.0
var _oxygen := 100.0
var _power := 100.0
var _mistakes := 0
var _trust := 50
var _fear := 35
var _thinking := false
var _candidate_pending := false
var _action_active := false
var _action_id := ""
var _action_flash := 0.0
var _action_success := true
var _terminal := false
var _outcome := "ongoing"
var _portrait: Texture2D = FALLBACK_PORTRAIT
var _character_asset := MALE_PIXEL_PORTRAIT_PATH
var _using_male_portrait := true
var _character_visual_rect := Rect2()
var _reduced_motion := false
var _focus_flash := 0.0
var _focus_kind := ""
var _last_event_signature := ""


func _ready() -> void:
	custom_minimum_size = Vector2(240, 218)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_pixel_portrait()
	set_process(true)


func _process(delta: float) -> void:
	if _reduced_motion:
		return
	_phase += delta
	_transition = minf(1.0, _transition + delta * 2.8)
	_action_flash = maxf(0.0, _action_flash - delta)
	_focus_flash = maxf(0.0, _focus_flash - delta)
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		_transition = 1.0
		_action_flash = 0.0
		_focus_flash = 0.0
	set_process(not enabled)
	queue_redraw()


## Backwards-compatible entry point. It accepts the original NPC dictionary and
## also the richer combined mission snapshot supplied by the main UI.
func set_npc_state(state: Dictionary, connection: String = "local") -> void:
	_connection = connection

	var npc := _dictionary(state.get("npc", {}))
	var resources := _dictionary(state.get("resources", {}))
	var merged := npc.duplicate(true)
	merged.merge(state, true)
	_state = merged.duplicate(true)

	_set_room_internal(
		str(merged.get("room_id", merged.get("location_id", _room_id))),
		str(merged.get("room_name", _room_name))
	)
	_oxygen = _number(merged, resources, ["oxygen", "oxygen_percent", "o2"], _oxygen)
	_power = _number(merged, resources, ["power", "power_percent"], _power)
	_mistakes = int(merged.get("mistakes", _mistakes))
	var social := _dictionary(merged.get("npc_social", {}))
	_trust = int(social.get("trust", _trust))
	_fear = int(social.get("fear", _fear))
	_flags = _dictionary(merged.get("flags", _flags)).duplicate(true)
	_thinking = bool(merged.get("thinking", false))
	_candidate_pending = bool(merged.get("candidate_pending", false))
	_terminal = bool(merged.get("is_terminal", false))
	_outcome = str(merged.get("outcome", "ongoing"))

	var pending := _dictionary(merged.get("pending_confirmation", {}))
	if not pending.is_empty():
		_candidate_pending = true
	var last_event := _dictionary(merged.get("last_event", {}))
	if not last_event.is_empty():
		var raw_event_action: Variant = last_event.get("action", last_event.get("action_id", ""))
		var event_action := (
			str((raw_event_action as Dictionary).get("id", ""))
			if raw_event_action is Dictionary
			else str(raw_event_action)
		)
		var signature := "%s|%s|%s" % [last_event.get("turn", ""), event_action, str(last_event.get("text", "")).left(24)]
		if not event_action.is_empty() and signature != _last_event_signature:
			_last_event_signature = signature
			pulse_action(event_action)
			if event_action in ["inspect", "connect", "toggle", "use"] or str(last_event.get("type", "")) in ["puzzle_solved", "ending"]:
				_focus_flash = 1.35
				_focus_kind = str(last_event.get("type", event_action))

	queue_redraw()


## Explicit alias for callers that naturally work with a complete snapshot.
func set_scene_state(snapshot: Dictionary, connection: String = "local") -> void:
	set_npc_state(snapshot, connection)


## Change only the rendered room. The old and new rooms cross-fade behind Lin Lan.
func set_room(room_id: String, room_name: String = "") -> void:
	_set_room_internal(room_id, room_name)
	queue_redraw()


## Hold or release the operating pose. `pulse_action()` is preferable for a
## one-shot event; this method is useful while an asynchronous action is running.
func set_action_active(active: bool, action_id: String = "") -> void:
	_action_active = active
	_action_id = action_id if active else ""
	_action_success = true
	queue_redraw()


## Brief operating animation for a newly completed mission event.
func pulse_action(action_id: String = "") -> void:
	trigger_action(action_id, true)


## Public one-shot action hook used by MissionConsoleUI after an action result.
## Failed operations produce a sharper shake and red feedback without requiring
## an additional sprite frame.
func trigger_action(action_id: String, success: bool = true) -> void:
	_action_id = action_id
	_action_success = success
	_action_flash = 0.85
	if action_id in ["inspect", "connect", "toggle", "use"]:
		_focus_flash = 1.35
		_focus_kind = "hazard" if not success else action_id
	queue_redraw()


## Read-only semantic state for integration tests and accessibility tooling.
## Callers should assert these values instead of coupling to draw-command details.
func get_debug_visual_state() -> Dictionary:
	var condition := "normal"
	if _terminal:
		condition = "terminal"
	elif _oxygen <= 25.0:
		condition = "low_oxygen"
	elif _is_injured():
		condition = "injured"
	elif _is_strained():
		condition = "tense"
	return {
		"room_id": _room_id,
		"display_room": _previous_room_id if _transition < 0.5 and not _previous_room_id.is_empty() else _room_id,
		"transitioning": _transition < 1.0,
		"transition_progress": _transition,
		"condition": condition,
		"action_active": _action_active or _action_flash > 0.0,
		"action_id": _action_id,
		"action_success": _action_success,
		"oxygen": _oxygen,
		"trust": _trust,
		"fear": _fear,
		"focus_active": _focus_flash > 0.0,
		"focus_kind": _focus_kind,
		"framing": "shoulders_up",
		"character_asset": _character_asset,
	}


func _set_room_internal(room_id: String, room_name: String) -> void:
	if room_id.is_empty():
		return
	if room_id != _room_id:
		_previous_room_id = _room_id
		_room_id = room_id
		_transition = 0.0
	if not room_name.is_empty():
		_room_name = room_name


func _load_pixel_portrait() -> void:
	# The trapped technician is consistently male in both the authored asset and
	# the fallback; a failed runtime load must never reveal the retired portrait.
	if _try_load_portrait(MALE_PIXEL_PORTRAIT_PATH):
		_using_male_portrait = true
		return
	_portrait = FALLBACK_PORTRAIT
	_character_asset = MALE_PIXEL_PORTRAIT_PATH
	_using_male_portrait = true


func _try_load_portrait(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var resource := load(path)
	if not resource is Texture2D:
		return false
	_portrait = resource as Texture2D
	_character_asset = path
	return true


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var image_rect := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	var world_rect := Rect2(
		image_rect.position + Vector2(0, 26),
		image_rect.size - Vector2(0, 50)
	)

	if _transition < 1.0 and not _previous_room_id.is_empty():
		_draw_room_scene(_previous_room_id, world_rect, 1.0 - _transition)
		_draw_room_scene(_room_id, world_rect, _transition)
		_draw_transition_shutter(world_rect)
	else:
		_draw_room_scene(_room_id, world_rect, 1.0)

	_draw_character(world_rect)
	_draw_room_foreground(_room_id, world_rect)
	_draw_state_effects(world_rect)
	_draw_focus_overlay(world_rect)
	_draw_feed_effects(image_rect)
	_draw_hud(image_rect)


func _draw_room_scene(room_id: String, rect: Rect2, alpha: float) -> void:
	if alpha <= 0.001:
		return
	match room_id:
		"central_junction":
			_draw_junction(rect, alpha)
		"power_bay":
			_draw_power_bay(rect, alpha)
		"coolant_gallery":
			_draw_coolant_gallery(rect, alpha)
		"escape_pod":
			_draw_escape_pod(rect, alpha)
		_:
			_draw_relay_control(rect, alpha)


func _draw_room_foreground(room_id: String, rect: Rect2) -> void:
	# Foreground silhouettes let machinery pass in front of the portrait, adding
	# depth without requiring another authored sprite sheet.
	match room_id:
		"power_bay":
			_fill(Rect2(rect.position + Vector2(-4, rect.size.y - 31), Vector2(rect.size.x * 0.32, 36)), Color("111918"), 0.88)
			_fill(Rect2(rect.position + Vector2(rect.size.x - 36, 44), Vector2(42, rect.size.y - 39)), Color("181914"), 0.82)
			if not bool(_flags.get("grid_online", false)):
				var spark := 0.35 + 0.35 * sin(_phase * 12.0)
				_draw_arc_flash(rect.position + Vector2(rect.size.x - 29, rect.size.y * 0.47), spark)
		"coolant_gallery":
			_fill(Rect2(rect.position + Vector2(-8, rect.size.y - 24), Vector2(rect.size.x + 16, 30)), Color("7ea3aa"), 0.08 if bool(_flags.get("leak_sealed", false)) else 0.18)
			for index: int in range(3):
				var fog_x := rect.position.x + fmod(_phase * (13.0 + index * 2.0) + index * 71.0, rect.size.x + 45.0) - 28.0
				_fill(Rect2(Vector2(fog_x, rect.end.y - 18.0 - index * 5.0), Vector2(48, 4)), Color("a7c8cd"), 0.10)
		"escape_pod":
			if bool(_flags.get("escape_unlocked", false)):
				_fill(rect, CYAN, 0.025 + 0.012 * sin(_phase * 2.0))
		"central_junction":
			_fill(Rect2(rect.position + Vector2(0, rect.size.y - 15), Vector2(rect.size.x, 17)), Color("0b1116"), 0.72)


func _draw_focus_overlay(rect: Rect2) -> void:
	if _focus_flash <= 0.0:
		return
	var strength := clampf(_focus_flash / 1.35, 0.0, 1.0)
	var focus_rect := rect.grow(-9.0)
	var accent := RED if _focus_kind == "hazard" else AMBER if _focus_kind == "puzzle" else CYAN
	_fill(Rect2(focus_rect.position, Vector2(focus_rect.size.x, 15)), Color("02070a"), 0.72 * strength)
	draw_string(ThemeDB.fallback_font, focus_rect.position + Vector2(5, 11), "FIELD CLOSE-UP // %s" % _focus_kind.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(accent, strength))
	var bracket := 18.0
	var center := _character_visual_rect.get_center() if _character_visual_rect.has_area() else rect.get_center()
	draw_line(center - Vector2(bracket, bracket), center - Vector2(5, bracket), Color(accent, strength), 1.0)
	draw_line(center - Vector2(bracket, bracket), center - Vector2(bracket, 5), Color(accent, strength), 1.0)
	draw_line(center + Vector2(bracket, bracket), center + Vector2(5, bracket), Color(accent, strength), 1.0)
	draw_line(center + Vector2(bracket, bracket), center + Vector2(bracket, 5), Color(accent, strength), 1.0)


func _draw_relay_control(rect: Rect2, alpha: float) -> void:
	_fill(rect, Color("07151a"), alpha)
	# Rear wall panels and a row of telemetry screens.
	for x: int in range(0, int(rect.size.x), 40):
		_fill(Rect2(rect.position + Vector2(x, 0), Vector2(2, rect.size.y)), Color("173139"), alpha * 0.55)
	for index: int in range(3):
		var screen := Rect2(rect.position + Vector2(12 + index * 71, 15), Vector2(56, 36))
		_fill(screen, Color("0b252a"), alpha)
		_stroke(screen, Color("356a6c"), alpha)
		var pulse := 0.45 + 0.3 * sin(_phase * 1.7 + index)
		_fill(Rect2(screen.position + Vector2(7, 8), Vector2(31, 3)), CYAN, alpha * pulse)
		_fill(Rect2(screen.position + Vector2(7, 17), Vector2(42, 2)), CYAN, alpha * 0.28)
		_fill(Rect2(screen.position + Vector2(7, 25), Vector2(23, 2)), AMBER, alpha * 0.42)
	# Console lip and floor markings.
	_fill(Rect2(rect.position + Vector2(0, rect.size.y - 52), Vector2(rect.size.x, 24)), Color("112a30"), alpha)
	_stroke(Rect2(rect.position + Vector2(14, rect.size.y - 43), Vector2(rect.size.x - 28, 22)), Color("315056"), alpha)
	for x: int in range(8, int(rect.size.x), 24):
		_fill(Rect2(rect.position + Vector2(x, rect.size.y - 8), Vector2(13, 2)), Color("27434a"), alpha)


func _draw_junction(rect: Rect2, alpha: float) -> void:
	_fill(rect, Color("0a1015"), alpha)
	# Four converging corridor ribs establish this as the map's central hub.
	for index: int in range(5):
		var inset := float(index * 12)
		_stroke(Rect2(rect.position + Vector2(inset, 8 + inset * 0.22), Vector2(rect.size.x - inset * 2.0, rect.size.y - 23 - inset * 0.45)), Color("263942"), alpha * (0.9 - index * 0.11), 2.0)
	_fill(Rect2(rect.position + Vector2(rect.size.x * 0.5 - 23, 14), Vector2(46, 58)), Color("121c22"), alpha)
	_stroke(Rect2(rect.position + Vector2(rect.size.x * 0.5 - 23, 14), Vector2(46, 58)), Color("3b4c53"), alpha)
	var locked := not bool(_flags.get("escape_unlocked", false))
	var lock_color := RED if locked else CYAN
	for x_offset: float in [-10.0, 10.0]:
		_fill(Rect2(rect.position + Vector2(rect.size.x * 0.5 + x_offset - 3, 22), Vector2(6, 6)), lock_color, alpha * (0.7 + 0.25 * sin(_phase * 3.0)))
	# Moving floor guide lights.
	for index: int in range(7):
		var light_x := fmod(float(index * 38) + _phase * 15.0, rect.size.x)
		_fill(Rect2(rect.position + Vector2(light_x, rect.size.y - 10), Vector2(12, 2)), AMBER, alpha * 0.48)


func _draw_power_bay(rect: Rect2, alpha: float) -> void:
	var online := bool(_flags.get("grid_online", false))
	_fill(rect, Color("10100e") if not online else Color("0b1716"), alpha)
	# Transformer blocks, hanging cables and power buses.
	for index: int in range(3):
		var block := Rect2(rect.position + Vector2(8 + index * 78, 34 + (index % 2) * 9), Vector2(57, 66))
		_fill(block, Color("1c2220"), alpha)
		_stroke(block, Color("555244"), alpha)
		for slot: int in range(3):
			_fill(Rect2(block.position + Vector2(9, 11 + slot * 14), Vector2(39, 4)), Color("343a35"), alpha)
	var cable_colors := [Color("397a91"), Color("81443d"), Color("9b8a3e")]
	for index: int in range(3):
		var x := rect.position.x + 45.0 + index * 59.0
		var points := PackedVector2Array([
			Vector2(x, rect.position.y),
			Vector2(x, rect.position.y + 20 + index * 4),
			Vector2(x + 12, rect.position.y + 30 + index * 4),
			Vector2(x + 12, rect.position.y + 52),
		])
		draw_polyline(points, _alpha(cable_colors[index], alpha), 3.0)
	var bus_color := CYAN if online else AMBER
	_fill(Rect2(rect.position + Vector2(0, rect.size.y - 18), Vector2(rect.size.x, 5)), bus_color, alpha * (0.35 if not online else 0.78))
	if not online and fmod(_phase, 2.2) < 0.12:
		_draw_arc_flash(rect.position + Vector2(rect.size.x - 53, 46), alpha)
	elif online:
		_fill(Rect2(rect.position + Vector2(rect.size.x - 22, 10), Vector2(8, 8)), CYAN, alpha * (0.7 + sin(_phase * 2.0) * 0.15))


func _draw_coolant_gallery(rect: Rect2, alpha: float) -> void:
	var sealed := bool(_flags.get("leak_sealed", false))
	_fill(rect, Color("07141a"), alpha)
	# Layered coolant pipes and valve wheels.
	for index: int in range(3):
		var y := rect.position.y + 20 + index * 35
		_fill(Rect2(Vector2(rect.position.x, y), Vector2(rect.size.x, 8)), Color("24434b"), alpha)
		_fill(Rect2(Vector2(rect.position.x, y), Vector2(rect.size.x, 2)), Color("527178"), alpha * 0.7)
		var wheel_center := Vector2(rect.position.x + 40 + index * 78, y + 5)
		draw_circle(wheel_center, 12.0, _alpha(Color("24343a"), alpha))
		draw_arc(wheel_center, 10.0, 0.0, TAU, 12, _alpha(AMBER, alpha * 0.7), 3.0)
		draw_line(wheel_center - Vector2(8, 0), wheel_center + Vector2(8, 0), _alpha(AMBER, alpha * 0.7), 2.0)
		draw_line(wheel_center - Vector2(0, 8), wheel_center + Vector2(0, 8), _alpha(AMBER, alpha * 0.7), 2.0)
	# Cold fog drifts horizontally until the leak is sealed.
	if not sealed:
		for index: int in range(7):
			var fog_x := rect.position.x + fmod(index * 43.0 + _phase * (8.0 + index), rect.size.x + 35.0) - 20.0
			var fog_y := rect.end.y - 11.0 - (index % 3) * 7.0
			_fill(Rect2(Vector2(fog_x, fog_y), Vector2(28 + (index % 2) * 12, 5)), Color("83acb5"), alpha * 0.12)
	else:
		_fill(Rect2(rect.position + Vector2(rect.size.x - 23, 9), Vector2(8, 8)), CYAN, alpha * 0.75)


func _draw_escape_pod(rect: Rect2, alpha: float) -> void:
	var unlocked := bool(_flags.get("escape_unlocked", false))
	_fill(rect, Color("111317"), alpha)
	# Bright oval hatch with restrained, hopeful illumination.
	var pod_rect := Rect2(rect.position + Vector2(rect.size.x * 0.5 - 55, 7), Vector2(110, rect.size.y - 15))
	_fill(pod_rect, Color("1a2226"), alpha)
	_stroke(pod_rect, Color("677279"), alpha, 3.0)
	var inner := pod_rect.grow(-10.0)
	_fill(inner, Color("182c30") if unlocked else Color("26191a"), alpha)
	_stroke(inner, CYAN if unlocked else RED, alpha * 0.78, 2.0)
	for index: int in range(4):
		var bar_y := inner.position.y + 17 + index * 25
		_fill(Rect2(Vector2(inner.position.x + 8, bar_y), Vector2(inner.size.x - 16, 3)), Color("40545a"), alpha)
	var lamp_alpha := 0.75 + sin(_phase * (2.0 if unlocked else 4.2)) * 0.2
	_fill(Rect2(pod_rect.position + Vector2(8, 7), Vector2(12, 5)), CYAN if unlocked else RED, alpha * lamp_alpha)
	_fill(Rect2(pod_rect.position + Vector2(pod_rect.size.x - 20, 7), Vector2(12, 5)), CYAN if unlocked else RED, alpha * lamp_alpha)


func _draw_character(rect: Rect2) -> void:
	if _portrait == null:
		_character_visual_rect = Rect2()
		return
	var texture_size := _portrait.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		_character_visual_rect = Rect2()
		return
	var source_rect := _shoulders_source_rect(texture_size)

	var operating := _action_active or _action_flash > 0.0
	var low_oxygen := _oxygen <= 25.0
	var strained := _is_strained()
	var injured := _is_injured()
	var breath_speed := 1.55 if low_oxygen else 0.82
	var breath_amount := 0.018 if low_oxygen else 0.007
	var breath := sin(_phase * TAU * breath_speed) * breath_amount
	var bob := sin(_phase * TAU * breath_speed) * (1.8 if low_oxygen else 0.55)
	var fear_shake := clampf((float(_fear) - 45.0) / 35.0, 0.0, 1.0)
	var shake := sin(_phase * 27.0) * (0.8 + fear_shake * 1.25) if strained else sin(_phase * 19.0) * fear_shake * 0.45
	var work_shift := sin(_phase * (15.0 if not _action_success else 7.0)) * (3.1 if operating and not _action_success else 1.45) if operating else 0.0

	# The shoulders sit just behind the lower camera HUD, while the face occupies
	# the central third. Transparent margins still leave enough machinery visible
	# on both sides to identify the current room.
	var max_height := rect.size.y * 1.06
	var max_width := rect.size.x * 0.84
	var scale_factor := minf(max_width / source_rect.size.x, max_height / source_rect.size.y)
	var draw_size := source_rect.size * scale_factor
	var shoulder_base := Vector2(rect.position.x + rect.size.x * 0.53, rect.end.y + 10.0)
	var origin := Vector2(shoulder_base.x - draw_size.x * 0.5 + shake + work_shift, shoulder_base.y - draw_size.y + bob)
	var character_rect := Rect2(origin, draw_size)
	_character_visual_rect = character_rect

	var modulation := _character_tint()
	var lean := -0.030 if injured else 0.0
	if operating:
		lean += 0.017 + sin(_phase * 6.0) * 0.008
	# Breathing and injury motion now pivot at the shoulder line, rather than at
	# the feet as in the former full-body composition.
	var pivot := character_rect.position + character_rect.size * Vector2(0.5, 0.91)
	draw_set_transform(pivot, lean, Vector2(1.0 + breath * 0.22, 1.0 + breath))
	draw_texture_rect_region(
		_portrait,
		Rect2(character_rect.position - pivot, character_rect.size),
		source_rect,
		modulation
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if operating:
		_draw_operating_pixels(character_rect)


func _shoulders_source_rect(texture_size: Vector2) -> Rect2:
	# The male asset is authored as a transparent shoulders-up portrait.
	return Rect2(Vector2.ZERO, texture_size)


func _draw_state_effects(rect: Rect2) -> void:
	var low_oxygen := _oxygen <= 25.0
	if low_oxygen:
		var warning := 0.07 + 0.06 * (0.5 + 0.5 * sin(_phase * 5.5))
		_fill(rect, RED, warning)
		# Position the uneven breath marks from the close-up face, not from the
		# former full-body scene coordinates.
		var face_rect := _character_visual_rect if _character_visual_rect.has_area() else rect
		var breath_x := face_rect.position.x + face_rect.size.x * 0.63
		var breath_y := face_rect.position.y + face_rect.size.y * 0.34
		for index: int in range(3):
			var drift := fmod(_phase * (12.0 + index * 3.0) + index * 13.0, 26.0)
			_fill(Rect2(Vector2(breath_x + drift, breath_y + index * 4), Vector2(8, 2)), Color("a7c5c7"), 0.22 * (1.0 - drift / 30.0))
	elif _oxygen <= 50.0:
		_fill(rect, AMBER, 0.035 + 0.02 * sin(_phase * 2.0))

	if _thinking:
		for index: int in range(3):
			var active := int(_phase * 3.5) % 3 == index
			_fill(Rect2(rect.position + Vector2(11 + index * 7, 11), Vector2(4, 4)), CYAN, 0.85 if active else 0.22)
	if _candidate_pending:
		var pulse := 0.45 + 0.25 * sin(_phase * 3.0)
		_stroke(rect.grow(-3.0), AMBER, pulse, 1.0)
	if _fear >= 70:
		_fill(rect, RED, 0.025 + 0.018 * sin(_phase * 5.0))
	if _terminal:
		var lost := _outcome == "failure"
		_fill(rect, Color("401016") if lost else Color("0c3936"), 0.16)
	elif _action_flash > 0.0 and not _action_success:
		_fill(rect, RED, 0.07 + 0.07 * (_action_flash / 0.85))


func _draw_feed_effects(rect: Rect2) -> void:
	var mood := str(_state.get("mood", "focused")).to_lower()
	var accent := RED if _is_strained() else AMBER if mood in ["cautious", "worried", "thinking", "nervous"] else CYAN
	_fill(rect, Color(0.01, 0.07, 0.08, 0.055))
	_fill(rect, accent, 0.018)
	_draw_vignette(rect)
	_draw_scanlines(rect)

	var sweep_y := rect.position.y + fmod(_phase * 21.0, rect.size.y)
	draw_line(Vector2(rect.position.x, sweep_y), Vector2(rect.end.x, sweep_y), Color(accent, 0.10), 1.0)
	# Occasional block dropout reinforces the remote, damaged-camera presentation.
	if int(_phase * 2.0) % 17 == 0:
		var glitch_y := rect.position.y + fmod(_phase * 47.0, rect.size.y - 18.0)
		_fill(Rect2(Vector2(rect.position.x + 5, glitch_y), Vector2(rect.size.x - 22, 2)), accent, 0.12)


func _draw_hud(image_rect: Rect2) -> void:
	var accent := _accent_color()
	_fill(Rect2(Vector2(4, 4), Vector2(size.x - 8, 25)), Color(0.01, 0.03, 0.04, 0.76))
	var connection_color := CYAN if _connection in ["online", "connecting"] else AMBER
	draw_circle(Vector2(15, 16), 3.5, connection_color)
	draw_string(ThemeDB.fallback_font, Vector2(25, 20), "LINK // %s" % _connection.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, connection_color)
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 75, 20), "CAM 02", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MUTED)

	_fill(Rect2(Vector2(4, size.y - 27), Vector2(size.x - 8, 23)), Color(0.01, 0.03, 0.04, 0.79))
	var room_code := _room_code(_room_id)
	var state_code := _state_code()
	draw_string(ThemeDB.fallback_font, Vector2(10, size.y - 11), "%s  //  %s" % [room_code, state_code], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(MUTED, 0.96))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 49, size.y - 11), "O2 %02d" % int(clampf(_oxygen, 0.0, 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, RED if _oxygen <= 25.0 else accent)

	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), FRAME, false, 2.0)
	_draw_frame_corners(accent)


func _draw_transition_shutter(rect: Rect2) -> void:
	# A quick iris-like camera reacquisition masks the cross-fade between rooms.
	var close_amount := 1.0 - absf(_transition * 2.0 - 1.0)
	var shutter_height := rect.size.y * 0.18 * close_amount
	_fill(Rect2(rect.position, Vector2(rect.size.x, shutter_height)), Color.BLACK, 0.68)
	_fill(Rect2(Vector2(rect.position.x, rect.end.y - shutter_height), Vector2(rect.size.x, shutter_height)), Color.BLACK, 0.68)
	for index: int in range(5):
		var x := rect.position.x + fmod(index * 59.0 + _phase * 80.0, rect.size.x)
		_fill(Rect2(Vector2(x, rect.position.y), Vector2(2, rect.size.y)), CYAN, 0.07 * close_amount)


func _draw_operating_pixels(character_rect: Rect2) -> void:
	# Tool/signal pixels orbit the near shoulder in close framing; keeping them
	# away from the eyes preserves readable emotion during an operation.
	var center := character_rect.position + character_rect.size * Vector2(0.78, 0.72)
	for index: int in range(4):
		var angle := _phase * 4.0 + index * TAU / 4.0
		var point := center + Vector2(cos(angle), sin(angle)) * (10.0 + index % 2 * 5.0)
		var work_color := RED if not _action_success else AMBER if index % 2 == 0 else CYAN
		_fill(Rect2(point.snapped(Vector2(PIXEL, PIXEL)), Vector2(3, 3)), work_color, 0.62)


func _draw_arc_flash(origin: Vector2, alpha: float) -> void:
	var points := PackedVector2Array([
		origin,
		origin + Vector2(-5, 8),
		origin + Vector2(2, 11),
		origin + Vector2(-3, 21),
		origin + Vector2(8, 15),
	])
	draw_polyline(points, _alpha(Color("9de9e1"), alpha * 0.9), 2.0)


func _draw_scanlines(rect: Rect2) -> void:
	for y: int in range(int(rect.position.y) + 2, int(rect.end.y), 4):
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.01, 0.04, 0.05, 0.13), 1.0)


func _draw_vignette(rect: Rect2) -> void:
	for inset: int in range(0, 15):
		var alpha := 0.075 * (1.0 - float(inset) / 15.0)
		var border_rect := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset * 2.0, inset * 2.0))
		draw_rect(border_rect, Color(0.0, 0.0, 0.0, alpha), false, 1.0)


func _draw_frame_corners(accent: Color) -> void:
	var length := 16.0
	var inset := 5.0
	var corners := [
		[Vector2(inset, inset + length), Vector2(inset, inset), Vector2(inset + length, inset)],
		[Vector2(size.x - inset - length, inset), Vector2(size.x - inset, inset), Vector2(size.x - inset, inset + length)],
		[Vector2(inset, size.y - inset - length), Vector2(inset, size.y - inset), Vector2(inset + length, size.y - inset)],
		[Vector2(size.x - inset - length, size.y - inset), Vector2(size.x - inset, size.y - inset), Vector2(size.x - inset, size.y - inset - length)],
	]
	for corner: Array in corners:
		draw_polyline(PackedVector2Array(corner), Color(accent, 0.82), 2.0)


func _fill(rect: Rect2, color: Color, alpha: float = 1.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or alpha <= 0.001:
		return
	draw_rect(rect, _alpha(color, alpha))


func _stroke(rect: Rect2, color: Color, alpha: float = 1.0, width: float = 1.0) -> void:
	if alpha <= 0.001:
		return
	draw_rect(rect, _alpha(color, alpha), false, width)


func _alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(alpha, 0.0, 1.0))


func _character_tint() -> Color:
	if _terminal and _outcome == "failure":
		return Color(0.48, 0.48, 0.52, 0.74)
	if _oxygen <= 25.0:
		return Color(0.76, 0.84, 0.88, 1.0).lerp(RED, 0.10 + 0.06 * sin(_phase * 5.5))
	if _is_strained():
		return Color(0.90, 0.86, 0.82, 1.0)
	if _action_active or _action_flash > 0.0:
		return Color(0.96, 0.77, 0.74, 1.0) if not _action_success else Color(0.91, 1.0, 0.96, 1.0)
	if _fear >= 70:
		return Color(0.90, 0.84, 0.82, 1.0)
	if _trust >= 65:
		return Color(0.90, 0.97, 0.94, 1.0)
	return Color(0.88, 0.94, 0.93, 1.0)


func _is_strained() -> bool:
	var mood := str(_state.get("mood", "focused")).to_lower()
	var stress := str(_state.get("stress", "")).to_lower()
	return _oxygen <= 25.0 or _mistakes >= 2 or _fear >= 70 or mood in ["strained", "afraid", "panic", "hurt", "injured"] or stress in ["strained", "critical_but_functional"]


func _is_injured() -> bool:
	var mood := str(_state.get("mood", "focused")).to_lower()
	var physical := str(_state.get("physical_state", ""))
	return mood in ["hurt", "injured"] or _mistakes > 0 or "伤" in physical or "肩" in physical


func _accent_color() -> Color:
	if _terminal and _outcome == "failure":
		return RED
	if _is_strained():
		return RED
	if _thinking or _candidate_pending or _oxygen <= 50.0:
		return AMBER
	return CYAN


func _state_code() -> String:
	if _terminal:
		return "LOST" if _outcome == "failure" else "EVAC"
	if _oxygen <= 25.0:
		return "HYPOXIA"
	if _action_active or _action_flash > 0.0:
		return "WORKING"
	if _thinking:
		return "LISTENING"
	if _candidate_pending:
		return "AWAIT AUTH"
	if _is_injured():
		return "INJURED"
	if _is_strained():
		return "TENSE"
	return "ACTIVE"


func _room_code(room_id: String) -> String:
	match room_id:
		"relay_control":
			return "RELAY CTRL"
		"central_junction":
			return "JUNCTION"
		"power_bay":
			return "POWER BAY"
		"coolant_gallery":
			return "COOLANT"
		"escape_pod":
			return "ESCAPE POD"
		_:
			return room_id.to_upper().left(11)


func _number(primary: Dictionary, secondary: Dictionary, keys: Array[String], fallback: float) -> float:
	for key: String in keys:
		if primary.has(key):
			return float(primary[key])
		if secondary.has(key):
			return float(secondary[key])
	return fallback


func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}
