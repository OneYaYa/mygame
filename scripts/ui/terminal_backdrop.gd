class_name TerminalBackdrop
extends Control


const BACKGROUND := Color("071119")
const GRID_MINOR := Color(0.14, 0.34, 0.39, 0.055)
const GRID_MAJOR := Color(0.19, 0.52, 0.56, 0.075)
const EDGE := Color(0.18, 0.58, 0.62, 0.16)
const SCAN := Color(0.36, 0.85, 0.82, 0.025)

var _scan_y := 0.0
var _reduced_motion := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	if _reduced_motion:
		return
	_scan_y = fmod(_scan_y + delta * 34.0, maxf(size.y, 1.0))
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	set_process(not enabled)
	_scan_y = 0.0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	for x: int in range(0, int(size.x) + 1, 24):
		var color := GRID_MAJOR if x % 120 == 0 else GRID_MINOR
		draw_line(Vector2(x, 0), Vector2(x, size.y), color, 1.0)
	for y: int in range(0, int(size.y) + 1, 24):
		var color := GRID_MAJOR if y % 120 == 0 else GRID_MINOR
		draw_line(Vector2(0, y), Vector2(size.x, y), color, 1.0)
	if not _reduced_motion:
		for offset: int in range(0, 5):
			draw_line(Vector2(0, _scan_y + offset), Vector2(size.x, _scan_y + offset), SCAN, 1.0)
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), EDGE, false, 1.0)
