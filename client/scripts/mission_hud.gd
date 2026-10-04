class_name MissionHud
extends Control

## The objective card introduces a beat, then leaves. Use prompts and the
## fallen-run choice stay for as long as they are true.
const STAGE_SECONDS: float = 8.0
const M02_KNOWN: Array[String] = ["ward_reached", "companion_released", "party_departed"]
const M02_USES: Array[String] = ["companion_released"]
signal notice_requested(text: String)
var _notice_attempt: String = ""
var _notice_mast_hp: int = -1
var _notice_mast_fired: bool = false
var _notice_m04_attempt: String = ""
var _notice_m04_known: bool = false
var _notice_m04_market: bool = false
var _notice_m04_fired: bool = false
var _notice_m06_attempt: String = ""
var _notice_m06_customs: bool = false
var _notice_m06_known: bool = false
var state: Dictionary = {}
var player_id: String = ""
var _stage_phase: String = ""
var _stage_left: float = 0.0
var _card: PanelContainer
var _copy: Label
var _run_badge: Label
var _evac_badge: Label
## Use and continue prompts carry the key or pad glyph for the device in the
## player's hands, so they are rich text. The plain strings are kept beside
## them for tests and for anything that reads the HUD as text.
var _prompt: RichTextLabel
var _recovery: PanelContainer
var _recovery_copy: RichTextLabel
var prompt_text: String = ""
var recovery_text: String = ""
var _prompt_template: String = ""
var _recovery_template: String = ""
var _device_revision: int = -1
var _run_wanted: bool = false
var _evac_wanted: bool = false
var _evac_seen: String = ""
var _status_left: float = 0.0
var _run_onward: bool = false

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
	_run_badge = _label(16)
	_run_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_run_badge)
	_evac_badge = _label(15)
	_evac_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_evac_badge.add_theme_color_override("font_color", MenuTheme.EMBER)
	add_child(_evac_badge)
	_prompt = _rich(22)
	add_child(_prompt)
	_recovery = PanelContainer.new()
	_recovery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recovery.add_theme_stylebox_override("panel", MenuTheme.panel(Color("201b19"), Color("986048")))
	add_child(_recovery)
	_recovery_copy = _rich(24)
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

func _rich(font_size: int) -> RichTextLabel:
	var label: RichTextLabel = RichTextLabel.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_font_override("normal_font", MenuTheme.FONT)
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", MenuTheme.BONE)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 4)
	return label

## Draw a prompt template with glyphs for the active device.
func _show_prompt(template: String) -> void:
	_prompt_template = template
	prompt_text = InputGlyphs.render(_prompt, template, 44, true) if not template.is_empty() else ""
	if template.is_empty():
		_prompt.clear()
	_prompt.visible = not prompt_text.is_empty()

func _show_recovery(template: String) -> void:
	_recovery_template = template
	recovery_text = InputGlyphs.render(_recovery_copy, template, 44, true) if not template.is_empty() else ""
	if template.is_empty():
		_recovery_copy.clear()

func apply(value: Dictionary, owner_id: String) -> void:
	_update_mast_notice(value)
	_update_market_notice(value)
	_update_port_notice(value)
	var phase: String = _stage_key(value)
	if phase != _stage_phase:
		_stage_phase = phase
		_stage_left = STAGE_SECONDS
	state = value
	player_id = owner_id
	_refresh()

## MapInfo temporarily clears the card before ordered mission facts arrive.
## Keep notice history through that handoff; session teardown resets it.
func reset_notices() -> void:
	_notice_attempt = ""
	_notice_mast_hp = -1
	_notice_mast_fired = false
	_notice_m04_attempt = ""
	_notice_m04_known = false
	_notice_m04_market = false
	_notice_m04_fired = false
	_notice_m06_attempt = ""
	_notice_m06_customs = false
	_notice_m06_known = false

func _update_port_notice(value: Dictionary) -> void:
	if value.is_empty():
		return
	if value.get("id") != MissionState.M06_ID:
		_notice_m06_attempt = ""
		_notice_m06_known = false
		_notice_m06_customs = false
		return
	var run: Dictionary = value.get("run", {})
	var identity: String = "%s:%s" % [str(run.get("id", "development")), str(value["attempt"])]
	if identity != _notice_m06_attempt:
		_notice_m06_attempt = identity
		_notice_m06_known = false
		_notice_m06_customs = false
	var cleared: bool = "customs_cleared" in value["m06"]["completed"]
	if cleared and _notice_m06_known and not _notice_m06_customs:
		notice_requested.emit(_catalog("WORLD_M06_TERN_LINE"))
	_notice_m06_customs = cleared
	_notice_m06_known = true

func _update_mast_notice(value: Dictionary) -> void:
	if value.is_empty():
		return
	if value.get("id") != MissionState.M03_ID:
		_notice_attempt = ""
		_notice_mast_hp = -1
		_notice_mast_fired = false
		return
	var run: Dictionary = value.get("run", {})
	var identity: String = "%s:%s" % [str(run.get("id", "development")), str(value["attempt"])]
	if identity != _notice_attempt:
		reset_notices()
		_notice_attempt = identity
	var hp: int = int(value["m03"]["mast_hp"])
	if hp == 0 and _notice_mast_hp > 0 and not _notice_mast_fired:
		_notice_mast_fired = true
		notice_requested.emit(_catalog("WORLD_M03_MARA_WARNING"))
	_notice_mast_hp = hp

func _update_market_notice(value: Dictionary) -> void:
	if value.is_empty():
		return
	if value.get("id") != MissionState.M04_ID:
		_notice_m04_attempt = ""
		_notice_m04_known = false
		_notice_m04_market = false
		_notice_m04_fired = false
		return
	var run: Dictionary = value.get("run", {})
	var identity: String = "%s:%s" % [str(run.get("id", "development")), str(value["attempt"])]
	if identity != _notice_m04_attempt:
		_notice_m04_attempt = identity
		_notice_m04_known = false
		_notice_m04_market = false
		_notice_m04_fired = false
	var cleared: bool = "market_wave_b_cleared" in value["m04"]["completed"]
	if cleared and _notice_m04_known and not _notice_m04_market and not _notice_m04_fired:
		_notice_m04_fired = true
		notice_requested.emit(_catalog("WORLD_M04_MARA_EVACUATE"))
	_notice_m04_market = cleared
	_notice_m04_known = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()

func _process(delta: float) -> void:
	if _device_revision != InputDevice.revision:
		_device_revision = InputDevice.revision
		# Plain objective/departure cards also contain input tokens. Refresh
		# copy without applying another mission packet or restarting its stage.
		_refresh()
	if _stage_left > 0.0:
		_stage_left = maxf(0.0, _stage_left - delta)
		if _card != null:
			_card.visible = _stage_card_visible()
	_status_left = maxf(0.0, _status_left - delta)
	_stage_badges()
	if not visible:
		return
	var viewport: Vector2 = get_viewport_rect().size
	var width: float = minf(408.0, viewport.x - 48.0)
	_card.position = Vector2(viewport.x - width - 24.0, 70.0)
	_card.size = Vector2(width, 0.0)
	_copy.custom_minimum_size.x = width - 32.0
	_run_badge.position = Vector2(viewport.x - width - 24.0, 45.0)
	_run_badge.size = Vector2(width, 0.0)
	# Departure copy and translated objectives can wrap beyond two lines.
	# Field status belongs below the actual card rather than through its text.
	var field_top: float = maxf(132.0, _card.position.y + _card.size.y + 8.0) if _card.visible else 132.0
	_evac_badge.position = Vector2(viewport.x - width - 24.0, field_top)
	_evac_badge.size = Vector2(width, 0.0)
	_prompt.position = Vector2(viewport.x * 0.2, viewport.y * 0.64)
	_prompt.size = Vector2(viewport.x * 0.6, 0.0)
	var recovery_width: float = minf(660.0, viewport.x - 48.0)
	_recovery_copy.custom_minimum_size.x = recovery_width - 32.0
	_recovery.size = Vector2(recovery_width, 0.0)
	_recovery.position = (viewport - _recovery.size) * 0.5

func _refresh() -> void:
	if _copy == null:
		return
	_refresh_content()
	# A completed local run can go straight on instead of through the menu.
	if _run_onward and str(state.get("phase", "")) == "departed":
		_show_prompt(tr("RUN_NEXT_MISSION_INPUT"))
	# Status badges are wanted by each mission; when they show is shared. A
	# changed status line gets its own few seconds, then rides with the card.
	_run_wanted = _run_badge.visible
	_evac_wanted = _evac_badge.visible
	if _evac_wanted and _evac_badge.text != _evac_seen:
		_status_left = STAGE_SECONDS
	_evac_seen = _evac_badge.text if _evac_wanted else ""
	_stage_badges()

## The run allowance and optional-route status are facts a player checks, not
## something to read all mission. They appear with the objective card, on a
## change and during recovery, and otherwise leave the view.
func _stage_badges() -> void:
	if _run_badge == null or _evac_badge == null:
		return
	_run_badge.visible = _run_wanted and (_card.visible or _recovery.visible)
	_evac_badge.visible = _evac_wanted and (_card.visible or _status_left > 0.0)

func _refresh_content() -> void:
	visible = not state.is_empty()
	if not visible:
		_copy.text = ""
		_run_badge.visible = false
		_evac_badge.visible = false
		_show_prompt("")
		_card.visible = false
		return
	if state.get("id") == MissionState.M02_ID:
		_refresh_m02()
		return
	if state.get("id") == MissionState.M03_ID:
		_refresh_m03()
		return
	if state.get("id") == MissionState.M04_ID:
		_refresh_m04()
		return
	if state.get("id") == MissionState.M05_ID:
		_refresh_m05()
		return
	if state.get("id") == MissionState.M08_ID:
		_refresh_m08()
		return
	if state.get("id") == MissionState.M06_ID:
		_refresh_m06()
		return
	if state.get("id") == MissionState.M07_ID:
		_refresh_m07()
		return
	_evac_badge.visible = false
	_recovery.visible = false
	# The same quiet card as the later missions: the run allowance is a corner
	# badge, and play shows the objective rather than the title and tier.
	_run_badge.visible = state.get("run") is Dictionary
	if _run_badge.visible:
		var run: Dictionary = state["run"]
		_run_badge.text = tr("RUN_LEVEL_BADGE").format({"attempt": int(state.get("attempt", 1)), "continues": int(run["continues"])})
		_refresh_run_recovery(run)
	var lines: Array[String] = []
	match state["phase"]:
		"briefing":
			lines.append(tr("MISSION_M01_TITLE"))
			lines.append(tr("DIFFICULTY_" + String(state["rules"]["difficulty"]).to_upper()))
			lines.append("")
			lines.append(tr("STORY_M01_RECAP"))
			lines.append(tr("STORY_WAITING"))
			for member: Dictionary in state["party"]:
				lines.append(tr("STORY_READY_MEMBER" if member["ready"] else "STORY_READING_MEMBER").format({"name": member["name"]}))
		"find_transfer":
			lines.append(tr("MISSION_FIND_RECORD"))
		"reach_lift":
			lines.append(tr("MISSION_REACH_LIFT"))
			lines.append(tr("MISSION_TRANSFER_RECORD"))
			# Only other people can keep the lift waiting. Listing the player
			# who is reading the card tells them they are waiting for themselves.
			var waiting: Array[String] = []
			for member: Dictionary in state["party"]:
				if not member["aboard"] and str(member["id"]) != player_id:
					waiting.append(member["name"])
			if not waiting.is_empty():
				lines.append(tr("MISSION_WAITING_FOR").format({"names": ", ".join(waiting)}))
		"departed":
			lines.append(InputGlyphs.plain(tr("MISSION_DEPARTED")))
	_copy.text = "\n".join(lines)
	_card.visible = _stage_card_visible()
	var use: String = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			use = tr("MISSION_USE_RECORD" if prompt["kind"] == "transfer_record" else "MISSION_USE_LIFT")
	_show_prompt(use)

func _stage_card_visible() -> bool:
	var phase := str(state.get("phase", ""))
	if state.get("id") in [MissionState.M02_ID, MissionState.M03_ID, MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID, MissionState.M08_ID]:
		# One line at most: a legal prompt replaces the objective line.
		if phase == "in_progress":
			return _stage_left > 0.0 and prompt_text.is_empty()
		return true
	if phase == "briefing" or phase == "departed":
		return true
	if phase == "find_transfer" or phase == "reach_lift":
		return _stage_left > 0.0
	return false

## GameManager owns whether the onward step is legal; the HUD only shows it.
func set_run_onward(available: bool) -> void:
	if available == _run_onward:
		return
	_run_onward = available
	_refresh()

## M01 restages the card on a phase change. M02 stays `in_progress`, so its
## card restages on each new objective and on a retry.
static func _stage_key(value: Dictionary) -> String:
	if value.is_empty():
		return ""
	var phase: String = str(value.get("phase", ""))
	var progress_key: String = "m07" if value.get("id") == MissionState.M07_ID else "m08" if value.get("id") == MissionState.M08_ID else ("m06" if value.get("id") == MissionState.M06_ID else ("m05" if value.get("id") == MissionState.M05_ID else "m04"))
	if value.get("id") in [MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID, MissionState.M08_ID] and value.get(progress_key) is Dictionary:
		var current: Variant = value[progress_key].get("current")
		var objective: String = str(current.get("id", "")) if current is Dictionary else ""
		return "%s:%s:%s" % [phase, objective, str(value.get("attempt", ""))]
	if value.get("id") == MissionState.M03_ID and value.get("m03") is Dictionary:
		var progress: Dictionary = value["m03"]
		return "%s:%s:%s:%s:%s" % [phase, str(int(progress.get("mast_hp", 40)) == 0), str(progress.get("mast_secured", false)), str(progress.get("train_secured", false)), str(value.get("attempt", ""))]
	if value.get("id") != MissionState.M02_ID or not value.get("m02") is Dictionary:
		return phase
	var current: Variant = value["m02"].get("current")
	var id: String = str(current.get("id", "")) if current is Dictionary else ""
	return "%s:%s:%s:%s" % [phase, id, str(value["m02"].get("ward_secured", false)), str(value.get("attempt", ""))]

## M02 keeps to one line outside menus: the use prompt while it is legal,
## otherwise the objective for a few seconds after it changes. Gates and
## panels in the world carry the rest.
func _refresh_m02() -> void:
	_recovery.visible = false
	_run_badge.visible = state.get("run") is Dictionary
	if _run_badge.visible:
		var run: Dictionary = state["run"]
		_run_badge.text = tr("RUN_LEVEL_BADGE").format({"attempt": int(state["attempt"]), "continues": int(run["continues"])})
		_refresh_run_recovery(run)
	var progress: Dictionary = state["m02"]
	var evacuation: Dictionary = progress.get("evacuation", {})
	var evac_phase: String = str(evacuation.get("phase", "held"))
	_evac_badge.visible = not evacuation.is_empty() and evac_phase != "held"
	if _evac_badge.visible:
		var key: String = "M02_EVAC_" + evac_phase.to_upper()
		if state["phase"] == "departed" and not evacuation["evacuated"]:
			key = "M02_EVAC_UNCONFIRMED"
		_evac_badge.text = _catalog(key)
	var line: String = ""
	match state["phase"]:
		"briefing":
			line = _catalog("M02_WAITING")
		"departed":
			line = InputGlyphs.plain(_catalog("M02_DEPARTED"))
		_:
			var objective_id: String = str(progress["current"]["id"])
			line = _catalog("M02_OBJECTIVE_COMPANION_SECURED" if objective_id == "companion_released" and progress["ward_secured"] else objective_key(objective_id))
	_copy.text = line
	var use: String = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			use = _catalog(use_key(str(progress["current"]["id"])))
	_show_prompt(use)
	_card.visible = _stage_card_visible()

func _refresh_m03() -> void:
	_recovery.visible = false
	_run_badge.visible = state.get("run") is Dictionary
	if _run_badge.visible:
		var run: Dictionary = state["run"]
		_run_badge.text = tr("RUN_LEVEL_BADGE").format({"attempt": int(state["attempt"]), "continues": int(run["continues"])})
		_refresh_run_recovery(run)
	var progress: Dictionary = state["m03"]
	var freed: int = 0
	for car: Dictionary in progress["cars"]:
		if car["released"]:
			freed += 1
	_evac_badge.visible = freed > 0 or state["phase"] == "departed"
	_evac_badge.text = _catalog("M03_CARS_FREED").format({"count": freed, "total": progress["cars"].size()})
	var line: String
	match state["phase"]:
		"briefing":
			line = _catalog("M03_WAITING")
		"departed":
			line = InputGlyphs.plain(_catalog("M03_DEPARTED"))
		_:
			if int(progress["mast_hp"]) > 0:
				line = _catalog("M03_OBJECTIVE_SHOOT_MAST" if progress["mast_secured"] else "M03_OBJECTIVE_CLEAR_MAST")
			else:
				line = _catalog("M03_OBJECTIVE_BOARD_TRAIN" if progress["train_secured"] else "M03_OBJECTIVE_CLEAR_TRAIN")
	_copy.text = line
	var use: String = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			use = _catalog("M03_USE_TRAIN")
	_show_prompt(use)
	_card.visible = _stage_card_visible()

func _refresh_m04() -> void:
	_recovery.visible = false
	_run_badge.visible = state.get("run") is Dictionary
	if _run_badge.visible:
		var run: Dictionary = state["run"]
		_run_badge.text = tr("RUN_LEVEL_BADGE").format({"attempt": int(state["attempt"]), "continues": int(run["continues"])})
		_refresh_run_recovery(run)
	var progress: Dictionary = state["m04"]
	_evac_badge.visible = progress["clinic_open"] or int(progress["photos_completed"]) > 0 or state["phase"] == "departed"
	var clinic: String = _catalog("M04_CLINIC_RELEASED" if progress["patients_released"] else ("M04_CLINIC_OPEN" if progress["clinic_open"] else "M04_CLINIC_UNCONFIRMED"))
	_evac_badge.text = _catalog("M04_FIELD_STATUS").format({"clinic": clinic, "photos": int(progress["photos_completed"])})
	var line: String
	match state["phase"]:
		"briefing": line = _catalog("M04_WAITING")
		"departed": line = InputGlyphs.plain(_catalog("M04_DEPARTED"))
		_: line = _catalog("M04_OBJECTIVE_" + str(progress["current"]["id"]).to_upper())
	_copy.text = line
	var use: String = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			use = _catalog("M04_USE_CLINIC" if prompt["kind"] == "clinic_shutter" else "M04_USE_ROOF")
	_show_prompt(use)
	_card.visible = _stage_card_visible()

func _refresh_run_recovery(run: Dictionary) -> void:
	_recovery.visible = run["status"] in ["continue", "failed", "abandoned"]
	if not _recovery.visible:
		_show_recovery("")
		return
	var copy: Array[String] = [tr("RUN_FALLEN" if run["status"] == "continue" else "RUN_ENDED"), "", tr("RUN_CONTINUES").format({"count": int(run["continues"])}), ""]
	if run["status"] == "continue":
		copy.append(tr("RUN_RESTORE_ENTRY"))
		copy.append(tr("RUN_CONTINUE_INPUT" if not player_id.is_empty() else "RUN_WAITING_OWNER"))
	else:
		copy.append(tr("RUN_FAILED" if run["status"] == "failed" else "RUN_ABANDONED"))
	copy.append("")
	copy.append(tr("RUN_MENU_INPUT"))
	_show_recovery("\n".join(copy))

func _refresh_m05() -> void:
	_recovery.visible = false
	_run_badge.visible = state.get("run") is Dictionary
	if _run_badge.visible:
		var run: Dictionary = state["run"]
		_run_badge.text = tr("RUN_LEVEL_BADGE").format({"attempt": int(state["attempt"]), "continues": int(run["continues"])})
		_refresh_run_recovery(run)
	var progress: Dictionary = state["m05"]
	_evac_badge.visible = progress["group_released"] or state["phase"] == "departed"
	var freed: int = progress["captives"].size() if progress["group_released"] else 0
	# Boarding is supplied separately by the validated geometry, never inferred
	# from release or route timing.
	_evac_badge.text = _catalog("M05_WORKERS_STATUS").format({"freed": freed, "aboard": workers_aboard(state, boarding_region)})
	match state["phase"]:
		"briefing": _copy.text = _catalog("M05_WAITING")
		"departed": _copy.text = InputGlyphs.plain(_catalog("M05_DEPARTED"))
		_: _copy.text = InputGlyphs.plain(_catalog("M05_OBJECTIVE_" + str(progress["current"]["id"]).to_upper()))
	var use: String = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			use = _catalog("M05_USE_SHIP")
	_show_prompt(use)
	_card.visible = _stage_card_visible()

func _refresh_m06() -> void:
	_recovery.visible = false
	_run_badge.visible = state.get("run") is Dictionary
	if _run_badge.visible:
		var run: Dictionary = state["run"]
		_run_badge.text = tr("RUN_LEVEL_BADGE").format({"attempt": int(state["attempt"]), "continues": int(run["continues"])})
		_refresh_run_recovery(run)
	var progress: Dictionary = state["m06"]
	_evac_badge.visible = true
	_evac_badge.text = _catalog("M06_SERVICE_MARKED" if progress["prisoner_route_marked"] else "M06_SERVICE_OPTIONAL")
	match state["phase"]:
		"briefing": _copy.text = _catalog("M06_WAITING")
		"departed": _copy.text = InputGlyphs.plain(_catalog("M06_DEPARTED"))
		_: _copy.text = _catalog("M06_OBJECTIVE_" + str(progress["current"]["id"]).to_upper())
	var use: String = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			use = _catalog("M06_USE_TRANSIT")
	_show_prompt(use)
	_card.visible = _stage_card_visible()

## The curfew town has one objective line and a legal freight prompt.
func _refresh_m07() -> void:
	_recovery.visible = false
	_run_badge.visible = state.get("run") is Dictionary
	if _run_badge.visible:
		var run: Dictionary = state["run"]
		_run_badge.text = tr("RUN_LEVEL_BADGE").format({"attempt": int(state["attempt"]), "continues": int(run["continues"])})
		_refresh_run_recovery(run)
	var progress: Dictionary = state["m07"]
	_evac_badge.visible = false
	match state["phase"]:
		"briefing": _copy.text = _catalog("M07_WAITING")
		"departed": _copy.text = InputGlyphs.plain(_catalog("M07_DEPARTED"))
		_: _copy.text = _catalog("M07_OBJECTIVE_" + str(progress["current"]["id"]).to_upper())
	var use: String = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			use = _catalog("M07_USE_FREIGHT")
	_show_prompt(use)
	_card.visible = _stage_card_visible()

func _refresh_m08() -> void:
	_recovery.visible = false
	_run_badge.visible = state.get("run") is Dictionary
	if _run_badge.visible:
		var run: Dictionary = state["run"]
		_run_badge.text = tr("RUN_LEVEL_BADGE").format({"attempt": int(state["attempt"]), "continues": int(run["continues"])})
		_refresh_run_recovery(run)
	var progress: Dictionary = state["m08"]
	# The optional rescues read only once the seal has lifted.
	_evac_badge.visible = progress["seal_open"]
	_evac_badge.text = _catalog("M08_BAYS_RELEASED" if progress["custody_released"] else "M08_BAYS_OPTIONAL") \
		+ "  " + _catalog("M08_CABINET_SECURED" if progress["recovered_mind_secured"] else "M08_CABINET_OPTIONAL")
	match state["phase"]:
		"briefing": _copy.text = _catalog("M08_WAITING")
		"departed": _copy.text = InputGlyphs.plain(_catalog("M08_DEPARTED"))
		_: _copy.text = InputGlyphs.plain(_catalog("M08_OBJECTIVE_" + str(progress["current"]["id"]).to_upper()))
	var use: String = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			use = _catalog("M08_USE_FREIGHT")
	_show_prompt(use)
	_card.visible = _stage_card_visible()

var boarding_region: Dictionary = {}

static func workers_aboard(value: Dictionary, boarding: Dictionary) -> int:
	if value.get("id") != MissionState.M05_ID or boarding.is_empty() or not value["m05"]["group_released"]:
		return 0
	var count: int = 0
	for captive: Dictionary in value["m05"]["captives"]:
		if M03MissionState._inside(captive["feet"], boarding):
			count += 1
	return count

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
