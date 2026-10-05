extends Node

@onready var net_client = $NetClient
@onready var hud = $HUD
@onready var arena = $Arena
@onready var camera = $SpectatorCamera
@onready var frag_sound = $AudioPlayers/FragSound
@onready var round_start_sound = $AudioPlayers/RoundStartSound
@onready var round_end_sound = $AudioPlayers/RoundEndSound

var players = {}
var pickups = {}
var jammer_dish_node = null
var arena_flags: ArenaFlags = null
## Sabotage sites and charge; empty outside a Sabotage server.
var arena_sabotage: ArenaSabotage = null
var sabotage_layout: Dictionary = {}
## The joined fighter's side, kept through a death so a fallen fighter still
## watches its own living teammates.
var _sabotage_team: String = ""
## The longest charge clock seen in this plant, for the HUD's draining timer.
var _sabotage_charge_ticks: int = 700
var _sabotage_watching_mates: bool = false
## A side-swap notice waiting for its round to open.
var _sabotage_swap_notice: String = ""
var traveling_shots: TravelingShots = null
var jammer_audio: JammerAudio = null
var notary_audio: NotaryAudio = null
var marksman_audio: RangedSweeperAudio = null
# tip_capture latch: keep forced live dish through nods-phase Snapshot nulls.
var tip_force_jammer_dish = false
const JammerDishBuilderScript = preload("res://scripts/jammer_dish.gd")
const StanceChipScript = preload("res://scripts/stance_chip.gd")
const NameplateLayoutScript = preload("res://scripts/nameplate_layout.gd")
var pickup_scene = preload("res://scenes/weapon_pickup.tscn")
var player_scene = preload("res://scenes/player.tscn")
var arena_duel_scene = preload("res://scenes/arena.tscn")
var compliance_yard_scene = preload("res://scenes/arena_compliance_yard.tscn")
var current_map_id := 1

var is_human_player = false
var radio = null
var local_fp_pawn_id = ""
var local_hp_seen = -1
var fp_spawn_flashed = false
# Mid-join Ended podium shown once per Ended phase.
var ended_podium_shown = false
var action_state = {
	"forward": false,
	"back": false,
	"left": false,
	"right": false,
	"turn_left": false,
	"turn_right": false,
	"fire": false,
	"jump": false,
	"interact": false,
	"throw_grenade": false,
	"place_mine": false,
	"weapon_swap": null,
	"yaw": 0.0,
	"pitch": 0.0,
	"seq": 0
}

const SPEAK_LINES = [
	"scrap on",
	"contested frequency",
	"deny the denial",
	"shall not be infringed",
]
var speak_line_index = 0
var pending_weapon_swap = null
var pending_jump: bool = false
var pending_interact: bool = false
var interact_held: bool = false
var pending_throw: bool = false
var throw_armed: bool = true
var pending_place: bool = false
var place_armed: bool = true
var mission_hud: MissionHud
var m02_ward: M02Ward
var m03_yard: M03Yard
var m04_town: M04Town
var m05_town: M05Town
var m06_port: M06Port
var m08_archive: M08Archive
var m07_town: M07Town
var m09_berth: M09Berth
var departure_review: DepartureReview
var _continue_armed: bool = false
var _continue_attempt_sent: int = -1
## A completed local run can go straight on to its saved next mission. The
## boot menu reads LocalMatch.ONWARD_META once and opens Continue Run.
var _onward_released: bool = false
var _onward_armed: bool = false
var _presented_attempt: int = 0
var _retry_snapshot_tick: int = -1

var arena_cover: ArenaCover = null
var current_map_info: Dictionary = {}
var latest_snapshot: Dictionary = {}
var console: FragrConsole = null
var pause_menu: PauseMenu = null
var settings: FragrSettings
var records: PlayerRecords
var _record_save_warning: bool = false
var role_transition: bool = false
var shot_effects: ShotEffects = null
var incoming_feedback: IncomingCombatFeedback = null
var grenade_effects: GrenadeEffects
var auditor_channels: AuditorChannels
var last_shot_tick: int = -1
var mouse_capture: MouseCapture
var local_match: LocalMatch
var _leaving: bool = false
var opening: ScenePlayer
## The between-level scene played once the server reports a departure.
var interlude: ScenePlayer
var campaign_results: CampaignResults
var _results_played: Dictionary[String, bool] = {}
var _interludes_played: Dictionary[String, bool] = {}
var _opening_finished: bool = false
var _opening_release: bool = false
var _readiness_attempt_sent: int = 0
var _awaiting_map: bool = false
var _world_load_generation: int = 0
var _world_reveal_pending: bool = false
var input_device: InputDevice
var local_prediction: LocalPrediction = LocalPrediction.new()
var _adopt_local_spawn_snapshot: bool = false
var _retired_environments: Array[Environment] = []

## Feedback for the fighter this screen belongs to: what they picked up and
## an empty trigger. Neither is positional; nobody else hears them.
const PICKUP_SOUND_PATHS: Dictionary[String, String] = {
	"weapon": "res://assets/audio/pickup/weapon.wav",
	"ammo": "res://assets/audio/pickup/ammo.wav",
	"cells": "res://assets/audio/pickup/cells.wav",
	"health": "res://assets/audio/pickup/health.wav",
	"armor": "res://assets/audio/pickup/armor.wav",
}
const DRY_FIRE_SOUND_PATH: String = "res://assets/audio/dry_fire.wav"
var pickup_streams: Dictionary[String, AudioStream] = {}
var pickup_sound: AudioStreamPlayer = null
var dry_fire_sound: AudioStreamPlayer = null
var pickup_cue_count: int = 0
var dry_fire_cue_count: int = 0
var scope_sound: AudioStreamPlayer = null
var scope_cue_count: int = 0
var _dry_fire_seen: int = -1

const CRAWLER_SOUND_PATH: String = "res://assets/audio/crawler_scrabble.wav"
const CRAWLER_SOUND_VOICES: int = 4
const CRAWLER_CUE_DISTANCE: float = 24.0
var crawler_sound_stream: AudioStream = null
var crawler_sound_players: Array[AudioStreamPlayer3D] = []
var crawler_sound_next: int = 0
var crawler_scrabble_count: int = 0
var crawler_last_position: Vector3 = Vector3.INF
var crawler_last_ms: int = -1000

func _ready():
	_begin_world_load()
	mission_hud = MissionHud.new()
	hud.add_child(mission_hud)
	mission_hud.notice_requested.connect(func(text: String) -> void:
		hud.combat_feed.push(text, MenuTheme.BONE))
	mouse_capture = MouseCapture.new()
	add_child(mouse_capture)
	input_device = InputDevice.new()
	input_device.name = "InputDevice"
	add_child(input_device)
	shot_effects = ShotEffects.new()
	incoming_feedback = IncomingCombatFeedback.new()
	incoming_feedback.name = "IncomingCombatFeedback"
	add_child(incoming_feedback)
	incoming_feedback.setup(hud)
	shot_effects.name = "ShotEffects"
	add_child(shot_effects)
	grenade_effects = GrenadeEffects.new()
	grenade_effects.name = "GrenadeEffects"
	grenade_effects.thrown.connect(func(owner_id: String) -> void:
		if is_human_player and owner_id == str(net_client.player_id):
			hud.show_grenade_throw())
	grenade_effects.placed.connect(func(owner_id: String) -> void:
		if is_human_player and owner_id == str(net_client.player_id):
			hud.show_mine_place())
	add_child(grenade_effects)
	auditor_channels = AuditorChannels.new()
	auditor_channels.name = "AuditorChannels"
	auditor_channels.pawns = players
	add_child(auditor_channels)
	jammer_audio = JammerAudio.new()
	jammer_audio.name = "JammerAudio"
	add_child(jammer_audio)
	marksman_audio = RangedSweeperAudio.new()
	marksman_audio.name = "MarksmanAudio"
	add_child(marksman_audio)
	notary_audio = NotaryAudio.new()
	notary_audio.name = "NotaryAudio"
	notary_audio.notice_requested.connect(func(text: String) -> void:
		hud.combat_feed.push(text, MenuTheme.BONE))
	add_child(notary_audio)
	if settings == null:
		settings = FragrSettings.for_tree(get_tree())
	settings.load_from_disk()
	records = PlayerRecords.for_tree(get_tree())
	settings.changed.connect(_apply_preferences)
	get_viewport().size_changed.connect(_apply_render_preferences)
	_apply_preferences()
	net_client.snapshot_received.connect(_on_snapshot_received)
	net_client.loadout_received.connect(_on_loadout_received)
	net_client.record_received.connect(_on_record_received)
	net_client.mission_received.connect(_on_mission_received)
	net_client.map_info_received.connect(_on_map_info)
	net_client.event_received.connect(_on_event_received)
	net_client.ack_received.connect(_on_ack_received)
	net_client.connected_to_server.connect(_on_connected)
	net_client.session_resumed.connect(_on_session_resumed)
	net_client.disconnected_from_server.connect(_on_disconnected)
	net_client.server_error.connect(_on_server_error)
	
	_load_audio_streams()
	
	var boot = _resolve_boot()
	if boot.get("mode") == "campaign":
		local_match = LocalMatch.for_tree(get_tree())
		_opening_finished = boot.get("run_mode") == "resume" and not bool(boot.get("play_arrival", false))
		if local_match.state != LocalMatch.State.RUNNING or local_match.url != boot.get("host"):
			_on_local_failure("LOCAL_SERVER_STOPPED")
			return
		local_match.failed.connect(_on_local_failure)
	var role = str(boot.get("role", "spectator"))
	var player_name = str(boot.get("name", "Spectator"))
	is_human_player = role == "human"
	
	if boot.has("host") and str(boot["host"]) != "":
		net_client.set_server_host(str(boot["host"]))
	
	_awaiting_map = true
	net_client.requested_body = settings.player_body()
	net_client.connect_to_server(role, player_name)
	hud.set_mode(str(boot.get("hud_mode", "SPECTATING")))
	_setup_radio()
	_setup_frontend()
	if pause_menu != null and str(boot.get("mode", "")) == "campaign":
		pause_menu.local_campaign = true

	_apply_arena_sky()

	# Cover is built from what the server sends, never from a second copy in
	# the scene. See arena_cover.gd for why that matters.
	arena_cover = ArenaCover.new()
	m03_yard = M03Yard.new()
	m03_yard.name = "M03Yard"
	add_child(m03_yard)
	m04_town = M04Town.new()
	m04_town.name = "M04Town"
	add_child(m04_town)
	m05_town = M05Town.new()
	m05_town.name = "M05Town"
	add_child(m05_town)
	m06_port = M06Port.new()
	m06_port.name = "M06Port"
	add_child(m06_port)
	m08_archive = M08Archive.new()
	m08_archive.name = "M08Archive"
	add_child(m08_archive)
	m07_town = M07Town.new()
	m07_town.name = "M07Town"
	m07_town.notice_requested.connect(func(text: String) -> void:
		hud.combat_feed.push(text, MenuTheme.BONE))
	add_child(m07_town)
	m09_berth = M09Berth.new()
	m09_berth.name = "M09Berth"
	add_child(m09_berth)
	var arena_root: Node = get_node_or_null("Arena")
	if arena_root != null:
		arena_root.add_child(arena_cover)
		m02_ward = M02Ward.new()
		m02_ward.pause_menu = pause_menu
		arena_root.add_child(m02_ward)
		arena_flags = ArenaFlags.new()
		arena_flags.name = "ArenaFlags"
		arena_root.add_child(arena_flags)
		arena_sabotage = ArenaSabotage.new()
		arena_sabotage.name = "ArenaSabotage"
		arena_root.add_child(arena_sabotage)
		traveling_shots = TravelingShots.new()
		traveling_shots.name = "TravelingShots"
		arena_root.add_child(traveling_shots)
	else:
		add_child(arena_cover)
		m02_ward = M02Ward.new()
		m02_ward.pause_menu = pause_menu
		add_child(m02_ward)
		arena_flags = ArenaFlags.new()
		arena_flags.name = "ArenaFlags"
		add_child(arena_flags)
		arena_sabotage = ArenaSabotage.new()
		arena_sabotage.name = "ArenaSabotage"
		add_child(arena_sabotage)
		traveling_shots = TravelingShots.new()
		traveling_shots.name = "TravelingShots"
		add_child(traveling_shots)

## Replace whatever the arena scene shipped with the environment in
## arena_sky.gd, so both arenas get the same sky from one place.
##
## It edits the existing WorldEnvironment rather than adding one. A second
## WorldEnvironment in the same viewport is not an error in Godot, it is
## silently ignored, which is the worst kind: the node is there, the values
## look right, and the sky stays black.
func _apply_arena_sky(map_name: String = "") -> void:
	var world: WorldEnvironment = _find_world_environment(self)
	if world == null:
		push_warning("game_manager: no WorldEnvironment found; sky left as authored")
		return
	var previous: Environment = world.environment
	world.environment = ArenaSky.build_environment(map_name)
	# The Compatibility renderer queues newly created skies for its next draw.
	# Keep replaced skies alive until that queue has been consumed.
	if previous != null and DisplayServer.get_name() != "headless":
		_retired_environments.append(previous)
		if not RenderingServer.frame_post_draw.is_connected(_release_retired_environments):
			RenderingServer.frame_post_draw.connect(_release_retired_environments, CONNECT_ONE_SHOT)
	RenderQuality.apply_environment(world.environment, settings)
	ArenaSky.apply_scene_lights(get_node_or_null("Arena/Layout"), map_name)
	ArenaSky.apply_view_fill(get_node_or_null("SpectatorCamera/Camera3D") as Camera3D, map_name)
	RenderQuality.apply_practicals(self, settings)


static func _find_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child in node.get_children():
		var found: WorldEnvironment = _find_world_environment(child)
		if found != null:
			return found
	return null

func _release_retired_environments() -> void:
	_retired_environments.clear()


func _on_map_info(info: Dictionary) -> void:
	if not current_map_info.is_empty() and info.get("map_id") != current_map_info.get("map_id"):
		_begin_world_load()
	if grenade_effects != null:
		grenade_effects.reset()
	if auditor_channels != null:
		auditor_channels.reset()
	pending_throw = false
	throw_armed = false
	pending_place = false
	place_armed = false
	_reset_crawler_cues()
	if jammer_audio != null:
		jammer_audio.reset()
	if marksman_audio != null:
		marksman_audio.reset()
	local_prediction.configure_map(info)
	_clear_predicted_pawn()
	for pawn: Node in players.values():
		if is_instance_valid(pawn) and pawn.has_method("reset_remote_presentation"):
			pawn.reset_remote_presentation()
	_adopt_local_spawn_snapshot = is_human_player
	var mission: Variant = info.get("mission")
	var m02: bool = info.get("m02_objectives") != null
	var m03: bool = info.get("m03") is Dictionary
	var m04: bool = info.get("m04") is Dictionary
	var m05: bool = info.get("m05") is Dictionary
	var m06: bool = info.get("m06") is Dictionary
	var m08: bool = info.get("m08") is Dictionary
	var m07: bool = info.get("m07") is Dictionary
	var m09: bool = info.get("m09") is Dictionary
	if local_match != null:
		var expected_m02: bool = local_match.mission == MissionState.M02_ID
		var expected_m03: bool = local_match.mission == MissionState.M03_ID
		var expected_m04: bool = local_match.mission == MissionState.M04_ID
		var expected_m05: bool = local_match.mission == MissionState.M05_ID
		var expected_m06: bool = local_match.mission == MissionState.M06_ID
		var expected_m07: bool = local_match.mission == MissionState.M07_ID
		var expected_m08: bool = local_match.mission == MissionState.M08_ID
		var expected_m09: bool = local_match.mission == MissionState.M09_ID
		if m02 != expected_m02 or m03 != expected_m03 or m04 != expected_m04 or m05 != expected_m05 or m06 != expected_m06 or m07 != expected_m07 or m08 != expected_m08 or m09 != expected_m09 or (not m02 and not m03 and not m04 and not m05 and not m06 and not m07 and not m08 and not m09 and (not mission is Dictionary or mission.get("id") != MissionState.ID)):
			_on_local_failure("LOCAL_SERVER_INVALID_READY")
			return
	last_shot_tick = -1
	if shot_effects != null:
		shot_effects.clear()
	current_map_info = info.duplicate(true)
	if incoming_feedback != null:
		incoming_feedback.configure_map(info)
	# The rule set arrives with the map; a campaign map has none.
	if hud and hud.has_method("set_match_rules"):
		hud.set_match_rules(MatchRules.parse(info.get("rules")))
	var layout: Variant = info.get("sabotage")
	sabotage_layout = layout.duplicate(true) if layout is Dictionary else {}
	if arena_sabotage != null:
		arena_sabotage.set_layout(sabotage_layout)
	if camera:
		camera.assist_solids = info.get("solids", []) if info.get("solids") is Array else []
	_awaiting_map = false
	if mission is Dictionary:
		if is_human_player and not _opening_finished and not is_instance_valid(opening):
			opening = CampaignOpening.new()
			opening.completed.connect(_on_opening_completed)
			add_child(opening)
	elif m03 or m04 or m05 or m06 or m07 or m08 or m09:
		if is_human_player and not _opening_finished and not is_instance_valid(opening):
			var scene_id: String = MissionState.M09_ID if m09 else MissionState.M07_ID if m07 else MissionState.M08_ID if m08 else (MissionState.M06_ID if m06 else (MissionState.M05_ID if m05 else (MissionState.M04_ID if m04 else MissionState.M03_ID)))
			opening = ScenePlayer.new(StoryScene.load_scene(StoryScene.BEFORE_MISSION[scene_id]))
			opening.completed.connect(_on_opening_completed)
			add_child(opening)
	elif m02:
		# The graybox has no story page yet. Readiness follows the first state.
		_opening_finished = true
	elif is_human_player:
		show_loading_card()
	if pause_menu != null:
		pause_menu.development_mission = (m02 or m03 or m04 or m05 or m06 or m07 or m08 or m09) and local_match != null and not local_match.has_durable_run()
	if arena_cover != null:
		arena_cover.apply_map_info(info)
		arena_cover.apply_m05({})
	# The venue decides the sky, and the venue is only known once the server
	# has said which one this is.
	_apply_arena_sky(str(info.get("map_name", "")))
	if m02_ward != null:
		m02_ward.configure_map(info)
	if m03_yard != null:
		m03_yard.configure_map(info)
	if m04_town != null:
		m04_town.configure_map(info)
	if m05_town != null:
		m05_town.configure_map(info)
	if m06_port != null:
		m06_port.configure_map(info)
	if m08_archive != null:
		m08_archive.configure_map(info)
	if m07_town != null:
		m07_town.configure_map(info)
	if m09_berth != null:
		m09_berth.configure_map(info)
	# Town fixtures are created after the venue preferences were applied.
	if settings != null:
		RenderQuality.apply_practicals(self, settings)
	NotaryAnimation.configure_map(info)
	if notary_audio != null:
		notary_audio.configure_map(info)
	# The story's opaque cover takes over without exposing an unfinished world.
	if is_instance_valid(opening):
		var loading: LoadingCard = get_node_or_null("LoadingCard") as LoadingCard
		if loading != null and loading.waiting_for_world:
			loading.finish_loading(false)

## The console, the pause menu and the loading card. Built here rather than in
## the scene because they are the same three things whatever the match is.
func _setup_frontend() -> void:
	console = FragrConsole.new()
	console.preferences = settings
	console.name = "FragrConsole"
	add_child(console)
	var frame_counter: PerformanceOverlay = PerformanceOverlay.new()
	frame_counter.name = "PerformanceOverlay"
	frame_counter.preferences = settings
	add_child(frame_counter)

	pause_menu = PauseMenu.new()
	pause_menu.preferences = settings
	pause_menu.name = "PauseMenu"
	pause_menu.leave_requested.connect(_on_leave_requested)
	add_child(pause_menu)

func _apply_preferences() -> void:
	settings.apply()
	camera.apply_preferences(settings)
	hud.apply_preferences(settings)
	_apply_render_preferences()

func _apply_render_preferences() -> void:
	var world: WorldEnvironment = _find_world_environment(self)
	RenderQuality.apply(get_viewport(), settings, world.environment if world != null else null)
	RenderQuality.apply_practicals(self, settings)
	RenderQuality.apply_dither(self, get_viewport(), settings)

func controls_blocked() -> bool:
	var loading: LoadingCard = get_node_or_null("LoadingCard") as LoadingCard
	if loading != null and loading.visible:
		return true
	if is_instance_valid(departure_review):
		return true
	return role_transition or _mission_controls_blocked() or (mission_hud != null and mission_hud.state.get("phase") == "departed") or (mouse_capture != null and not mouse_capture.gameplay_input_allowed()) or (console != null and console.is_open()) or (pause_menu != null and pause_menu.is_open())

func _mission_controls_blocked() -> bool:
	if not is_human_player:
		return false
	if _awaiting_map or _opening_release or _retry_snapshot_tick >= 0 or is_instance_valid(opening) or is_instance_valid(interlude) or is_instance_valid(campaign_results):
		return true
	if not _mission_map():
		return false
	if net_client.mission.is_empty():
		return true
	var state: Dictionary = net_client.mission["state"]
	if state.get("run") is Dictionary and state["run"]["status"] != "playing":
		return true
	if state["phase"] == "briefing":
		return true
	for member: Dictionary in state["party"]:
		if member["id"] == net_client.player_id:
			return not member["ready"]
	return true

## Mission maps carry M01 geometry or the M02 objective marker.
func _mission_map() -> bool:
	return current_map_info.get("mission") is Dictionary or current_map_info.get("m02_objectives") != null or current_map_info.get("m03") is Dictionary or current_map_info.get("m04") is Dictionary or current_map_info.get("m05") is Dictionary or current_map_info.get("m06") is Dictionary or current_map_info.get("m07") is Dictionary or current_map_info.get("m08") is Dictionary or current_map_info.get("m09") is Dictionary

func _on_opening_completed() -> void:
	_opening_finished = true
	_opening_release = true
	opening.queue_free()
	opening = null
	pending_jump = false
	pending_throw = false
	throw_armed = false
	pending_place = false
	place_armed = false
	pending_interact = false
	interact_held = false
	pending_weapon_swap = null

func _opening_input_released() -> bool:
	for action: String in ["ui_accept", "ui_cancel", "fire", "jump", "interact", "throw_grenade", "place_mine", "move_forward", "move_back", "move_left", "move_right"]:
		if Input.is_action_pressed(action):
			return false
	return true

func _submit_mission_readiness() -> void:
	if not is_human_player or not _opening_finished or _opening_release or net_client.mission.is_empty():
		return
	var attempt: int = int(net_client.mission["state"]["attempt"])
	if attempt != _readiness_attempt_sent and net_client.send_mission_ready():
		_readiness_attempt_sent = attempt

## The controls card. Shown on every join, including pressing J mid-match,
## because a player who joined from the booth never saw the boot one.
func show_loading_card(wait_for_world: bool = false) -> void:
	if get_node_or_null("LoadingCard") != null:
		if wait_for_world:
			(get_node("LoadingCard") as LoadingCard).begin_loading()
		return
	var card: LoadingCard = LoadingCard.new()
	card.name = "LoadingCard"
	if wait_for_world:
		card.begin_loading()
	card.return_requested.connect(_on_leave_requested)
	card.dismissed.connect(_on_loading_dismissed)
	add_child(card)

func _on_loading_dismissed() -> void:
	# Released devices are ready immediately, including a press before the
	# next action tick. A key held through the curtain still needs release.
	throw_armed = not Input.is_action_pressed("throw_grenade")
	place_armed = not Input.is_action_pressed("place_mine")

func _begin_world_load() -> void:
	_world_load_generation += 1
	_world_reveal_pending = false
	_awaiting_map = true
	show_loading_card(true)

func _queue_world_reveal(snapshot: Dictionary) -> void:
	var card: LoadingCard = get_node_or_null("LoadingCard") as LoadingCard
	if card == null or not card.waiting_for_world or card.failed or _world_reveal_pending \
		or _awaiting_map or current_map_info.is_empty() \
		or snapshot.get("map_id") != current_map_info.get("map_id"):
		return
	_world_reveal_pending = true
	_reveal_world_after_draw.call_deferred(_world_load_generation)

func _reveal_world_after_draw(generation: int) -> void:
	# A real first draw occurs beneath the opaque card. Headless checks have no
	# framebuffer and exercise lifecycle ordering on their next process frame.
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	if generation != _world_load_generation or _awaiting_map:
		return
	_world_reveal_pending = false
	var card: LoadingCard = get_node_or_null("LoadingCard") as LoadingCard
	if card != null and not card.failed:
		card.finish_loading(is_human_player and not _mission_map())

func _on_leave_requested() -> void:
	if _leaving:
		return
	_leaving = true
	if local_match != null:
		net_client.disconnect_from_server()
	else:
		net_client.leave_match()
	if local_match != null:
		local_match.stop()
	if get_tree().has_meta("fragr_boot"):
		get_tree().remove_meta("fragr_boot")
	get_tree().change_scene_to_file("res://scenes/boot_menu.tscn")

func _on_local_failure(key: String) -> void:
	if _leaving:
		return
	local_match.error_key = key
	_on_leave_requested.call_deferred()

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_release_retired_environments):
		RenderingServer.frame_post_draw.disconnect(_release_retired_environments)
	_retired_environments.clear()
	if records != null:
		_report_record_save(records.save())
	if is_instance_valid(local_match):
		local_match.stop()

func _on_record_received(data: Dictionary) -> void:
	_report_record_save(records.accept(data, "local" if local_match != null else "external"))
	_try_campaign_results()

func _report_record_save(result: Error) -> void:
	if result != OK and not _record_save_warning:
		_record_save_warning = true
		push_warning("Service record could not be saved: " + error_string(result))

## Escape or Start opens and closes the match menu; Back on a gamepad (the
## same ui_cancel as Escape) steps out of it too.
func _unhandled_input(event: InputEvent) -> void:
	if console != null and console.is_open() or pause_menu == null:
		return
	if event.is_echo():
		return
	if event.is_action_pressed("pause") or (pause_menu.is_open() and event.is_action_pressed("ui_cancel")):
		pause_menu.toggle()
		get_viewport().set_input_as_handled()

## Contested Frequency radio lives under AudioPlayers and reads the audiogen manifest.
func _setup_radio() -> void:
	var radio_script = load("res://scripts/radio.gd")
	if radio_script == null:
		return
	radio = radio_script.new()
	radio.name = "Radio"
	var audio_parent = get_node_or_null("AudioPlayers")
	if audio_parent:
		audio_parent.add_child(radio)
	else:
		add_child(radio)
	radio.set_human_mode(is_human_player)
	if hud and hud.has_method("show_radio"):
		radio.track_started.connect(func(station, title): hud.show_radio(station, title))
		radio.station_changed.connect(func(station, tagline, _has): hud.show_radio(station, tagline))
	if hud and hud.has_method("show_station_card"):
		radio.station_card.connect(func(card): hud.show_station_card(card))
	if hud and hud.has_signal("host_spoke"):
		hud.host_spoke.connect(func(seconds): radio.duck(seconds))

func _resolve_boot() -> Dictionary:
	# Boot menu meta wins; then --solo / FRAGR_SOLO; then --human; else spectator.
	if get_tree().has_meta("fragr_boot"):
		var meta = get_tree().get_meta("fragr_boot")
		if typeof(meta) == TYPE_DICTIONARY:
			var mode = str(meta.get("mode", "spectate"))
			var host = str(meta.get("host", "127.0.0.1:6767"))
			if mode == "campaign":
				var run_mode: String = str(meta.get("run_mode", "new"))
				var play_arrival: bool = typeof(meta.get("play_arrival")) == TYPE_BOOL and meta["play_arrival"]
				return {"role": "human", "name": settings.player_name(), "host": host, "hud_mode": "CAMPAIGN", "mode": mode, "run_mode": run_mode if run_mode in ["new", "resume"] else "new", "play_arrival":play_arrival}
			if mode == "solo":
				return {"role": "human", "name": settings.player_name(), "host": host, "hud_mode": "SOLO BROADCAST", "mode": mode}
			if mode == "join":
				return {"role": "human", "name": settings.player_name(), "host": host, "hud_mode": "PLAYING", "mode": mode}
			return {"role": "spectator", "name": "Spectator", "host": host, "hud_mode": "SPECTATING"}
	
	var args = OS.get_cmdline_args()
	var user_args = OS.get_cmdline_user_args()
	var wants_solo = OS.get_environment("FRAGR_SOLO") == "1" or "--solo" in args or "--solo" in user_args
	if wants_solo:
		return {"role": "human", "name": settings.player_name(), "host": "127.0.0.1:6767", "hud_mode": "SOLO BROADCAST", "mode": "solo"}
	if "--human" in args or "--human" in user_args:
		return {"role": "human", "name": settings.player_name(), "host": "", "hud_mode": "PLAYING"}
	return {"role": "spectator", "name": "Spectator", "host": "", "hud_mode": "SPECTATING"}

func _load_audio_streams():
	var audio_dir = "res://assets/audio/"
	
	if frag_sound and ResourceLoader.exists(audio_dir + "frag.wav"):
		frag_sound.stream = load(audio_dir + "frag.wav")
	
	if round_start_sound and ResourceLoader.exists(audio_dir + "round_start.wav"):
		round_start_sound.stream = load(audio_dir + "round_start.wav")
	
	if round_end_sound and ResourceLoader.exists(audio_dir + "round_end.wav"):
		round_end_sound.stream = load(audio_dir + "round_end.wav")
	if ResourceLoader.exists(CRAWLER_SOUND_PATH):
		crawler_sound_stream = load(CRAWLER_SOUND_PATH)
	for key: String in PICKUP_SOUND_PATHS:
		if ResourceLoader.exists(PICKUP_SOUND_PATHS[key]):
			pickup_streams[key] = load(PICKUP_SOUND_PATHS[key])
	var audio_parent: Node = get_node_or_null("AudioPlayers")
	if audio_parent == null:
		audio_parent = self
	if pickup_sound == null:
		pickup_sound = AudioStreamPlayer.new()
		pickup_sound.name = "PickupSound"
		pickup_sound.bus = &"Effects"
		pickup_sound.volume_db = -6.0
		audio_parent.add_child(pickup_sound)
	if scope_sound == null:
		scope_sound = AudioStreamPlayer.new()
		scope_sound.name = "ScopeSound"
		scope_sound.bus = &"Effects"
		scope_sound.volume_db = -6.0
		audio_parent.add_child(scope_sound)
	if dry_fire_sound == null and ResourceLoader.exists(DRY_FIRE_SOUND_PATH):
		dry_fire_sound = AudioStreamPlayer.new()
		dry_fire_sound.name = "DryFireSound"
		dry_fire_sound.bus = &"Effects"
		dry_fire_sound.volume_db = -6.0
		dry_fire_sound.stream = load(DRY_FIRE_SOUND_PATH)
		audio_parent.add_child(dry_fire_sound)

## Pickup feedback for the watched fighter. The event carries no ammunition
## pool, so the pad it came from says whether it was Cells.
func _play_pickup_cue(kind: String, pickup_id: String) -> void:
	var key: String = kind
	match kind:
		"golden_rail":
			key = "weapon"
		"grenade":
			key = "ammo"
		"ammo":
			var pad: Variant = pickups.get(pickup_id)
			if is_instance_valid(pad) and str(pad.get("ammo_pool")) == "cells":
				key = "cells"
	if pickup_sound == null or not pickup_streams.has(key):
		return
	pickup_sound.stream = pickup_streams[key]
	pickup_sound.play()
	pickup_cue_count += 1

func _scope_engaged() -> bool:
	return hud != null and hud.get("sniper_scope") != null and hud.sniper_scope.scoped()

## Raising and lowering the Sniper Rifle scope, heard only by its holder.
func _play_scope_cue(was_scoped: bool, now_scoped: bool) -> void:
	if was_scoped == now_scoped or scope_sound == null:
		return
	var path: String = L07Assets.SCOPE_IN_SOUND if now_scoped else L07Assets.SCOPE_OUT_SOUND
	if not ResourceLoader.exists(path):
		return
	scope_sound.stream = load(path)
	scope_sound.play()
	scope_cue_count += 1

## The owner's dry trigger count only grows within one life; a held empty
## trigger repeats at the weapon's own cadence on the server.
func _play_dry_fire_cue(loadout: Dictionary) -> void:
	if loadout.is_empty():
		_dry_fire_seen = -1
		return
	var count: Variant = loadout.get("dry_fire_count")
	if not EquipmentState.integer(count, EquipmentState.MAX_EXACT_INTEGER):
		return
	if _dry_fire_seen >= 0 and int(count) > _dry_fire_seen and dry_fire_sound != null:
		dry_fire_sound.play()
		dry_fire_cue_count += 1
	_dry_fire_seen = int(count)

func _crawler_position(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3:
		return Vector3.INF
	var coords: Array[float] = []
	for component: Variant in value:
		if typeof(component) != TYPE_FLOAT and typeof(component) != TYPE_INT:
			return Vector3.INF
		var number: float = float(component)
		if not is_finite(number) or absf(number) > 10000.0:
			return Vector3.INF
		coords.append(number)
	return Vector3(coords[0], coords[1], coords[2])

func _reset_crawler_cues() -> void:
	crawler_scrabble_count = 0
	crawler_last_position = Vector3.INF
	crawler_last_ms = -1000
	for voice: AudioStreamPlayer3D in crawler_sound_players:
		if is_instance_valid(voice):
			voice.stop()
	if hud != null and hud.crawler_caption != null:
		hud.crawler_caption.clear()

func _accept_crawler_scrabble(position: Vector3, now_ms: int) -> bool:
	if now_ms - crawler_last_ms < 300 and position.distance_squared_to(crawler_last_position) < 1.0:
		return false
	crawler_last_ms = now_ms
	crawler_last_position = position
	crawler_scrabble_count += 1
	return true

func _crawler_listener_near(position: Vector3) -> bool:
	var lens: Camera3D = get_node_or_null("SpectatorCamera/Camera3D") as Camera3D
	return lens != null and lens.global_position.distance_squared_to(position) <= CRAWLER_CUE_DISTANCE * CRAWLER_CUE_DISTANCE

func _play_crawler_scrabble(position: Vector3) -> void:
	var arena_root: Node3D = get_node_or_null("Arena") as Node3D
	if crawler_sound_stream == null or arena_root == null:
		return
	for index: int in range(crawler_sound_players.size() - 1, -1, -1):
		var existing: AudioStreamPlayer3D = crawler_sound_players[index]
		if not is_instance_valid(existing) or existing.get_parent() != arena_root:
			crawler_sound_players.remove_at(index)
	if crawler_sound_next >= crawler_sound_players.size():
		crawler_sound_next = 0
	if crawler_sound_players.size() < CRAWLER_SOUND_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "CrawlerScrabble%d" % crawler_sound_players.size()
		voice.stream = crawler_sound_stream
		voice.bus = &"Effects"
		voice.unit_size = 4.0
		voice.max_distance = 24.0
		voice.volume_db = -4.0
		arena_root.add_child(voice)
		crawler_sound_players.append(voice)
		crawler_sound_next = crawler_sound_players.size() - 1
	var player: AudioStreamPlayer3D = crawler_sound_players[crawler_sound_next]
	crawler_sound_next = (crawler_sound_next + 1) % CRAWLER_SOUND_VOICES
	player.global_position = position
	player.play()

func _try_continue(event: InputEvent) -> bool:
	if _continue_armed and is_human_player and event.is_action_pressed("ui_accept") \
		and (pause_menu == null or not pause_menu.is_open()) \
		and (console == null or not console.is_open()):
		var attempt: int = int(net_client.mission.get("state", {}).get("attempt", 0))
		if attempt != _continue_attempt_sent and net_client.send_mission_continue():
			_continue_attempt_sent = attempt
			_continue_armed = false
			_opening_release = true
			pending_jump = false
			pending_interact = false
			pending_throw = false
			throw_armed = false
			pending_place = false
			place_armed = false
			pending_weapon_swap = null
			interact_held = false
			return true
	return false

func _arm_continue() -> void:
	if not _continue_armed and _opening_input_released() and not net_client.mission.is_empty():
		var run: Variant = net_client.mission["state"].get("run")
		_continue_armed = run is Dictionary and run.get("status") == "continue"

## A departed mission in this process's own saved run. Development children,
## joined servers and arena matches never offer it.
func _onward_available() -> bool:
	if not is_human_player or local_match == null or not local_match.has_durable_run() or _leaving:
		return false
	if is_instance_valid(interlude) or is_instance_valid(departure_review) or is_instance_valid(opening) or is_instance_valid(campaign_results):
		return false
	var state: Dictionary = net_client.mission.get("state", {})
	var run: Variant = state.get("run")
	var result: Dictionary = CampaignResult.select(net_client.record, state, net_client.player_id)
	return state.get("phase") == "departed" and run is Dictionary and run.get("status") == "complete" \
		and not result.is_empty() and _results_played.has(result["key"])

## The prompt appears only after every held control is released, so the key
## that dismissed the departure scene cannot also leave the mission.
func _arm_onward() -> void:
	var available: bool = _onward_available()
	if not available:
		_onward_released = false
	elif not _onward_released and _opening_input_released():
		_onward_released = true
	var armed: bool = available and _onward_released
	if armed != _onward_armed:
		_onward_armed = armed
		if mission_hud != null:
			mission_hud.set_run_onward(armed)

func _try_onward(event: InputEvent) -> bool:
	if not _onward_armed or not event.is_action_pressed("ui_accept") or event.is_echo() \
		or (pause_menu != null and pause_menu.is_open()) or (console != null and console.is_open()):
		return false
	_onward_armed = false
	get_tree().set_meta(LocalMatch.ONWARD_META, true)
	_on_leave_requested()
	return true

func _input(_event):
	if _try_continue(_event) or _try_onward(_event):
		get_viewport().set_input_as_handled()
		return
	if _event.is_action_released("interact"):
		interact_held = false
	if _event.is_action_released("throw_grenade"):
		throw_armed = true
	if _event.is_action_released("place_mine"):
		place_armed = true
	if controls_blocked():
		pending_throw = false
		throw_armed = false
		pending_place = false
		place_armed = false
		return
	if is_human_player and throw_armed and _event.is_action_pressed("throw_grenade") and not _event.is_echo():
		pending_throw = true
	if is_human_player and place_armed and _event.is_action_pressed("place_mine") and not _event.is_echo():
		pending_place = true
	if is_human_player and _event.is_action_pressed("jump"):
		pending_jump = true
	if is_human_player and _event.is_action_pressed("interact"):
		if _offer_m05_departure():
			get_viewport().set_input_as_handled()
			return
		pending_interact = true
		interact_held = true
	# InputMap actions (keyboard + joypad). Same join/leave path.
	if Input.is_action_just_pressed("join_as_human") and not is_human_player:
		change_role(true)
	elif Input.is_action_just_pressed("leave_match") and is_human_player:
		change_role(false)
	elif is_human_player and Input.is_action_just_pressed("speak"):
		_send_speak_taunt()
	elif is_human_player and _event.is_action_pressed("weapon_next"):
		_choose_weapon(_next_weapon_swap(1))
	elif is_human_player and _event.is_action_pressed("weapon_prev"):
		_choose_weapon(_next_weapon_swap(-1))
	elif is_human_player:
		_choose_weapon(_slot_from_event(_event))

## One transition for input, the menu, and the real-wire visual tour.
func change_role(play: bool) -> void:
	if local_match != null or role_transition or play == is_human_player:
		return
	role_transition = true
	pending_jump = false
	pending_interact = false
	pending_throw = false
	throw_armed = false
	pending_place = false
	place_armed = false
	interact_held = false
	net_client.leave_match()
	is_human_player = play
	_clear_fp_state()
	pending_weapon_swap = null
	await get_tree().create_timer(0.1).timeout
	net_client.requested_body = settings.player_body()
	net_client.connect_to_server("human" if play else "spectator", settings.player_name())
	hud.set_mode(("CAMPAIGN" if local_match != null else "PLAYING") if play else "SPECTATING")
	hud.set_ghost_rival("")
	if radio:
		radio.set_human_mode(play)
	_awaiting_map = true
	role_transition = false

## Input sequence. The server echoes the newest accepted one in an Ack.
var input_seq: int = 0
## Newest Ack from the server: {seq, tick, x, z, yaw}. Live prediction needs
## a replayable movement step and a full authoritative body state first.
var last_ack: Dictionary = {}
var ack_probe: InputAckProbe = InputAckProbe.new()


func _on_ack_received(data: Dictionary) -> void:
	last_ack = data
	ack_probe.record_ack(data, Time.get_ticks_usec())
	if is_human_player:
		local_prediction.accept_ack(data, Time.get_ticks_usec())
		_apply_local_prediction()


func begin_ack_probe() -> bool:
	if not is_human_player or net_client.connection_state != WebSocketPeer.STATE_OPEN:
		return false
	ack_probe.begin(Time.get_ticks_usec())
	net_client.tx_text_bytes = 0
	net_client.rx_text_bytes = 0
	net_client.track_text_bytes = true
	return true


func end_ack_probe() -> Dictionary:
	var report: Dictionary = ack_probe.finish(Time.get_ticks_usec())
	report["tx_text_payload_bytes"] = net_client.tx_text_bytes
	report["rx_text_payload_bytes"] = net_client.rx_text_bytes
	net_client.track_text_bytes = false
	return report


func _process(_delta):
	_arm_continue()
	_arm_onward()
	if _opening_release and _opening_input_released():
		_opening_release = false
		_submit_mission_readiness()
	if mouse_capture != null:
		mouse_capture.set_gameplay(not controls_blocked())
	if is_human_player and net_client.connection_state != WebSocketPeer.STATE_OPEN and local_prediction.active():
		_reset_prediction_for_connection("connection_lost")
	if not is_human_player:
		_update_followed_weapon()
	_update_nameplates()
	if camera and is_human_player:
		camera.assist_targets = assist_targets()
	if hud and camera:
		var watched: Node = players.get(local_fp_pawn_id) if is_human_player else camera.get_followed_target()
		hud.set_fp_walk_speed(float(watched.get("presentation_speed")) if is_instance_valid(watched) else 0.0)
		_update_scope(_delta)
	if is_human_player and not role_transition and net_client.connection_state == WebSocketPeer.STATE_OPEN and _has_local_input_target():
		_send_local_action(Time.get_ticks_usec())
	if is_human_player:
		local_prediction.advance(Time.get_ticks_usec())
		local_prediction.decay_visual(_delta)
		_apply_local_prediction()


## The Sniper Rifle's scope is presentation: held input narrows the local view
## and look rate only. The selected weapon and life come from server facts.
func _update_scope(delta: float) -> void:
	var pawn: Node = players.get(local_fp_pawn_id)
	var alive: bool = is_instance_valid(pawn) and int(pawn.get("hp")) > 0
	var held: bool = is_human_player and not controls_blocked() and InputMap.has_action("scope") and Input.is_action_pressed("scope")
	var enabled: bool = is_human_player and alive and bool(camera.get("fp_mode"))
	var was_scoped: bool = _scope_engaged()
	camera.zoom_factor = hud.update_scope(delta, _current_weapon_wire(), held, enabled)
	_play_scope_cue(was_scoped, _scope_engaged())
	if camera.has_method("apply_zoom"):
		camera.apply_zoom()

func _clear_predicted_pawn() -> void:
	var pawn: Node = players.get(local_fp_pawn_id)
	if is_instance_valid(pawn) and pawn.has_method("clear_predicted_position"):
		pawn.clear_predicted_position()


func _reset_prediction_for_connection(reason: String) -> void:
	if incoming_feedback != null:
		incoming_feedback.reset()
	local_prediction.reset(reason, true)
	_clear_predicted_pawn()
	_adopt_local_spawn_snapshot = is_human_player
	pending_jump = false
	pending_interact = false
	pending_throw = false
	throw_armed = false
	pending_place = false
	place_armed = false


func _apply_local_prediction() -> void:
	var pawn: Node = players.get(local_fp_pawn_id)
	if not is_instance_valid(pawn):
		return
	if local_prediction.active() and pawn.hp > 0 and _has_local_input_target() and pawn.has_method("set_predicted_position"):
		var velocity: Vector2 = Vector2(float(local_prediction.state["vx"]), float(local_prediction.state["vz"]))
		pawn.set_predicted_position(local_prediction.presented_position(), velocity.length())
	elif pawn.has_method("clear_predicted_position"):
		pawn.clear_predicted_position()

## One action message per displayed frame flooded the server at high frame
## rates: a 500 fps client sent twice the 256 per second inbound budget, so
## about half its messages were dropped, and a one-frame Use or jump tap rode
## exactly one of them. Sends are paced below the budget instead, and discrete
## presses stay latched until a message actually carries them.
const ACTION_SEND_INTERVAL_USEC: int = 1000000 / 120
const MAX_ACTION_SEQ: int = 4294967295
var _last_action_usec: int = -ACTION_SEND_INTERVAL_USEC

func _send_local_action(now_usec: int) -> bool:
	if now_usec - _last_action_usec < ACTION_SEND_INTERVAL_USEC:
		return false
	_last_action_usec = now_usec
	# Keys, the strafe modifier and the left stick all reduce to the same four
	# direction bits the server has always read.
	var strafing: bool = Input.is_action_pressed("strafe")
	var pad: Dictionary = camera.pad_move_bits() if camera and camera.has_method("pad_move_bits") else {}
	action_state.forward = Input.is_action_pressed("move_forward") or bool(pad.get("forward", false))
	action_state.back = Input.is_action_pressed("move_back") or bool(pad.get("back", false))
	action_state.left = Input.is_action_pressed("move_left") or (strafing and Input.is_action_pressed("turn_left")) or bool(pad.get("left", false))
	action_state.right = Input.is_action_pressed("move_right") or (strafing and Input.is_action_pressed("turn_right")) or bool(pad.get("right", false))
	action_state.fire = Input.is_action_pressed("fire")
	action_state.jump = pending_jump or Input.is_action_pressed("jump")
	action_state.interact = pending_interact or interact_held
	if not Input.is_action_pressed("throw_grenade") and not pending_throw:
		throw_armed = true
	action_state.throw_grenade = throw_armed and (pending_throw or Input.is_action_pressed("throw_grenade"))
	if not Input.is_action_pressed("place_mine") and not pending_place:
		place_armed = true
	action_state.place_mine = place_armed and (pending_place or Input.is_action_pressed("place_mine"))
	# Client-owned yaw: the server takes the absolute facing and never turns
	# us at a fixed rate, so the look axis does not round-trip. Turn bits stay
	# zero for humans and remain the path for agents and older clients.
	if camera and camera.has_method("consume_yaw"):
		action_state.yaw = camera.consume_yaw()
		action_state.pitch = camera.consume_pitch()
	if controls_blocked():
		interact_held = false
		pending_jump = false
		pending_interact = false
		pending_throw = false
		throw_armed = false
		pending_place = false
		place_armed = false
		for key in ["forward", "back", "left", "right", "fire", "jump", "interact", "throw_grenade", "place_mine"]:
			action_state[key] = false
		pending_weapon_swap = null
	action_state.turn_left = false
	action_state.turn_right = false
	if _mission_controls_blocked():
		action_state.erase("yaw")
		action_state.erase("pitch")
	input_seq = 1 if input_seq >= MAX_ACTION_SEQ else input_seq + 1
	action_state.seq = input_seq
	action_state.weapon_swap = pending_weapon_swap
	var send_usec: int = 0
	if ack_probe.active:
		send_usec = Time.get_ticks_usec()
	var predicting: bool = local_prediction.active()
	net_client.last_send_ok = false
	net_client.send_action(action_state)
	if predicting:
		local_prediction.record_action(action_state, now_usec, net_client.last_send_ok)
	if ack_probe.active:
		if net_client.last_send_ok:
			ack_probe.record_send(input_seq, send_usec)
		else:
			ack_probe.failed_sends += 1
	if net_client.last_send_ok:
		pending_jump = false
		pending_interact = false
		pending_throw = false
		pending_place = false
		pending_weapon_swap = null
	return true

func _on_mission_received(state: Dictionary) -> void:
	_continue_armed = false
	if is_instance_valid(departure_review):
		if not _m05_departure_available():
			_close_departure_review()
		else:
			departure_review.apply(state, net_client.mission_geometry["m05"]["boarding"])
	local_prediction.apply_m05(state)
	if arena_cover != null:
		arena_cover.apply_m05(state)
	if camera != null and not local_prediction.arena.is_empty():
		camera.assist_solids = local_prediction.arena["solids"]
	if is_human_player and state.get("run") is Dictionary and state["run"]["status"] == "playing":
		var attempt: int = int(state["attempt"])
		if attempt > 1 and attempt != _presented_attempt:
			local_prediction.reset("continue", true)
			_clear_predicted_pawn()
			_retry_snapshot_tick = int(net_client.mission["tick"])
			_reset_crawler_cues()
			_adopt_local_spawn_snapshot = true
		_presented_attempt = attempt
	if mission_hud != null:
		mission_hud.boarding_region = net_client.mission_geometry.get("m05", {}).get("boarding", {})
		mission_hud.apply(state, str(net_client.player_id) if is_human_player else "")
	if m02_ward != null:
		m02_ward.apply_state(state)
	if m03_yard != null:
		m03_yard.apply_state(state)
	if m04_town != null:
		m04_town.apply_state(state)
	if m05_town != null:
		m05_town.apply_state(state)
	if m06_port != null:
		m06_port.apply_state(state)
	if m08_archive != null:
		m08_archive.apply_state(state)
	if m07_town != null:
		m07_town.apply_state(state)
	if m09_berth != null:
		m09_berth.apply_state(state)
	hud.combat_feed.set_campaign(not state.is_empty())
	_submit_mission_readiness()
	play_departure_scene(state)
	_try_campaign_results()

func _m05_departure_available() -> bool:
	var value: Dictionary = net_client.mission.get("state", {})
	if value.get("id") != MissionState.M05_ID or value.get("phase") != "in_progress":
		return false
	for prompt: Dictionary in value["prompts"]:
		if prompt["player_id"] == net_client.player_id and prompt["kind"] == "objective_use":
			return true
	return false

func _offer_m05_departure() -> bool:
	if not _m05_departure_available():
		return false
	departure_review = DepartureReview.new()
	departure_review.name = "DepartureReview"
	departure_review.apply(net_client.mission["state"], net_client.mission_geometry["m05"]["boarding"])
	departure_review.confirmed.connect(_confirm_m05_departure)
	departure_review.cancelled.connect(_close_departure_review)
	add_child(departure_review)
	pending_interact = false
	interact_held = false
	pending_throw = false
	throw_armed = false
	pending_place = false
	place_armed = false
	return true

func _close_departure_review() -> void:
	if is_instance_valid(departure_review):
		departure_review.queue_free()
	departure_review = null

func _confirm_m05_departure() -> void:
	var available: bool = _m05_departure_available()
	_close_departure_review()
	# The fresh physical Use press goes through the existing Action channel.
	# Server readiness, position and current mission still decide departure.
	if available:
		pending_interact = true
		interact_held = false

## Presentation after the server has already moved the party on. Once per
## mission per session; skipping or finishing sends nothing to the server.
func play_departure_scene(state: Dictionary) -> void:
	if not is_human_player or local_match == null or state.get("phase") != "departed" or is_instance_valid(interlude):
		return
	var mission_id: String = str(state.get("id", ""))
	var scene_id: String = StoryScene.AFTER_MISSION.get(mission_id, "")
	if scene_id.is_empty() or _interludes_played.has(mission_id) or not StoryScene.exists(scene_id):
		return
	_interludes_played[mission_id] = true
	var manifest: Dictionary = StoryScene.load_scene(scene_id)
	if manifest.is_empty():
		return
	interlude = ScenePlayer.new(manifest)
	interlude.completed.connect(_on_interlude_completed)
	add_child(interlude)

func _on_interlude_completed() -> void:
	if is_instance_valid(interlude):
		interlude.queue_free()
	interlude = null
	_clear_story_input()
	_try_campaign_results()

func _try_campaign_results() -> void:
	if not is_human_player or local_match == null or net_client == null or _leaving or is_instance_valid(opening) or is_instance_valid(interlude) or is_instance_valid(campaign_results):
		return
	var result: Dictionary = CampaignResult.select(net_client.record, net_client.mission.get("state", {}), net_client.player_id)
	if result.is_empty() or _results_played.has(result["key"]):
		return
	# A record may arrive before mission state. Give the existing story hook its
	# first opportunity regardless of which wire update completed the pair.
	play_departure_scene(net_client.mission["state"])
	if is_instance_valid(interlude):
		return
	_results_played[result["key"]] = true
	_onward_armed = false
	_onward_released = false
	_clear_story_input()
	campaign_results = CampaignResults.new(result)
	campaign_results.completed.connect(_on_campaign_results_completed)
	add_child(campaign_results)

func _on_campaign_results_completed() -> void:
	_close_campaign_results()
	_onward_armed = false
	_onward_released = false
	_clear_story_input()

func _close_campaign_results() -> void:
	if is_instance_valid(campaign_results):
		campaign_results.queue_free()
	campaign_results = null

func _clear_story_input() -> void:
	pending_jump = false
	pending_interact = false
	pending_throw = false
	throw_armed = false
	pending_place = false
	place_armed = false
	interact_held = false
	pending_weapon_swap = null

## Body centres of the hostiles aim assist may help with: live Union
## enemies on a mission map, every other live fighter in an arena. The camera
## still checks range, the cone and line of sight against the map solids.
func assist_targets() -> Array:
	var out: Array = []
	var mission: bool = _mission_map()
	var own_team: String = ""
	var local_pawn: Node = players.get(local_fp_pawn_id)
	if is_instance_valid(local_pawn):
		own_team = MatchRules.valid_team(local_pawn.get("team"))
	for id: Variant in players:
		var pawn: Node = players[id]
		if not is_instance_valid(pawn) or str(id) == local_fp_pawn_id or int(pawn.get("hp")) <= 0:
			continue
		if bool(pawn.get("is_campaign_companion")):
			continue
		var enemy: bool = bool(pawn.get("is_campaign_enemy"))
		if enemy != mission:
			continue
		if not mission and own_team != "" and MatchRules.valid_team(pawn.get("team")) == own_team:
			continue
		if mission and str((pawn.get("campaign_actor") as Dictionary).get("phase", "")) == "dead":
			continue
		out.append(AimAssist.body_centre(pawn.get("target_position"),
			pawn.get("campaign_actor") if mission else {}))
	return out

func _has_local_input_target() -> bool:
	# An open socket precedes the first snapshot. Sending the default camera aim
	# in that interval overwrites the authored spawn facing before we adopt it.
	if _adopt_local_spawn_snapshot or net_client.player_id == null or local_fp_pawn_id != str(net_client.player_id):
		return false
	var pawn: Node = players.get(local_fp_pawn_id)
	return is_instance_valid(pawn) and is_instance_valid(camera) and camera.fp_mode and camera.fp_target == pawn

func _carried_weapons() -> Array[String]:
	var carried: Array[String] = []
	if net_client != null and not net_client.equipment.is_empty():
		for weapon: Variant in net_client.equipment["weapons"]:
			carried.append(str(weapon).to_lower())
		return carried
	for weapon in EquipmentState.ARCADE:
		carried.append(weapon)
	return carried

func _current_weapon_wire() -> String:
	if net_client != null and not net_client.equipment.is_empty():
		return str(net_client.equipment["selected"]).to_lower()
	var name: String = _local_weapon_name().to_lower()
	if name in EquipmentState.WEAPONS:
		return name
	return "flechette"

func _next_weapon_swap(step: int) -> String:
	var current: String = str(pending_weapon_swap) if pending_weapon_swap != null else _current_weapon_wire()
	return EquipmentState.cycle_owned(_carried_weapons(), current, step)

func _slot_from_event(event: InputEvent) -> String:
	for slot in range(1, EquipmentState.SLOTS.size() + 1):
		if event.is_action_pressed("weapon_%d" % slot):
			var current: String = str(pending_weapon_swap) if pending_weapon_swap != null else _current_weapon_wire()
			return EquipmentState.slot_if_owned(_carried_weapons(), slot, current)
	return ""

func _choose_weapon(weapon: String) -> void:
	if weapon == "":
		return
	var current: String = str(pending_weapon_swap) if pending_weapon_swap != null else _current_weapon_wire()
	if weapon == current:
		return
	pending_weapon_swap = weapon

func _send_speak_taunt() -> void:
	if not net_client or not net_client.has_method("send_speak"):
		return
	var line = SPEAK_LINES[speak_line_index % SPEAK_LINES.size()]
	speak_line_index += 1
	net_client.send_speak(line)


func _apply_map_from_snapshot(snapshot: Dictionary) -> void:
	var map_id = int(snapshot.get("map_id", 1))
	if map_id < 1:
		map_id = 1
	# Always prefer Snapshot map_name for HUD / playlist face (Solo Broadcast
	# publishes "Larak Lot" on map 1). Do not keep a stale Hangar Candy chip
	# when layout geometry is unchanged across snapshots.
	var map_name = str(snapshot.get("map_name", "")).strip_edges()
	if map_name != "" and hud and hud.has_method("set_map_name"):
		hud.set_map_name(map_name)
	if map_id == current_map_id and arena.get_node_or_null("Layout") != null:
		return
	current_map_id = map_id
	var packed = compliance_yard_scene if map_id == 2 else arena_duel_scene
	if packed == null:
		push_warning("game_manager: map packed scene null for map_id " + str(map_id))
		return
	var old_layout = arena.get_node_or_null("Layout")
	if old_layout:
		arena.remove_child(old_layout)
		old_layout.queue_free()
	var layout = packed.instantiate()
	if layout == null:
		push_warning("game_manager: map layout instantiate returned null for map_id " + str(map_id))
		return
	layout.name = "Layout"
	arena.add_child(layout)
	arena.move_child(layout, 0)
	if arena_cover != null and int(current_map_info.get("map_id", -1)) == map_id:
		arena_cover.apply_map_info(current_map_info)
	_apply_arena_sky(map_name)
	if map_name == "":
		map_name = str(snapshot.get("map_name", "Arena Duel"))
	if hud and hud.has_method("set_map_name"):
		hud.set_map_name(map_name)

func _on_connected():
	_reset_prediction_for_connection("connected")
	if ack_probe.active:
		ack_probe.interrupted = true
		ack_probe.active = false
	net_client.track_text_bytes = false
	hud.set_status("Connected to server")

func _on_session_resumed() -> void:
	hud.set_status("Reconnected.")

func _on_disconnected():
	if ack_probe.active:
		ack_probe.interrupted = true
		ack_probe.active = false
	net_client.track_text_bytes = false
	hud.set_status("Disconnected")
	hud.reset_host_chrome()
	ended_podium_shown = false
	_clear_world()
	if local_match != null and not role_transition and not _leaving:
		_on_local_failure("LOCAL_SERVER_STOPPED")

func _on_server_error(message: String) -> void:
	hud.set_status(message)
	var card: LoadingCard = get_node_or_null("LoadingCard") as LoadingCard
	if card != null:
		_world_load_generation += 1
		_world_reveal_pending = false
		card.show_error(message)

func _clear_world() -> void:
	_world_load_generation += 1
	_world_reveal_pending = false
	var loading: LoadingCard = get_node_or_null("LoadingCard") as LoadingCard
	if loading != null:
		loading.show_error(tr("LOADING_DISCONNECTED"))
	_close_departure_review()
	_close_campaign_results()
	if grenade_effects != null:
		grenade_effects.reset()
	if auditor_channels != null:
		auditor_channels.reset()
	local_prediction.reset("disconnect", true)
	if jammer_audio != null:
		jammer_audio.reset()
	if notary_audio != null:
		notary_audio.reset()
	NotaryAnimation.configure_map({})
	_adopt_local_spawn_snapshot = false
	if is_instance_valid(opening):
		opening.queue_free()
	opening = null
	if is_instance_valid(interlude):
		interlude.queue_free()
	interlude = null
	_opening_finished = false
	_opening_release = false
	_readiness_attempt_sent = 0
	_awaiting_map = true
	current_map_info.clear()
	if hud and hud.has_method("set_match_rules"):
		hud.set_match_rules({})
	if arena_flags != null:
		arena_flags.clear_flags()
	if arena_sabotage != null:
		arena_sabotage.clear_layout()
	sabotage_layout = {}
	_sabotage_team = ""
	_sabotage_watching_mates = false
	if traveling_shots != null:
		traveling_shots.clear_shots()
	pending_jump = false
	pending_interact = false
	pending_throw = false
	throw_armed = false
	pending_place = false
	place_armed = false
	interact_held = false
	if mission_hud != null:
		mission_hud.apply({}, "")
		mission_hud.reset_notices()
	if m02_ward != null:
		m02_ward.clear_map()
	if m03_yard != null:
		m03_yard.clear_map()
	if m04_town != null:
		m04_town.clear_map()
	if m05_town != null:
		m05_town.clear_map()
	if m06_port != null:
		m06_port.clear_map()
	if m08_archive != null:
		m08_archive.clear_map()
	if m07_town != null:
		m07_town.clear_map()
	if m09_berth != null:
		m09_berth.clear_map()
	hud.combat_feed.set_campaign(false)
	pending_weapon_swap = null
	latest_snapshot.clear()
	hud.equipment_hud.apply({})
	last_shot_tick = -1
	if shot_effects != null:
		shot_effects.clear()
	_clear_fp_state()
	# Drop presentation nodes so rejoin does not keep stale pawns/pads.
	for id in players.keys():
		if is_instance_valid(players[id]):
			players[id].queue_free()
	players.clear()
	for pid in pickups.keys():
		if is_instance_valid(pickups[pid]):
			pickups[pid].queue_free()
	pickups.clear()
	if jammer_dish_node != null and is_instance_valid(jammer_dish_node):
		jammer_dish_node.queue_free()
	jammer_dish_node = null
	if camera:
		camera.set_available_targets([])

func _on_loadout_received(data: Dictionary) -> void:
	hud.equipment_hud.apply(data)
	_play_dry_fire_cue(data)
	_sync_pickups(latest_snapshot.get("pickups", []))
	_refresh_equipment_visibility()

func _refresh_equipment_visibility() -> void:
	var pawn: Node = players.get(net_client.player_id)
	hud.equipment_hud.visible = is_human_player and not net_client.equipment.is_empty() \
		and is_instance_valid(pawn) and pawn.hp > 0 and hud.fp_juice_enabled

func _on_snapshot_received(data):
	if grenade_effects != null:
		grenade_effects.apply(data, camera.global_position if camera != null else Vector3(NAN, NAN, NAN))
	if auditor_channels != null:
		auditor_channels.apply(data)
	ack_probe.record_snapshot(data.get("tick"), Time.get_ticks_usec())
	latest_snapshot = data
	_apply_map_from_snapshot(data)
	_update_prediction_contacts(data)
	var tick = data.get("tick", 0)
	var player_list = data.get("players", [])
	var companion_phase: String = ""
	var companion_started: int = -1
	for player_data: Dictionary in player_list:
		if ActorState.is_companion(player_data):
			companion_phase = str(player_data["campaign"]["phase"])
			companion_started = int(player_data["campaign"]["phase_started"])
			break
	if companion_phase.is_empty() and net_client.mission.get("state", {}).get("phase") == "departed":
		companion_phase = "departed"
	if m02_ward != null:
		m02_ward.set_companion_phase(companion_phase, companion_started, int(data.get("tick", 0)))
	var participant_list: Array[Dictionary] = ActorState.participants(player_list)
	var round_state = data.get("round_state", "")
	var round_time_left = data.get("round_time_left", 0)
	var frag_limit = data.get("frag_limit", 0)
	var mode_name = str(data.get("mode_name", "Contested Frequency"))
	var playlist = str(data.get("playlist", "Arena Duel"))
	var pressure = data.get("pressure", null)
	var host_line = str(data.get("host_line", ""))
	
	hud.set_league_identity(mode_name, playlist)
	var snap_map = str(data.get("map_name", "")).strip_edges()
	if snap_map != "" and hud.has_method("set_map_name"):
		hud.set_map_name(snap_map)
	if pressure == null:
		hud.set_pressure("")
	else:
		hud.set_pressure(str(pressure))
	# Sticky Host chrome always. Flash once on Warmup / Active / Ended join so
	# pre-round Contested Frequency drama is readable (RoundStart still fights).
	var roster = _warmup_roster_callsigns(participant_list)
	if host_line != "":
		var flash = round_state == "Warmup" or round_state == "Active" or round_state == "Ended"
		var did_flash = hud.set_host_line(host_line, false)
		if flash and not hud.host_line_seen:
			hud.host_line_seen = true
			if round_state == "Warmup" and hud.has_method("show_warmup_bumper"):
				hud.show_warmup_bumper(host_line, int(round_time_left) if round_time_left != null else 0, roster)
			else:
				hud.show_host_join(host_line)
			did_flash = true
		elif round_state == "Warmup" and hud.has_method("refresh_warmup_tv"):
			# Live giant countdown + roster chips while Warmup TV is up.
			hud.refresh_warmup_tv(host_line, int(round_time_left) if round_time_left != null else 0, roster)
		if did_flash:
			if round_start_sound and round_start_sound.stream:
				round_start_sound.play()
	elif round_state == "Warmup" and hud.has_method("refresh_warmup_tv"):
		hud.refresh_warmup_tv("", int(round_time_left) if round_time_left != null else 0, roster)
	var ep_id = str(data.get("episode_id", "")) if data.get("episode_id", null) != null else ""
	var ep_title = str(data.get("episode_title", "")) if data.get("episode_title", null) != null else ""
	var ep_obj = str(data.get("episode_objective", "")) if data.get("episode_objective", null) != null else ""
	var ep_prog = str(data.get("episode_progress", "")) if data.get("episode_progress", null) != null else ""
	var ep_phase = str(data.get("episode_phase", "")) if data.get("episode_phase", null) != null else ""
	if hud.has_method("set_episode_chrome"):
		hud.set_episode_chrome(ep_id, ep_title, ep_obj, ep_prog, ep_phase)
	hud.set_tick(tick)
	hud.set_player_count(participant_list.size())
	hud.sync_scores_from_players(participant_list)
	hud.set_round_info(round_state, round_time_left, frag_limit)
	if hud.has_method("set_team_scores"):
		hud.set_team_scores(data.get("team_scores"))
	if hud.has_method("set_ctf_state"):
		var ctf_viewer_id: String = str(net_client.player_id) if is_human_player and net_client.player_id != null else _followed_player_id()
		hud.set_ctf_state(data.get("flags"), data.get("capture_scores"), data.get("capture_limit", 0), player_list, ctf_viewer_id)
	if is_human_player and net_client.player_id != null and hud.has_method("set_own_lives"):
		for player_data in player_list:
			if str(player_data.get("id", "")) == str(net_client.player_id):
				var lives: Variant = player_data.get("lives")
				hud.set_own_lives(int(lives) if lives is float or lives is int else -1)
	hud.round_label.visible = not _mission_map() and not hud.sabotage()
	_maybe_rehydrate_ended_mvp(data, round_state)
	_maybe_assign_ghost_rival(participant_list)
	
	var current_ids = {}
	
	for player_data in player_list:
		var id = player_data.id
		current_ids[id] = true
		
		if not players.has(id):
			if player_scene == null or not is_instance_valid(arena):
				continue
			var pawn = player_scene.instantiate()
			if pawn == null:
				push_warning("game_manager: player instantiate returned null for " + str(id))
				continue
			arena.add_child(pawn)
			pawn.position = Vector3(player_data.x, player_data.y, player_data.z)
			pawn.rotation.y = ServerYaw.pawn_rotation_y(float(player_data.yaw))
			pawn.set_player_data(id, player_data.name)
			players[id] = pawn
		
		if players.has(id):
			players[id].update_state(player_data, int(tick))
			if players[id].is_campaign_companion:
				# Every real companion snapshot owns the visible body, including
				# the stationary release phase and its authoritative shot stop.
				players[id].visible = true
	
	for id in players.keys():
		if not current_ids.has(id):
			if is_instance_valid(players[id]):
				players[id].queue_free()
			players.erase(id)
	
	var targets = []
	for pawn in players.values():
		if is_instance_valid(pawn) and not pawn.is_campaign_enemy and not pawn.is_campaign_companion:
			targets.append(pawn)
	if camera:
		camera.set_available_targets(_sabotage_watch_targets(targets, player_list, str(data.get("round_state", ""))))
		
		var followed = camera.get_followed_target()
		for pawn in players.values():
			if is_instance_valid(pawn):
				pawn.set_highlighted(pawn == followed)
				pawn.broadcast_scale_enabled = not is_human_player and not camera.is_observing_first_person()
	
	_update_followed_weapon()
	_sync_pickups(data.get("pickups", []))
	var flag_rows: Variant = data.get("flags")
	if arena_flags != null:
		# Hide this view's own grip before the marker is seated.
		arena_flags.set_first_person_carrier(_first_person_carrier_id())
		var carriers: Dictionary = {}
		if flag_rows is Array:
			for flag_row: Variant in flag_rows:
				if flag_row is Dictionary and str(flag_row.get("status", "")) == "carried" and players.has(str(flag_row.get("carrier", ""))):
					var carrier_pawn: Node = players[str(flag_row.get("carrier", ""))]
					if is_instance_valid(carrier_pawn):
						carriers[str(flag_row.get("carrier", ""))] = carrier_pawn
		arena_flags.apply(flag_rows, carriers)
	_apply_sabotage(data)
	if traveling_shots != null:
		traveling_shots.apply(data.get("projectiles"))
	_sync_jammer_dish(data.get("jammer_dish", null))
	if is_human_player:
		_refresh_fp_target()
		_update_local_fp_hud(data.get("players", []))
		_apply_local_prediction()
	if hud and hud.has_method("set_fp_carried_flag"):
		hud.set_fp_carried_flag(_carried_flag_team(_first_person_carrier_id(), flag_rows))
	_process_shot_results(data.get("shot_results", []), int(data.get("tick", -1)))
	_present_jammer_launches(data)
	if notary_audio != null:
		var listener: Camera3D = get_viewport().get_camera_3d()
		notary_audio.apply(data, listener.global_position if listener != null else Vector3.INF)
	if marksman_audio != null:
		var marksman_listener: Camera3D = get_viewport().get_camera_3d()
		marksman_audio.apply(data, marksman_listener.global_position if marksman_listener != null else Vector3.INF)
	hud.equipment_hud.tick = int(data.get("tick", 0))
	_refresh_equipment_visibility()
	_update_nameplates()
	_queue_world_reveal(data)


func _update_prediction_contacts(snapshot: Dictionary) -> void:
	if is_human_player and net_client != null and net_client.player_id != null:
		local_prediction.accept_snapshot(snapshot, str(net_client.player_id), net_client.mission.get("state", {}), Time.get_ticks_usec())


func _present_jammer_launches(snapshot: Dictionary) -> void:
	if jammer_audio == null:
		return
	var listener: Camera3D = get_viewport().get_camera_3d()
	jammer_audio.apply(snapshot, listener.global_position if listener != null else Vector3.INF)

func _update_nameplates() -> void:
	if camera == null:
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var watching: bool = not is_human_player and not camera.is_observing_first_person()
	var view: Camera3D = viewport.get_camera_3d()
	if not watching or view == null:
		for pawn: Node in players.values():
			if is_instance_valid(pawn):
				pawn.set_nameplate_enabled(false)
		return
	var carrier_ids: Array[String] = []
	var flags: Variant = latest_snapshot.get("flags")
	if flags is Array:
		for flag: Variant in flags:
			if flag is Dictionary and flag.get("status") == "carried" and flag.get("carrier") is String:
				carrier_ids.append(str(flag["carrier"]))
	var followed: Node = camera.get_followed_target()
	var viewport_rect: Rect2 = viewport.get_visible_rect()
	var entries: Array[Dictionary] = []
	for id: Variant in players:
		var pawn: Node3D = players[id]
		if not is_instance_valid(pawn):
			continue
		var label: Label3D = pawn.get_node_or_null("Label3D") as Label3D
		if label == null or view.is_position_behind(label.global_position):
			pawn.set_nameplate_enabled(false)
			continue
		var area: Rect2 = NameplateLayoutScript.project_label(view, label)
		if area.position.x < viewport_rect.position.x or area.position.y < viewport_rect.position.y \
			or area.end.x > viewport_rect.end.x or area.end.y > viewport_rect.end.y:
			pawn.set_nameplate_enabled(false)
			continue
		var priority: int = 0 if carrier_ids.has(str(id)) else (1 if pawn == followed else 2)
		entries.append({"id": str(id), "rect": area, "priority": priority,
			"distance": view.global_position.distance_to(label.global_position)})
	var reserved: Array[Rect2] = arena_flags.blocker_rects(view) if arena_flags != null else []
	var visible_ids: Array[String] = NameplateLayoutScript.choose(entries, reserved)
	for id: Variant in players:
		var pawn: Node = players[id]
		if is_instance_valid(pawn):
			pawn.set_nameplate_enabled(visible_ids.has(str(id)))

func _on_event_received(data):
	var event_type = data.get("event", "")
	if event_type == "sabotage":
		_on_sabotage_event(data)
	elif event_type == "flag":
		hud.show_flag_event(data)
	elif event_type == "frag":
		var killer_name = data.get("killer", "?")
		var victim_name = data.get("victim", "?")
		
		var killer_id = ""
		for pawn in players.values():
			if is_instance_valid(pawn) and pawn.player_name == killer_name:
				killer_id = pawn.player_id
				break
		
		var killer_color = Color.WHITE
		var victim_color = Color.WHITE
		if killer_id != "" and players.has(killer_id):
			killer_color = players[killer_id].player_color
		for pawn in players.values():
			if is_instance_valid(pawn) and pawn.player_name == victim_name:
				victim_color = pawn.player_color
				break
		# In a team mode the killfeed wears the sides' colours, which also
		# covers a victim whose pawn already left the field.
		var killer_team: String = MatchRules.valid_team(data.get("killer_team"))
		var victim_team: String = MatchRules.valid_team(data.get("victim_team"))
		if killer_team != "":
			killer_color = MatchRules.team_label_color(killer_team)
		if victim_team != "":
			victim_color = MatchRules.team_label_color(victim_team)
		if is_human_player and hud.has_method("set_own_lives") and hud.own_lives > 0 and players.has(str(net_client.player_id)) \
				and players[str(net_client.player_id)].player_name == victim_name:
			hud.set_own_lives(hud.own_lives - 1)
		
		hud.show_frag(killer_name, victim_name, killer_color, victim_color)
		
		for pawn in players.values():
			if is_instance_valid(pawn) and pawn.player_name == killer_name:
				pawn.show_winner_glow()
				break
		
		if frag_sound and frag_sound.stream:
			frag_sound.play()
		
		if not is_human_player and killer_id != "" and camera:
			camera.lock_on_frag(killer_id, 2.0)
	elif event_type == "round_start":
		ended_podium_shown = false
		var mode_name = str(data.get("mode_name", "Contested Frequency"))
		var playlist = str(data.get("playlist", "Arena Duel"))
		hud.set_league_identity(mode_name, playlist)
		var shown_round: int = int(data.get("round_number", 0))
		var sabotage_round: Variant = latest_snapshot.get("sabotage")
		if hud.sabotage() and sabotage_round is Dictionary:
			# The match's own round, not the server's count of rounds since boot.
			shown_round = int(sabotage_round.get("round", shown_round))
		hud.show_round_start(shown_round, str(data.get("host_line", "")))
		if _sabotage_swap_notice != "":
			# The swap arrives just before its round opens; it outranks the
			# round number on the card.
			hud.show_sabotage_notice(_sabotage_swap_notice, 3.0)
			_sabotage_swap_notice = ""
		if round_start_sound and round_start_sound.stream:
			round_start_sound.play()
	elif event_type == "compliance_ping":
		hud.set_pressure("compliance")
		var duration_ticks = int(data.get("duration_ticks", 120))
		var duration_sec = float(duration_ticks) / 20.0
		hud.show_compliance_ping(str(data.get("message", "")), duration_sec)
	elif event_type == "crawler_scrabble":
		var crawler_position: Vector3 = _crawler_position(data.get("position"))
		if crawler_position.is_finite() and _crawler_listener_near(crawler_position) \
				and _accept_crawler_scrabble(crawler_position, Time.get_ticks_msec()):
			hud.show_crawler_scrabble_caption()
			_play_crawler_scrabble(crawler_position)
	elif event_type == "boss_spawn":
		hud.set_pressure("compliance_drone")
		hud.show_boss_spawn(str(data.get("message", "")), str(data.get("name", "COMPLIANCE-DRONE")))
	elif event_type == "episode_start":
		var title = str(data.get("title", "Solo Broadcast: Calibration"))
		var objective = str(data.get("objective", ""))
		var map_name = str(data.get("map_name", "Larak Lot"))
		if hud.has_method("set_map_name"):
			hud.set_map_name(map_name)
		if hud.has_method("set_episode_chrome"):
			hud.set_episode_chrome(str(data.get("id", "ep0")), title, objective, "", "nods")
		if hud.has_method("show_episode_title_card"):
			hud.show_episode_title_card(title, objective)
		hud.set_host_line(str(data.get("host_line", "")), true)
		if round_start_sound and round_start_sound.stream:
			round_start_sound.play()
	elif event_type == "episode_complete":
		if hud.has_method("show_episode_complete"):
			hud.show_episode_complete(str(data.get("host_line", "")), str(data.get("unlock_teaser", "")))
		if round_end_sound and round_end_sound.stream:
			round_end_sound.play()
	elif event_type == "episode_fail":
		if hud.has_method("show_episode_fail"):
			hud.show_episode_fail(str(data.get("host_line", "")))
	elif event_type == "boss_down":
		hud.set_pressure("")
		var killer_raw = data.get("killer", null)
		var killer_name = "" if killer_raw == null else str(killer_raw)
		hud.show_boss_down(str(data.get("message", "")), killer_name)
	elif event_type == "hit":
		# Victim blood flash only. Shooter hit markers come from Snapshot shot_results.
		var target_id = str(data.get("target_id", ""))
		var my_id = str(net_client.player_id) if net_client.player_id != null else ""
		if is_human_player and my_id != "" and target_id == my_id:
			if hud and hud.has_method("show_damage_flash"):
				hud.show_damage_flash()
			if camera:
				camera.camera_punch()
	elif event_type == "respawn":
		var who = str(data.get("player", ""))
		var my_name = str(net_client.player_name) if net_client else ""
		var my_id: String = str(net_client.player_id) if net_client and net_client.player_id != null else ""
		if players.has(my_id) and is_instance_valid(players[my_id]):
			my_name = players[my_id].player_name
		if is_human_player and who != "" and who == my_name:
			if hud and hud.has_method("show_spawn_flash"):
				hud.show_spawn_flash()
			fp_spawn_flashed = true
	elif event_type == "pickup":
		if not _shows_participant_notice(str(data.get("player_id", ""))):
			return
		var who = str(data.get("player", "?"))
		var kind = str(data.get("kind", "weapon"))
		var weapon = str(data.get("weapon", ""))
		var amount = int(data.get("amount", 0))
		hud.show_pickup_toast(who, weapon, kind, amount)
		_play_pickup_cue(kind, str(data.get("pickup_id", "")))
		if data.get("secret") == true:
			hud.show_secret_found()
	elif event_type == "killstreak":
		var who = str(data.get("player", "?"))
		var streak = int(data.get("streak", 0))
		var tier = str(data.get("tier", ""))
		var message = str(data.get("message", ""))
		if hud and hud.has_method("show_killstreak"):
			hud.show_killstreak(who, streak, tier, message)
		if frag_sound and frag_sound.stream:
			frag_sound.play()
	elif event_type == "host_reaction":
		if hud.has_method("show_host_reaction"):
			hud.show_host_reaction(data)
	elif event_type == "speak":
		var speaker = str(data.get("player", "?"))
		var line = str(data.get("text", ""))
		hud.show_speak(speaker, line)
	elif event_type == "round_end":
		ended_podium_shown = true
		var mvp_name = str(data.get("mvp", data.get("winner", "")))
		var mvp_frags = int(data.get("mvp_frags", data.get("winner_score", 0)))
		var host_line = str(data.get("host_line", ""))
		var podium = data.get("final_scores", [])
		if hud and hud.sabotage():
			hud.show_sabotage_result(SabotageState.result_text(data, _sabotage_viewer_team()), host_line)
			hud.show_host_join(host_line)
		elif hud and hud.has_method("show_round_end"):
			hud.show_round_end(mvp_name, str(data.get("reason", "")), mvp_frags, host_line, podium, data.get("winning_team"), data.get("capture_scores"))
		if round_end_sound and round_end_sound.stream:
			round_end_sound.play()

func _shows_participant_notice(subject_id: String) -> bool:
	if subject_id.is_empty():
		return false
	var watched_id: String = str(net_client.player_id) if is_human_player else _followed_player_id()
	return subject_id == watched_id



func _maybe_rehydrate_ended_mvp(data, round_state) -> void:
	# Mid-join during Ended: structured Snapshot mvp/mvp_frags/host_line sell podium.
	# A Sabotage round is between rounds for five seconds; its card needs the
	# round_end event, and the Host line already says who won.
	if round_state != "Ended" or ended_podium_shown or hud.sabotage():
		return
	var mvp_raw = data.get("mvp", null)
	var frags_raw = data.get("mvp_frags", null)
	var host_line = str(data.get("host_line", ""))
	# Need at least one structured Ended field (or sticky Host bumper).
	if mvp_raw == null and frags_raw == null and host_line == "":
		return
	var mvp_name = str(mvp_raw) if mvp_raw != null else ""
	var mvp_frags = int(frags_raw) if frags_raw != null else 0
	# Light podium from live player scores when final_scores absent on Snapshot.
	var podium = []
	var player_list = data.get("players", [])
	if typeof(player_list) == TYPE_ARRAY:
		var rows = []
		for p in player_list:
			rows.append({"name": str(p.get("name", "?")), "score": int(p.get("score", 0))})
		rows.sort_custom(func(a, b): return a.score > b.score)
		podium = rows
	ended_podium_shown = true
	if hud and hud.has_method("show_round_end"):
		var captures: Variant = data.get("capture_scores")
		var winner_side: Variant = null
		if captures is Dictionary:
			var union_count: int = int(captures.get("union", 0))
			var coalition_count: int = int(captures.get("coalition", 0))
			if union_count != coalition_count:
				winner_side = "union" if union_count > coalition_count else "coalition"
		hud.show_round_end(mvp_name, "MID-JOIN // ROUND ENDED", mvp_frags, host_line, podium, winner_side, captures)

func _sync_pickups(pickup_list):
	var seen = {}
	for pad in pickup_list:
		var pid = str(pad.get("id", ""))
		if pid == "":
			continue
		seen[pid] = true
		var kind = str(pad.get("kind", "weapon"))
		var weapon = str(pad.get("weapon", ""))
		var amount = int(pad.get("amount", 0))
		var pos = Vector3(float(pad.get("x", 0.0)), float(pad.get("y", 0.4)), float(pad.get("z", 0.0)))
		var is_up = bool(pad.get("available", true))
		if pad.get("claim") == "personal" and pid in net_client.equipment.get("personal_claims", []):
			is_up = false
		if not pickups.has(pid):
			if pickup_scene == null or not is_instance_valid(arena):
				continue
			var node = pickup_scene.instantiate()
			if node == null:
				push_warning("game_manager: pickup instantiate returned null for " + pid)
				continue
			arena.add_child(node)
			node.setup(pid, weapon, pos, kind, amount, str(pad.get("pool", "")))
			pickups[pid] = node
		if pickups.has(pid):
			pickups[pid].position = pos
			var dirty = false
			if pickups[pid].weapon_name != weapon:
				pickups[pid].weapon_name = weapon
				dirty = true
			if pickups[pid].pickup_kind != kind:
				pickups[pid].pickup_kind = kind
				dirty = true
			if pickups[pid].amount != amount:
				pickups[pid].amount = amount
				dirty = true
			if dirty:
				pickups[pid]._apply_look()
			pickups[pid].set_available(is_up)
	for pid in pickups.keys():
		if not seen.has(pid):
			if is_instance_valid(pickups[pid]):
				pickups[pid].queue_free()
			pickups.erase(pid)


func _sync_jammer_dish(dish):
	# Solo Broadcast jammer dish: chunky in-world silhouette while phase is jammer (and after seize).
	# tip_capture latches tip_force_jammer_dish so live hangar stills keep the ember bowl
	# through NODS-phase nulls AND post-seize Snapshots (green JAMMER OK would kill orange).
	if tip_force_jammer_dish:
		dish = {
			"live": true,
			"seized": false,
			"x": 0.0,
			"y": 0.35,
			"z": 0.0,
		}
	if dish == null:
		if jammer_dish_node != null and is_instance_valid(jammer_dish_node):
			jammer_dish_node.visible = false
		return
	if jammer_dish_node == null or not is_instance_valid(jammer_dish_node):
		jammer_dish_node = JammerDishBuilderScript.build()
		if arena != null and is_instance_valid(arena):
			arena.add_child(jammer_dish_node)
		else:
			add_child(jammer_dish_node)
	var live = bool(dish.get("live", false)) if typeof(dish) == TYPE_DICTIONARY else false
	var seized = bool(dish.get("seized", false)) if typeof(dish) == TYPE_DICTIONARY else false
	var x = float(dish.get("x", 0.0)) if typeof(dish) == TYPE_DICTIONARY else 0.0
	var y = float(dish.get("y", 0.35)) if typeof(dish) == TYPE_DICTIONARY else 0.35
	var z = float(dish.get("z", 0.0)) if typeof(dish) == TYPE_DICTIONARY else 0.0
	jammer_dish_node.position = Vector3(x, y, z)
	jammer_dish_node.visible = true
	JammerDishBuilderScript.apply_tint(jammer_dish_node, live, seized)


func _update_followed_weapon():
	if not camera or not hud:
		return
	
	if is_human_player:
		# FP path owns weapon chrome via _update_local_fp_hud.
		return
	
	if not camera.follow_mode or len(camera.available_targets) == 0:
		hud.set_followed_weapon("", "")
		hud.set_fp_juice(false)
		return
	
	var target_index = camera.follow_target_index % len(camera.available_targets)
	var target = camera.available_targets[target_index]
	
	if not is_instance_valid(target):
		hud.set_followed_weapon("", "")
		hud.set_fp_juice(false)
		return
	
	var weapon_name = ""
	var player_name = ""
	var behavior = ""
	var team: String = ""
	if players.has(target.player_id):
		var pawn = players[target.player_id]
		if pawn.has_method("get_weapon_name"):
			weapon_name = pawn.get_weapon_name()
		player_name = pawn.player_name
		if "behavior" in pawn:
			behavior = pawn.behavior
		team = pawn.team
	
	hud.set_fp_juice(camera.is_observing_first_person())
	if camera.is_observing_first_person():
		hud.set_vitals(int(target.hp), int(target.armor))
	hud.set_fp_weapon(weapon_name)
	hud.set_followed_weapon(weapon_name, player_name, behavior, team)

func _pick_ghost_rival_from_alive():
	var names = []
	for pawn in players.values():
		if is_instance_valid(pawn) and not pawn.is_campaign_enemy and not pawn.is_campaign_companion \
			and pawn.player_name != "" and pawn.player_name != "Human Player":
			names.append(pawn.player_name)
	if names.is_empty():
		hud.set_ghost_rival("")
		return
	names.shuffle()
	hud.set_ghost_rival(names[0])

func _warmup_roster_callsigns(player_list: Array) -> Array:
	# Warmup TV chips: callsign + stance so spectators never need Tab.
	var names = []
	for p in player_list:
		var n = str(p.get("name", ""))
		if n == "" or n == "Spectator":
			continue
		var beh = ""
		var raw = p.get("behavior", null)
		if raw != null:
			beh = str(raw)
		names.append(StanceChipScript.roster_entry(n, beh))
	return names

func _maybe_assign_ghost_rival(player_list: Array):
	if is_human_player:
		return
	# Spectators: keep a live rival chip so the fight has a face.
	if hud.ghost_rival != "":
		for p in player_list:
			if str(p.get("name", "")) == hud.ghost_rival:
				return
	var names = []
	for p in player_list:
		var n = str(p.get("name", ""))
		if n != "" and n != "Spectator" and n != "Human Player":
			names.append(n)
	if names.is_empty():
		hud.set_ghost_rival("")
		return
	names.shuffle()
	hud.set_ghost_rival(names[0])

func _set_human_fp(enabled: bool) -> void:
	if not enabled:
		_clear_fp_state()
		return
	_refresh_fp_target()

func _clear_fp_state() -> void:
	if incoming_feedback != null:
		incoming_feedback.reset()
	local_prediction.reset("role", true)
	_adopt_local_spawn_snapshot = false
	_clear_predicted_pawn()
	if local_fp_pawn_id != "" and players.has(local_fp_pawn_id):
		var old = players[local_fp_pawn_id]
		if is_instance_valid(old) and old.has_method("set_local_fp"):
			old.set_local_fp(false)
	local_fp_pawn_id = ""
	local_hp_seen = -1
	fp_spawn_flashed = false
	if camera and camera.has_method("set_fp_mode"):
		camera.set_fp_mode(false)
	if hud and hud.has_method("set_fp_juice"):
		hud.set_fp_juice(false)
	if hud and hud.has_method("set_fp_carried_flag"):
		hud.set_fp_carried_flag("")
	if arena_flags != null:
		arena_flags.set_first_person_carrier("")

func _refresh_fp_target() -> void:
	if not is_human_player:
		return
	var pid = str(net_client.player_id) if net_client.player_id != null else ""
	if pid == "" or not players.has(pid):
		return
	var pawn = players[pid]
	if not is_instance_valid(pawn):
		return
	if local_fp_pawn_id != "" and local_fp_pawn_id != pid and players.has(local_fp_pawn_id):
		var prev = players[local_fp_pawn_id]
		if is_instance_valid(prev) and prev.has_method("set_local_fp"):
			prev.set_local_fp(false)
	local_fp_pawn_id = pid
	if pawn.has_method("set_local_fp"):
		pawn.set_local_fp(true)
	if camera and camera.has_method("set_fp_mode"):
		camera.set_fp_mode(true, pawn)
	if hud and hud.has_method("set_fp_juice"):
		hud.set_fp_juice(true)
		if pawn.has_method("get_weapon_name"):
			hud.set_fp_weapon(pawn.get_weapon_name())
	if not fp_spawn_flashed and hud and hud.has_method("show_spawn_flash"):
		hud.show_spawn_flash()
		fp_spawn_flashed = true

func _update_local_fp_hud(player_list: Array) -> void:
	var pid = str(net_client.player_id) if net_client.player_id != null else ""
	if pid == "":
		return
	for pdata in player_list:
		if str(pdata.get("id", "")) != pid:
			continue
		if _adopt_local_spawn_snapshot and (_retry_snapshot_tick < 0 or int(latest_snapshot.get("tick", -1)) >= _retry_snapshot_tick):
			var pawn: Node = players.get(pid)
			if is_instance_valid(pawn) and pawn.has_method("snap_authoritative_position"):
				pawn.snap_authoritative_position()
			if camera:
				camera.fp_yaw = float(pdata["yaw"])
				camera.fp_pitch = float(pdata["pitch"])
				camera.turn_accum = 0.0
				if is_instance_valid(pawn):
					camera.position = pawn.global_position + Vector3(0.0, MoveStep.EYE_HEIGHT - LocalPrediction.FLOOR_OFFSET, 0.0)
			_adopt_local_spawn_snapshot = false
		var hp = int(pdata.get("hp", 100))
		if hp <= 0:
			local_prediction.reset("death", true)
			_clear_predicted_pawn()
		elif local_hp_seen <= 0 and local_hp_seen >= 0:
			local_prediction.reset("respawn", true)
			_clear_predicted_pawn()
			var pawn: Node = players.get(pid)
			if is_instance_valid(pawn) and pawn.has_method("snap_authoritative_position"):
				pawn.snap_authoritative_position()
			if camera:
				camera.fp_yaw = float(pdata["yaw"])
				camera.fp_pitch = float(pdata["pitch"])
				camera.turn_accum = 0.0
				if is_instance_valid(pawn):
					camera.position = pawn.global_position + Vector3(0.0, MoveStep.EYE_HEIGHT - LocalPrediction.FLOOR_OFFSET, 0.0)
		if local_hp_seen >= 0 and hp < local_hp_seen and hp > 0:
			if hud and hud.has_method("show_damage_flash"):
				hud.show_damage_flash()
			if camera:
				camera.camera_punch()
		# Respawn: hp jumped back up while we were playing.
		if local_hp_seen >= 0 and local_hp_seen <= 0 and hp > 0:
			if hud and hud.has_method("show_spawn_flash"):
				hud.show_spawn_flash()
		if camera and hp > 0 and _retry_snapshot_tick >= 0 and int(latest_snapshot.get("tick", -1)) >= _retry_snapshot_tick:
			# Mission state precedes the restored body. Adopt that body's facing
			# before another local action can overwrite it with the death view.
			camera.fp_yaw = float(pdata["yaw"])
			camera.fp_pitch = float(pdata["pitch"])
			camera.turn_accum = 0.0
			_retry_snapshot_tick = -1
		local_hp_seen = hp
		# The number a player actually needs. It was never on screen.
		if hud and hud.has_method("set_vitals"):
			hud.set_vitals(hp, int(pdata.get("armor", 0)))
		var weapon = str(pdata.get("weapon", ""))
		if hud and hud.has_method("set_fp_weapon"):
			hud.set_fp_weapon(weapon)
		if hud and hud.has_method("set_followed_weapon"):
			hud.set_followed_weapon(weapon, str(pdata.get("name", "YOU")), "")
		return

func _process_shot_results(results, tick: int) -> void:
	if results == null or typeof(results) != TYPE_ARRAY:
		return
	if results.size() > ShotEffects.MAX_RESULTS or tick <= last_shot_tick:
		return
	last_shot_tick = tick
	if shot_effects != null:
		shot_effects.ingest(tick, results)
	var my_id = str(net_client.player_id) if net_client.player_id != null else ""
	var followed_id = "" if is_human_player else _followed_player_id()
	var feedback_viewport: Viewport = get_viewport()
	var feedback_camera: Camera3D = feedback_viewport.get_camera_3d() if feedback_viewport != null else null
	var feedback_pawn: Node = players.get(my_id)
	var feedback_fp: bool = is_human_player and not role_transition \
		and net_client.connection_state == WebSocketPeer.STATE_OPEN and local_fp_pawn_id == my_id \
		and is_instance_valid(feedback_pawn) and camera != null and bool(camera.get("fp_mode")) \
		and is_instance_valid(feedback_camera) and not _awaiting_map and not _opening_release \
		and _retry_snapshot_tick < 0 and not is_instance_valid(opening) \
		and not is_instance_valid(interlude) and not is_instance_valid(campaign_results) \
		and get_node_or_null("LoadingCard") == null \
		and (local_hp_seen <= 0 or not _mission_controls_blocked())
	if incoming_feedback != null:
		incoming_feedback.ingest(tick, results, my_id,
			feedback_camera.global_transform if is_instance_valid(feedback_camera) else Transform3D.IDENTITY,
			feedback_fp, local_hp_seen > 0)
	_play_shot_impacts(results)
	# A scatter blast arrives as one result per struck fighter plus one for its
	# missed pellets. A fighter fires at most once a tick, so fold each
	# shooter's results into one shot: one flash, one kick, one summed marker.
	var shots: Array[Dictionary] = []
	var by_shooter: Dictionary = {}
	for result in results:
		if typeof(result) != TYPE_DICTIONARY:
			continue
		var key: String = str(result.get("shooter_id", ""))
		if not by_shooter.has(key):
			by_shooter[key] = shots.size()
			shots.append(result.duplicate())
			continue
		var folded: Dictionary = shots[by_shooter[key]]
		if bool(result.get("hit", false)):
			folded["damage"] = int(folded.get("damage", 0)) * int(bool(folded.get("hit", false))) + int(result.get("damage", 0))
			folded["hit"] = true
	for shot: Dictionary in shots:
		var shooter_id = str(shot.get("shooter_id", ""))
		var hit = bool(shot.get("hit", false))
		var dmg = int(shot.get("damage", 0))
		var is_local = is_human_player and my_id != "" and shooter_id == my_id
		var is_followed = (not is_human_player) and followed_id != "" and shooter_id == followed_id
		var shooter: Node = players.get(shooter_id)
		var wpn: String = _shot_weapon(shot)
		# A pickup can change held equipment after the shot resolves in this tick.
		if is_instance_valid(shooter):
			shooter.show_muzzle_flash(wpn)
		if not is_local and not is_followed:
			continue
		# Every shot you take kicks the view model and lights the barrel. This
		# used to happen only when you missed, so landing a shot was the one
		# case where pulling the trigger looked like nothing happened.
		if (is_local or (is_followed and camera.is_observing_first_person())) and hud and hud.has_method("show_fire_juice"):
			hud.show_fire_juice(wpn)
		if hit and dmg > 0:
			if hud and hud.has_method("show_hit_marker"):
				hud.show_hit_marker(dmg, wpn)

## The gun a resolved shot was fired with: the trace's weapon when present,
## otherwise what the shooter holds now.
func _shot_weapon(shot: Dictionary) -> String:
	var shooter: Node = players.get(str(shot.get("shooter_id", "")))
	var wpn: String = shooter.get_weapon_name() if is_instance_valid(shooter) else ""
	var trace: Variant = shot.get("trace")
	if trace is Dictionary and trace.get("weapon") is String and trace["weapon"] in EquipmentState.WEAPONS:
		wpn = str(trace["weapon"]).capitalize()
	return wpn

## Each struck fighter answers once per tick with the impact of the gun that
## hit it. A Shotgun's pellets on one body are one impact, not seven.
func _play_shot_impacts(results: Array) -> void:
	var struck: Dictionary[String, bool] = {}
	for result: Variant in results:
		if typeof(result) != TYPE_DICTIONARY or not bool(result.get("hit", false)) \
				or int(result.get("damage", 0)) <= 0:
			continue
		var target_id: String = str(result.get("target_id", ""))
		if target_id.is_empty() or struck.has(target_id):
			continue
		var target: Node = players.get(target_id)
		if not is_instance_valid(target) or not target.has_method("play_impact"):
			continue
		struck[target_id] = true
		target.play_impact(_shot_weapon(result))

func _local_weapon_name() -> String:
	var pid = str(net_client.player_id) if net_client.player_id != null else ""
	if pid != "" and players.has(pid) and is_instance_valid(players[pid]):
		if players[pid].has_method("get_weapon_name"):
			return players[pid].get_weapon_name()
	return ""

## The fighter whose eyes this client is using. Empty in a chase view.
func _first_person_carrier_id() -> String:
	if is_human_player:
		var pid: String = local_fp_pawn_id
		if pid == "":
			pid = str(net_client.player_id) if net_client != null and net_client.player_id != null else ""
		if pid != "" and players.has(pid) and is_instance_valid(players[pid]):
			return pid
		return ""
	if camera != null and camera.has_method("is_observing_first_person") and camera.is_observing_first_person():
		return _followed_player_id()
	return ""

## The side whose view this is: the joined fighter's own, kept through death,
## or empty for a spectator.
func _sabotage_viewer_team() -> String:
	return _sabotage_team if is_human_player else ""


## Whose eyes this view looks through: the living joined fighter, or the
## fighter a camera follows in first person.
func _sabotage_eyes_id() -> String:
	if is_human_player:
		if _sabotage_watching_mates and camera != null and camera.is_observing_first_person():
			return _followed_player_id()
		return _first_person_carrier_id()
	if camera != null and camera.is_observing_first_person():
		return _followed_player_id()
	return ""


## A fallen Sabotage fighter watches living teammates only, in first person or
## the follow camera, until the next round puts them back in their own eyes.
func _sabotage_watch_targets(targets: Array, player_list: Array, round_state: String) -> Array:
	if not hud.sabotage() or not is_human_player:
		_sabotage_watching_mates = false
		return targets
	var my_id: String = str(net_client.player_id) if net_client.player_id != null else ""
	var alive: bool = false
	for player_data: Variant in player_list:
		if player_data is Dictionary and str(player_data.get("id", "")) == my_id:
			alive = true
			_sabotage_team = MatchRules.valid_team(player_data.get("team"))
	var watching: bool = not alive and round_state == "Active" and _sabotage_team != ""
	if watching != _sabotage_watching_mates:
		_sabotage_watching_mates = watching
		if camera != null:
			if watching:
				camera.set_fp_mode(false)
				camera.follow_mode = true
				camera.spectator_first_person = true
				# Their own gun must not sit over a teammate's eyes.
				if hud.has_method("set_fp_juice"):
					hud.set_fp_juice(false)
			else:
				_refresh_fp_target()
	if not watching:
		return targets
	var mates: Array = []
	for pawn: Variant in targets:
		if is_instance_valid(pawn) and str(pawn.get("team")) == _sabotage_team:
			mates.append(pawn)
	return mates


func _apply_sabotage(data: Dictionary) -> void:
	if arena_sabotage == null or sabotage_layout.is_empty():
		return
	var state: Dictionary = data.get("sabotage") if data.get("sabotage") is Dictionary else {}
	var carriers: Dictionary = {}
	var charge: Variant = state.get("charge")
	var carrier_id: String = str(charge.get("carrier", "")) if charge is Dictionary else ""
	if carrier_id != "" and players.has(carrier_id) and is_instance_valid(players[carrier_id]):
		carriers[carrier_id] = players[carrier_id]
	if state.get("phase") == "planted":
		_sabotage_charge_ticks = maxi(_sabotage_charge_ticks if _sabotage_charge_ticks > 0 else 1, int(state.get("clock_ticks", 0)))
	elif state.get("phase") == "live" or state.get("phase") == "muster":
		_sabotage_charge_ticks = 1
	var eyes: String = _sabotage_eyes_id()
	arena_sabotage.set_charge_ticks(_sabotage_charge_ticks)
	arena_sabotage.set_first_person(eyes)
	arena_sabotage.apply(state, carriers, _sabotage_viewer_team())
	var progress: Variant = state.get("progress")
	var owner: bool = progress is Dictionary and eyes != "" and str(progress.get("player_id", "")) == eyes
	var prompt: String = ""
	var my_id: String = str(net_client.player_id) if is_human_player and net_client.player_id != null else ""
	if my_id != "" and not owner:
		for player_data: Variant in data.get("players", []):
			if player_data is Dictionary and str(player_data.get("id", "")) == my_id and int(player_data.get("hp", 0)) > 0:
				# The prompt reads horizontal distance only.
				var feet: Vector3 = Vector3(float(player_data.get("x", 0.0)), 0.0, float(player_data.get("z", 0.0)))
				prompt = SabotageState.use_prompt(state, sabotage_layout, my_id, _sabotage_team, feet)
	hud.set_sabotage_state(state, _sabotage_viewer_team(), _sabotage_charge_ticks, owner, carrier_id != "" and carrier_id == eyes, prompt)


func _on_sabotage_event(data: Dictionary) -> void:
	var kind: String = str(data.get("kind", ""))
	var line: String = SabotageState.event_line(data, _sabotage_viewer_team())
	if not line.is_empty():
		var color: Color = MatchRules.COALITION_LABEL if kind in ["charge_taken", "charge_dropped", "plant_started", "planted", "detonated"] else MatchRules.UNION_LABEL
		hud.combat_feed.push(line, color)
	if kind in ["plant_started", "defuse_started"] and arena_sabotage != null:
		arena_sabotage.play_arm_cue()
	if kind == "sides_swapped":
		var job: String = ""
		if is_human_player and _sabotage_team != "":
			# The swap lands before this client's next snapshot names the new side.
			job = tr("SABOTAGE_JOB_DEFEND") if _sabotage_team == "coalition" else tr("SABOTAGE_JOB_ATTACK")
		var notice: String = tr("SABOTAGE_SWAPPED")
		if job != "":
			notice += "\n" + tr("SABOTAGE_SWAPPED_JOB").format({"job": job})
		_sabotage_swap_notice = notice


func _carried_flag_team(subject: String, flags: Variant) -> String:
	if subject == "" or not flags is Array:
		return ""
	for flag: Variant in flags:
		if not flag is Dictionary:
			continue
		if str(flag.get("status", "")) != "carried" or str(flag.get("carrier", "")) != subject:
			continue
		return MatchRules.valid_team(flag.get("team"))
	return ""

func _followed_player_id() -> String:
	if not camera or not camera.has_method("get_followed_target"):
		return ""
	var followed = camera.get_followed_target()
	if followed != null and is_instance_valid(followed) and "player_id" in followed:
		return str(followed.player_id)
	return ""

func _followed_weapon_name() -> String:
	if not camera or not camera.has_method("get_followed_target"):
		return ""
	var followed = camera.get_followed_target()
	if followed != null and is_instance_valid(followed) and followed.has_method("get_weapon_name"):
		return followed.get_weapon_name()
	return ""
