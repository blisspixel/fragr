class_name MissionHud
extends Control

## A shared objective and physical-use prompt, never a local completion timer.
var state: Dictionary = {}
var player_id: String = ""
var _card: PanelContainer
var _copy: Label
var _prompt: Label
var _recovery: PanelContainer
var _recovery_copy: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", MenuTheme.panel(Color("1c2420"), Color("716344")))
	add_child(_card)
	_copy = _label(18)
	_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(_copy)
	_prompt = _label(22)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_prompt)
	_recovery = PanelContainer.new()
	_recovery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recovery.add_theme_stylebox_override("panel", MenuTheme.panel(Color("201b19"), Color("986048")))
	add_child(_recovery)
	_recovery_copy = _label(24)
	_recovery_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recovery_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_recovery.add_child(_recovery_copy)
	_refresh()

func _label(font_size: int) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", MenuTheme.BONE)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 4)
	return label

func apply(value: Dictionary, owner_id: String) -> void:
	state = value
	player_id = owner_id
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()

func _process(_delta: float) -> void:
	if not visible:
		return
	var viewport: Vector2 = get_viewport_rect().size
	var width: float = minf(408.0, viewport.x - 48.0)
	_card.position = Vector2(viewport.x - width - 24.0, 70.0)
	_card.size = Vector2(width, 0.0)
	_copy.custom_minimum_size.x = width - 32.0
	_prompt.position = Vector2(viewport.x * 0.2, viewport.y * 0.64)
	_prompt.size = Vector2(viewport.x * 0.6, 0.0)
	var recovery_width: float = minf(660.0, viewport.x - 48.0)
	_recovery_copy.custom_minimum_size.x = recovery_width - 32.0
	_recovery.size = Vector2(recovery_width, 0.0)
	_recovery.position = (viewport - _recovery.size) * 0.5

func _refresh() -> void:
	if _copy == null:
		return
	visible = not state.is_empty()
	if not visible:
		_copy.text = ""
		_prompt.text = ""
		return
	var lines: Array[String] = [tr("MISSION_M01_TITLE"), tr("DIFFICULTY_" + String(state["rules"]["difficulty"]).to_upper()), ""]
	_recovery.visible = false
	if state.get("run") is Dictionary:
		var run: Dictionary = state["run"]
		lines.insert(2, tr("RUN_CONTINUES").format({"count": int(run["continues"])}))
		if run["status"] in ["continue", "failed", "abandoned"]:
			_recovery.visible = true
			var copy: Array[String] = [tr("RUN_FALLEN" if run["status"] == "continue" else "RUN_ENDED"), "", tr("RUN_CONTINUES").format({"count": int(run["continues"])}), ""]
			if run["status"] == "continue":
				copy.append(tr("RUN_RESTORE_ENTRY"))
				copy.append(tr("RUN_CONTINUE_INPUT" if not player_id.is_empty() else "RUN_WAITING_OWNER"))
			else:
				copy.append(tr("RUN_FAILED" if run["status"] == "failed" else "RUN_ABANDONED"))
			copy.append("")
			copy.append(tr("RUN_MENU_INPUT"))
			_recovery_copy.text = "\n".join(copy)
	match state["phase"]:
		"briefing":
			lines.append(tr("STORY_M01_RECAP"))
			lines.append(tr("STORY_WAITING"))
			for member: Dictionary in state["party"]:
				lines.append(tr("STORY_READY_MEMBER" if member["ready"] else "STORY_READING_MEMBER").format({"name": member["name"]}))
		"find_transfer":
			lines.append(tr("STORY_M01_RECAP"))
			lines.append(tr("MISSION_FIND_RECORD"))
		"reach_lift":
			lines.append(tr("MISSION_REACH_LIFT"))
			lines.append(tr("MISSION_TRANSFER_RECORD"))
			var waiting: Array[String] = []
			for member: Dictionary in state["party"]:
				if not member["aboard"]:
					waiting.append(member["name"])
			if not waiting.is_empty():
				lines.append(tr("MISSION_WAITING_FOR").format({"names": ", ".join(waiting)}))
		"departed":
			lines.append(tr("MISSION_DEPARTED"))
	_copy.text = "\n".join(lines)
	_prompt.text = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			_prompt.text = tr("MISSION_USE_RECORD" if prompt["kind"] == "transfer_record" else "MISSION_USE_LIFT")
	_prompt.visible = not _prompt.text.is_empty()
