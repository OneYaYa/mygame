extends "res://tests/godot/promo_capture.gd"


var _v2_black: ColorRect
var _v2_red_flash: ColorRect
var _v2_punch: Label
var _v2_subtitle: PanelContainer
var _v2_speaker: Label
var _v2_line: Label
var _v2_context: PanelContainer
var _v2_context_rows: Array[Label] = []
var _v2_status: Label
var _v2_end_card: Control
var _v2_logo_cyan: Label
var _v2_logo_red: Label
var _v2_logo: Label
var _glitch_bars: Array[ColorRect] = []


func _ready() -> void:
	_main = MainScene.instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_ui = _main.get_node("MissionConsoleUI") as Control
	_ui.call("skip_intro")
	_build_overlay()
	_build_v2_overlay()
	await get_tree().process_frame
	await _run_v2_storyboard()
	get_tree().quit(0)


func _run_v2_storyboard() -> void:
	# Observation-style crisis-first cold open: no feature explanation.
	_v2_black.visible = true
	_v2_status.text = "K-17  /  DISTRESS SIGNAL"
	_v2_status.visible = true
	_cue("hazard")
	await _wait(0.28)
	await _glitch_cut(Vector2(538, 225), 2.05)
	_set_subtitle("林岚", "……调度？门卡死了。")
	await _show(_v2_subtitle, 0.06)
	await _wait(0.58)

	# Two asymmetric viewpoints, cut like The Operator rather than explained.
	await _glitch_cut(Vector2(205, 225), 1.78)
	await _punch("你看得见全局", CYAN, 0.42)
	await _wait(0.08)
	await _glitch_cut(Vector2(710, 220), 1.65)
	await _punch("他只看得见眼前", AMBER, 0.42)
	await _hide(_v2_subtitle, 0.05)

	# Event[0]-style emotional terminal exchange.
	_cut_to(Vector2(640, 360), 1.0)
	_ui.call("append_dialogue", "OPERATOR", "逃生舱就在前面。", "player")
	_set_subtitle("OPERATOR", "逃生舱就在前面。")
	await _show(_v2_subtitle, 0.05)
	_cue("message")
	await _wait(0.28)
	_ui.call("append_dialogue", "林岚", "我看不见门后。别让我猜。", "npc")
	_set_subtitle("林岚", "我看不见门后。别让我猜。")
	_cue("message")
	await _wait(0.46)
	await _hide(_v2_subtitle, 0.05)

	# SIGNALIS-like red interruption, one idea only.
	await _red_strobe()
	_v2_black.visible = true
	await _punch("AI 不知道答案", TEXT, 0.34)
	_v2_black.visible = false

	# Minimal diegetic HUD: implementation is implied in motion, not lectured.
	await _glitch_cut(Vector2(620, 226), 1.88)
	_v2_context.visible = true
	_v2_context.modulate.a = 1.0
	for row: Label in _v2_context_rows:
		row.visible = true
		row.modulate.a = 0.0
		await _show(row, 0.06)
		_cue("inspection")
		await _wait(0.08)
	await _wait(0.26)
	_v2_context.visible = false

	# AI requests an action; the player remains the authority.
	_ui.call("append_dialogue", "林岚", "蓝色接头 4.2 Ω……等你授权。", "npc")
	_ui.call("show_candidate", "inspect", "telemetry_console")
	await get_tree().process_frame
	await _glitch_cut(Vector2(1130, 565), 1.72)
	_set_subtitle("林岚", "蓝色 4.2 Ω……等你授权。")
	await _show(_v2_subtitle, 0.05)
	_v2_status.text = "PROPOSAL  //  NOT EXECUTED"
	_v2_status.visible = true
	_cue("candidate")
	await _wait(0.40)
	await _hide(_v2_subtitle, 0.04)
	# Give the actual authorization controls one clean beat before execution.
	await _wait(0.26)
	_ui.call("_authorize_candidate")
	_v2_status.text = "AUTHORIZED  //  CORE VERIFY"
	await _green_flash()
	_cue("success")
	await _wait(0.18)

	# Core result, then a fast gameplay montage.
	await _glitch_cut(Vector2(215, 520), 1.58)
	_v2_status.text = "CORE VERIFIED  //  WORLD UPDATED"
	await _wait(0.32)
	await _prepare_clue_workbench()
	await _glitch_cut(Vector2(205, 225), 1.80)
	_cue("movement")
	await _wait(0.22)
	await _glitch_cut(Vector2(540, 225), 1.96)
	_cue("inspection")
	await _wait(0.25)
	await _glitch_cut(Vector2(720, 510), 1.45)
	await _wait(0.26)
	await _glitch_cut(Vector2(1125, 465), 1.64)
	_v2_status.text = "REMOTE DATA  ×  LOCAL SIGHT"
	await _wait(0.48)

	# Consequence spike: low oxygen is rendered by the real portrait/UI state.
	var danger := (_main.get("_snapshot") as Dictionary).duplicate(true)
	var resources := (danger.get("resources", {}) as Dictionary).duplicate(true)
	resources["oxygen"] = 22
	danger["resources"] = resources
	var npc := (danger.get("npc", {}) as Dictionary).duplicate(true)
	npc["mood"] = "afraid"
	npc["fear"] = 78
	danger["npc"] = npc
	_ui.call("render_snapshot", danger)
	await _red_strobe()
	_cut_to(Vector2(540, 225), 2.10)
	_set_subtitle("林岚", "氧气……只剩 22%。")
	await _show(_v2_subtitle, 0.04)
	_cue("hazard")
	await _wait(0.38)
	await _hide(_v2_subtitle, 0.04)
	await _glitch_cut(Vector2(320, 300), 1.12)
	_v2_status.text = "ESC-05  //  LOCKED"
	await _wait(0.20)

	# Final question and compact brand reveal.
	_v2_status.visible = false
	_v2_black.visible = true
	await _punch("你信他吗？", TEXT, 0.40)
	await _wait(0.10)
	await _show_end_card()
	await _wait(0.06)


func _build_v2_overlay() -> void:
	# Hide the explanatory V1 modules; retain only the shared scan-line layer.
	_banner.visible = false
	_context_card.visible = false
	_title_card.visible = false
	_focus_frame.visible = false
	_dim.visible = false

	_v2_black = ColorRect.new()
	_v2_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_v2_black.color = Color("02090c")
	_v2_black.visible = false
	_overlay_root.add_child(_v2_black)

	_v2_red_flash = ColorRect.new()
	_v2_red_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_v2_red_flash.color = Color(0.86, 0.02, 0.04, 0.48)
	_v2_red_flash.visible = false
	_overlay_root.add_child(_v2_red_flash)

	_build_glitch_bars()
	_build_v2_punch()
	_build_v2_subtitle()
	_build_v2_context()
	_build_v2_status()
	_build_v2_letterbox()
	_build_v2_end_card()


func _build_glitch_bars() -> void:
	var specs := [
		[84.0, 4.0, CYAN],
		[192.0, 10.0, RED],
		[408.0, 5.0, AMBER],
		[606.0, 8.0, CYAN],
	]
	for spec: Array in specs:
		var bar := ColorRect.new()
		bar.position = Vector2(-60, float(spec[0]))
		bar.size = Vector2(1400, float(spec[1]))
		bar.color = spec[2] as Color
		bar.visible = false
		_overlay_root.add_child(bar)
		_glitch_bars.append(bar)


func _build_v2_punch() -> void:
	_v2_punch = _label("", 43, TEXT)
	_v2_punch.position = Vector2(90, 510)
	_v2_punch.size = Vector2(1100, 80)
	_v2_punch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_v2_punch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_v2_punch.visible = false
	_overlay_root.add_child(_v2_punch)


func _build_v2_subtitle() -> void:
	_v2_subtitle = PanelContainer.new()
	_v2_subtitle.position = Vector2(185, 592)
	_v2_subtitle.size = Vector2(910, 70)
	_v2_subtitle.add_theme_stylebox_override("panel", _panel_style(Color(0.01, 0.035, 0.045, 0.94), CYAN, 2, 0, 0, 0))
	_v2_subtitle.visible = false
	_overlay_root.add_child(_v2_subtitle)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_v2_subtitle.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)
	_v2_speaker = _label("", 12, AMBER)
	_v2_speaker.custom_minimum_size.x = 120
	_v2_speaker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_v2_speaker)
	_v2_line = _label("", 23, TEXT)
	_v2_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_v2_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_v2_line)


func _build_v2_context() -> void:
	_v2_context = PanelContainer.new()
	_v2_context.position = Vector2(742, 155)
	_v2_context.size = Vector2(430, 224)
	_v2_context.add_theme_stylebox_override("panel", _panel_style(Color(0.01, 0.04, 0.05, 0.94), CYAN, 1, 1, 1, 1))
	_v2_context.visible = false
	_overlay_root.add_child(_v2_context)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_v2_context.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	body.add_child(_label("NPC CONTEXT  //  TURN 03", 12, AMBER))
	var specs := [
		["LOCAL SCENE", "RLY-01  /  VISIBLE ONLY", CYAN],
		["MEMORY", "3 RELEVANT  /  9 HIDDEN", AMBER],
		["RELATION", "TRUST 56  /  FEAR 41", GREEN],
		["ACTION", "1 VALID  /  CORE LOCKED", RED],
	]
	for spec: Array in specs:
		var row := _label("%-12s  %s" % [str(spec[0]), str(spec[1])], 14, spec[2] as Color)
		row.visible = false
		body.add_child(row)
		_v2_context_rows.append(row)


func _build_v2_status() -> void:
	_v2_status = _label("", 13, AMBER)
	_v2_status.position = Vector2(34, 42)
	_v2_status.size = Vector2(720, 24)
	_v2_status.visible = false
	_overlay_root.add_child(_v2_status)


func _build_v2_letterbox() -> void:
	var top := ColorRect.new()
	top.position = Vector2(0, 0)
	top.size = Vector2(1280, 28)
	top.color = Color("02090c")
	_overlay_root.add_child(top)
	var bottom := ColorRect.new()
	bottom.position = Vector2(0, 684)
	bottom.size = Vector2(1280, 36)
	bottom.color = Color("02090c")
	_overlay_root.add_child(bottom)
	var live := _label("BR//07  •  LIVE", 11, RED)
	live.position = Vector2(1120, 4)
	live.size = Vector2(130, 20)
	live.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_overlay_root.add_child(live)


func _build_v2_end_card() -> void:
	_v2_end_card = Control.new()
	_v2_end_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_v2_end_card.visible = false
	_overlay_root.add_child(_v2_end_card)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("02090c")
	_v2_end_card.add_child(bg)
	var red_block := ColorRect.new()
	red_block.position = Vector2(0, 0)
	red_block.size = Vector2(24, 720)
	red_block.color = RED
	_v2_end_card.add_child(red_block)
	var signal_line := ColorRect.new()
	signal_line.position = Vector2(96, 183)
	signal_line.size = Vector2(1088, 2)
	signal_line.color = CYAN
	_v2_end_card.add_child(signal_line)
	_v2_logo_cyan = _label("BLINDSPOT", 72, Color(CYAN, 0.65))
	_v2_logo_red = _label("BLINDSPOT", 72, Color(RED, 0.65))
	_v2_logo = _label("BLINDSPOT", 72, TEXT)
	for logo: Label in [_v2_logo_cyan, _v2_logo_red, _v2_logo]:
		logo.position = Vector2(105, 202)
		logo.size = Vector2(1070, 96)
		logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_v2_end_card.add_child(logo)
	var chinese := _label("盲 区 中 继", 28, AMBER)
	chinese.position = Vector2(105, 304)
	chinese.size = Vector2(1070, 48)
	chinese.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_v2_end_card.add_child(chinese)
	var tagline := _label("和一个不知道答案的 AI，一起逃出去。", 19, TEXT)
	tagline.position = Vector2(105, 385)
	tagline.size = Vector2(1070, 40)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_v2_end_card.add_child(tagline)
	var meta := _label("AI NPC  /  ASYMMETRIC INFORMATION  /  MULTIPLE ROUTES", 11, MUTED)
	meta.position = Vector2(105, 442)
	meta.size = Vector2(1070, 28)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_v2_end_card.add_child(meta)


func _cut_to(focus: Vector2, zoom: float) -> void:
	_ui.scale = Vector2(zoom, zoom)
	_ui.position = Vector2(640, 360) - focus * zoom


func _glitch_cut(focus: Vector2, zoom: float) -> void:
	_v2_black.visible = false
	for index: int in range(_glitch_bars.size()):
		var bar := _glitch_bars[index]
		bar.position.x = -80.0 + float(index * 37)
		bar.visible = true
	_cue("message")
	await _wait(0.025)
	_cut_to(focus, zoom)
	for bar: ColorRect in _glitch_bars:
		bar.visible = false
	await _wait(0.018)


func _red_strobe() -> void:
	_v2_red_flash.visible = true
	_cue("failure")
	await _wait(0.045)
	_v2_red_flash.visible = false
	await _wait(0.025)
	_v2_red_flash.visible = true
	await _wait(0.035)
	_v2_red_flash.visible = false


func _green_flash() -> void:
	_v2_red_flash.color = Color(0.20, 0.95, 0.65, 0.34)
	_v2_red_flash.visible = true
	await _wait(0.055)
	_v2_red_flash.visible = false
	_v2_red_flash.color = Color(0.86, 0.02, 0.04, 0.48)


func _punch(text: String, color: Color, hold: float) -> void:
	_v2_punch.text = text
	_v2_punch.add_theme_color_override("font_color", color)
	await _show(_v2_punch, 0.045)
	await _wait(hold)
	await _hide(_v2_punch, 0.045)


func _set_subtitle(speaker: String, line: String) -> void:
	_v2_speaker.text = speaker.to_upper()
	_v2_line.text = line


func _show_end_card() -> void:
	_v2_black.visible = false
	_v2_end_card.visible = true
	_v2_end_card.modulate.a = 0.0
	_v2_logo_cyan.position.x = 97
	_v2_logo_red.position.x = 113
	_cue("success")
	await _show(_v2_end_card, 0.08)
	await _wait(0.08)
	_v2_logo_cyan.position.x = 105
	_v2_logo_red.position.x = 105
	await _wait(0.92)


func _cue(name: String) -> void:
	var audio: Variant = _main.get("_audio")
	if audio is Node and is_instance_valid(audio as Node):
		(audio as Node).call("play_cue", name)
