extends Control

## The front menu, in the shape every shooter has used since Doom: single
## player, multiplayer, settings, quit. It builds itself in code rather than
## living in a scene file, because a menu with submenus is a state machine and
## a state machine is easier to read as code than as a node tree.
##
## It is fully keyboard navigable. Arrow keys move, Enter chooses, Escape goes
## back. A laptop with no mouse is a first-class way to play this.

const ARENA_SCENE: String = "res://scenes/main.tscn"
const LOOPBACK: String = "127.0.0.1:6767"
const MENU_FONT: Font = preload("res://assets/fonts/BlackOpsOne-Regular.ttf")

var _page: String = "main"
var _root: VBoxContainer = null
var _status: Label = null
var _host_edit: LineEdit = null
var _match_line: Label = null
var _watch_button: Button = null
var _join_button: Button = null
var _probe: HTTPRequest = null
var _console: FragrConsole = null
var _settings: FragrSettings
var _name_edit: LineEdit = null
var _local_match: LocalMatch
var _local_host: LocalHost
var _host_settings: Dictionary = {"mode": "tdm", "map_id": 1, "bots": 4, "lan": false, "port": 0}
var _host_mode: OptionButton
var _host_map: OptionButton
var _host_bots: SpinBox
var _host_lan: CheckButton
var _host_port: SpinBox
var _launch_pending: bool = false
## A finished mission asked to continue the run; cleared once it starts or the
## saved run turns out to have nothing playable next.
var _onward_pending: bool = false
var _campaign_run_mode: String = "new"
var _campaign_play_arrival: bool = false
var _profile_return: String = "main"
var _opening: CampaignOpening
var _title: Label
var _tagline: Label
var _device_revision: int = -1

func _ready() -> void:
	MouseCapture.release()
	_local_match = LocalMatch.for_tree(get_tree())
	_local_match.stop()
	_local_host = LocalHost.for_tree(get_tree())
	_local_host.state_changed.connect(_on_host_state_changed)
	_local_match.mission_ready.connect(_on_local_ready)
	_local_match.state_changed.connect(_on_local_state_changed)
	_local_match.run_preview_changed.connect(_on_run_preview_changed)
	theme = MenuTheme.build()
	UserDataMigration.run_for(get_tree())
	if _settings == null:
		_settings = FragrSettings.for_tree(get_tree())
	_settings.load_from_disk()
	_settings.changed.connect(_apply_preferences)
	get_viewport().size_changed.connect(_apply_render_preferences)
	_apply_preferences()
	var watcher: InputDevice = InputDevice.new()
	watcher.name = "InputDevice"
	add_child(watcher)
	_build_chrome()
	# A finished mission asked to go straight on. Open Single Player and start
	# Continue Run once the stopped child and the saved run preview allow it.
	if get_tree().has_meta(LocalMatch.ONWARD_META):
		get_tree().remove_meta(LocalMatch.ONWARD_META)
		_onward_pending = true
		_show("single")
	else:
		_show("main")
	_console = FragrConsole.new()
	_console.name = "FragrConsole"
	_console.preferences = _settings
	add_child(_console)
	var frame_counter: PerformanceOverlay = PerformanceOverlay.new()
	frame_counter.name = "PerformanceOverlay"
	frame_counter.preferences = _settings
	add_child(frame_counter)
	if InstallCheck.requested():
		add_child(InstallCheck.new(_local_match))

func _apply_preferences() -> void:
	_settings.apply()
	_apply_render_preferences()

func _apply_render_preferences() -> void:
	RenderQuality.apply(get_viewport(), _settings)

func _build_chrome() -> void:
	var back: MenuBackdrop = MenuBackdrop.new()
	back.anchor_right = 1.0
	back.anchor_bottom = 1.0
	add_child(back)

	var centre: CenterContainer = CenterContainer.new()
	centre.anchor_right = 1.0
	centre.anchor_bottom = 1.0
	add_child(centre)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.custom_minimum_size = Vector2(660.0, 0.0)
	centre.add_child(column)

	var title: Label = Label.new()
	_title = title
	title.text = "FRAGR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 154)
	title.add_theme_color_override("font_color", Color("c7b89a"))
	title.add_theme_color_override("font_shadow_color", Color("5d291d"))
	title.add_theme_constant_override("shadow_offset_x", 6)
	title.add_theme_constant_override("shadow_offset_y", 9)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color("080b0b"))
	column.add_child(title)
	var tagline: Label = Label.new()
	_tagline = tagline
	tagline.text = "CONTESTED FREQUENCY  //  PORT 6767"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 18)
	tagline.add_theme_color_override("font_color", Color("a4774c"))
	column.add_child(tagline)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 8)
	column.add_child(_root)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(0.6, 0.62, 0.64))
	_status.text = _nav_hint()
	column.add_child(_status)

func _clear() -> void:
	for child in _root.get_children():
		_root.remove_child(child)
		child.queue_free()

func _button(text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text.to_upper()
	b.custom_minimum_size = Vector2(0.0, 62.0)
	b.add_theme_font_size_override("font_size", 32)
	b.add_theme_color_override("font_color", Color("bba789"))
	b.add_theme_color_override("font_focus_color", Color("ffcc83"))
	b.add_theme_color_override("font_hover_color", Color("ffcc83"))
	b.add_theme_color_override("font_pressed_color", Color("ffffff"))
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	var selected: StyleBoxFlat = StyleBoxFlat.new()
	selected.bg_color = Color("4a2019")
	selected.border_color = Color("b66637")
	selected.border_width_left = 6
	selected.border_width_bottom = 2
	b.add_theme_stylebox_override("focus", selected)
	b.add_theme_stylebox_override("hover", selected)
	b.add_theme_stylebox_override("pressed", selected)
	b.pressed.connect(handler)
	_root.add_child(b)
	return b

func _label(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.55, 0.7, 0.72))
	_root.add_child(l)
	return l

func _show(page: String) -> void:
	if _probe != null:
		_probe.cancel_request()
	_page = page
	_title.add_theme_font_size_override("font_size", 96 if page in ["single", "practice"] else (60 if page in ["records", "settings", "profile", "multi", "host"] else 154))
	_tagline.visible = page not in ["records", "settings", "profile", "single", "practice", "multi", "host"]
	_clear()
	_status.text = tr(_local_match.error_key) if not _local_match.error_key.is_empty() else _nav_hint()
	match page:
		"main":
			_page_main()
		"single":
			_page_single()
		"practice":
			_page_practice()
		"difficulty":
			_page_difficulty()
		"new_confirm":
			_page_new_confirm()
		"multi":
			_page_multi()
		"host":
			_page_host()
		"settings":
			_page_settings()
		"profile":
			_page_profile()
		"records":
			var panel: RecordsPanel = RecordsPanel.new()
			panel.name = "ServiceRecord"
			panel.records = PlayerRecords.for_tree(get_tree())
			panel.preferences = _settings
			_root.add_child(panel)
			_button(tr("RECORD_BACK"), func() -> void: _show("main"))
		"launch":
			_page_launch()
	await get_tree().process_frame
	if _page != page:
		return
	if page == "settings" and _page == page:
		(_root.get_node("SettingsPanel") as SettingsPanel).focus_first()
		return
	if page == "records":
		(_root.get_node("ServiceRecord") as RecordsPanel).focus_first()
		return
	for child in _root.get_children():
		if child is Button and not (child as Button).disabled:
			(child as Button).grab_focus()
			break

## Navigation help for the device in the player's hands.
func _nav_hint() -> String:
	var line: String = InputGlyphs.plain(tr("MENU_NAV_PAD" if InputDevice.is_gamepad() else "MENU_NAV_KEYS"))
	return line + "\nFreedom is not a licensed feature."

func _process(_delta: float) -> void:
	if _device_revision != InputDevice.revision and _status != null:
		_device_revision = InputDevice.revision
		if _local_match == null or _local_match.error_key.is_empty():
			_status.text = _nav_hint()

func _page_main() -> void:
	_button("Single Player", func() -> void: _show("single"))
	_button("Multiplayer", func() -> void: _show("multi"))
	_button("Your callsign", func() -> void: _open_profile("main"))
	_button(tr("RECORD_TITLE"), func() -> void: _show("records"))
	_button("Settings", func() -> void: _show("settings"))
	_button("Quit", func() -> void: get_tree().quit())

func _page_single() -> void:
	_label(tr("MENU_CAMPAIGN"))
	if _local_match.run_preview.is_empty():
		_local_match.refresh_run_preview.call_deferred()
	var status: String = str(_local_match.run_preview.get("status", "loading"))
	var can_start: bool = _local_match.state in [LocalMatch.State.IDLE, LocalMatch.State.FAILED]
	match status:
		"ready":
			var saved_mission: String = str(_local_match.run_preview["mission"])
			var mission: Button = _button(tr("RUN_CONTINUE"), _start_campaign_resume)
			mission.name = _saved_mission_button(saved_mission)
			mission.disabled = not can_start
			_label(tr("RUN_SAVED_MISSION").format({"mission": _saved_mission_title(saved_mission)}))
			_label(tr("RUN_SAVED_DETAIL").format({"attempt": int(_local_match.run_preview["attempt"]), "continues": int(_local_match.run_preview["continues"]), "difficulty": _local_match.run_preview["difficulty"]}))
			_saved_body_choice(_local_match.run_preview)
			_button(tr("RUN_NEW"), func() -> void: _show("new_confirm")).disabled = not can_start
		"missing":
			var mission: Button = _button(tr("MISSION_M01_TITLE"), func() -> void: _show("difficulty"))
			mission.name = "RecallNotice"
			mission.disabled = not can_start
		"awaiting_mission":
			var pending_mission: String = str(_local_match.run_preview.get("mission", ""))
			if pending_mission in [MissionState.M02_ID, MissionState.M03_ID, MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID, MissionState.M08_ID, MissionState.M09_ID, MissionState.M10_ID]:
				var next: Button = _button(tr("RUN_CONTINUE"), _start_campaign_resume)
				next.name = _saved_mission_button(pending_mission)
				next.disabled = not can_start
				_label(tr("RUN_SAVED_MISSION").format({"mission": _saved_mission_title(pending_mission)}))
				_label(tr("RUN_AWAITING_DETAIL").format({"continues": int(_local_match.run_preview["continues"]), "difficulty": _local_match.run_preview["difficulty"]}))
				_saved_body_choice(_local_match.run_preview)
			else:
				_label(tr("RUN_SAVED_MISSION").format({"mission": _saved_mission_title(LocalMatch.NEXT_MISSION)}))
				_label(tr("RUN_AWAITING_DETAIL").format({"continues": int(_local_match.run_preview["continues"]), "difficulty": _local_match.run_preview["difficulty"]}))
				_saved_body_choice(_local_match.run_preview, false)
				_label(tr("M10_NEXT_PENDING"))
			_button(tr("RUN_NEW"), func() -> void: _show("new_confirm")).disabled = not can_start
		"failed":
			_label(tr("RUN_FAILED"))
			_button(tr("RUN_NEW"), func() -> void: _show("new_confirm")).disabled = not can_start
		"abandoned":
			_label(tr("RUN_ABANDONED"))
			_button(tr("RUN_NEW"), func() -> void: _show("new_confirm")).disabled = not can_start
		"incompatible", "corrupt":
			_label(tr("RUN_UNREADABLE"))
			_button(tr("RUN_NEW"), func() -> void: _show("new_confirm")).disabled = not can_start
		_:
			_label(tr("RUN_CHECKING" if status == "loading" else "RUN_PREVIEW_UNAVAILABLE"))
			if status == "unavailable":
				_button(tr("RUN_RETRY_PREVIEW"), func() -> void:
					_local_match.run_preview.clear()
					_show("single")
				)
	if status != "awaiting_mission" or _local_match.run_preview.get("mission") != LocalMatch.NEXT_MISSION:
		var description: String = "MENU_M01_DESCRIPTION"
		if status in ["ready", "awaiting_mission"]:
			if _local_match.run_preview.get("mission") == MissionState.M02_ID:
				description = "RUN_M02_DESCRIPTION"
			elif _local_match.run_preview.get("mission") == MissionState.M03_ID:
				description = "M03_RUN_DESCRIPTION"
			elif _local_match.run_preview.get("mission") == MissionState.M04_ID:
				description = "M04_RUN_DESCRIPTION"
			elif _local_match.run_preview.get("mission") == MissionState.M05_ID:
				description = "M05_RUN_DESCRIPTION"
			elif _local_match.run_preview.get("mission") == MissionState.M06_ID:
				description = "M06_RUN_DESCRIPTION"
			elif _local_match.run_preview.get("mission") == MissionState.M07_ID:
				description = "M07_RUN_DESCRIPTION"
			elif _local_match.run_preview.get("mission") == MissionState.M08_ID:
				description = "M08_RUN_DESCRIPTION"
			elif _local_match.run_preview.get("mission") == MissionState.M10_ID:
				description = "M10_RUN_DESCRIPTION"
			elif _local_match.run_preview.get("mission") == MissionState.M09_ID:
				description = "M09_RUN_DESCRIPTION"
		_label(tr(description))
	_button(tr("MENU_PRACTICE_DEVELOPMENT"), func() -> void: _show("practice"))
	_button("Back", func() -> void: _show("main"))

func _page_practice() -> void:
	var can_start: bool = _local_match.state in [LocalMatch.State.IDLE, LocalMatch.State.FAILED]
	_button(tr("STORY_REPLAY"), _replay_opening)
	_label(tr("M05_MENU_DEVELOPMENT"))
	var selector: OptionButton = OptionButton.new()
	selector.name = "DevelopmentMission"
	selector.custom_minimum_size.y = 46.0
	for key: String in ["MISSION_M02_GRAYBOX", "M03_PROTOTYPE_TITLE", "M04_PROTOTYPE_TITLE", "M05_PROTOTYPE_TITLE", "M06_PROTOTYPE_TITLE", "M07_PROTOTYPE_TITLE", "M08_PROTOTYPE_TITLE", "M09_PROTOTYPE_TITLE", "M10_PROTOTYPE_TITLE"]:
		selector.add_item(tr(key))
	selector.select(5)
	_root.add_child(selector)
	var launch: Button = _button(tr("M05_LAUNCH_PROTOTYPE"), func() -> void:
		var ids: Array[String] = [MissionState.M02_ID, MissionState.M03_ID, MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID, MissionState.M08_ID, MissionState.M09_ID, MissionState.M10_ID]
		_start_development(ids[selector.selected]))
	launch.name = "LaunchDevelopmentMission"
	launch.disabled = not can_start
	_label(tr("MENU_PRACTICE"))
	_button("Calibration challenge", func() -> void: _launch("solo", LOOPBACK))
	_button("Arena against bots", func() -> void: _launch("join", LOOPBACK))
	_button("Watch the bots", func() -> void: _launch("spectate", LOOPBACK))
	_label(tr("MENU_PRACTICE_SERVER"))
	_button("Back", func() -> void: _show("single"))

func _on_run_preview_changed() -> void:
	_try_onward()
	if _page == "single" and not _launch_pending:
		_show("single")

func _saved_mission_title(mission_id: String) -> String:
	match mission_id:
		MissionState.M02_ID:
			return tr("MISSION_M02_TITLE")
		MissionState.M03_ID:
			return tr("MISSION_M03_TITLE")
		MissionState.M04_ID:
			return tr("MISSION_M04_TITLE")
		MissionState.M05_ID:
			return tr("MISSION_M05_TITLE")
		MissionState.M06_ID:
			return tr("MISSION_M06_TITLE")
		MissionState.M07_ID:
			return tr("MISSION_M07_TITLE")
		MissionState.M08_ID:
			return tr("MISSION_M08_TITLE")
		MissionState.M09_ID:
			return tr("MISSION_M09_TITLE")
		MissionState.M10_ID:
			return tr("MISSION_M10_TITLE")
		LocalMatch.NEXT_MISSION:
			return tr("M10_NEXT_TITLE")
	return tr("MISSION_M01_TITLE")

func _saved_mission_button(mission_id: String) -> String:
	match mission_id:
		MissionState.M02_ID:
			return "PersonsUnknownSaved"
		MissionState.M03_ID:
			return "ScheduledServiceSaved"
		MissionState.M04_ID:
			return "NoticeToVacateSaved"
		MissionState.M05_ID:
			return "NoForwardingAddressSaved"
		MissionState.M06_ID:
			return "PortOfEntrySaved"
		MissionState.M07_ID:
			return "DeclaredGoodsSaved"
		MissionState.M08_ID:
			return "CustodianOfRecordSaved"
		MissionState.M10_ID:
			return "CommonCarrierSaved"
		MissionState.M09_ID:
			return "PassengerManifestSaved"
	return "RecallNotice"

func _saved_body_choice(preview: Dictionary, can_choose: bool = true) -> void:
	if preview["body"] == null:
		if can_choose:
			_label(tr("RUN_BODY_UNBOUND").format({"body": PlayerBody.label(_settings.player_body())}))
			var choose: Button = _button(tr("RUN_CHOOSE_BODY"), func() -> void: _open_profile("single"))
			choose.name = "ChooseRunBody"
		else:
			_label(tr("RUN_BODY_PENDING"))
	else:
		_label(tr("RUN_BODY_BOUND").format({"body": PlayerBody.label(str(preview["body"]))}))

func _page_new_confirm() -> void:
	_label(tr("RUN_NEW_CONFIRM"))
	_button(tr("RUN_ARCHIVE_START"), func() -> void: _show("difficulty"))
	_button(tr("MENU_BACK"), func() -> void: _show("single"))

func _replay_opening() -> void:
	if is_instance_valid(_opening):
		return
	_opening = CampaignOpening.new()
	_opening.completed.connect(_finish_replay)
	add_child(_opening)

func _finish_replay() -> void:
	_opening.queue_free()
	_opening = null
	_show("practice")

func _page_difficulty() -> void:
	_label(tr("MISSION_M01_TITLE"))
	_label(tr("DIFFICULTY_CHOOSE"))
	for difficulty: String in ["standard", "assisted", "severe"]:
		var choice: Button = _button(tr("DIFFICULTY_" + difficulty.to_upper()), _start_campaign.bind(difficulty))
		choice.name = "Difficulty_" + difficulty
		_label(tr("DIFFICULTY_" + difficulty.to_upper() + "_DESCRIPTION"))
	_button(tr("MENU_BACK"), func() -> void: _show("single"))

func _start_campaign(difficulty: String = "standard") -> void:
	if _launch_pending:
		return
	_launch_pending = true
	_campaign_run_mode = "new"
	_show("launch")
	_local_match.start_mission(difficulty, "new")
	_on_local_state_changed()

## M02 is a development child: no difficulty page, run file or M01 carry.
func _start_development_m02() -> void:
	if _launch_pending:
		return
	_launch_pending = true
	_campaign_run_mode = ""
	_show("launch")
	_local_match.start_mission("standard", "", MissionState.M02_ID)
	_on_local_state_changed()

func _start_development_m03() -> void:
	if _launch_pending:
		return
	_launch_pending = true
	_campaign_run_mode = ""
	_show("launch")
	_local_match.start_mission("standard", "", MissionState.M03_ID)
	_on_local_state_changed()

func _start_development_m04() -> void:
	if _launch_pending:
		return
	_launch_pending = true
	_campaign_run_mode = ""
	_show("launch")
	_local_match.start_mission("standard", "", MissionState.M04_ID)
	_on_local_state_changed()

func _start_development(mission_id: String) -> void:
	if _launch_pending or mission_id not in [MissionState.M02_ID, MissionState.M03_ID, MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID, MissionState.M08_ID, MissionState.M09_ID, MissionState.M10_ID]:
		return
	_launch_pending = true
	_campaign_run_mode = ""
	_show("launch")
	_local_match.start_mission("standard", "", mission_id)
	_on_local_state_changed()

func _start_campaign_resume() -> void:
	var preview: Dictionary = _local_match.run_preview
	if _launch_pending or preview.get("status") not in ["ready", "awaiting_mission"]:
		return
	var mission_id: String = str(preview.get("mission", ""))
	if mission_id not in [MissionState.ID, MissionState.M02_ID, MissionState.M03_ID, MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID, MissionState.M08_ID, MissionState.M09_ID, MissionState.M10_ID] or (preview["status"] == "awaiting_mission" and mission_id not in [MissionState.M02_ID, MissionState.M03_ID, MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID, MissionState.M08_ID, MissionState.M09_ID, MissionState.M10_ID]):
		return
	var difficulty: String = str(preview["difficulty"])
	_launch_pending = true
	_campaign_run_mode = "resume"
	_campaign_play_arrival = _arrival_for_preview(preview)
	_show("launch")
	_local_match.start_mission(difficulty, "resume", mission_id)
	_on_local_state_changed()

static func _arrival_for_preview(preview: Dictionary) -> bool:
	var mission_id: String = str(preview.get("mission", ""))
	return preview.get("status") == "awaiting_mission" \
		and mission_id in [MissionState.M02_ID, MissionState.M03_ID, MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID, MissionState.M08_ID, MissionState.M09_ID, MissionState.M10_ID] \
		and StoryScene.BEFORE_MISSION.has(mission_id)

func _page_launch() -> void:
	var title: String = _saved_mission_title(_local_match.mission)
	if _campaign_run_mode.is_empty():
		title = tr("M10_PROTOTYPE_TITLE") if _local_match.mission == MissionState.M10_ID else tr("M09_PROTOTYPE_TITLE") if _local_match.mission == MissionState.M09_ID else tr("M07_PROTOTYPE_TITLE") if _local_match.mission == MissionState.M07_ID else tr("M08_PROTOTYPE_TITLE") if _local_match.mission == MissionState.M08_ID else tr("M06_PROTOTYPE_TITLE") if _local_match.mission == MissionState.M06_ID else (tr("M05_PROTOTYPE_TITLE") if _local_match.mission == MissionState.M05_ID else tr("M04_PROTOTYPE_TITLE" if _local_match.mission == MissionState.M04_ID else ("M03_PROTOTYPE_TITLE" if _local_match.mission == MissionState.M03_ID else "MISSION_M02_GRAYBOX")))
	_label(title)
	var preparing: String = "M10_LOCAL_STARTING" if _local_match.mission == MissionState.M10_ID else "M09_LOCAL_STARTING" if _local_match.mission == MissionState.M09_ID else "M07_LOCAL_STARTING" if _local_match.mission == MissionState.M07_ID else "M08_LOCAL_STARTING" if _local_match.mission == MissionState.M08_ID else "M06_LOCAL_STARTING" if _local_match.mission == MissionState.M06_ID else ("M05_LOCAL_STARTING" if _local_match.mission == MissionState.M05_ID else "M04_LOCAL_STARTING" if _local_match.mission == MissionState.M04_ID else ("M03_LOCAL_STARTING" if _local_match.mission == MissionState.M03_ID else "LOCAL_SERVER_STARTING"))
	_label(tr("LOCAL_SERVER_STOPPING") if _local_match.state == LocalMatch.State.STOPPING else tr(preparing))
	_button(tr("MENU_CANCEL"), _cancel_campaign)

func _cancel_campaign() -> void:
	_launch_pending = false
	_local_match.stop()
	_show("single")

## Start Continue Run for an onward request as soon as the previous child has
## stopped and the preview names a playable saved mission. Anything else
## leaves the player on Single Player, which explains what is next.
func _try_onward() -> void:
	if not _onward_pending or _launch_pending:
		return
	if _local_match.state not in [LocalMatch.State.IDLE, LocalMatch.State.FAILED]:
		return
	var status: String = str(_local_match.run_preview.get("status", "loading"))
	if status == "loading":
		return
	_onward_pending = false
	# The Continue Run button's own checks decide whether the saved mission is
	# playable; an unbuilt destination stays on this page.
	_start_campaign_resume()

func _on_local_state_changed() -> void:
	_try_onward()
	if _launch_pending:
		if _local_match.state in [LocalMatch.State.IDLE, LocalMatch.State.FAILED]:
			_launch_pending = false
			_show("single")
		elif _local_match.state != LocalMatch.State.RUNNING:
			_show("launch")
	elif _page == "single":
		_show("single")

func _on_local_ready(address: String) -> void:
	if _launch_pending:
		_launch_pending = false
		_launch("campaign", address, _campaign_run_mode)

func _page_multi() -> void:
	_button(tr("HOST_CREATE"), func() -> void: _show("host"))
	_label("Host")
	_host_edit = LineEdit.new()
	_host_edit.name = "HostAddress"
	_host_edit.text = _local_host.url if _local_host.state == LocalHost.State.RUNNING else OS.get_environment("FRAGR_SERVER")
	if _host_edit.text.is_empty():
		_host_edit.text = _local_host.url if _local_host.state == LocalHost.State.RUNNING else LOOPBACK
	_host_edit.custom_minimum_size = Vector2(0.0, 36.0)
	_root.add_child(_host_edit)
	_button("Check host", _probe_host)
	_button(tr("HOST_USE_RUNNING"), func() -> void:
		_host_edit.text = _local_host.url if _local_host.state == LocalHost.State.RUNNING else LOOPBACK
		_probe_host()
	).name = "UseRunningServer"
	_match_line = _label("Checking the host.")
	_match_line.name = "MatchLine"
	_watch_button = _button("Watch", func() -> void: _launch("spectate", _host_address()))
	_join_button = _button("Join", func() -> void: _launch("join", _host_address()))
	_watch_button.name = "Watch"
	_join_button.name = "Join"
	_watch_button.disabled = true
	_join_button.disabled = true
	_label("The host chooses the arena and rules. You watch in this app, then join.")
	_button("Back", func() -> void: _show("main"))
	_probe_host()

func _on_host_state_changed() -> void:
	if _page == "host":
		_show("host")

func _host_option(label: String, name_text: String) -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	_root.add_child(row)
	var text: Label = Label.new()
	text.text = label
	text.custom_minimum_size.x = 210.0
	row.add_child(text)
	var option: OptionButton = OptionButton.new()
	option.name = name_text
	option.custom_minimum_size.y = 42.0
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option

func _page_host() -> void:
	if _local_host.state == LocalHost.State.RUNNING:
		var mode_text: String = tr("HOST_SABOTAGE") if _local_host.settings["mode"] == "sabotage" else tr("MODE_TDM")
		_label(tr("HOST_RUNNING") % mode_text)
		_label(_local_host.url)
		if _local_host.settings["lan"]:
			_label(tr("HOST_LAN_ADDRESS") % int(_local_host.settings["port"]))
		else:
			_label(tr("HOST_LOOPBACK_ONLY"))
		_button("Watch", func() -> void: _launch("spectate", _local_host.url)).name = "WatchHosted"
		_button("Join", func() -> void: _launch("join", _local_host.url)).name = "JoinHosted"
		_button(tr("HOST_STOP"), _local_host.stop).name = "StopServer"
		_button("Back", func() -> void: _show("multi"))
		return
	if _local_host.state in [LocalHost.State.STARTING, LocalHost.State.STOPPING]:
		_label(tr("HOST_STARTING" if _local_host.state == LocalHost.State.STARTING else "HOST_STOPPING"))
		if _local_host.state == LocalHost.State.STARTING:
			_button("Cancel", _local_host.stop)
		_button("Back", func() -> void: _show("multi"))
		return
	if not _local_host.error_key.is_empty():
		_label(tr(_local_host.error_key))
	_host_mode = _host_option(tr("HOST_MODE"), "HostMode")
	_host_mode.add_item(tr("MODE_TDM"))
	_host_mode.add_item(tr("HOST_SABOTAGE"))
	_host_mode.select(1 if _host_settings["mode"] == "sabotage" else 0)
	_host_map = _host_option(tr("HOST_MAP"), "HostMap")
	_rebuild_host_maps()
	_host_mode.item_selected.connect(func(_index: int) -> void: _rebuild_host_maps())
	var bots_row: HBoxContainer = HBoxContainer.new()
	_root.add_child(bots_row)
	var bots_label: Label = Label.new()
	bots_label.text = tr("HOST_BOTS")
	bots_label.custom_minimum_size.x = 210.0
	bots_row.add_child(bots_label)
	_host_bots = SpinBox.new()
	_host_bots.name = "HostBots"
	_host_bots.min_value = 0
	_host_bots.max_value = 10
	_host_bots.step = 1
	_host_bots.value = _host_settings["bots"]
	bots_row.add_child(_host_bots)
	_host_lan = CheckButton.new()
	_host_lan.name = "HostLAN"
	_host_lan.text = tr("HOST_ALLOW_LAN")
	_host_lan.button_pressed = _host_settings["lan"]
	_root.add_child(_host_lan)
	_host_port = SpinBox.new()
	_host_port.name = "HostPort"
	_host_port.prefix = tr("HOST_PORT") + " "
	_host_port.min_value = 1
	_host_port.max_value = 65535
	_host_port.step = 1
	_host_port.value = _host_settings["port"] if _host_settings["lan"] else 6767
	_host_port.editable = _host_lan.button_pressed
	_root.add_child(_host_port)
	_host_lan.toggled.connect(func(enabled: bool) -> void: _host_port.editable = enabled)
	_label(tr("HOST_FINITE_SEATS"))
	_button(tr("HOST_START"), _start_host).name = "StartServer"
	_button("Back", func() -> void: _show("multi"))

func _rebuild_host_maps() -> void:
	_host_map.clear()
	if _host_mode.selected == 1:
		_host_map.add_item("Sector 9", 4)
		return
	var names: Array[String] = ["Arena Duel", "Compliance Yard", "Directive 17", "Sector 9", "Reclamation Gulch", "Tripoint Works"]
	for index: int in names.size():
		_host_map.add_item(names[index], index + 1)
	var selected: int = int(_host_settings["map_id"]) - 1
	_host_map.select(clampi(selected, 0, names.size() - 1))

func _start_host() -> void:
	_host_settings = {"mode": "sabotage" if _host_mode.selected == 1 else "tdm",
		"map_id": _host_map.get_selected_id(), "bots": int(_host_bots.value),
		"lan": _host_lan.button_pressed, "port": int(_host_port.value) if _host_lan.button_pressed else 0}
	_local_host.start_host(_host_settings)

func _probe_host() -> void:
	if _watch_button != null:
		_watch_button.disabled = true
	if _join_button != null:
		_join_button.disabled = true
	if _match_line != null:
		_match_line.text = "Checking the host."
	if _probe == null:
		_probe = HTTPRequest.new()
		_probe.name = "StatusProbe"
		_probe.timeout = 2.0
		_probe.body_size_limit = 4096
		add_child(_probe)
		_probe.request_completed.connect(_on_status_completed)
	_probe.cancel_request()
	var endpoint: Dictionary = ServerEndpoint.parse(_host_address())
	if endpoint.is_empty():
		_match_line.text = tr("HOST_INVALID_ADDRESS")
		return
	var err: Error = _probe.request(endpoint["status_url"])
	if err != OK and _match_line != null:
		_match_line.text = "This host did not answer."

func _on_status_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _page != "multi":
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_apply_status(null)
		return
	_apply_status(JSON.parse_string(body.get_string_from_utf8()))

## A readable schema 2 match line enables Watch and Join. Anything else does not.
func _apply_status(parsed: Variant) -> void:
	if _match_line == null or _watch_button == null or _join_button == null:
		return
	_watch_button.disabled = true
	_join_button.disabled = true
	if typeof(parsed) != TYPE_DICTIONARY:
		_match_line.text = "This host did not answer."
		return
	var data: Dictionary = parsed
	if not EquipmentState.integer(data.get("schema_version"), 2) or data["schema_version"] != 2:
		_match_line.text = "This host did not return a match line."
		return
	if not data.get("kind") is String or not data.get("map") is String \
		or not EquipmentState.integer(data.get("fighters"), 4294967295) \
		or not EquipmentState.integer(data.get("connections"), 4294967295):
		_match_line.text = "This host did not return a match line."
		return
	var kind: String = str(data.get("kind", ""))
	var map_name: String = str(data.get("map", ""))
	var fighters: int = int(data.get("fighters", -1))
	var connections: int = int(data.get("connections", -1))
	if (kind != "arena" and kind != "campaign") or map_name.is_empty() or fighters < 0 or connections < 0:
		_match_line.text = "This host did not say whether this is an arena or a mission."
		return
	var kind_line: String = "Mission" if kind == "campaign" else "Arena"
	_match_line.text = "%s. %s. %d fighters. %d connections." % [map_name, kind_line, fighters, connections]
	if kind == "arena" and data.has("mode"):
		var rules: Dictionary = MatchRules.parse({"mode": data.get("mode", "ffa"), "mutators": data.get("mutators", [])})
		if rules.is_empty():
			_match_line.text = tr("HOST_INVALID_RULES")
			return
		_match_line.text += " " + MatchRules.chip_text(rules)
	_watch_button.disabled = false
	_join_button.disabled = false

func _page_profile() -> void:
	_label("CALLSIGN")
	_name_edit = LineEdit.new()
	_name_edit.name = "Callsign"
	_name_edit.text = _settings.player_name()
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(0, 58)
	_name_edit.add_theme_font_size_override("font_size", 28)
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_name_edit)
	_label("RETICLE COLOUR")
	var colour: OptionButton = OptionButton.new()
	colour.name = "ReticleColour"
	colour.custom_minimum_size.y = 50
	colour.add_theme_font_size_override("font_size", 24)
	var choices: Array[String] = ["bone", "amber", "cyan"]
	for choice in choices:
		colour.add_item(choice.to_upper())
	colour.select(choices.find(str(_settings.get_value("profile", "reticle_colour"))))
	colour.item_selected.connect(func(index: int) -> void:
		_settings.set_value("profile", "reticle_colour", choices[index])
	)
	_root.add_child(colour)
	_label("BODY")
	var body_row: HBoxContainer = HBoxContainer.new()
	body_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body_row.add_theme_constant_override("separation", 18)
	var body: OptionButton = OptionButton.new()
	body.name = "Body"
	body.custom_minimum_size = Vector2(300, 50)
	body.add_theme_font_size_override("font_size", 24)
	for kind: String in PlayerBody.KINDS:
		body.add_item(PlayerBody.label(kind))
	body.select(PlayerBody.KINDS.find(_settings.player_body()))
	var preview: TextureRect = TextureRect.new()
	preview.name = "BodyPreview"
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	preview.custom_minimum_size = BODY_PREVIEW.size
	_preview_body(preview, _settings.player_body())
	body.item_selected.connect(func(index: int) -> void:
		_settings.set_value("profile", "body", PlayerBody.KINDS[index])
		_preview_body(preview, PlayerBody.KINDS[index])
	)
	body_row.add_child(body)
	body_row.add_child(preview)
	_root.add_child(body_row)
	_label(tr("MENU_BODY_PREFERENCE"))
	var bob: CheckButton = CheckButton.new()
	bob.name = "WeaponBob"
	bob.text = "WEAPON BOB"
	bob.add_theme_font_size_override("font_size", 24)
	bob.button_pressed = bool(_settings.get_value("gameplay", "head_bob"))
	bob.toggled.connect(func(on: bool) -> void: _settings.set_value("gameplay", "head_bob", on))
	_root.add_child(bob)
	_button("Save and back", _save_profile)
	_button("Cancel", func() -> void:
		_settings.load_from_disk()
		_show(_profile_return)
	)

func _open_profile(return_page: String) -> void:
	_profile_return = return_page
	_show("profile")

## The standing figure inside the first idle cell of a baked body strip.
const BODY_PREVIEW: Rect2 = Rect2(40, 22, 80, 114)

func _preview_body(preview: TextureRect, kind: String) -> void:
	var strip: Texture2D = load(PlayerBody.strip_path(kind))
	if strip == null:
		preview.texture = null
		return
	var cell: AtlasTexture = AtlasTexture.new()
	cell.atlas = strip
	cell.region = BODY_PREVIEW
	preview.texture = cell

func _save_profile() -> void:
	_settings.set_value("profile", "name", _name_edit.text)
	var result: Error = _settings.save_to_disk()
	if result != OK:
		_status.text = "Could not save callsign. Check available disk space."
		return
	_show(_profile_return)

func _page_settings() -> void:
	var panel: SettingsPanel = SettingsPanel.new()
	panel.name = "SettingsPanel"
	panel.preferences = _settings
	panel.closed.connect(func() -> void: _show("main"))
	_root.add_child(panel)

func _host_address() -> String:
	if _host_edit != null and not _host_edit.text.strip_edges().is_empty():
		return _host_edit.text.strip_edges()
	return LOOPBACK

func _unhandled_input(event: InputEvent) -> void:
	if _console != null and _console.is_open():
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and _page != "main":
		_settings.load_from_disk()
		if _launch_pending:
			_cancel_campaign()
		else:
			_show(_profile_return if _page == "profile" else ("single" if _page in ["difficulty", "new_confirm", "practice"] else "main"))
		get_viewport().set_input_as_handled()

func _launch(mode: String, host: String, run_mode: String = "") -> void:
	var endpoint: Dictionary = ServerEndpoint.parse(host)
	if endpoint.is_empty():
		_status.text = tr("HOST_INVALID_ADDRESS")
		return
	var boot: Dictionary = {
		"mode": mode,
		"host": endpoint["game_url"],
	}
	if mode == "campaign":
		boot["run_mode"] = run_mode
		boot["play_arrival"] = run_mode == "resume" and _campaign_play_arrival
	get_tree().set_meta("fragr_boot", boot)
	var err: Error = get_tree().change_scene_to_file(ARENA_SCENE)
	if err != OK:
		get_tree().remove_meta("fragr_boot")
		if mode == "campaign":
			_local_match.stop()
		push_error("boot_menu: failed to load arena scene: " + str(err))
		if _status != null:
			_status.text = "Failed to load arena (" + str(err) + ")"
