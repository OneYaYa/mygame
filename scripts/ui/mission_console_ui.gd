class_name MissionConsoleUI
extends Control


signal message_submitted(text: String)
signal action_requested(action_id: String, target: String, arguments: Dictionary)
signal proposal_confirmation_requested(proposal_id: int, accepted: bool)
signal restart_requested()
signal decision_cancel_requested()
signal settings_changed(settings: Dictionary)


const BackdropClass := preload("res://scripts/ui/terminal_backdrop.gd")
const FacilityMapClass := preload("res://scripts/ui/facility_node_map.gd")
const PortraitClass := preload("res://scripts/ui/npc_portrait.gd")
const SignalBootClass := preload("res://scripts/ui/signal_boot_overlay.gd")

const COLOR_BG := Color("071119")
const COLOR_PANEL := Color("0b1a22")
const COLOR_PANEL_ALT := Color("0e222a")
const COLOR_LINE := Color("315f66")
const COLOR_TEXT := Color("d6e1d6")
const COLOR_MUTED := Color("789398")
const COLOR_CYAN := Color("62b9b3")
const COLOR_AMBER := Color("d3a354")
const COLOR_RED := Color("d45e57")
const COLOR_GREEN := Color("68b596")
const GENERIC_ACTION_KEYWORDS: Array[String] = [
	"move", "inspect", "take", "drop", "connect", "toggle", "use", "wait",
	"去", "检查", "拿", "放下", "连接", "阀", "使用", "等待",
]

var _snapshot: Dictionary = {}
var _actions: Array[Dictionary] = []
var _log_entries: Array[Dictionary] = []
var _system_entries: Array[Dictionary] = []
var _pending_proposal: Dictionary = {}
var _pending_candidate: Dictionary = {}
var _connection_status := "local"
var _thinking := false
var _settings: Dictionary = {
	"font_scale": 1.0,
	"volume": 0.65,
	"muted": false,
	"reduced_motion": false,
	"online_enabled": true,
	"quick_safe_actions": true,
}

var _mission_label: Label
var _clock_label: Label
var _core_badge: Label
var _connection_badge: Label
var _facility_map: Control
var _oxygen_bar: ProgressBar
var _power_bar: ProgressBar
var _oxygen_value: Label
var _power_value: Label
var _room_value: Label
var _carried_value: Label
var _objective_text: RichTextLabel
var _portrait: Control
var _npc_name: Label
var _npc_state: Label
var _npc_observation: RichTextLabel
var _dialogue_log: RichTextLabel
var _candidate_label: Label
var _quick_box: GridContainer
var _telemetry_box: VBoxContainer
var _local_clue_box: VBoxContainer
var _workbench_remote: Label
var _workbench_local: Label
var _workbench_summary: Label
var _pinned_remote := ""
var _pinned_local := ""
var _candidate_panel: PanelContainer
var _candidate_action_label: Label
var _candidate_target_label: Label
var _candidate_note: Label
var _authorize_button: Button
var _reject_button: Button
var _keyword_scroll: ScrollContainer
var _keyword_box: HBoxContainer
var _message_input: LineEdit
var _send_button: Button
var _cancel_button: Button
var _status_line: Label
var _restart_button: Button
var _settings_button: Button
var _danger_dialog: ConfirmationDialog
var _restart_dialog: ConfirmationDialog
var _outcome_dialog: AcceptDialog
var _screen_layer: Control
var _intro_overlay: SignalBootOverlay
var _backdrop: Control
var _body: HBoxContainer
var _left_panel: Control
var _right_panel: Control
var _settings_dialog: Window
var _font_slider: HSlider
var _volume_slider: HSlider
var _mute_check: CheckButton
var _motion_check: CheckButton
var _online_check: CheckButton
var _quick_action_check: CheckButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_settings()
	theme = _create_theme()
	_build_interface()
	_apply_settings(false)
	resized.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
	set_process_unhandled_key_input(true)
	call_deferred("focus_message_input")


func get_settings() -> Dictionary:
	return _settings.duplicate(true)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("focus_input"):
		focus_message_input()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart_mission"):
		_request_restart_confirmation()
		get_viewport().set_input_as_handled()


func render_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	var resources: Dictionary = _dictionary(snapshot.get("resources", {}))
	var oxygen := _resource_percent(resources, snapshot, ["oxygen", "oxygen_percent", "o2"], 100.0)
	var power := _resource_percent(resources, snapshot, ["power", "power_percent", "battery"], 100.0)
	_set_meter(_oxygen_bar, _oxygen_value, oxygen, "O₂")
	_set_meter(_power_bar, _power_value, power, "PWR")

	var npc: Dictionary = _dictionary(snapshot.get("npc", {}))
	var room_id := str(snapshot.get("room_id", npc.get("room_id", npc.get("location_id", "UNKNOWN"))))
	var room_name := str(snapshot.get("room_name", npc.get("room_name", room_id)))
	_room_value.text = room_name
	var carried_display: Variant = snapshot.get("carried_item_name", snapshot.get("carried_item", snapshot.get("inventory", "无")))
	var carried_text := _display_value(carried_display, "无")
	_carried_value.text = "无 / EMPTY" if carried_text == "无" else carried_text
	_npc_name.text = str(npc.get("name", "林岚"))
	var mood := str(npc.get("mood", "focused"))
	var npc_status := str(npc.get("status", "ONLINE"))
	var social: Dictionary = _dictionary(snapshot.get("npc_social", {}))
	var trust := int(social.get("trust", 50))
	var link_state := "信赖" if trust >= 60 else "疏离" if trust < 35 else "协作"
	var comm_cycles := int(social.get("communication_cycles", 0))
	_npc_state.text = "%s  ·  %s  ·  %s  ·  通讯周期 %d" % [_mood_label(mood), npc_status.to_upper(), link_state, comm_cycles]
	_npc_state.add_theme_color_override("font_color", _mood_color(mood))
	_refresh_portrait()
	_npc_observation.text = _observation_text(snapshot, npc)

	var map_snapshot := snapshot.duplicate(true)
	var map_npc := npc.duplicate(true)
	map_npc["room_id"] = room_id
	map_snapshot["npc"] = map_npc
	_facility_map.call("set_snapshot", map_snapshot)

	var turn := int(snapshot.get("turn", snapshot.get("step", 0)))
	var max_turns := int(snapshot.get("max_turns", snapshot.get("turn_limit", 0)))
	_clock_label.text = "TURN %02d%s" % [turn, " / %02d" % max_turns if max_turns > 0 else ""]
	_mission_label.text = str(snapshot.get("mission_name", snapshot.get("mission_title", snapshot.get("mission_id", "BLINDSPOT RELAY")))).to_upper()
	_render_objective_panel()
	_render_operator_telemetry(snapshot)
	_render_local_evidence(snapshot)

	var outcome := str(snapshot.get("outcome", ""))
	if bool(snapshot.get("is_terminal", false)) and not outcome.is_empty():
		show_outcome(outcome, snapshot)

	_ingest_snapshot_log(snapshot)
	_update_status_summary()


func set_actions(actions: Array[Dictionary]) -> void:
	_actions = []
	for action: Dictionary in actions:
		_actions.append(action.duplicate(true))
	_render_keyword_cards()
	# The whitelist is deliberately not rendered. It is an internal guard used to
	# resolve one NPC request at a time.
	if not _pending_candidate.is_empty():
		var still_valid := _resolve_candidate(
			str(_pending_candidate.get("id", "")),
			str(_pending_candidate.get("target", ""))
		)
		if still_valid.is_empty():
			_clear_candidate()


func append_dialogue(speaker: String, text: String, kind: String = "npc") -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	if speaker.strip_edges().to_upper() == "SYSTEM":
		append_system(clean, kind)
		return
	_log_entries.append({
		"speaker": speaker,
		"text": clean,
		"kind": kind,
		"time": Time.get_time_string_from_system(),
	})
	if _log_entries.size() > 100:
		_log_entries = _log_entries.slice(_log_entries.size() - 100)
	_render_log()


func append_system(text: String, severity: String = "info") -> void:
	_append_system_entry({
		"speaker": "SYSTEM",
		"text": text,
		"kind": severity,
		"time": Time.get_time_string_from_system(),
	})


func clear_log() -> void:
	_log_entries.clear()
	_system_entries.clear()
	_dialogue_log.clear()
	_render_objective_panel()


func set_connection_status(status: String, detail: String = "") -> void:
	_connection_status = status
	var color := COLOR_CYAN if status in ["online", "connecting"] else COLOR_AMBER if status in ["local", "local_ready", "local_fallback"] else COLOR_RED if status in ["error", "offline"] else COLOR_MUTED
	_connection_badge.text = "● %s" % status.replace("_", " ").to_upper()
	_connection_badge.add_theme_color_override("font_color", color)
	if not detail.is_empty():
		_status_line.text = detail
	_refresh_portrait()


func set_core_status(connected: bool, detail: String = "") -> void:
	_core_badge.text = "● CORE %s" % ("LINKED" if connected else "WAITING")
	_core_badge.add_theme_color_override("font_color", COLOR_GREEN if connected else COLOR_AMBER)
	if not detail.is_empty():
		_status_line.text = detail


func set_thinking(active: bool) -> void:
	_thinking = active
	_message_input.editable = not active
	_send_button.disabled = active
	_send_button.text = "WAIT" if active else "SEND"
	_cancel_button.visible = active
	if active:
		_status_line.text = "远端推理中；设施模拟保持本地权威"
	_refresh_portrait()


func show_candidate(action_id: String, target: String = "") -> void:
	_clear_candidate()
	if action_id.strip_edges().is_empty():
		return
	var resolved := _resolve_candidate(action_id, target)
	if resolved.is_empty():
		_candidate_label.text = "这项请求未通过本地状态校验，已阻止。"
		_candidate_label.add_theme_color_override("font_color", COLOR_RED)
		return
	_pending_candidate = resolved.duplicate(true)
	_candidate_panel.visible = true
	var label := str(resolved.get("label", action_id))
	var resolved_target := str(resolved.get("target", target))
	var dangerous := bool(resolved.get("dangerous", resolved.get("requires_confirmation", false)))
	_candidate_action_label.text = ("⚠  " if dangerous else "▸  ") + label
	_candidate_action_label.add_theme_color_override("font_color", COLOR_RED if dangerous else COLOR_AMBER)
	_candidate_target_label.text = "LOCAL MATCH  //  %s%s" % [
		str(resolved.get("id", action_id)).to_upper(),
		" : %s" % resolved_target if not resolved_target.is_empty() else "",
	]
	_candidate_note.text = (
		"高风险请求。点击后由本地核心校验并立即执行，不再重复弹窗。"
		if dangerous
		else "安全请求已通过本地校验。点击按钮或在输入框留空时按 Enter 即可授权。"
	)
	_authorize_button.text = "确认风险并执行" if dangerous else "授权这一步  [Enter]"
	_candidate_label.text = "林岚正在等你决定是否授权这一项行动。"
	_candidate_label.add_theme_color_override("font_color", COLOR_AMBER)
	_status_line.text = "收到一项行动请求；未授权前不会改变世界状态"
	_refresh_portrait()


func present_confirmation(proposal: Dictionary) -> void:
	_pending_proposal = proposal.duplicate(true)
	_refresh_portrait()
	var action_value: Variant = proposal.get("action", proposal.get("action_id", "危险动作"))
	var action_label := str(proposal.get("label", ""))
	if action_label.is_empty() and action_value is Dictionary:
		var action := action_value as Dictionary
		action_label = "%s  %s" % [str(action.get("id", "危险动作")).to_upper(), str(action.get("target", ""))]
	elif action_label.is_empty():
		action_label = str(action_value)
	var reason := str(proposal.get("reason", proposal.get("warning", proposal.get("message", "该动作可能消耗资源或造成不可逆后果。"))))
	_danger_dialog.title = "危险动作二次确认"
	_danger_dialog.dialog_text = "%s\n\n%s\n\n只有确认后，Godot 本地模拟才会执行。" % [action_label, reason]
	_danger_dialog.popup_centered(Vector2i(520, 250))


func show_action_result(result: Dictionary) -> void:
	var ok := bool(result.get("ok", false))
	var message := str(result.get("message", result.get("reason", result.get("status", "动作请求已处理"))))
	# Executed actions arrive through the core snapshot log. Only non-event
	# results (invalid, canceled, stale) are written here.
	if str(result.get("status", "")) != "executed":
		append_system(message, "success" if ok else "warning")
	_status_line.text = message
	var action: Dictionary = _dictionary(result.get("action", {}))
	var action_id := str(action.get("id", result.get("action_id", "")))
	if is_instance_valid(_portrait) and _portrait.has_method("trigger_action") and not action_id.is_empty():
		_portrait.call("trigger_action", action_id, ok)
	_refresh_portrait()


func show_outcome(outcome: String, snapshot: Dictionary = {}) -> void:
	if _outcome_dialog.visible:
		return
	var normalized := outcome.to_lower()
	var title := "任务结束"
	if normalized in ["success", "rescued", "clean_success"]:
		title = "中继恢复 / 人员撤离"
	elif normalized in ["costly_success", "partial_success", "success_with_cost"]:
		title = "代价撤离"
	elif normalized in ["failure", "dead", "oxygen_depleted"]:
		title = "通讯终止"
	var resources: Dictionary = _dictionary(snapshot.get("resources", {}))
	var debrief: Dictionary = _dictionary(snapshot.get("debrief", {}))
	_outcome_dialog.title = str(debrief.get("title", title))
	_outcome_dialog.dialog_text = "%s\n\nOUTCOME: %s\nSCENARIO: %s\nROUTE: %s\nTURN: %s\nCOMM CYCLES: %s\nO₂: %s\nPOWER: %s\nMISTAKES: %s\n关系：%s\n\n可从右上角重新开始新的事故变体。" % [
		str(debrief.get("body", "任务记录已封存。")),
		outcome.to_upper(),
		str(debrief.get("scenario_id", snapshot.get("scenario_id", "--"))),
		str(debrief.get("power_route", "--")).to_upper(),
		str(snapshot.get("turn", "--")),
		str(debrief.get("communication_cycles", 0)),
		str(resources.get("oxygen", "--")),
		str(resources.get("power", "--")),
		str(snapshot.get("mistakes", 0)),
		str(debrief.get("relationship", "保持专业")),
	]
	_outcome_dialog.popup_centered(Vector2i(480, 270))


func reset_console() -> void:
	_pending_proposal.clear()
	_pending_candidate.clear()
	_pinned_remote = ""
	_pinned_local = ""
	_update_workbench()
	if _danger_dialog.visible:
		_danger_dialog.hide()
	if _outcome_dialog.visible:
		_outcome_dialog.hide()
	clear_log()
	show_candidate("")
	set_thinking(false)
	append_system("任务状态已由本地核心重置。", "info")


func focus_message_input() -> void:
	if is_instance_valid(_message_input) and _message_input.editable:
		_message_input.grab_focus()


func get_intro_debug_state() -> Dictionary:
	if not is_instance_valid(_intro_overlay):
		return {
			"active": false,
			"completed": true,
			"phase": "unavailable",
			"screen_restored": true,
		}
	return _intro_overlay.get_intro_debug_state()


func skip_intro() -> void:
	if is_instance_valid(_intro_overlay):
		_intro_overlay.skip_intro()


func _build_interface() -> void:
	_screen_layer = Control.new()
	_screen_layer.name = "ScreenLayer"
	_screen_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_layer)

	_backdrop = BackdropClass.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_layer.add_child(_backdrop)

	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		safe.add_theme_constant_override("margin_%s" % side, 10)
	_screen_layer.add_child(safe)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	safe.add_child(root_box)
	_build_header(root_box)
	_build_body(root_box)
	_build_composer(root_box)
	_build_footer(root_box)
	_build_dialogs()
	_build_intro_overlay()


func _build_intro_overlay() -> void:
	_intro_overlay = SignalBootClass.new()
	_intro_overlay.name = "SignalBootOverlay"
	_intro_overlay.configure(_screen_layer)
	_intro_overlay.intro_finished.connect(_on_intro_finished)
	add_child(_intro_overlay)
	if bool(_settings.get("reduced_motion", false)):
		_intro_overlay.call_deferred("skip_intro")


func _on_intro_finished(_skipped: bool) -> void:
	call_deferred("focus_message_input")


func _build_header(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 48
	parent.add_child(panel)
	var margin := _margin(10, 5)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)
	var mark := Label.new()
	mark.text = "BR//07"
	mark.add_theme_color_override("font_color", COLOR_AMBER)
	mark.add_theme_font_size_override("font_size", 17)
	row.add_child(mark)
	_mission_label = Label.new()
	_mission_label.text = "BLINDSPOT RELAY"
	_mission_label.add_theme_font_size_override("font_size", 17)
	_mission_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_mission_label)
	_core_badge = Label.new()
	_core_badge.text = "● CORE WAITING"
	_core_badge.add_theme_color_override("font_color", COLOR_AMBER)
	row.add_child(_core_badge)
	_connection_badge = Label.new()
	_connection_badge.text = "● LOCAL"
	_connection_badge.add_theme_color_override("font_color", COLOR_AMBER)
	row.add_child(_connection_badge)
	_clock_label = Label.new()
	_clock_label.text = "TURN 00"
	_clock_label.add_theme_color_override("font_color", COLOR_CYAN)
	row.add_child(_clock_label)
	_settings_button = Button.new()
	_settings_button.text = "⚙  SETTINGS"
	_settings_button.pressed.connect(_open_settings)
	row.add_child(_settings_button)
	_restart_button = Button.new()
	_restart_button.text = "↻  RESTART"
	_restart_button.tooltip_text = "Ctrl+R"
	_restart_button.pressed.connect(_request_restart_confirmation)
	row.add_child(_restart_button)


func _build_body(parent: VBoxContainer) -> void:
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	parent.add_child(_body)
	_build_left_column(_body)
	_build_center_column(_body)
	_build_right_column(_body)


func _build_left_column(parent: HBoxContainer) -> void:
	var box := _section(parent, "FACILITY / 设施遥测", Vector2(400, 0))
	_left_panel = box.get_parent().get_parent() as Control
	_facility_map = FacilityMapClass.new()
	_facility_map.size_flags_vertical = Control.SIZE_FILL
	box.add_child(_facility_map)
	_facility_map.custom_minimum_size.y = 200.0
	var rule := HSeparator.new()
	box.add_child(rule)
	var resource_title := _small_header("RESOURCE BUDGET / 资源")
	box.add_child(resource_title)
	var oxygen_row := _meter_row("OXYGEN", COLOR_CYAN)
	box.add_child(oxygen_row["root"])
	_oxygen_bar = oxygen_row["bar"] as ProgressBar
	_oxygen_value = oxygen_row["value"] as Label
	var power_row := _meter_row("POWER", COLOR_AMBER)
	box.add_child(power_row["root"])
	_power_bar = power_row["bar"] as ProgressBar
	_power_value = power_row["value"] as Label
	var facts := GridContainer.new()
	facts.columns = 2
	facts.add_theme_constant_override("h_separation", 10)
	facts.add_theme_constant_override("v_separation", 5)
	box.add_child(facts)
	facts.add_child(_muted_label("NPC LOCATION"))
	_room_value = _value_label("UNKNOWN")
	facts.add_child(_room_value)
	facts.add_child(_muted_label("CARRIED ITEM"))
	_carried_value = _value_label("NONE")
	facts.add_child(_carried_value)
	_objective_text = RichTextLabel.new()
	_objective_text.bbcode_enabled = true
	_objective_text.custom_minimum_size.y = 150
	_objective_text.fit_content = false
	_objective_text.scroll_active = true
	_objective_text.selection_enabled = true
	_objective_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_objective_text.text = "[color=#789398]等待任务核心投影目标……[/color]"
	box.add_child(_objective_text)


func _build_center_column(parent: HBoxContainer) -> void:
	var box := _section(parent, "REMOTE CHANNEL / 林岚", Vector2(0, 0))
	(box.get_parent().get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var upper := HBoxContainer.new()
	upper.custom_minimum_size.y = 250
	upper.add_theme_constant_override("separation", 10)
	box.add_child(upper)
	_portrait = PortraitClass.new()
	_portrait.custom_minimum_size = Vector2(220, 250)
	upper.add_child(_portrait)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 7)
	upper.add_child(identity)
	_npc_name = Label.new()
	_npc_name.text = "林岚"
	_npc_name.add_theme_font_size_override("font_size", 25)
	identity.add_child(_npc_name)
	_npc_state = Label.new()
	_npc_state.text = "FOCUSED  ·  ONLINE"
	_npc_state.add_theme_color_override("font_color", COLOR_CYAN)
	identity.add_child(_npc_state)
	var divider := HSeparator.new()
	identity.add_child(divider)
	_npc_observation = RichTextLabel.new()
	_npc_observation.bbcode_enabled = true
	_npc_observation.fit_content = false
	_npc_observation.scroll_active = true
	_npc_observation.custom_minimum_size.y = 126
	_npc_observation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_npc_observation.text = "[color=#789398]OBSERVATION[/color]\n等待林岚的局部观察。"
	identity.add_child(_npc_observation)
	_candidate_label = Label.new()
	_candidate_label.text = "先听他说。行动请求会在右侧单独等待授权。"
	_candidate_label.add_theme_color_override("font_color", COLOR_MUTED)
	_candidate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_child(_candidate_label)

	box.add_child(_small_header("DIALOGUE LOG / 通讯记录"))
	_dialogue_log = RichTextLabel.new()
	_dialogue_log.bbcode_enabled = true
	_dialogue_log.scroll_active = true
	_dialogue_log.scroll_following = true
	_dialogue_log.selection_enabled = true
	_dialogue_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue_log.text = "[color=#789398]链路待命。所有模型动作仅作为候选显示。[/color]"
	box.add_child(_dialogue_log)


func _build_right_column(parent: HBoxContainer) -> void:
	var box := _section(parent, "OPERATOR CHANNEL / 调度员", Vector2(312, 0))
	_right_panel = box.get_parent().get_parent() as Control
	box.add_child(_small_header("CHECK IN / 先和他说话"))
	_quick_box = GridContainer.new()
	_quick_box.columns = 2
	_quick_box.add_theme_constant_override("h_separation", 4)
	_quick_box.add_theme_constant_override("v_separation", 4)
	box.add_child(_quick_box)
	var quick_prompts: Array[Dictionary] = [
		{"label": "尝试询问他的状态", "message": "林岚，你现在感觉怎么样？哪里最难受？"},
		{"label": "尝试询问他的周边环境", "message": "先别动。告诉我你周围能听见、闻到或者看见什么。"},
		{"label": "尝试安抚他的心情", "message": "我在，别怕。慢一点，我们一起想办法。"},
		{"label": "尝试询问他最后的记忆", "message": "你最后还记得什么？不用急，想到什么说什么。"},
	]
	for index: int in range(quick_prompts.size()):
		var prompt: Dictionary = quick_prompts[index]
		var label := str(prompt.get("label", "尝试和他交流"))
		var message := str(prompt.get("message", label))
		var button := Button.new()
		button.text = "%02d  %s" % [index + 1, label]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("quick_message", message)
		button.pressed.connect(_submit_quick.bind(message))
		_quick_box.add_child(button)
	var separator := HSeparator.new()
	box.add_child(separator)
	var evidence_scroll := ScrollContainer.new()
	evidence_scroll.custom_minimum_size.y = 160
	evidence_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	evidence_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	evidence_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(evidence_scroll)
	var evidence_box := VBoxContainer.new()
	evidence_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	evidence_box.add_theme_constant_override("separation", 4)
	evidence_scroll.add_child(evidence_box)
	evidence_box.add_child(_small_header("OPERATOR TELEMETRY / 调度员独占遥测"))
	_telemetry_box = VBoxContainer.new()
	_telemetry_box.add_theme_constant_override("separation", 3)
	evidence_box.add_child(_telemetry_box)
	evidence_box.add_child(_small_header("LOCAL EVIDENCE / 林岚已确认线索"))
	_local_clue_box = VBoxContainer.new()
	_local_clue_box.add_theme_constant_override("separation", 3)
	evidence_box.add_child(_local_clue_box)
	_build_clue_workbench(evidence_box)
	var privacy := Label.new()
	privacy.text = "点击两侧线索固定到工作台；远端数据不会发送给林岚。"
	privacy.add_theme_font_size_override("font_size", 10)
	privacy.add_theme_color_override("font_color", Color(COLOR_MUTED, 0.78))
	evidence_box.add_child(privacy)
	var candidate_separator := HSeparator.new()
	box.add_child(candidate_separator)
	box.add_child(_small_header("REQUEST / 单步授权"))
	_build_candidate_card(box)


func _build_clue_workbench(parent: VBoxContainer) -> void:
	parent.add_child(_small_header("CLUE WORKBENCH / 线索工作台"))
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("09161c")
	style.border_color = Color("3e7074")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var margin := _margin(7, 5)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	margin.add_child(content)
	_workbench_remote = Label.new()
	_workbench_remote.text = "REMOTE  //  点击一条调度遥测"
	_workbench_remote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workbench_remote.add_theme_color_override("font_color", COLOR_CYAN)
	_workbench_remote.add_theme_font_size_override("font_size", 10)
	content.add_child(_workbench_remote)
	_workbench_local = Label.new()
	_workbench_local.text = "LOCAL   //  点击一条现场线索"
	_workbench_local.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workbench_local.add_theme_color_override("font_color", COLOR_AMBER)
	_workbench_local.add_theme_font_size_override("font_size", 10)
	content.add_child(_workbench_local)
	_workbench_summary = Label.new()
	_workbench_summary.text = "等待拼合两侧证据。"
	_workbench_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workbench_summary.add_theme_color_override("font_color", COLOR_MUTED)
	_workbench_summary.add_theme_font_size_override("font_size", 10)
	content.add_child(_workbench_summary)


func _build_candidate_card(parent: VBoxContainer) -> void:
	_candidate_panel = PanelContainer.new()
	_candidate_panel.visible = false
	_candidate_panel.custom_minimum_size.y = 136
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("111f24")
	card_style.border_color = COLOR_AMBER
	card_style.set_border_width_all(1)
	card_style.corner_radius_top_left = 3
	card_style.corner_radius_top_right = 3
	card_style.corner_radius_bottom_left = 3
	card_style.corner_radius_bottom_right = 3
	_candidate_panel.add_theme_stylebox_override("panel", card_style)
	parent.add_child(_candidate_panel)
	var margin := _margin(8, 7)
	_candidate_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	margin.add_child(content)
	_candidate_action_label = Label.new()
	_candidate_action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_candidate_action_label.add_theme_font_size_override("font_size", 14)
	content.add_child(_candidate_action_label)
	_candidate_target_label = Label.new()
	_candidate_target_label.add_theme_color_override("font_color", COLOR_MUTED)
	_candidate_target_label.add_theme_font_size_override("font_size", 10)
	content.add_child(_candidate_target_label)
	_candidate_note = Label.new()
	_candidate_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_candidate_note.add_theme_color_override("font_color", COLOR_TEXT)
	_candidate_note.add_theme_font_size_override("font_size", 11)
	content.add_child(_candidate_note)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	content.add_child(controls)
	_authorize_button = Button.new()
	_authorize_button.text = "授权这一步"
	_authorize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_authorize_button.add_theme_color_override("font_color", COLOR_GREEN)
	_authorize_button.pressed.connect(_authorize_candidate)
	controls.add_child(_authorize_button)
	_reject_button = Button.new()
	_reject_button.text = "不授权 / 清除"
	_reject_button.pressed.connect(_reject_candidate)
	controls.add_child(_reject_button)


func _build_composer(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 90
	parent.add_child(panel)
	var margin := _margin(10, 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var keyword_row := HBoxContainer.new()
	keyword_row.add_theme_constant_override("separation", 8)
	column.add_child(keyword_row)
	var keyword_header := Label.new()
	keyword_header.text = "KEYWORDS / 点击填入"
	keyword_header.add_theme_color_override("font_color", COLOR_MUTED)
	keyword_header.add_theme_font_size_override("font_size", 10)
	keyword_header.custom_minimum_size.x = 138
	keyword_row.add_child(keyword_header)
	_keyword_scroll = ScrollContainer.new()
	_keyword_scroll.custom_minimum_size.y = 28
	_keyword_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keyword_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_keyword_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	keyword_row.add_child(_keyword_scroll)
	_keyword_box = HBoxContainer.new()
	_keyword_box.add_theme_constant_override("separation", 5)
	_keyword_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keyword_scroll.add_child(_keyword_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var channel := Label.new()
	channel.text = "TX\nOPERATOR"
	channel.add_theme_color_override("font_color", COLOR_CYAN)
	channel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	channel.custom_minimum_size.x = 84
	row.add_child(channel)
	_message_input = LineEdit.new()
	_message_input.placeholder_text = "输入指令或追问他，例如：检查遥测台；AI 提议后仍需在右侧授权"
	_message_input.max_length = 500
	_message_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_input.text_submitted.connect(_submit_message)
	row.add_child(_message_input)
	_send_button = Button.new()
	_send_button.text = "SEND"
	_send_button.custom_minimum_size.x = 100
	_send_button.pressed.connect(_submit_message_from_button)
	row.add_child(_send_button)
	_cancel_button = Button.new()
	_cancel_button.text = "CANCEL"
	_cancel_button.visible = false
	_cancel_button.custom_minimum_size.x = 84
	_cancel_button.add_theme_color_override("font_color", COLOR_AMBER)
	_cancel_button.pressed.connect(_cancel_decision)
	row.add_child(_cancel_button)


func _build_footer(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 22
	parent.add_child(row)
	_status_line = Label.new()
	_status_line.text = "SYSTEM READY  ·  Ctrl+T 聚焦输入  ·  Ctrl+R 重开"
	_status_line.add_theme_color_override("font_color", COLOR_MUTED)
	_status_line.add_theme_font_size_override("font_size", 11)
	_status_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status_line)
	var authority := Label.new()
	authority.text = "AUTHORITATIVE STATE: LOCAL"
	authority.add_theme_color_override("font_color", COLOR_GREEN)
	authority.add_theme_font_size_override("font_size", 11)
	row.add_child(authority)


func _build_dialogs() -> void:
	_danger_dialog = ConfirmationDialog.new()
	_danger_dialog.ok_button_text = "确认执行"
	_danger_dialog.cancel_button_text = "保持原位"
	_danger_dialog.confirmed.connect(_confirm_pending_proposal.bind(true))
	_danger_dialog.canceled.connect(_confirm_pending_proposal.bind(false))
	add_child(_danger_dialog)
	_restart_dialog = ConfirmationDialog.new()
	_restart_dialog.title = "重新开始任务"
	_restart_dialog.dialog_text = "当前任务状态和通讯记录将被重置。确定重开？"
	_restart_dialog.ok_button_text = "重开任务"
	_restart_dialog.cancel_button_text = "继续当前任务"
	_restart_dialog.confirmed.connect(_emit_restart)
	add_child(_restart_dialog)
	_outcome_dialog = AcceptDialog.new()
	_outcome_dialog.ok_button_text = "返回控制台"
	add_child(_outcome_dialog)
	_build_settings_dialog()


func _build_settings_dialog() -> void:
	_settings_dialog = Window.new()
	_settings_dialog.title = "控制台设置 / SETTINGS"
	_settings_dialog.size = Vector2i(520, 460)
	_settings_dialog.min_size = Vector2i(440, 410)
	_settings_dialog.transient = true
	_settings_dialog.exclusive = false
	_settings_dialog.visible = false
	_settings_dialog.close_requested.connect(_settings_dialog.hide)
	add_child(_settings_dialog)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	_settings_dialog.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var intro := Label.new()
	intro.text = "这些选项保存在本机，不会发送给模型。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(intro)
	content.add_child(_small_header("TEXT SIZE / 字号"))
	_font_slider = HSlider.new()
	_font_slider.min_value = 0.9
	_font_slider.max_value = 1.45
	_font_slider.step = 0.05
	_font_slider.set_value_no_signal(float(_settings.get("font_scale", 1.0)))
	_font_slider.value_changed.connect(_on_settings_control_changed.unbind(1))
	content.add_child(_font_slider)
	content.add_child(_small_header("AUDIO / 程序化无线电音频"))
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_slider.set_value_no_signal(float(_settings.get("volume", 0.65)))
	_volume_slider.value_changed.connect(_on_settings_control_changed.unbind(1))
	content.add_child(_volume_slider)
	_mute_check = CheckButton.new()
	_mute_check.text = "静音"
	_mute_check.set_pressed_no_signal(bool(_settings.get("muted", false)))
	_mute_check.toggled.connect(_on_settings_control_changed.unbind(1))
	content.add_child(_mute_check)
	_motion_check = CheckButton.new()
	_motion_check.text = "减少闪烁、震动和持续扫描动画"
	_motion_check.set_pressed_no_signal(bool(_settings.get("reduced_motion", false)))
	_motion_check.toggled.connect(_on_settings_control_changed.unbind(1))
	content.add_child(_motion_check)
	_online_check = CheckButton.new()
	_online_check.text = "启用在线 AI 增强（关闭后固定使用本地规则）"
	_online_check.set_pressed_no_signal(bool(_settings.get("online_enabled", true)))
	_online_check.toggled.connect(_on_settings_control_changed.unbind(1))
	content.add_child(_online_check)
	_quick_action_check = CheckButton.new()
	_quick_action_check.text = "安全候选可按 Enter 快速授权（危险动作仍需明确确认）"
	_quick_action_check.set_pressed_no_signal(bool(_settings.get("quick_safe_actions", true)))
	_quick_action_check.toggled.connect(_on_settings_control_changed.unbind(1))
	content.add_child(_quick_action_check)
	var close_button := Button.new()
	close_button.text = "保存并返回控制台"
	close_button.pressed.connect(_settings_dialog.hide)
	content.add_child(close_button)


func _section(parent: HBoxContainer, title: String, minimum: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var margin := _margin(9, 8)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_color_override("font_color", COLOR_AMBER)
	heading.add_theme_font_size_override("font_size", 12)
	box.add_child(heading)
	return box


func _margin(horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	return margin


func _meter_row(label_text: String, color: Color) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 62
	label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(label)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 14
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 1
	fill.corner_radius_top_right = 1
	fill.corner_radius_bottom_left = 1
	fill.corner_radius_bottom_right = 1
	bar.add_theme_stylebox_override("fill", fill)
	root.add_child(bar)
	var value := Label.new()
	value.text = "100%"
	value.custom_minimum_size.x = 48
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color", color)
	root.add_child(value)
	return {"root": root, "bar": bar, "value": value}


func _small_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", COLOR_MUTED)
	label.add_theme_font_size_override("font_size", 10)
	return label


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", COLOR_MUTED)
	label.add_theme_font_size_override("font_size", 10)
	return label


func _value_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 120.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _set_meter(bar: ProgressBar, value_label: Label, value: float, prefix: String) -> void:
	var normalized := clampf(value * 100.0 if value >= 0.0 and value <= 1.0 else value, 0.0, 100.0)
	bar.value = normalized
	value_label.text = "%d%%" % int(round(normalized))
	var color := COLOR_RED if normalized <= 20.0 else COLOR_AMBER if normalized <= 45.0 else COLOR_CYAN if prefix == "O₂" else COLOR_GREEN
	value_label.add_theme_color_override("font_color", color)
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = color


func _resource_percent(resources: Dictionary, snapshot: Dictionary, keys: Array[String], fallback: float) -> float:
	for key: String in keys:
		if resources.has(key):
			return float(resources[key])
		if snapshot.has(key):
			return float(snapshot[key])
	return fallback


func _observation_text(snapshot: Dictionary, npc: Dictionary) -> String:
	var observation: Dictionary = _dictionary(snapshot.get("observation", npc.get("observation", {})))
	var summary := str(observation.get("summary", npc.get("observation_summary", snapshot.get("observation_summary", "尚未收到新的局部观察。"))))
	var hazards: Array = _array(observation.get("hazards", []))
	var result := "[color=#789398]LOCAL OBSERVATION[/color]\n%s" % _escape_bbcode(summary)
	if not hazards.is_empty():
		result += "\n[color=#d45e57]HAZARD[/color]  %s" % _escape_bbcode(_display_value(hazards[0], "未知风险"))
	return result


func _objective_body(snapshot: Dictionary) -> String:
	var objective := str(snapshot.get("objective", snapshot.get("current_objective", "抵达逃生舱；交换信息后再确认行动。")))
	var guidance: Dictionary = _dictionary(snapshot.get("guidance", {}))
	var result := ""
	if not guidance.is_empty():
		var instruction := str(guidance.get("instruction", "")).strip_edges()
		var example := str(guidance.get("example_command", "")).strip_edges()
		result = "[color=#d3a354][b]NEXT / 现在做什么[/b][/color]\n%s" % _escape_bbcode(instruction)
		if not example.is_empty():
			result += "\n[color=#62b9b3]输入示例[/color]  “%s”" % _escape_bbcode(example)
		result += "\n[color=#789398]操作方式[/color]  输入指令 → AI 提出动作 → 右侧授权执行"
		result += "\n\n[color=#789398]OBJECTIVE / 总目标[/color]\n%s" % _escape_bbcode(objective)
	else:
		result = "[color=#789398]OBJECTIVE[/color]\n%s" % _escape_bbcode(objective)
	var hint := _context_hint(snapshot)
	if guidance.is_empty() and not hint.is_empty():
		result += "\n[color=#62b9b3]HINT[/color] %s" % _escape_bbcode(hint)
	return result


func _render_objective_panel() -> void:
	if not is_instance_valid(_objective_text):
		return
	var result := _objective_body(_snapshot)
	if not _system_entries.is_empty():
		result += "\n\n[color=#789398]SYSTEM FEED / 系统事件[/color]"
		# Keep the panel glanceable. Full deduplicated history remains in memory,
		# while the left rail behaves like a live status display for the latest event.
		var start := maxi(0, _system_entries.size() - 1)
		for index: int in range(start, _system_entries.size()):
			var entry: Dictionary = _system_entries[index]
			var kind := str(entry.get("kind", "info"))
			var color := _log_color(kind).to_html(false)
			var timestamp := _escape_bbcode(str(entry.get("time", "--:--")))
			var message := _escape_bbcode(str(entry.get("text", "")).strip_edges().left(260))
			result += "\n[color=#526d73]%s[/color] [color=%s][b]SYSTEM[/b][/color]  %s" % [timestamp, color, message]
	_objective_text.text = result


func _append_system_entry(entry: Dictionary) -> void:
	var clean := str(entry.get("text", "")).strip_edges()
	if clean.is_empty():
		return
	var source_id := str(entry.get("source_id", ""))
	if not source_id.is_empty():
		for existing: Dictionary in _system_entries:
			if str(existing.get("source_id", "")) == source_id:
				return
	var stored := entry.duplicate(true)
	stored["speaker"] = "SYSTEM"
	stored["text"] = clean
	_system_entries.append(stored)
	if _system_entries.size() > 40:
		_system_entries = _system_entries.slice(_system_entries.size() - 40)
	_render_objective_panel()


func _context_hint(snapshot: Dictionary) -> String:
	var flags: Dictionary = _dictionary(snapshot.get("flags", {}))
	var room_id := str(snapshot.get("room_id", ""))
	if int(snapshot.get("turn", 0)) == 0:
		return "先问候林岚，再试着输入“检查遥测台”或“拿起保险芯”。"
	if not bool(flags.get("telemetry_inspected", false)):
		return "RLY-01 的遥测深扫能恢复本轮随机事故的调度端半条线索。"
	if room_id == "power_bay" and not bool(flags.get("power_panel_inspected", false)):
		return "让林岚靠近检查电缆面板，再把三只接头读数与调度记录交叉核对。"
	if room_id == "coolant_gallery" and not bool(flags.get("manifold_inspected", false)):
		return "先检查阀组，确认本轮 I/B/P 各自连接的管路。"
	if bool(flags.get("escape_unlocked", false)):
		return "两项联锁均已解除；返回中央交汇舱并前往逃生舱。"
	return "现场映射每次重开都会变化；只依据本轮证据下令。"


func _ingest_snapshot_log(snapshot: Dictionary) -> void:
	var log: Array = _array(snapshot.get("log", []))
	if log.is_empty():
		return
	var existing_ids: Dictionary = {}
	for entry: Dictionary in _log_entries:
		existing_ids[str(entry.get("source_id", ""))] = true
	for entry: Dictionary in _system_entries:
		existing_ids[str(entry.get("source_id", ""))] = true
	for index: int in range(log.size()):
		var value: Variant = log[index]
		var entry: Dictionary = value as Dictionary if value is Dictionary else {"text": str(value)}
		var source_id := str(entry.get("id", "core:%s:%s" % [entry.get("turn", 0), index]))
		if existing_ids.has(source_id):
			continue
		var normalized := {
			"source_id": source_id,
			"speaker": str(entry.get("speaker", "SYSTEM")),
			"text": str(entry.get("text", entry.get("message", ""))),
			"kind": str(entry.get("kind", entry.get("type", "info"))),
			"time": str(entry.get("time", "T%02d" % int(snapshot.get("turn", 0)))),
		}
		if str(normalized.get("speaker", "SYSTEM")).to_upper() == "SYSTEM":
			_append_system_entry(normalized)
		else:
			_log_entries.append(normalized)
	if _log_entries.size() > 100:
		_log_entries = _log_entries.slice(_log_entries.size() - 100)
	_render_log()


func _render_log() -> void:
	_dialogue_log.clear()
	for entry: Dictionary in _log_entries:
		if str(entry.get("speaker", "")).to_upper() == "SYSTEM":
			continue
		var kind := str(entry.get("kind", "info"))
		var color := _log_color(kind)
		var speaker := _escape_bbcode(str(entry.get("speaker", "SYSTEM")))
		var message := _escape_bbcode(str(entry.get("text", "")))
		var timestamp := _escape_bbcode(str(entry.get("time", "--:--")))
		_dialogue_log.append_text("[color=#526d73]%s[/color] [color=%s][b]%s[/b][/color]\n%s\n\n" % [timestamp, color.to_html(false), speaker, message])
	_dialogue_log.scroll_to_line(maxi(0, _dialogue_log.get_line_count() - 1))


func _render_operator_telemetry(snapshot: Dictionary) -> void:
	if not is_instance_valid(_telemetry_box):
		return
	for child: Node in _telemetry_box.get_children():
		child.queue_free()
	var telemetry: Array = _array(snapshot.get("operator_telemetry", []))
	if telemetry.is_empty():
		var waiting := Label.new()
		waiting.text = "◆  等待调度端传感器回传。"
		waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		waiting.add_theme_color_override("font_color", COLOR_MUTED)
		waiting.add_theme_font_size_override("font_size", 11)
		_telemetry_box.add_child(waiting)
		return
	for raw: Variant in telemetry:
		var line := str(raw).strip_edges()
		if line.is_empty():
			continue
		var button := Button.new()
		button.text = "◆  %s" % line
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_color_override("font_color", COLOR_CYAN)
		button.add_theme_font_size_override("font_size", 11)
		button.tooltip_text = "固定到线索工作台"
		button.pressed.connect(_pin_remote_clue.bind(line))
		_telemetry_box.add_child(button)
	_update_workbench()


func _render_local_evidence(snapshot: Dictionary) -> void:
	if not is_instance_valid(_local_clue_box):
		return
	for child: Node in _local_clue_box.get_children():
		child.queue_free()
	var evidence: Dictionary = _dictionary(snapshot.get("evidence", {}))
	var added := 0
	for key: String in ["power_local", "coolant_local"]:
		var line := str(evidence.get(key, "")).strip_edges()
		if line.is_empty() or line.begins_with("等待"):
			continue
		var button := Button.new()
		button.text = "◇  %s" % line
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_color_override("font_color", COLOR_AMBER)
		button.add_theme_font_size_override("font_size", 10)
		button.tooltip_text = "固定到线索工作台"
		button.pressed.connect(_pin_local_clue.bind(line))
		_local_clue_box.add_child(button)
		added += 1
	if added == 0:
		var waiting := Label.new()
		waiting.text = "◇  让林岚检查现场设备后，可固定他的读数。"
		waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		waiting.add_theme_color_override("font_color", COLOR_MUTED)
		waiting.add_theme_font_size_override("font_size", 10)
		_local_clue_box.add_child(waiting)
	_update_workbench()


func _pin_remote_clue(line: String) -> void:
	_pinned_remote = line.strip_edges()
	_update_workbench()


func _pin_local_clue(line: String) -> void:
	_pinned_local = line.strip_edges()
	_update_workbench()


func _update_workbench() -> void:
	if not is_instance_valid(_workbench_remote) or not is_instance_valid(_workbench_local) or not is_instance_valid(_workbench_summary):
		return
	_workbench_remote.text = "REMOTE  //  %s" % (_pinned_remote if not _pinned_remote.is_empty() else "点击一条调度遥测")
	_workbench_local.text = "LOCAL   //  %s" % (_pinned_local if not _pinned_local.is_empty() else "点击一条现场线索")
	if _pinned_remote.is_empty() or _pinned_local.is_empty():
		_workbench_summary.text = "等待拼合两侧证据。"
		_workbench_summary.add_theme_color_override("font_color", COLOR_MUTED)
		return
	var remote_power := _pinned_remote.contains("PWR-03") or _pinned_remote.contains("闭环")
	var local_power := _pinned_local.contains("接头") or _pinned_local.contains("Ω")
	var remote_coolant := _pinned_remote.contains("CLT-04") or _pinned_remote.contains("目标") and _pinned_remote.contains("kPa")
	var local_coolant := _pinned_local.contains("阀铭牌") or _pinned_local.contains("kPa")
	if remote_power and local_power:
		_workbench_summary.text = "同域证据已对齐：用远端所需闭环读数，在现场三只接头中寻找相同读数。"
		_workbench_summary.add_theme_color_override("font_color", COLOR_GREEN)
	elif remote_coolant and local_coolant:
		_workbench_summary.text = "同域证据已对齐：从当前压力出发，组合现场增减量，使结果等于远端目标压力。"
		_workbench_summary.add_theme_color_override("font_color", COLOR_GREEN)
	else:
		_workbench_summary.text = "这两条证据来自不同系统；换一条线索再进行拼合。"
		_workbench_summary.add_theme_color_override("font_color", COLOR_RED)


func _resolve_candidate(action_id: String, target: String) -> Dictionary:
	var normalized_id := action_id.strip_edges().to_lower()
	var normalized_target := target.strip_edges().to_lower()
	if normalized_id.is_empty():
		return {}
	var same_id: Array[Dictionary] = []
	for action: Dictionary in _actions:
		if not bool(action.get("enabled", true)):
			continue
		var available_id := str(action.get("action", action.get("id", action.get("action_id", "")))).strip_edges().to_lower()
		if available_id != normalized_id:
			continue
		same_id.append(action)
		var available_target := str(action.get("target", "")).strip_edges().to_lower()
		if available_target == normalized_target:
			var resolved := action.duplicate(true)
			resolved["id"] = available_id
			resolved["target"] = available_target
			return resolved
	# A targetless decision is only unambiguous when the whitelist has one match.
	if normalized_target.is_empty() and same_id.size() == 1:
		var sole := same_id[0].duplicate(true)
		sole["id"] = normalized_id
		sole["target"] = str(sole.get("target", "")).strip_edges().to_lower()
		return sole
	return {}


func _authorize_candidate() -> void:
	if _pending_candidate.is_empty():
		return
	var authorized := _pending_candidate.duplicate(true)
	_clear_candidate()
	append_system("你授权林岚尝试这一步；本地核心正在校验。", "info")
	var arguments := _dictionary(authorized.get("arguments", {})).duplicate(true)
	if bool(authorized.get("dangerous", authorized.get("requires_confirmation", false))):
		arguments["risk_acknowledged"] = true
	_emit_action(
		str(authorized.get("id", "")),
		str(authorized.get("target", "")),
		arguments
	)


func _reject_candidate() -> void:
	if _pending_candidate.is_empty():
		return
	_clear_candidate()
	append_system("你没有授权这项请求。林岚仍在通讯中。", "info")
	focus_message_input()


func _clear_candidate() -> void:
	_pending_candidate.clear()
	if is_instance_valid(_candidate_panel):
		_candidate_panel.visible = false
	if is_instance_valid(_candidate_label):
		_candidate_label.text = "先听他说。行动请求会在右侧单独等待授权。"
		_candidate_label.add_theme_color_override("font_color", COLOR_MUTED)
	if is_instance_valid(_status_line):
		_update_status_summary()
	_refresh_portrait()


func _submit_message(text: String) -> void:
	if _thinking:
		return
	var clean := text.strip_edges().left(500)
	if clean.is_empty():
		if bool(_settings.get("quick_safe_actions", true)) and not _pending_candidate.is_empty() and not bool(_pending_candidate.get("dangerous", _pending_candidate.get("requires_confirmation", false))):
			_authorize_candidate()
		return
	_message_input.clear()
	message_submitted.emit(clean)


func _submit_message_from_button() -> void:
	_submit_message(_message_input.text)


func _cancel_decision() -> void:
	if not _thinking:
		return
	set_thinking(false)
	append_system("你中止了本轮远端等待；世界状态没有改变。", "info")
	decision_cancel_requested.emit()
	focus_message_input()


func _submit_quick(text: String) -> void:
	if not _thinking:
		message_submitted.emit(text)


func _render_keyword_cards() -> void:
	if not is_instance_valid(_keyword_box):
		return
	for child: Node in _keyword_box.get_children():
		_keyword_box.remove_child(child)
		child.queue_free()
	var keywords: Array[String] = []
	var guidance: Dictionary = _dictionary(_snapshot.get("guidance", {}))
	for raw: Variant in _array(guidance.get("keywords", [])):
		_append_keyword(keywords, str(raw))
	for action: Dictionary in _actions:
		for raw: Variant in _array(action.get("keywords", [])):
			_append_keyword(keywords, str(raw))
			if keywords.size() >= 10:
				break
		if keywords.size() >= 10:
			break
	if keywords.is_empty():
		keywords.append("林岚")
	for keyword: String in keywords:
		var button := Button.new()
		button.text = "＋ %s" % keyword
		button.add_theme_font_size_override("font_size", 11)
		button.tooltip_text = "填入“%s”；仍需自行补充动词并发送" % keyword
		button.set_meta("keyword", keyword)
		button.pressed.connect(_insert_keyword.bind(keyword))
		_keyword_box.add_child(button)
	call_deferred("_reset_keyword_scroll")


func _reset_keyword_scroll() -> void:
	if is_instance_valid(_keyword_scroll):
		_keyword_scroll.scroll_horizontal = 0


func _append_keyword(output: Array[String], raw: String) -> void:
	var clean := raw.strip_edges()
	if clean.is_empty() or clean in GENERIC_ACTION_KEYWORDS or clean in output:
		return
	if clean.contains("_") or clean.length() > 18:
		return
	output.append(clean)


func _insert_keyword(keyword: String) -> void:
	if _thinking or not is_instance_valid(_message_input):
		return
	var clean := keyword.strip_edges()
	if clean.is_empty():
		return
	var current := _message_input.text
	var existing_at := current.find(clean)
	if existing_at >= 0:
		_message_input.caret_column = existing_at + clean.length()
	else:
		var caret := clampi(_message_input.caret_column, 0, current.length())
		_message_input.text = current.left(caret) + clean + current.substr(caret)
		_message_input.caret_column = caret + clean.length()
	focus_message_input()


func get_keyword_card_texts() -> Array[String]:
	var result: Array[String] = []
	if not is_instance_valid(_keyword_box):
		return result
	for child: Node in _keyword_box.get_children():
		if child is Button:
			result.append(str((child as Button).get_meta("keyword", "")))
	return result


func _emit_action(action_id: String, target: String, arguments: Dictionary) -> void:
	action_requested.emit(action_id, target, arguments.duplicate(true))


func _confirm_pending_proposal(accepted: bool) -> void:
	if _pending_proposal.is_empty():
		return
	var proposal_id := int(_pending_proposal.get("proposal_id", _pending_proposal.get("id", -1)))
	_pending_proposal.clear()
	_refresh_portrait()
	if proposal_id >= 0:
		proposal_confirmation_requested.emit(proposal_id, accepted)


func _request_restart_confirmation() -> void:
	_restart_dialog.popup_centered(Vector2i(440, 190))


func _emit_restart() -> void:
	restart_requested.emit()


func _update_status_summary() -> void:
	if _thinking:
		return
	if bool(_snapshot.get("is_terminal", false)):
		_status_line.text = "任务已结束；可检查日志或重开"
	elif not _pending_candidate.is_empty():
		_status_line.text = "一项行动请求正在等待你的明确授权"
	else:
		_status_line.text = "继续和林岚沟通；模型不会自动执行任何行动"


func _refresh_portrait() -> void:
	if not is_instance_valid(_portrait) or not _portrait.has_method("set_npc_state"):
		return
	var npc: Dictionary = _dictionary(_snapshot.get("npc", {}))
	var state := npc.duplicate(true)
	var resources: Dictionary = _dictionary(_snapshot.get("resources", {}))
	state["room_id"] = str(_snapshot.get("room_id", npc.get("room_id", "relay_control")))
	state["room_name"] = str(_snapshot.get("room_name", npc.get("room_name", state["room_id"])))
	state["oxygen"] = _resource_percent(resources, _snapshot, ["oxygen", "oxygen_percent", "o2"], 100.0)
	state["power"] = _resource_percent(resources, _snapshot, ["power", "power_percent", "battery"], 100.0)
	state["mistakes"] = int(_snapshot.get("mistakes", 0))
	state["turn"] = int(_snapshot.get("turn", 0))
	state["flags"] = _dictionary(_snapshot.get("flags", {})).duplicate(true)
	state["npc_social"] = _dictionary(_snapshot.get("npc_social", {})).duplicate(true)
	state["thinking"] = _thinking
	state["candidate_pending"] = not _pending_candidate.is_empty()
	state["pending_confirmation"] = (
		_pending_proposal.duplicate(true)
		if not _pending_proposal.is_empty()
		else _dictionary(_snapshot.get("pending_confirmation", {})).duplicate(true)
	)
	state["carried_item"] = str(_snapshot.get("carried_item", ""))
	state["is_terminal"] = bool(_snapshot.get("is_terminal", false))
	state["outcome"] = str(_snapshot.get("outcome", "ongoing"))
	state["last_event"] = _dictionary(_snapshot.get("last_event", {})).duplicate(true)
	_portrait.call("set_npc_state", state, _connection_status)


func _mood_label(mood: String) -> String:
	match mood.to_lower():
		"strained", "panic", "afraid", "hurt":
			return "高压"
		"cautious", "worried", "thinking", "nervous":
			return "谨慎"
		"relieved", "calm":
			return "稳定"
		_:
			return "专注"


func _mood_color(mood: String) -> Color:
	if mood.to_lower() in ["strained", "panic", "afraid", "injured"]:
		return COLOR_RED
	if mood.to_lower() in ["cautious", "worried", "thinking", "nervous"]:
		return COLOR_AMBER
	return COLOR_CYAN


func _log_color(kind: String) -> Color:
	match kind.to_lower():
		"player", "operator":
			return COLOR_CYAN
		"npc", "lin_lan":
			return COLOR_AMBER
		"error", "danger", "warning":
			return COLOR_RED
		"success":
			return COLOR_GREEN
		_:
			return COLOR_MUTED


func _display_value(value: Variant, fallback: String) -> String:
	if value == null:
		return fallback
	if value is Dictionary:
		var item := value as Dictionary
		return str(item.get("label", item.get("name", item.get("id", fallback))))
	if value is Array:
		var list := value as Array
		if list.is_empty():
			return fallback
		return _display_value(list[0], fallback)
	var text := str(value)
	return text if not text.is_empty() else fallback


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "［").replace("]", "］")


func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value as Array if value is Array else []


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://blindspot_settings.cfg") != OK:
		return
	for key: String in _settings:
		_settings[key] = config.get_value("accessibility", key, _settings[key])


func _save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in _settings:
		config.set_value("accessibility", key, _settings[key])
	config.save("user://blindspot_settings.cfg")


func _open_settings() -> void:
	if is_instance_valid(_settings_dialog):
		_settings_dialog.popup_centered()


func _on_settings_control_changed() -> void:
	_settings["font_scale"] = float(_font_slider.value)
	_settings["volume"] = float(_volume_slider.value)
	_settings["muted"] = bool(_mute_check.button_pressed)
	_settings["reduced_motion"] = bool(_motion_check.button_pressed)
	_settings["online_enabled"] = bool(_online_check.button_pressed)
	_settings["quick_safe_actions"] = bool(_quick_action_check.button_pressed)
	_save_settings()
	_apply_settings(true)


func _apply_settings(should_emit: bool) -> void:
	var font_scale := clampf(float(_settings.get("font_scale", 1.0)), 0.9, 1.45)
	theme.default_font_size = int(round(13.0 * font_scale))
	_scale_font_overrides(self, font_scale)
	var reduced := bool(_settings.get("reduced_motion", false))
	if is_instance_valid(_backdrop) and _backdrop.has_method("set_reduced_motion"):
		_backdrop.call("set_reduced_motion", reduced)
	if is_instance_valid(_portrait) and _portrait.has_method("set_reduced_motion"):
		_portrait.call("set_reduced_motion", reduced)
	if reduced and is_instance_valid(_intro_overlay):
		_intro_overlay.skip_intro()
	_apply_responsive_layout()
	if should_emit:
		settings_changed.emit(_settings.duplicate(true))


func _scale_font_overrides(node: Node, font_scale: float) -> void:
	if node is Control:
		var control := node as Control
		if control.has_theme_font_size_override("font_size"):
			if not control.has_meta("base_font_size"):
				control.set_meta("base_font_size", control.get_theme_font_size("font_size"))
			control.add_theme_font_size_override("font_size", int(round(float(control.get_meta("base_font_size")) * font_scale)))
	for child: Node in node.get_children():
		_scale_font_overrides(child, font_scale)


func _apply_responsive_layout() -> void:
	if not is_instance_valid(_left_panel) or not is_instance_valid(_right_panel) or not is_instance_valid(_portrait):
		return
	# Use the actual visible viewport rather than this control's computed minimum
	# size. The three columns can otherwise make `size.x` wider than the window,
	# preventing the compact branch precisely when the right rail is clipped.
	var viewport_width := get_viewport_rect().size.x
	var compact := viewport_width < 1440.0
	_left_panel.custom_minimum_size.x = 350.0 if compact else 400.0
	_right_panel.custom_minimum_size.x = 280.0 if compact else 312.0
	_portrait.custom_minimum_size.x = 180.0 if compact else 220.0
	if is_instance_valid(_settings_button):
		_settings_button.text = "⚙" if viewport_width < 1080.0 else "⚙  SETTINGS"


func _create_theme() -> Theme:
	var result := Theme.new()
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Noto Sans Mono CJK SC", "Microsoft YaHei UI"])
	system_font.font_weight = 500
	result.default_font = system_font
	result.default_font_size = int(round(13.0 * float(_settings.get("font_scale", 1.0))))
	result.set_color("font_color", "Label", COLOR_TEXT)
	result.set_color("font_color", "Button", COLOR_TEXT)
	result.set_color("font_hover_color", "Button", Color("efffe9"))
	result.set_color("font_pressed_color", "Button", COLOR_AMBER)
	result.set_color("font_color", "LineEdit", COLOR_TEXT)
	result.set_color("caret_color", "LineEdit", COLOR_CYAN)
	result.set_color("font_placeholder_color", "LineEdit", Color("587178"))
	var panel := StyleBoxFlat.new()
	panel.bg_color = COLOR_PANEL
	panel.border_color = COLOR_LINE
	panel.set_border_width_all(1)
	panel.corner_radius_top_left = 2
	panel.corner_radius_top_right = 2
	panel.corner_radius_bottom_left = 2
	panel.corner_radius_bottom_right = 2
	result.set_stylebox("panel", "PanelContainer", panel)
	var button := StyleBoxFlat.new()
	button.bg_color = COLOR_PANEL_ALT
	button.border_color = Color("294e55")
	button.set_border_width_all(1)
	button.content_margin_left = 8.0
	button.content_margin_right = 8.0
	button.content_margin_top = 6.0
	button.content_margin_bottom = 6.0
	var button_hover := button.duplicate() as StyleBoxFlat
	button_hover.bg_color = Color("17323a")
	button_hover.border_color = COLOR_CYAN
	var button_pressed := button_hover.duplicate() as StyleBoxFlat
	button_pressed.bg_color = Color("243d3d")
	button_pressed.border_color = COLOR_AMBER
	result.set_stylebox("normal", "Button", button)
	result.set_stylebox("hover", "Button", button_hover)
	result.set_stylebox("pressed", "Button", button_pressed)
	result.set_stylebox("focus", "Button", button_hover)
	var input := StyleBoxFlat.new()
	input.bg_color = Color("061117")
	input.border_color = COLOR_LINE
	input.set_border_width_all(1)
	input.content_margin_left = 10.0
	input.content_margin_right = 10.0
	input.content_margin_top = 8.0
	input.content_margin_bottom = 8.0
	var input_focus := input.duplicate() as StyleBoxFlat
	input_focus.border_color = COLOR_CYAN
	result.set_stylebox("normal", "LineEdit", input)
	result.set_stylebox("focus", "LineEdit", input_focus)
	var progress_bg := StyleBoxFlat.new()
	progress_bg.bg_color = Color("061117")
	progress_bg.border_color = Color("28474e")
	progress_bg.set_border_width_all(1)
	result.set_stylebox("background", "ProgressBar", progress_bg)
	return result
