class_name MissionHud
extends Control

## The objective card introduces a beat, then leaves. Use prompts and the
## fallen-run choice stay for as long as they are true.
const STAGE_SECONDS: float = 8.0
const M02_KNOWN: Array[String] = ["companion_released", "party_departed"]
const M02_USES: Array[String] = []
var state: Dictionary = {}
var player_id: String = ""
var _stage_phase: String = ""
var _stage_left: float = 0.0
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
	var phase: String = _stage_key(value)
	if phase != _stage_phase:
		_stage_phase = phase
		_stage_left = STAGE_SECONDS
	state = value
	player_id = owner_id
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()

func _process(delta: float) -> void:
	if _stage_left > 0.0:
		_stage_left = maxf(0.0, _stage_left - delta)
		if _card != null:
			_card.visible = _stage_card_visible()
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
		_card.visible = false
		return
	if state.get("id") == MissionState.M02_ID:
		_refresh_m02()
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
	_card.visible = _stage_card_visible()
	_prompt.text = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			_prompt.text = tr("MISSION_USE_RECORD" if prompt["kind"] == "transfer_record" else "MISSION_USE_LIFT")
	_prompt.visible = not _prompt.text.is_empty()

func _stage_card_visible() -> bool:
	var phase := str(state.get("phase", ""))
	if state.get("id") == MissionState.M02_ID:
		# One line at most: a legal prompt replaces the objective line.
		if phase == "in_progress":
			return _stage_left > 0.0 and (_prompt == null or not _prompt.visible)
		return true
	if phase == "briefing" or phase == "departed":
		return true
	if phase == "find_transfer" or phase == "reach_lift":
		return _stage_left > 0.0
	return false

## M01 restages the card on a phase change. M02 stays `in_progress`, so its
## card restages on each new objective and on a retry.
static func _stage_key(value: Dictionary) -> String:
	if value.is_empty():
		return ""
	var phase: String = str(value.get("phase", ""))
	if value.get("id") != MissionState.M02_ID or not value.get("m02") is Dictionary:
		return phase
	var current: Variant = value["m02"].get("current")
	var id: String = str(current.get("id", "")) if current is Dictionary else ""
	return "%s:%s:%s" % [phase, id, str(value.get("attempt", ""))]

## M02 keeps to one line outside menus: the use prompt while it is legal,
## otherwise the objective for a few seconds after it changes. Gates and
## panels in the world carry the rest.
func _refresh_m02() -> void:
	_recovery.visible = false
	var progress: Dictionary = state["m02"]
	var line: String = ""
	match state["phase"]:
		"briefing":
			line = _catalog("M02_WAITING")
		"departed":
			line = _catalog("M02_DEPARTED")
		_:
			line = _catalog(objective_key(str(progress["current"]["id"])))
	_copy.text = line
	_prompt.text = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			_prompt.text = _catalog(use_key(str(progress["current"]["id"])))
	_prompt.visible = not _prompt.text.is_empty()
	_card.visible = _stage_card_visible()

## Catalog copy only. A missing key is an error and shows nothing, never the key.
func _catalog(key: String) -> String:
	var copy: String = WorldSign.localized(key)
	if copy.is_empty():
		push_error("mission_hud: missing localized key " + key)
	return copy

static func objective_key(id: String) -> String:
	return "M02_OBJECTIVE_" + id.to_upper() if id in M02_KNOWN else "M02_OBJECTIVE_UNKNOWN"

static func use_key(id: String) -> String:
	return "M02_USE_" + id.to_upper() if id in M02_USES else "M02_USE_CONSOLE"
