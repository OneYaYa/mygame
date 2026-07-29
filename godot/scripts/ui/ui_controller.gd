class_name TimeEchoUI
extends CanvasLayer

signal new_game_requested()
signal continue_requested()
signal save_requested()
signal dialogue_action_requested(action_id: String)
signal dialogue_text_requested(message: String)
signal dialogue_closed()
signal modal_dismissed(kind: String)
signal puzzle_completed(puzzle_id: String)
signal prologue_completed()
signal restart_requested()
signal loop_cinematic_finished()

var root: Control
var title_screen: Control
var hud: Control
var location_label: Label
var time_label: Label
var loop_label: Label
var journal_panel: PanelContainer
var journal_title: Label
var journal_text: RichTextLabel
var hint_panel: PanelContainer
var hint_label: Label
var modal_layer: ColorRect
var modal_panel: PanelContainer
var modal_title: Label
var modal_subtitle: Label
var modal_body: RichTextLabel
var modal_actions: VBoxContainer
var dialogue_input: LineEdit
var toast_label: Label
var continue_button: Button
var sound_button: Button
var _modal_kind: String = ""
var _current_puzzle: String = ""
var _puzzle_state: Dictionary = {}
var _journal_visible: bool = true
var _reset_pending: bool = false


func _ready() -> void:
	layer = 30
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		if not _modal_kind.is_empty() and _modal_kind not in ["ending", "reset"]:
			close_modal()
			get_viewport().set_input_as_handled()
		elif not title_screen.visible:
			show_pause()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("journal") and title_screen.visible == false and _modal_kind.is_empty():
		show_journal("journal")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") and title_screen.visible == false and _modal_kind.is_empty():
		show_journal("inventory")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and title_screen.visible == false:
		show_pause()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	root = Control.new()
	root.name = "UIRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _create_theme()
	add_child(root)
	_build_title()
	_build_hud()
	_build_journal()
	_build_hint()
	_build_modal()
	toast_label = Label.new()
	toast_label.position = Vector2(24, 585)
	toast_label.size = Vector2(760, 36)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_color", Color("f4df9c"))
	toast_label.add_theme_color_override("font_shadow_color", Color("101819"))
	toast_label.add_theme_constant_override("shadow_offset_x", 2)
	toast_label.add_theme_constant_override("shadow_offset_y", 2)
	toast_label.visible = false
	root.add_child(toast_label)


func _build_title() -> void:
	title_screen = Control.new()
	title_screen.name = "TitleScreen"
	title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(title_screen)
	var backdrop := TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.texture = load("res://assets/images/time_echo_horizon.webp") as Texture2D
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.modulate = Color("829090")
	title_screen.add_child(backdrop)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.035, 0.06, 0.065, 0.68)
	title_screen.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_screen.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var kicker := Label.new()
	kicker.text = "A LAKESIDE MYSTERY"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_color_override("font_color", Color("d0aa62"))
	box.add_child(kicker)
	var title := Label.new()
	title.text = "TIME  ECHO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color("f0e2bd"))
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "THE FERRY LEAVES ON SUNDAY.\nTHE TOWN NEVER GETS THERE."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("b8c2b4"))
	box.add_child(subtitle)
	continue_button = _button("Continue", _on_continue)
	box.add_child(continue_button)
	box.add_child(_button("Begin", _on_new_game))
	box.add_child(_button("Loop Archive", show_archive))
	var controls := Label.new()
	controls.text = "WASD / 方向键  MOVE   ·   E  INTERACT   ·   J  JOURNAL"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_theme_font_size_override("font_size", 12)
	box.add_child(controls)


func _build_hud() -> void:
	hud = PanelContainer.new()
	hud.name = "HUD"
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_bottom = 70
	root.add_child(hud)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	hud.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	location_label = Label.new()
	location_label.text = "LAKESIDE TOWN\n湖畔旅店 · 八号房"
	location_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	location_label.add_theme_font_size_override("font_size", 18)
	row.add_child(location_label)
	var clock_box := VBoxContainer.new()
	clock_box.custom_minimum_size = Vector2(150, 0)
	row.add_child(clock_box)
	time_label = Label.new()
	time_label.text = "SATURDAY  06:00"
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 20)
	clock_box.add_child(time_label)
	loop_label = Label.new()
	loop_label.text = "LOOP 01"
	loop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loop_label.add_theme_color_override("font_color", Color("d2ad67"))
	clock_box.add_child(loop_label)
	row.add_child(_button("J", func() -> void: show_journal("journal"), Vector2(44, 42)))
	row.add_child(_button("I", func() -> void: show_journal("inventory"), Vector2(44, 42)))
	sound_button = _button("♪", _toggle_sound, Vector2(44, 42))
	row.add_child(sound_button)
	row.add_child(_button("▣", func() -> void: save_requested.emit(), Vector2(44, 42)))
	row.add_child(_button("?", show_help, Vector2(44, 42)))
	hud.visible = false


func _build_journal() -> void:
	journal_panel = PanelContainer.new()
	journal_panel.name = "FieldJournal"
	journal_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	journal_panel.offset_left = -316
	journal_panel.offset_top = 78
	journal_panel.offset_right = -12
	journal_panel.offset_bottom = -18
	root.add_child(journal_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	journal_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var tabs := HBoxContainer.new()
	box.add_child(tabs)
	tabs.add_child(_button("委托", func() -> void: _render_side_journal("orders"), Vector2(82, 34)))
	tabs.add_child(_button("证据", func() -> void: _render_side_journal("evidence"), Vector2(82, 34)))
	tabs.add_child(_button("居民", func() -> void: _render_side_journal("people"), Vector2(82, 34)))
	journal_title = Label.new()
	journal_title.text = "THREE CLOCKS / ONE MORNING"
	journal_title.add_theme_color_override("font_color", Color("c89c55"))
	box.add_child(journal_title)
	journal_text = RichTextLabel.new()
	journal_text.bbcode_enabled = true
	journal_text.fit_content = false
	journal_text.scroll_active = true
	journal_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(journal_text)
	journal_panel.visible = false


func _build_hint() -> void:
	hint_panel = PanelContainer.new()
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_panel.offset_left = -210
	hint_panel.offset_top = -66
	hint_panel.offset_right = 210
	hint_panel.offset_bottom = -22
	root.add_child(hint_panel)
	hint_label = Label.new()
	hint_label.text = "[ E ] 检查"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_panel.add_child(hint_label)
	hint_panel.visible = false


func _build_modal() -> void:
	modal_layer = ColorRect.new()
	modal_layer.name = "ModalLayer"
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.color = Color(0.02, 0.035, 0.038, 0.82)
	root.add_child(modal_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(center)
	modal_panel = PanelContainer.new()
	modal_panel.custom_minimum_size = Vector2(720, 500)
	center.add_child(modal_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 22)
	modal_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	modal_subtitle = Label.new()
	modal_subtitle.text = "FIELD NOTE"
	modal_subtitle.add_theme_color_override("font_color", Color("c69e5e"))
	box.add_child(modal_subtitle)
	modal_title = Label.new()
	modal_title.add_theme_font_size_override("font_size", 28)
	box.add_child(modal_title)
	modal_body = RichTextLabel.new()
	modal_body.bbcode_enabled = true
	modal_body.custom_minimum_size = Vector2(660, 250)
	modal_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_body.scroll_active = true
	box.add_child(modal_body)
	modal_actions = VBoxContainer.new()
	modal_actions.add_theme_constant_override("separation", 6)
	box.add_child(modal_actions)
	dialogue_input = LineEdit.new()
	dialogue_input.placeholder_text = "也可以用自己的话问……"
	dialogue_input.max_length = 260
	dialogue_input.text_submitted.connect(_on_dialogue_text)
	box.add_child(dialogue_input)
	modal_layer.visible = false


func show_title(has_save: bool) -> void:
	title_screen.visible = true
	hud.visible = false
	journal_panel.visible = false
	hint_panel.visible = false
	continue_button.visible = has_save
	close_modal(false)


func show_game() -> void:
	title_screen.visible = false
	hud.visible = true
	journal_panel.visible = _journal_visible
	_render_side_journal("orders")


func update_state(state: Dictionary, scene: Dictionary) -> void:
	if state.is_empty():
		return
	location_label.text = "LAKESIDE TOWN\n%s" % scene.get("name", state.get("placeId", ""))
	time_label.text = "%s  %s" % [state.get("dayLabel", "SATURDAY"), TimeManager.format_time(int(state.get("minute", 360)))]
	loop_label.text = "LOOP %02d" % (int(state.get("loopCount", 0)) + 1)
	if journal_panel.visible:
		_render_side_journal("orders")


func set_interaction(target: Dictionary) -> void:
	hint_panel.visible = not target.is_empty() and _modal_kind.is_empty() and not title_screen.visible
	if hint_panel.visible:
		hint_label.text = "[ E ]  %s" % target.get("label", "检查")


func show_prologue() -> void:
	_open_modal("prologue", "FRIDAY · 17:40 / CITY WORKSHOP", "玛拉 · 工坊主管", "湖镇的三座公共钟在同一时刻停摆。第一班星期日渡船之前，把它们修好。\n\n三份委托都写着 SATURDAY 06:00，收件地点都是湖畔旅店八号房。")
	modal_actions.add_child(_button("收下工具箱，连夜赶往湖镇", func() -> void:
		close_modal(false)
		prologue_completed.emit()
	))


func show_inspect(title: String, text: String) -> void:
	_open_modal("inspect", "FIELD NOTE", title, text)
	modal_actions.add_child(_button("收起记录", func() -> void: close_modal()))


func show_dialogue(npc: Dictionary, state: Dictionary, actions: Array[Dictionary]) -> void:
	var npc_id: String = str(npc.get("id", ""))
	var title: String = str(npc.get("name", "镇民"))
	if npc_id == "ada" and not bool((state.get("flags", {}) as Dictionary).get("ada_name_anchored", false)):
		title = "暗房中的潜影"
	_open_modal("dialogue", str(npc.get("role", "RESIDENT")), title, "[color=#d7c69d]%s[/color]\n\n" % _greeting(npc_id))
	dialogue_input.visible = true
	refresh_dialogue_actions(actions)
	dialogue_input.grab_focus.call_deferred()


func append_dialogue(speaker: String, text: String, player: bool = false) -> void:
	var color: String = "#9fc4bf" if player else "#d9bd76"
	modal_body.append_text("[color=%s][b]%s[/b][/color]\n%s\n\n" % [color, speaker, text])
	modal_body.scroll_to_line(maxi(0, modal_body.get_line_count() - 1))


func refresh_dialogue_actions(actions: Array[Dictionary]) -> void:
	_clear_actions()
	for action: Dictionary in actions:
		var action_id: String = str(action.get("id", ""))
		modal_actions.add_child(_button(str(action.get("label", action_id)), _emit_dialogue_action.bind(action_id)))
	modal_actions.add_child(_button("结束交谈", func() -> void: close_modal()))


func show_puzzle(puzzle_id: String, state: Dictionary) -> void:
	_current_puzzle = puzzle_id
	_puzzle_state = {}
	_open_modal("puzzle", "CLOCKWORK", _puzzle_title(puzzle_id), _puzzle_instruction(puzzle_id))
	match puzzle_id:
		"master": _build_master_puzzle()
		"chapel": _build_chapel_puzzle(state)
		"tide": _build_tide_puzzle()
		"photo": _build_photo_puzzle()
		"identity": _build_identity_puzzle(state)
	modal_actions.add_child(_button("暂时离开", func() -> void: close_modal()))


func show_journal(tab: String = "journal") -> void:
	var state: Dictionary = GameManager.state
	_open_modal("journal", "PERSISTENT FIELD JOURNAL", "维修工的循环日志", "")
	if tab == "inventory":
		modal_title.text = "背包与照片"
		var rows: PackedStringArray = []
		for entry: Dictionary in InventoryManager.display_entries(state):
			rows.append("[b]%s ×%d[/b]\n%s" % [entry["name"], entry["count"], entry["description"]])
		modal_body.text = "\n\n".join(rows) if not rows.is_empty() else "背包还是空的。"
	else:
		var rows: PackedStringArray = []
		for raw: Variant in (state.get("journal", []) as Array).slice(maxi(0, (state.get("journal", []) as Array).size() - 80)):
			var entry: Dictionary = raw as Dictionary
			rows.append("[color=#c6a25e]%s · LOOP %d[/color]\n%s" % [entry.get("stamp", ""), entry.get("loop", 1), entry.get("text", "")])
		modal_body.text = "\n\n".join(rows)
	modal_actions.add_child(_button("收起日志", func() -> void: close_modal()))


func show_archive() -> void:
	_open_modal("archive", "LOOP ARCHIVE", "已经留下的清晨", "")
	var endings: Array = SaveManager.load_endings()
	var body: PackedStringArray = ["已进入过的循环会留在 user:// 存档中。"]
	for raw: Variant in endings:
		var ending: Dictionary = raw as Dictionary
		body.append("LOOP %d · %s" % [ending.get("loops", 1), "七人继续：正确的星期日" if ending.get("id") == "true" else "六人终止：失去第七人的星期日"])
	modal_body.text = "\n\n".join(body)
	modal_actions.add_child(_button("返回", func() -> void: close_modal()))


func show_help() -> void:
	_open_modal("help", "CONTROLS", "别和钟赛跑，先学会读它", "[b]WASD / 方向键[/b] 移动；[b]Shift[/b] 奔跑；[b]E / Space[/b] 交互；[b]J[/b] 日志；[b]I / B[/b] 背包；[b]P / Esc[/b] 暂停。\n\n一轮现实时间约 12 分钟。自由对话时世界以四分之一速度继续；退潮洞穴和隐藏暗房中时间完全停止。")
	modal_actions.add_child(_button("明白了", func() -> void: close_modal()))


func show_pause() -> void:
	if _modal_kind == "pause":
		close_modal()
		return
	_open_modal("pause", "PAUSED", "湖面暂时静止", "暂停菜单不会改写任何谜题或时间循环状态。")
	modal_actions.add_child(_button("继续", func() -> void: close_modal()))
	modal_actions.add_child(_button("保存", func() -> void: save_requested.emit()))
	modal_actions.add_child(_button("声音：%s" % ("开启" if AudioManager.enabled else "关闭"), _toggle_sound))


func show_ending(ending_id: String) -> void:
	var true_ending: bool = ending_id == "true"
	_open_modal("ending", "SUNDAY · 06:00", "七人继续" if true_ending else "六人终止", "白光没有倒流。渡船的缆绳第一次被解开，七个人的名字同时留在登记簿上。" if true_ending else "星期日终于到来。镇上只剩六份互相吻合的记录，没人再记得七号房为何存在。")
	modal_actions.add_child(_button("从另一个星期六醒来", func() -> void: restart_requested.emit()))


func play_reset(loop_count: int) -> void:
	if _reset_pending:
		return
	_reset_pending = true
	_open_modal("reset", "05:55 · RETURN EXPOSURE", "白线正在逆向升起", "湖镇的影子同时转向湖心。\n\nLOOP %02d 的实物、承诺与维修状态正在复位；日志、照片与已知信息会留下。" % (loop_count + 1))
	AudioManager.play("reset")
	await get_tree().create_timer(4.2).timeout
	_reset_pending = false
	close_modal(false)
	loop_cinematic_finished.emit()


func notify(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	var stamp: int = Time.get_ticks_msec()
	toast_label.set_meta("stamp", stamp)
	await get_tree().create_timer(2.6).timeout
	if int(toast_label.get_meta("stamp", 0)) == stamp:
		toast_label.visible = false


func is_blocking() -> bool:
	return title_screen.visible or not _modal_kind.is_empty()


func close_modal(notify_close: bool = true) -> void:
	var closed_kind: String = _modal_kind
	var was_dialogue: bool = _modal_kind == "dialogue"
	modal_layer.visible = false
	_modal_kind = ""
	_current_puzzle = ""
	dialogue_input.visible = false
	if notify_close and was_dialogue:
		dialogue_closed.emit()
	if notify_close and not closed_kind.is_empty():
		modal_dismissed.emit(closed_kind)


func _open_modal(kind: String, subtitle: String, title: String, body: String) -> void:
	_modal_kind = kind
	modal_layer.visible = true
	modal_subtitle.text = subtitle
	modal_title.text = title
	modal_body.text = body
	dialogue_input.visible = false
	_clear_actions()


func _clear_actions() -> void:
	for child: Node in modal_actions.get_children():
		modal_actions.remove_child(child)
		child.queue_free()


func _render_side_journal(tab: String) -> void:
	if GameManager.state.is_empty():
		return
	var state: Dictionary = GameManager.state
	if tab == "orders":
		journal_title.text = "THREE CLOCKS / ONE MORNING"
		var repairs: Dictionary = state.get("repairs", {}) as Dictionary
		journal_text.text = "[b]%s[/b] 主钟\n[b]%s[/b] 礼拜堂六声钟\n[b]%s[/b] 港口潮汐钟\n\n时间推进：%s %s" % [
			"✓" if repairs.get("master") else "□", "✓" if repairs.get("chapel") else "□", "✓" if repairs.get("tide") else "□",
			state.get("dayLabel", "SATURDAY"), TimeManager.format_time(int(state.get("minute", 360)))
		]
	elif tab == "evidence":
		journal_title.text = "本轮证据"
		var rows: PackedStringArray = []
		for id: Variant in (state.get("evidence", {}) as Dictionary).keys():
			if bool((state["evidence"] as Dictionary)[id]): rows.append("• %s" % DataManager.get_evidence(str(id)).get("name", id))
		journal_text.text = "\n".join(rows) if not rows.is_empty() else "尚未记录证据。"
	else:
		journal_title.text = "七位居民"
		var rows: PackedStringArray = []
		for npc_value: Variant in DataManager.world.get("npcs", []):
			var npc: Dictionary = npc_value as Dictionary
			rows.append("[b]%s[/b]\n%s" % [npc.get("name", ""), npc.get("role", "")])
		journal_text.text = "\n\n".join(rows)


func _build_master_puzzle() -> void:
	_puzzle_state = {"gears": [0, 1, 2], "rotations": [1, 2, 3], "options": [], "rotate_buttons": []}
	var gear_names: Array[String] = ["小齿轮", "中齿轮", "大齿轮"]
	for slot: int in range(3):
		var row := HBoxContainer.new()
		var label := Label.new(); label.text = "%d 号槽" % (slot + 1); label.custom_minimum_size = Vector2(90, 32); row.add_child(label)
		var option := OptionButton.new()
		for gear_name: String in gear_names: option.add_item(gear_name)
		option.select(slot)
		option.item_selected.connect(_on_master_gear_selected.bind(slot))
		row.add_child(option)
		var glyphs: Array[String] = ["↑", "→", "↓", "←"]
		var rotate := _button(glyphs[int((_puzzle_state["rotations"] as Array)[slot])], _rotate_gear.bind(slot), Vector2(80, 34))
		row.add_child(rotate)
		(_puzzle_state["rotate_buttons"] as Array).append(rotate)
		modal_actions.add_child(row)
	modal_actions.add_child(_button("试运行", _test_master))


func _rotate_gear(slot: int) -> void:
	var rotations: Array = _puzzle_state["rotations"] as Array
	rotations[slot] = (int(rotations[slot]) + 1) % 4
	var glyphs: Array[String] = ["↑", "→", "↓", "←"]
	((_puzzle_state["rotate_buttons"] as Array)[slot] as Button).text = glyphs[int(rotations[slot])]


func _on_master_gear_selected(index: int, slot: int) -> void:
	(_puzzle_state["gears"] as Array)[slot] = index


func _test_master() -> void:
	if _puzzle_state["gears"] == [1, 2, 0] and _puzzle_state["rotations"] == [0, 0, 0]:
		_finish_puzzle()
	else:
		modal_body.text = "齿轮能转，但红线没有同时经过上方基准刻痕。目标顺序是中、大、小，三条红线都朝上。"


func _build_chapel_puzzle(state: Dictionary) -> void:
	var has_pin: bool = InventoryManager.has_item(state, "chapel_pin")
	var button := _button("安装擒纵销并拉绳" if has_pin else "缺少擒纵销", _finish_puzzle)
	button.disabled = not has_pin
	modal_actions.add_child(button)


func _build_tide_puzzle() -> void:
	_puzzle_state = {"values": [2, 0, 1]}
	for ring: int in range(3):
		var option := OptionButton.new()
		option.add_item("低刻度"); option.add_item("中刻度"); option.add_item("高刻度")
		option.select(int((_puzzle_state["values"] as Array)[ring]))
		option.item_selected.connect(_on_tide_ring_selected.bind(ring))
		modal_actions.add_child(option)
	modal_actions.add_child(_button("对照三根系船柱", func() -> void:
		if _puzzle_state["values"] == [0, 1, 2]: _finish_puzzle()
		else: modal_body.text = "测试浮标撞上了错误水位限位。三根柱依次是低、中、高。"
	))


func _on_tide_ring_selected(index: int, ring: int) -> void:
	(_puzzle_state["values"] as Array)[ring] = index


func _build_photo_puzzle() -> void:
	_puzzle_state = {"next": 0}
	var labels: Array[String] = ["重影", "反差", "反射"]
	for index: int in range(labels.size()):
		modal_actions.add_child(_button(labels[index], _photo_step.bind(index, labels[index])))


func _photo_step(index: int, label: String) -> void:
	if index != int(_puzzle_state["next"]):
		_puzzle_state["next"] = 0
		modal_body.text = "乳剂发灰，顺序被打断。重新从重影开始。"
		return
	_puzzle_state["next"] = index + 1
	modal_body.text = "%s稳定了。" % label
	if index == 2:
		_finish_puzzle()


func _build_identity_puzzle(state: Dictionary) -> void:
	var missing: PackedStringArray = DialogueManager.missing_identity_anchors(state)
	modal_body.text = "姓名 · 住处 · 职责 · 面孔\n\n" + ("四种来源互不替代，但现在指向同一个人。" if missing.is_empty() else "仍缺：%s" % "、".join(missing))
	var button := _button("完成定影", _finish_puzzle)
	button.disabled = not missing.is_empty()
	modal_actions.add_child(button)


func _finish_puzzle() -> void:
	var completed_id: String = _current_puzzle
	close_modal(false)
	puzzle_completed.emit(completed_id)


func _puzzle_title(id: String) -> String:
	return {"master": "主钟三齿轮校准", "chapel": "六锤擒纵机构", "tide": "三环潮汐刻度", "photo": "洞穴底片三步显影", "identity": "第七见证人身份定影"}.get(id, "机构")


func _puzzle_instruction(id: String) -> String:
	return {"master": "交换三枚齿轮，并把每条红色标记旋到正上方。", "chapel": "第四个空槽需要一枚尺寸吻合的黄铜擒纵销。", "tide": "按港外三根系船柱实际水线设为低、中、高。", "photo": "严格按重影 → 反差 → 反射处理。", "identity": "四项锚点必须分别由 Ada 在本轮当面确认。"}.get(id, "检查机构。")


func _greeting(id: String) -> String:
	return {"arthur": "如果是维修，请把可验证的现象逐项说清。", "beatrice": "钟不会替人承担决定。", "conrad": "潮水只认刻度。", "dorothea": "先坐下，炉边还有热茶。", "elias": "别先猜照片里是谁。", "florence": "把原件放在桌上。", "ada": "你终于让光照到了这里。"}.get(id, "对方等你开口。")


func _on_dialogue_text(text: String) -> void:
	var clean: String = text.strip_edges()
	if clean.is_empty(): return
	dialogue_input.clear()
	dialogue_text_requested.emit(clean)


func _emit_dialogue_action(action_id: String) -> void:
	dialogue_action_requested.emit(action_id)


func _on_new_game() -> void: new_game_requested.emit()
func _on_continue() -> void: continue_requested.emit()


func _toggle_sound() -> void:
	AudioManager.set_enabled(not AudioManager.enabled)
	sound_button.text = "♪" if AudioManager.enabled else "×"
	notify("声音已%s。" % ("开启" if AudioManager.enabled else "关闭"))


func _button(text: String, callback: Callable, minimum: Vector2 = Vector2(0, 42)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.pressed.connect(callback)
	return button


func _create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color("e7dcc0"))
	theme.set_color("font_color", "Button", Color("eadcb7"))
	theme.set_color("font_hover_color", "Button", Color("fff0bf"))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("18272a")
	panel.border_color = Color("8c7148")
	panel.set_border_width_all(2)
	panel.corner_radius_top_left = 3
	panel.corner_radius_top_right = 3
	panel.corner_radius_bottom_left = 3
	panel.corner_radius_bottom_right = 3
	theme.set_stylebox("panel", "PanelContainer", panel)
	var button_normal := StyleBoxFlat.new()
	button_normal.bg_color = Color("24383a")
	button_normal.border_color = Color("806a48")
	button_normal.set_border_width_all(1)
	button_normal.set_corner_radius_all(2)
	var button_hover := button_normal.duplicate() as StyleBoxFlat
	button_hover.bg_color = Color("345052")
	button_hover.border_color = Color("d1a65d")
	theme.set_stylebox("normal", "Button", button_normal)
	theme.set_stylebox("hover", "Button", button_hover)
	theme.set_stylebox("pressed", "Button", button_hover)
	return theme
