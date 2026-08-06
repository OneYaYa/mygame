extends Node


const MainScene := preload("res://scenes/main.tscn")
const CYAN := Color("69d7d0")
const AMBER := Color("f2b84b")
const GREEN := Color("79d2aa")
const RED := Color("ff6961")
const TEXT := Color("dcebed")
const MUTED := Color("8da9ad")
const INK := Color("071419")

var _main: Node
var _ui: Control
var _overlay_root: Control
var _dim: ColorRect
var _banner: PanelContainer
var _banner_kicker: Label
var _banner_title: Label
var _banner_detail: Label
var _context_card: PanelContainer
var _context_chips: Array[PanelContainer] = []
var _title_card: Control
var _title_kicker: Label
var _title_main: Label
var _title_sub: Label
var _title_meta: Label
var _focus_frame: Panel
var _scan_line: ColorRect
var _elapsed := 0.0


func _ready() -> void:
	_main = MainScene.instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_ui = _main.get_node("MissionConsoleUI") as Control
	_ui.call("skip_intro")
	_build_overlay()
	await get_tree().process_frame
	await _run_storyboard()
	get_tree().quit(0)


func _process(delta: float) -> void:
	_elapsed += delta
	if is_instance_valid(_scan_line):
		_scan_line.position.y = fmod(_elapsed * 115.0, 720.0)
		_scan_line.modulate.a = 0.12 + sin(_elapsed * 4.0) * 0.04


func _run_storyboard() -> void:
	# 0.0-1.4s — premise hook.
	_title_kicker.text = "AI NPC × 信息不对称生存推理"
	_title_main.text = "你知道全局。\n他只看见眼前。"
	_title_sub.text = "每一句话，都可能决定谁能活着离开。"
	_title_meta.text = "K-17 DISTRESS RELAY  //  SIGNAL ACQUIRED"
	await _show_title_card(1.0)

	# 1.4-3.5s — staged player/NPC exchange inside the real dialogue log.
	_set_banner(
		"AI NPC // 林岚",
		"他不是全知助手",
		"只依据当前房间、亲眼事实与主观记忆回答"
	)
	await _show(_banner, 0.14)
	await _wait(0.22)
	_ui.call("append_dialogue", "OPERATOR", "林岚，告诉我你亲眼看见了什么。", "player")
	await _wait(0.42)
	_ui.call("set_thinking", true)
	await _wait(0.34)
	_ui.call("append_dialogue", "林岚", "四条走廊在这里汇合。逃生舱门还是红的……门后是什么，我看不见。", "npc")
	_ui.call("set_thinking", false)
	await _wait(0.72)
	await _hide(_banner, 0.14)

	# 3.5-5.45s — context-engineering reveal.
	_dim.color = Color(0.0, 0.02, 0.025, 0.72)
	await _show(_dim, 0.12)
	await _show(_context_card, 0.14)
	for chip: PanelContainer in _context_chips:
		await _show(chip, 0.12)
		await _wait(0.08)
	await _wait(0.62)
	for chip: PanelContainer in _context_chips:
		chip.visible = false
	_context_card.visible = false
	await _hide(_dim, 0.14)

	# 5.45-7.35s — candidate action, authorization, authoritative core.
	_set_banner(
		"ACTION PROTOCOL // 动作协议",
		"AI 可以提议，但不能替你行动",
		"候选动作  →  玩家授权  →  本地核心二次校验"
	)
	await _show(_banner, 0.12)
	_ui.call("append_dialogue", "林岚", "遥测台就在右手边。你确认，我再检查。", "npc")
	_ui.call("show_candidate", "inspect", "telemetry_console")
	_focus_frame.visible = true
	_focus_frame.modulate.a = 0.0
	await _show(_focus_frame, 0.12)
	await _wait(0.92)
	_ui.call("_authorize_candidate")
	_set_banner(
		"AUTHORIZATION ACCEPTED",
		"你的决定，才会改变世界",
		"NPC 输出永远不能直接改写氧气、物品或谜题状态"
	)
	await _wait(0.56)
	_focus_frame.visible = false
	await _hide(_banner, 0.12)

	# 7.35-9.0s — route to the power puzzle and join remote/local evidence.
	await _prepare_clue_workbench()
	_set_banner(
		"ASYMMETRIC CLUES // 双侧线索",
		"你掌握远端数据，他掌握现场读数",
		"把两边的真相拼起来，才能找到唯一生路"
	)
	await _show(_banner, 0.12)
	await _wait(1.28)
	await _hide(_banner, 0.12)

	# 9.0-10.4s — end card.
	_title_kicker.text = "BLINDSPOT RELAY"
	_title_main.text = "盲区中继"
	_title_sub.text = "和一个不知道答案的 AI，一起逃出去。"
	_title_meta.text = "AI NPC  /  信息不对称  /  多路线谜题"
	await _show_title_card(1.05)
	await _wait(0.12)


func _prepare_clue_workbench() -> void:
	_main.call("_on_action_requested", "take", "phase_fuse", {})
	await get_tree().process_frame
	_main.call("_on_action_requested", "move", "central_junction", {})
	await get_tree().process_frame
	_main.call("_on_action_requested", "move", "power_bay", {})
	await get_tree().process_frame
	_main.call("_on_action_requested", "inspect", "cable_panel", {})
	await get_tree().process_frame
	var snapshot := _main.get("_snapshot") as Dictionary
	var telemetry := snapshot.get("operator_telemetry", []) as Array
	for value: Variant in telemetry:
		if str(value).contains("PWR-03"):
			_ui.call("_pin_remote_clue", str(value))
			break
	var evidence := snapshot.get("evidence", {}) as Dictionary
	_ui.call("_pin_local_clue", str(evidence.get("power_local", "")))
	await get_tree().process_frame


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_overlay_root = Control.new()
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay_root)

	_scan_line = ColorRect.new()
	_scan_line.color = CYAN
	_scan_line.position = Vector2(0, 0)
	_scan_line.size = Vector2(1280, 1)
	_scan_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.add_child(_scan_line)

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.02, 0.025, 0.72)
	_dim.visible = false
	_overlay_root.add_child(_dim)

	_build_banner()
	_build_context_card()
	_build_focus_frame()
	_build_title_card()


func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.position = Vector2(0, 0)
	_banner.size = Vector2(1280, 92)
	_banner.add_theme_stylebox_override("panel", _panel_style(Color(0.012, 0.047, 0.057, 0.97), CYAN, 0, 0, 2, 0))
	_banner.visible = false
	_overlay_root.add_child(_banner)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_banner.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	margin.add_child(row)
	_banner_kicker = _label("", 13, AMBER)
	_banner_kicker.custom_minimum_size.x = 245
	_banner_kicker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_banner_kicker)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 1)
	row.add_child(copy)
	_banner_title = _label("", 25, TEXT)
	copy.add_child(_banner_title)
	_banner_detail = _label("", 14, MUTED)
	copy.add_child(_banner_detail)


func _build_context_card() -> void:
	_context_card = PanelContainer.new()
	_context_card.position = Vector2(70, 156)
	_context_card.size = Vector2(1140, 360)
	_context_card.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.055, 0.065, 0.98), CYAN, 2, 2, 2, 2))
	_context_card.visible = false
	_overlay_root.add_child(_context_card)
	var margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_context_card.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	var kicker := _label("CONTEXT COMPILER  //  最小权限上下文", 13, AMBER)
	body.add_child(kicker)
	var headline := _label("AI NPC 不是“全知模型”", 32, TEXT)
	body.add_child(headline)
	var detail := _label("每轮对话，只编译林岚此刻有权知道的信息", 16, MUTED)
	body.add_child(detail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var chip_specs := [
		["LOCAL SCENE", "局部视野", CYAN],
		["MEMORY", "主观记忆", AMBER],
		["RELATIONSHIP", "信任 / 恐惧", GREEN],
		["VALID ACTIONS", "动作白名单", RED],
	]
	for spec: Array in chip_specs:
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(260, 92)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.08, 0.09, 0.96), spec[2] as Color, 1, 1, 1, 1))
		chip.visible = false
		row.add_child(chip)
		var chip_margin := MarginContainer.new()
		chip_margin.add_theme_constant_override("margin_left", 14)
		chip_margin.add_theme_constant_override("margin_top", 12)
		chip.add_child(chip_margin)
		var chip_copy := VBoxContainer.new()
		chip_margin.add_child(chip_copy)
		chip_copy.add_child(_label(str(spec[0]), 12, spec[2] as Color))
		chip_copy.add_child(_label(str(spec[1]), 19, TEXT))
		_context_chips.append(chip)
	var footer := _label("MODEL PROPOSAL  ≠  AUTHORITATIVE WORLD STATE", 12, AMBER)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body.add_child(footer)


func _build_focus_frame() -> void:
	_focus_frame = Panel.new()
	_focus_frame.position = Vector2(995, 476)
	_focus_frame.size = Vector2(275, 168)
	_focus_frame.add_theme_stylebox_override("panel", _panel_style(Color(0, 0, 0, 0.04), AMBER, 3, 3, 3, 3))
	_focus_frame.visible = false
	_overlay_root.add_child(_focus_frame)
	var badge := _label("WAITING FOR PLAYER", 11, AMBER)
	badge.position = Vector2(10, 8)
	badge.size = Vector2(240, 22)
	_focus_frame.add_child(badge)


func _build_title_card() -> void:
	_title_card = Control.new()
	_title_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_card.visible = false
	_overlay_root.add_child(_title_card)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.004, 0.025, 0.031, 0.97)
	_title_card.add_child(background)
	var accent := ColorRect.new()
	accent.position = Vector2(104, 158)
	accent.size = Vector2(8, 314)
	accent.color = AMBER
	_title_card.add_child(accent)
	var copy := VBoxContainer.new()
	copy.position = Vector2(144, 154)
	copy.size = Vector2(990, 390)
	copy.add_theme_constant_override("separation", 12)
	_title_card.add_child(copy)
	_title_kicker = _label("", 15, CYAN)
	copy.add_child(_title_kicker)
	_title_main = _label("", 54, TEXT)
	_title_main.add_theme_constant_override("line_spacing", 3)
	copy.add_child(_title_main)
	_title_sub = _label("", 22, AMBER)
	copy.add_child(_title_sub)
	_title_meta = _label("", 13, MUTED)
	copy.add_child(_title_meta)
	var corner := _label("BR//07", 18, AMBER)
	corner.position = Vector2(1090, 54)
	corner.size = Vector2(130, 32)
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title_card.add_child(corner)


func _set_banner(kicker: String, title: String, detail: String) -> void:
	_banner_kicker.text = kicker
	_banner_title.text = title
	_banner_detail.text = detail


func _show_title_card(hold: float) -> void:
	await _show(_title_card, 0.18)
	await _wait(hold)
	await _hide(_title_card, 0.18)


func _show(control: CanvasItem, duration: float) -> void:
	control.visible = true
	control.modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, duration)
	await tween.finished


func _hide(control: CanvasItem, duration: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(control, "modulate:a", 0.0, duration)
	await tween.finished
	control.visible = false


func _wait(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func _label(text: String, size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	result.add_theme_constant_override("outline_size", 2)
	return result


func _panel_style(background: Color, border: Color, left: int, top: int, right: int, bottom: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = left
	style.border_width_top = top
	style.border_width_right = right
	style.border_width_bottom = bottom
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style
