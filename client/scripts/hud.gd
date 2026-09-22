extends CanvasLayer

const StanceChipScript = preload("res://scripts/stance_chip.gd")

## Fired whenever the Host takes the air so the radio can duck underneath.
signal host_spoke(seconds: float)

@onready var status_label = $Panel/VBoxContainer/StatusLabel
@onready var tick_label = $Panel/VBoxContainer/TickLabel
@onready var player_count_label = $Panel/VBoxContainer/PlayerCountLabel
@onready var mode_label = $Panel/VBoxContainer/ModeLabel
@onready var round_label = $Panel/VBoxContainer/RoundLabel
@onready var weapon_label = $Panel/VBoxContainer/WeaponLabel
@onready var combat_feed: CombatFeed = $CombatFeed
@onready var round_message = $RoundMessage
@onready var scoreboard = $Panel/VBoxContainer/Scoreboard
@onready var weapon_icon = $WeaponIcon
@onready var weapon_icon_bg = $WeaponIconBg
@onready var crosshair = $Crosshair
@onready var damage_flash = $DamageFlash
@onready var spawn_flash = $SpawnFlash
@onready var streak_flash = $StreakFlash
@onready var fp_weapon = $FpWeapon
@onready var fp_muzzle = $FpMuzzle
@onready var vitals = $Vitals
@onready var health_value = $Vitals/HealthValue
@onready var health_bar = $Vitals/HealthBar
@onready var armor_value = $Vitals/ArmorValue
@onready var armor_bar = $Vitals/ArmorBar
@onready var chrome_strip = $ChromeStrip
@onready var on_air_badge = $OnAirBadge
@onready var contested_frequency_badge = $ContestedFrequencyBadge
@onready var hangar_candy_badge = $HangarCandyBadge
var map_chip_label: Label = null
@onready var warmup_tv = $WarmupTv
var crosshair_hbar = null
var crosshair_vbar = null
var crosshair_dot = null
## Dark rectangles sitting behind each crosshair part. A cream crosshair over a
## tan floor is invisible, which is how a one pixel plus disappeared exactly
## where a player was aiming.
var crosshair_edges: Dictionary = {}
const CROSSHAIR_EDGE_PAD: float = 2.0
var hit_marker = null
var damage_numbers = null

var scores = {}
var behaviors = {}
var ghost_rival = ""
var leader_name = ""
var host_bumper_index = 0
var league_mode_name = "Contested Frequency"
var league_playlist = "Arena Duel"
var map_label = "Arena Duel"
var pressure_id = ""
var sticky_host_line = ""
var host_line_seen = false
var client_mode = "SPECTATING"
## Milliseconds the control legend stays up after joining, then it gets out of the way.
const CONTROLS_HINT_MS: int = 8000

## Broadcast ident (the top strip, ON AIR, the station badge). Off by default:
## it is right for a let's-play capture and wrong for playing. See
## _update_broadcast_chrome.
var broadcast_chrome: bool = false

## Connection status, wall clock and head count. Debug furniture, off.
var debug_telemetry: bool = false
var mode_entered_ms: int = 0
var episode_id = ""
var episode_title = ""
var episode_objective = ""
var episode_progress = ""
var episode_phase = ""
var episode_title_shown = false
var round_chrome_state = "Warmup"

const HOST_BUMPERS = [
	"HOST: CONTESTED FREQUENCY. LEAGUE DENIES EXISTENCE.",
	"HOST: ARENA DUEL UNDER THE LIE. LIVE LAUGH FRAG.",
	"HOST: CONTINUANCE WATCHES. YOU SHOOT.",
	"HOST: SHALL NOT BE INFRINGED. OPEN WEIGHTS. OPEN FIRE.",
	"HOST: PORT 6767 ENERGY. DENY EVERYTHING.",
]

var weapon_textures = {}
var viewmodel_textures: Dictionary[String, Texture2D] = {
	"Fists": preload("res://assets/weapons/viewmodels/wpn_fists_0.png"),
	"Tack": preload("res://assets/weapons/viewmodels/px_tack_issued_0.png"),
	"Flechette": preload("res://assets/weapons/viewmodels/wpn_flechette_0.png"),
	"Rail": preload("res://assets/weapons/viewmodels/px_rail_issued_0.png"),
	"Scatter": preload("res://assets/weapons/viewmodels/wpn_scatter_0.png"),
}
var followed_player_name = ""
var fp_juice_enabled = false
var fp_bob_t = 0.0
var fp_walk_speed: float = 0.0
var fp_bob_weight: float = 0.0
# The bottom of each full-canvas sprite is cut off. It must stay below the
# viewport, including the largest upward bob (5.4 pixels) and pixel rounding.
const FP_BOTTOM_OVERLAP: float = 12.0
var head_bob_enabled: bool = true
var reticle_colour: Color = Color("e8e2d6")
var damage_flash_timer = 0.0
var spawn_flash_timer = 0.0
var streak_flash_timer = 0.0
var hit_marker_timer = 0.0
var round_banner_remaining: float = 0.0
var fp_kick_timer = 0.0
## Seconds the first-person muzzle flash stays up. Short: it is a flash, and a
## player sees it for the frame or two that the shot leaves the barrel.
var fp_muzzle_timer: float = 0.0
var fp_muzzle_texture: Texture2D
var fp_kick_amount = Vector2.ZERO
var current_fp_weapon = ""
var equipment_hud: EquipmentHud
var melee_view: MeleeView
const FP_MUZZLE_SECONDS: float = 0.07
## Full width of the vitals bars, so a fill can be scaled against it.
const HEALTH_BAR_WIDTH: float = 200.0
const ARMOR_BAR_WIDTH: float = 100.0
## What the server considers a full fighter.
const PLAYER_MAX_HP: int = 100
const PLAYER_MAX_ARMOR: int = 100
var floating_damage_nodes = []

# Full-frame Warmup Contested Frequency TV bumper (unmissable scrap open).
var warmup_tv_veil = null
var warmup_tv_league = null
var warmup_tv_map = null
var warmup_tv_countdown = null
var warmup_tv_roster = null
var warmup_tv_host = null
var warmup_tv_active = false
var warmup_tv_roster_names = []
var warmup_tv_secs = 0
var warmup_tv_host_line = ""

func _ready():
	equipment_hud = EquipmentHud.new()
	equipment_hud.name = "Equipment"
	add_child(equipment_hud)
	melee_view = MeleeView.new()
	melee_view.name = "MeleeView"
	add_child(melee_view)
	_load_display_settings()
	_ensure_map_chip_label()
	if vitals:
		vitals.visible = false
	fp_muzzle_texture = load("res://assets/vfx/32/muzzle_flash.png")
	if fp_muzzle:
		fp_muzzle.texture = fp_muzzle_texture
		fp_muzzle.visible = false
	weapon_textures["Flechette"] = load("res://assets/weapons/32/flechette.png")
	weapon_textures["Rail"] = load("res://assets/weapons/32/rail.png")
	weapon_textures["Scatter"] = load("res://assets/weapons/32/scatter.png")
	weapon_textures["Tack"] = load("res://assets/weapons/32/_future/shock_pistol.png")
	crosshair_hbar = get_node_or_null("Crosshair/HBar")
	crosshair_vbar = get_node_or_null("Crosshair/VBar")
	crosshair_dot = get_node_or_null("Crosshair/Dot")
	crosshair_edges = {
		crosshair_hbar: get_node_or_null("Crosshair/HBarEdge"),
		crosshair_vbar: get_node_or_null("Crosshair/VBarEdge"),
		crosshair_dot: get_node_or_null("Crosshair/DotEdge"),
	}
	hit_marker = get_node_or_null("HitMarker")
	damage_numbers = get_node_or_null("DamageNumbers")

	if round_message:
		round_message.text = ""
		round_message.visible = false
	if weapon_label:
		weapon_label.text = ""
	if weapon_icon:
		weapon_icon.visible = false
		if weapon_icon_bg:
			weapon_icon_bg.visible = false
	set_mode("SPECTATING")
	update_scoreboard()
	if crosshair:
		crosshair.visible = false
	if damage_flash:
		damage_flash.visible = false
		damage_flash.modulate.a = 0.0
	if spawn_flash:
		spawn_flash.visible = false
		spawn_flash.modulate.a = 0.0
	if streak_flash:
		streak_flash.visible = false
		streak_flash.modulate.a = 0.0
	if fp_weapon:
		fp_weapon.visible = false
	_update_broadcast_chrome("Warmup")
	_bind_warmup_tv()

func _bind_warmup_tv() -> void:
	if warmup_tv == null:
		warmup_tv = get_node_or_null("WarmupTv")
	if warmup_tv == null:
		return
	warmup_tv_veil = warmup_tv.get_node_or_null("Veil")
	var center = warmup_tv.get_node_or_null("Center")
	if center:
		warmup_tv_league = center.get_node_or_null("LeagueLabel")
		warmup_tv_map = center.get_node_or_null("MapTitle")
		warmup_tv_countdown = center.get_node_or_null("Countdown")
		warmup_tv_roster = center.get_node_or_null("RosterChips")
		warmup_tv_host = center.get_node_or_null("HostLine")
	warmup_tv.visible = false
	warmup_tv_active = false


func _ensure_map_chip_label() -> void:
	# Bottom-left map chip must show Snapshot map_name (Larak Lot), never the
	# static Hangar Candy brand texture strangers read as the map name.
	if map_chip_label != null and is_instance_valid(map_chip_label):
		return
	map_chip_label = Label.new()
	map_chip_label.name = "MapChipLabel"
	map_chip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_chip_label.add_theme_font_size_override("font_size", 18)
	map_chip_label.add_theme_color_override("font_color", Color(0.96, 0.90, 0.72, 0.95))
	map_chip_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 1))
	map_chip_label.add_theme_constant_override("outline_size", 4)
	map_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	map_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	map_chip_label.anchor_top = 1.0
	map_chip_label.anchor_bottom = 1.0
	map_chip_label.anchor_left = 0.0
	map_chip_label.anchor_right = 0.0
	map_chip_label.offset_left = 16.0
	map_chip_label.offset_top = -72.0
	map_chip_label.offset_right = 280.0
	map_chip_label.offset_bottom = -16.0
	map_chip_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(map_chip_label)
	_refresh_map_chip_badge()


func _refresh_map_chip_badge() -> void:
	_ensure_map_chip_label()
	if map_chip_label:
		map_chip_label.text = map_label.to_upper()
		# The venue, in the corner the vitals now own. A player behind a gun
		# knows which map they are on; a spectator tuning in does not, so the
		# chip belongs to the spectator view and to the round bumper.
		map_chip_label.visible = map_label != "" and client_mode == "SPECTATING"
	# Hide brand Hangar Candy art so it cannot impersonate the map chip.
	if hangar_candy_badge:
		hangar_candy_badge.visible = false
	# chrome_strip_hud.png bakes Hangar Candy as a third top chip. During Solo
	# Broadcast (Larak Lot) that reads as a second map name beside MapChipLabel.
	# The strip is also spectator furniture, so it never comes back while a
	# person is playing; this used to re-show it after the chrome decided not to.
	if chrome_strip:
		var solo_larak = map_label.strip_edges().to_lower() == "larak lot"
		chrome_strip.visible = broadcast_chrome and not solo_larak and client_mode == "SPECTATING"


func set_status(text: String):
	if status_label:
		status_label.text = "Status: " + text

func set_league_identity(mode_name: String, playlist: String):
	if mode_name != "":
		league_mode_name = mode_name
	if playlist != "":
		league_playlist = playlist
	_refresh_mode_label()
	update_scoreboard()

func set_map_name(name: String):
	if name != "":
		map_label = name
	_refresh_map_chip_badge()
	_refresh_mode_label()

func set_pressure(pressure: String):
	pressure_id = pressure
	_refresh_mode_label()

func set_mode(mode: String):
	if mode != client_mode:
		mode_entered_ms = Time.get_ticks_msec()
	client_mode = mode
	_refresh_mode_label()
	_refresh_telemetry_lines()
	_refresh_map_chip_badge()
	_update_broadcast_chrome(round_chrome_state)

## Connection status, wall clock, and head count are for whoever is debugging
## the client, not for anybody looking at the game. The round line already
## carries the clock and the scoreboard already carries the head count, so
## these three lines are three copies of nothing wherever they appear.
##
## They used to be hidden only while playing, which meant a spectator opened on
## "Status: Connected to server / Time: 16s / Fighters: 3" stacked above five
## more chips. Watching a match is not debugging one.
func _refresh_telemetry_lines() -> void:
	for node in [status_label, tick_label, player_count_label]:
		if node:
			node.visible = debug_telemetry

func _refresh_mode_label():
	if not mode_label:
		return
	# The league and the playlist are how a spectator knows what they tuned
	# into. A player picked the match and is standing in it.
	var league = ""
	if client_mode == "SPECTATING":
		league = league_mode_name.to_upper() + " // " + league_playlist.to_upper()
	# The map name is already on screen as its own chip. It used to be here as
	# well, and inside the playlist above, so the first visual QA tour
	# photographed three copies of "ARENA DUEL" in a single frame.
	var host_chip = ""
	if sticky_host_line != "" and broadcast_chrome:
		host_chip = "
" + sticky_host_line
	# A spectator needs to know how to join. A player who has joined needs the
	# screen. The legend shows for a few seconds after joining and then gets out
	# of the way; it belongs in a settings screen once there is one.
	# Two rules here, both learned from a screenshot.
	#
	# It times out in every mode. The spectator legend used to be permanent
	# while the playing one expired, so the view you sit in longest was the one
	# that never stopped explaining itself. Eight lines of chrome in the corner
	# of a match is not a HUD, it is a manual.
	#
	# And it leads with the mouse and keyboard. It used to open with "J/A" and
	# "RT/A: Fire", which names the gamepad binding first and the mouse never,
	# so a player on a laptop could read the whole line and still not know what
	# fires the gun. The full scheme lives on the loading card and in settings.
	var controls = ""
	if Time.get_ticks_msec() - mode_entered_ms < CONTROLS_HINT_MS:
		if client_mode == "SPECTATING":
			controls = "
J join   F fighter   V view   ~ console"
		else:
			controls = "
Mouse or Ctrl fire   WASD move   Wheel or 1-5 weapon   L leave"
	# The Host line already says a drone is on deck, in its own words, directly
	# above. Saying it again underneath is the same sentence twice.
	var pressure_chip = ""
	if sticky_host_line == "":
		if pressure_id == "compliance_drone":
			pressure_chip = "
PRESSURE: CONTINUANCE COMPLIANCE DRONE"
		elif pressure_id == "compliance":
			pressure_chip = "
PRESSURE: CONTINUANCE COMPLIANCE"
	var episode_chip = ""
	if episode_title != "":
		episode_chip = "
" + episode_title.to_upper()
		if episode_objective != "":
			episode_chip += "
OBJ: " + episode_objective
		if episode_progress != "":
			episode_chip += "
" + episode_progress
	mode_label.text = league + host_chip + controls + pressure_chip + episode_chip

func set_tick(tick: int):
	if tick_label:
		var seconds = tick / 20
		tick_label.text = "Time: " + str(seconds) + "s"

func set_round_info(state: String, time_left: int, frag_limit: int):
	round_chrome_state = state
	_update_broadcast_chrome(state)
	if not round_label:
		return
	var text = "Round: " + state
	if state == "Active":
		if episode_title != "":
			text = episode_title.to_upper()
			if episode_progress != "":
				text += "\n" + episode_progress
			elif episode_objective != "":
				text += "\n" + episode_objective
			if time_left > 0:
				text += " | " + str(time_left) + "s"
		elif frag_limit > 0:
			# The map name is its own chip in the corner. This line is the race,
			# not the venue.
			text = "FIRST TO " + str(frag_limit)
			if time_left > 0:
				text += " | " + str(time_left) + "s"
		elif time_left > 0:
			text += " | Time: " + str(time_left) + "s"
		# Who is leading is the first row of the scoreboard directly below, and
		# so is the rival. Spelling both out here was two lines of the panel
		# repeating the two lines under them.
		if pressure_id == "compliance_drone":
			text += "\nARTICLE 7 ENFORCEMENT"
		elif pressure_id == "compliance":
			text += "\nAPPROVED LANES ONLY"
	elif state == "Warmup":
		text = "WARMUP // " + map_label.to_upper()
		if time_left > 0:
			text += " // GOES LIVE IN " + str(time_left)
		else:
			text += " // Contested Frequency tuning in"
	elif state == "Ended":
		text = "ROUND OVER - podium holds"
		if leader_name != "":
			text += "\nMVP: " + leader_name
	round_label.text = text

func set_player_count(count: int):
	if player_count_label:
		player_count_label.text = "Fighters: " + str(count)

const HUD_SCOREBOARD_ROWS: int = 4

func update_scoreboard():
	if not scoreboard:
		return
	var sorted_scores = []
	for player in scores.keys():
		sorted_scores.append({"name": player, "kills": scores[player]})
	sorted_scores.sort_custom(func(a, b): return a.kills > b.kills)
	# No headers. The league and the playlist are already the first line of
	# the panel, so repeating them above the names was two more lines saying
	# what the player had just read.
	var text = ""
	# Four names, not the whole roster. Eight ran the panel off the bottom of
	# the window, which the first visual QA tour caught, and a standing HUD is
	# for who is winning. The full table belongs on the scoreboard screen.
	for i in range(min(HUD_SCOREBOARD_ROWS, len(sorted_scores))):
		var entry = sorted_scores[i]
		var chip = ""
		if behaviors.has(entry.name):
			chip = " [" + _short_behavior(behaviors[entry.name]) + "]"
		var marker = "*" if i == 0 and entry.kills > 0 else " "
		text += str(i + 1) + "." + marker + entry.name + chip + ": " + str(entry.kills) + "\n"
	scoreboard.text = text if len(sorted_scores) > 0 else "(waiting for scrap)"

func _short_behavior(behavior: String) -> String:
	return StanceChipScript.short(behavior)

func sync_scores_from_players(player_list: Array):
	var next_scores = {}
	var next_behaviors = {}
	for player_data in player_list:
		var pname = str(player_data.get("name", "?"))
		next_scores[pname] = int(player_data.get("score", 0))
		var beh = player_data.get("behavior", null)
		if beh != null:
			next_behaviors[pname] = str(beh)
	scores = next_scores
	behaviors = next_behaviors
	leader_name = ""
	var best = -1
	for pname in scores.keys():
		if scores[pname] > best:
			best = scores[pname]
			leader_name = pname + " (" + str(best) + ")"
	if best <= 0:
		leader_name = ""
	update_scoreboard()

func set_ghost_rival(rival: String):
	ghost_rival = rival


func set_episode_chrome(ep_id: String, title: String, objective: String, progress: String, phase: String):
	# Solo Broadcast face: title + objective chip. Silly booth, not wiki.
	var prev_progress = episode_progress
	episode_id = ep_id
	episode_title = title
	episode_objective = objective
	episode_progress = progress
	episode_phase = phase
	_refresh_mode_label()
	if title != "" and not episode_title_shown and round_message:
		episode_title_shown = true
		show_episode_title_card(title, objective)
	# Host-per-NODS-tick: flash when progress advances under nods phase.
	# Skip empty first paint (join / cold open) and jammer+ handoff.
	if phase == "nods" and progress != "" and prev_progress != "" and progress != prev_progress:
		show_nods_tick(progress, sticky_host_line)

func show_episode_title_card(title: String, objective: String = ""):
	round_banner_remaining = 0.0
	if not round_message:
		return
	round_message.visible = true
	var line = title.to_upper()
	if objective != "":
		line += "\n" + objective
	line += "\nLARAK LOT // YOU'RE ON THE AIR"
	round_message.text = line
	await get_tree().create_timer(3.2).timeout
	if round_message and episode_phase != "won" and episode_phase != "failed":
		round_message.visible = false

func show_nods_tick(progress: String, host_line: String = ""):
	round_banner_remaining = 0.0
	# Short Contested Frequency booth beat per NODS clear. Not speak. Not killstreak length.
	flash_broadcast_chrome("host")
	streak_flash_timer = 0.32
	if streak_flash:
		streak_flash.visible = true
		streak_flash.modulate = Color(1.0, 0.78, 0.28, 0.42)
	if not round_message:
		return
	var line = host_line
	if line == "":
		line = "HOST: " + progress
	round_message.text = line + "\n" + progress
	round_message.visible = true
	var tween = create_tween()
	tween.tween_property(round_message, "scale", Vector2(1.18, 1.18), 0.08)
	tween.tween_property(round_message, "scale", Vector2(1.0, 1.0), 0.14)
	await get_tree().create_timer(1.35).timeout
	if is_instance_valid(round_message) and episode_phase == "nods":
		round_message.visible = false

func show_episode_complete(host_line: String, unlock_teaser: String = ""):
	round_banner_remaining = 0.0
	if not round_message:
		return
	round_message.visible = true
	var line = host_line if host_line != "" else "HOST: Amen, fistbump. Frequency still unmetered."
	if unlock_teaser != "":
		line += "\n" + unlock_teaser
	round_message.text = line
	streak_flash_timer = 0.7
	if streak_flash:
		streak_flash.visible = true
		streak_flash.modulate = Color(1.0, 0.85, 0.3, 0.55)

func show_episode_fail(host_line: String):
	round_banner_remaining = 0.0
	# Comedy fail splash, not a lecture.
	if not round_message:
		return
	round_message.visible = true
	var line = host_line if host_line != "" else "HOST: Citizen Handle assigned. Reload."
	round_message.text = line + "\n( Continuance paperwork is the real final boss )"
	if damage_flash:
		damage_flash.visible = true
		damage_flash.modulate = Color(0.6, 0.15, 0.55, 0.45)
		damage_flash_timer = 0.8

func show_frag(killer: String, victim: String, killer_color: Color = Color.WHITE, _victim_color: Color = Color.WHITE) -> void:
	if not scores.has(killer):
		scores[killer] = 0
	scores[killer] += 1
	update_scoreboard()
	combat_feed.push(killer + " > " + victim, killer_color.lightened(0.4))

func reset_host_chrome():
	# Clear sticky Host + flash latch so a reconnect mid-round can flash once again.
	sticky_host_line = ""
	host_line_seen = false
	episode_progress = ""
	hide_warmup_tv()
	_refresh_mode_label()


## Standalone previews load their own store. Live changes use the same reader.
func _load_display_settings() -> void:
	var settings: FragrSettings = FragrSettings.for_tree(get_tree())
	settings.load_from_disk()
	apply_preferences(settings)

func apply_preferences(settings: FragrSettings) -> void:
	broadcast_chrome = bool(settings.get_value("gameplay", "broadcast_chrome"))
	debug_telemetry = bool(settings.get_value("gameplay", "debug_telemetry"))
	head_bob_enabled = bool(settings.get_value("gameplay", "head_bob"))
	reticle_colour = settings.reticle_colour()


func _update_broadcast_chrome(state: String) -> void:
	# The broadcast ident is off unless somebody asks for it.
	#
	# It was a 72 pixel strip pinned across the top of the screen with a red ON
	# AIR box in it, and it was the highest-contrast thing in every spectator
	# frame the visual QA tour has ever taken. The station is a thread through
	# the world and not the world, and a network ident does not get to be the
	# first thing the eye lands on in a screenshot of a shooter.
	#
	# It is kept rather than deleted because a broadcast overlay is genuinely
	# right for a let's-play capture, where the viewer is watching a programme.
	# It is simply not right for playing or for the README, so it is a setting
	# that defaults to off instead of furniture that defaults to on.
	var warm = state == "Warmup"
	var live = state == "Active"
	var ended = state == "Ended"
	# Do not re-show the Hangar Candy strip during Solo Broadcast / Larak Lot.
	var solo_larak = map_label.strip_edges().to_lower() == "larak lot"
	var spectating = client_mode == "SPECTATING"
	var strip_shown = (
		broadcast_chrome
		and chrome_strip != null
		and not solo_larak
		and spectating
	)
	if chrome_strip:
		chrome_strip.visible = strip_shown
		var a = 0.92 if live else (0.88 if warm else 0.7)
		chrome_strip.modulate = Color(1, 1, 1, a)
	# The strip already bakes ON AIR and Contested Frequency, the same way it
	# bakes Hangar Candy. Drawing the loose badges underneath it put both marks
	# on screen twice, which the first visual QA tour caught. They are the
	# fallback for when the strip is not up, not a second copy of it.
	if on_air_badge:
		on_air_badge.visible = broadcast_chrome and live and not strip_shown and spectating
		if on_air_badge.visible:
			on_air_badge.modulate = Color(1, 1, 1, 0.95)
	if contested_frequency_badge:
		# Warm on Warmup / Host face; quieter while live so ON AIR owns the scrap.
		contested_frequency_badge.visible = broadcast_chrome and not strip_shown and spectating
		var ca = 0.95 if warm else (0.72 if live else 0.8)
		contested_frequency_badge.modulate = Color(0.95, 0.95, 0.98, ca)
	# Map chip is Snapshot map_name (see _refresh_map_chip_badge). Never re-show
	# the Hangar Candy brand texture as if it were the map name.
	if hangar_candy_badge:
		hangar_candy_badge.visible = false
	_refresh_map_chip_badge()

func flash_broadcast_chrome(kind: String = "host") -> void:
	# Brief badge lift on Host / Warmup bumper without neon wash.
	var badge = contested_frequency_badge
	# A flash must never be a way back in for chrome that is switched off. This
	# line used to set visible unconditionally, so a Host bumper would put the
	# red ON AIR box back on screen no matter what the rest of the file decided.
	if not broadcast_chrome:
		return
	if kind == "on_air":
		badge = on_air_badge
		if on_air_badge:
			on_air_badge.visible = true
	elif kind == "hangar":
		# Pulse the Snapshot map chip, not the retired Hangar Candy brand art.
		_refresh_map_chip_badge()
		badge = map_chip_label
	if badge == null:
		return
	var base_a = badge.modulate.a
	badge.modulate.a = minf(base_a + 0.15, 1.0)
	var tween = create_tween()
	tween.tween_property(badge, "modulate:a", base_a, 0.45)

func set_host_line(line: String, flash_on_first: bool = false) -> bool:
	# Returns true when this call triggered the one-shot mid-join Host flash.
	if line == "":
		return false
	sticky_host_line = line
	_refresh_mode_label()
	if flash_on_first and not host_line_seen:
		host_line_seen = true
		show_host_join(line)
		return true
	return false

func show_host_join(host_line: String) -> void:
	combat_feed.push(host_line)

func show_warmup_bumper(host_line: String, secs_left: int = 0, roster = []):
	round_banner_remaining = 0.0
	host_spoke.emit(3.0)
	# Warmup / pre-round Host drama: roster + map bumper readable before RoundStart.
	flash_broadcast_chrome("host")
	# Unmissable full-frame Contested Frequency Warmup TV bumper.
	_apply_warmup_tv(host_line, secs_left, roster, false)
	# Fallback only when WarmupTv nodes are missing (headless / old scene).
	if warmup_tv == null and round_message:
		var line = host_line
		if line == "":
			line = "HOST: CONTESTED FREQUENCY. " + map_label.to_upper() + " TUNES IN."
		var sub = "WARMUP // " + map_label.to_upper()
		if secs_left > 0:
			sub += " // GOES LIVE IN " + str(secs_left)
		round_message.text = line + "\n" + sub
		round_message.visible = true

func refresh_warmup_tv(host_line: String, secs_left: int = 0, roster = []) -> void:
	# Live Warmup Snapshot refresh while the TV is up.
	if not warmup_tv_active:
		return
	_apply_warmup_tv(host_line, secs_left, roster, true)

func hide_warmup_tv() -> void:
	warmup_tv_active = false
	warmup_tv_secs = 0
	warmup_tv_roster_names = []
	warmup_tv_host_line = ""
	if warmup_tv:
		warmup_tv.visible = false
	if round_message and round_message.visible and "WARMUP //" in round_message.text:
		round_message.visible = false

func _apply_warmup_tv(host_line: String, secs_left: int, roster, refresh_only: bool) -> void:
	if warmup_tv == null:
		_bind_warmup_tv()
	if warmup_tv == null:
		return
	var line = host_line
	if line == "":
		line = "HOST: CONTESTED FREQUENCY. " + map_label.to_upper() + " TUNES IN."
	warmup_tv_host_line = line
	warmup_tv_secs = max(secs_left, 0)
	if warmup_tv_league:
		warmup_tv_league.text = league_mode_name.to_upper()
	if warmup_tv_map:
		warmup_tv_map.text = map_label.to_upper()
	if warmup_tv_countdown:
		if warmup_tv_secs > 0:
			warmup_tv_countdown.text = "GOES LIVE IN " + str(warmup_tv_secs)
		else:
			warmup_tv_countdown.text = "GOES LIVE"
		warmup_tv_countdown.add_theme_color_override("font_color", Color(1.0, 0.72, 0.22, 1))
	_set_warmup_roster(roster)
	if warmup_tv_host:
		warmup_tv_host.text = line
	warmup_tv_active = true
	warmup_tv.visible = true
	if not refresh_only:
		# Punch scale on first raise so tip capture / spectators feel the open.
		warmup_tv.scale = Vector2(1.0, 1.0)
		var tween = create_tween()
		tween.tween_property(warmup_tv, "scale", Vector2(1.04, 1.04), 0.08)
		tween.tween_property(warmup_tv, "scale", Vector2(1.0, 1.0), 0.14)
		streak_flash_timer = 0.35
		if streak_flash:
			streak_flash.visible = true
			streak_flash.modulate = Color(1.0, 0.72, 0.22, 0.4)

func _set_warmup_roster(roster) -> void:
	var names = []
	if typeof(roster) == TYPE_ARRAY:
		for entry in roster:
			var n = str(entry)
			if n == "" or n == "Spectator":
				continue
			names.append(n)
	warmup_tv_roster_names = names
	if warmup_tv_roster == null:
		return
	if names.size() == 0:
		warmup_tv_roster.text = "SCRAP ROSTER TUNING IN"
		return
	var upper = []
	for n in names:
		upper.append(n.to_upper())
	var shown = upper
	if upper.size() > 6:
		shown = upper.slice(0, 5)
		shown.append("+" + str(upper.size() - 5))
	warmup_tv_roster.text = " // ".join(PackedStringArray(shown))

func show_round_start(round_number: int, host_line: String = "") -> void:
	var line: String = host_line
	if line.is_empty():
		line = HOST_BUMPERS[host_bumper_index % HOST_BUMPERS.size()]
		host_bumper_index += 1
	sticky_host_line = line
	host_line_seen = true
	_refresh_mode_label()
	hide_warmup_tv()
	combat_feed.push(line)
	_show_round_banner(tr("HUD_ROUND_START").format({"round": round_number}), 1.0)

func show_compliance_ping(message: String, _duration_sec: float = 6.0) -> void:
	var line: String = message if not message.is_empty() else tr("HUD_COMPLIANCE")
	sticky_host_line = line
	host_line_seen = true
	_refresh_mode_label()
	combat_feed.push(line)


func show_boss_spawn(message: String, name: String = "COMPLIANCE-DRONE") -> void:
	sticky_host_line = message
	host_line_seen = true
	pressure_id = "compliance_drone"
	_refresh_mode_label()
	combat_feed.push(tr("HUD_BOSS_ARRIVED").format({"name": name}), MenuTheme.EMBER)

func show_boss_down(message: String, killer: String = "") -> void:
	sticky_host_line = message
	host_line_seen = true
	pressure_id = ""
	_refresh_mode_label()
	combat_feed.push(tr("HUD_BOSS_DOWN").format({"killer": killer}), MenuTheme.EMBER)

func show_killstreak(player_name: String, streak: int, _tier: String, _message: String) -> void:
	combat_feed.push(tr("HUD_STREAK").format({"player": player_name, "count": streak}), MenuTheme.EMBER)

func show_speak(player: String, line: String) -> void:
	if not line.is_empty():
		combat_feed.push(player + ": " + line)

func show_round_end(mvp_name: String, reason: String, mvp_frags: int = 0, host_line: String = "", podium = []):
	host_spoke.emit(4.0)
	# Round-end MVP / podium Host drama (Contested Frequency voice).
	scores = {}
	behaviors = {}
	leader_name = mvp_name
	pressure_id = ""
	if host_line != "":
		sticky_host_line = host_line
		host_line_seen = true
	_refresh_mode_label()
	update_scoreboard()

	if weapon_label:
		weapon_label.text = ""
	if weapon_icon:
		weapon_icon.visible = false
		if weapon_icon_bg:
			weapon_icon_bg.visible = false

	followed_player_name = ""

	# Brief ember podium flash (same grit as killstreak).
	streak_flash_timer = 0.55
	if streak_flash:
		streak_flash.visible = true
		streak_flash.modulate = Color(1.0, 0.78, 0.28, 0.55)

	if round_message:
		var message = host_line
		if message == "":
			if mvp_name != "":
				message = "HOST: ROUND MVP. " + mvp_name + " WITH " + str(mvp_frags) + " FRAGS. CONTINUANCE DENIES THE PODIUM."
			else:
				message = "HOST: ROUND CLOSED. NO MVP. LEAGUE DENIES THE SCRAP."
		if reason != "":
			message += "\n" + reason.to_upper()
		# Podium: top three scrap scores.
		var lines = []
		if typeof(podium) == TYPE_ARRAY:
			var n = mini(3, podium.size())
			for i in range(n):
				var row = podium[i]
				var nm = str(row.get("name", "?")) if typeof(row) == TYPE_DICTIONARY else str(row)
				var sc = str(row.get("score", "?")) if typeof(row) == TYPE_DICTIONARY else ""
				var rank = str(i + 1)
				if sc != "":
					lines.append("#" + rank + " " + nm + " " + sc)
				else:
					lines.append("#" + rank + " " + nm)
		if lines.size() > 0:
			message += "\nPODIUM: " + " | ".join(PackedStringArray(lines))
		message += "\n" + league_mode_name.to_upper() + " // " + league_playlist.to_upper()

		_show_round_banner(message, 5.5)

func _show_round_banner(text: String, seconds: float) -> void:
	round_banner_remaining = seconds
	round_message.text = text
	round_message.scale = Vector2.ONE
	round_message.modulate = Color.WHITE
	round_message.visible = true

func show_pickup_toast(player_name: String, weapon_name: String, kind: String = "weapon", amount: int = 0) -> void:
	var what: String
	match kind:
		"health": what = tr("HUD_PICKUP_HEALTH").format({"amount": amount})
		"armor": what = tr("HUD_PICKUP_ARMOR").format({"amount": amount})
		"ammo": what = tr("HUD_PICKUP_AMMO").format({"amount": amount})
		_: what = EquipmentState.display_name(weapon_name).to_upper()
	combat_feed.push(tr("HUD_PICKUP").format({"player": player_name, "item": what}))

func set_followed_weapon(weapon_name: String, player_name: String = "", behavior: String = ""):
	if not weapon_label or not weapon_icon:
		return

	followed_player_name = player_name

	var weapon_desc = ""
	var has_weapon = weapon_name != "" and weapon_textures.has(weapon_name)
	if has_weapon:
		weapon_desc = EquipmentState.display_name(weapon_name).to_upper()

	# Stance stays loud even when the followed pawn has no known weapon yet.
	if player_name == "" and not has_weapon:
		weapon_label.text = ""
		weapon_label.remove_theme_color_override("font_color")
		weapon_icon.visible = false
		if weapon_icon_bg:
			weapon_icon_bg.visible = false
		return

	# "FOLLOWING: Human Player" is what a player was told about themselves.
	# The line is for a spectator watching someone else.
	if client_mode != "SPECTATING":
		# The gun is already in the player's hands, drawn large. Naming it in
		# the corner as well is the third copy of the same fact.
		weapon_label.text = ""
	else:
		weapon_label.text = StanceChipScript.follow_line(player_name, behavior, weapon_desc)
	weapon_label.add_theme_color_override("font_color", StanceChipScript.accent_color(behavior != ""))
	# A player already has the gun in their hands, drawn large in the corner
	# this icon sits in. Two pictures of the same weapon, one of them in a
	# dark box, is one too many. The icon is how a spectator knows what the
	# fighter they are watching is holding.
	if has_weapon and client_mode == "SPECTATING" and not fp_juice_enabled:
		weapon_icon.texture = weapon_textures[weapon_name]
		weapon_icon.modulate = Color(1.15, 1.1, 1.05, 1)
		weapon_icon.visible = true
		if weapon_icon_bg:
			weapon_icon_bg.visible = true
	else:
		weapon_icon.visible = false
		if weapon_icon_bg:
			weapon_icon_bg.visible = false

func _process(delta):
	if round_banner_remaining > 0.0:
		round_banner_remaining = maxf(0.0, round_banner_remaining - delta)
		if round_banner_remaining == 0.0:
			round_message.visible = false
	if scoreboard:
		scoreboard.visible = not fp_juice_enabled or Input.is_physical_key_pressed(KEY_TAB)
	if damage_flash_timer > 0:
		damage_flash_timer -= delta
		if damage_flash:
			damage_flash.visible = true
			damage_flash.modulate.a = clampf(damage_flash_timer / 0.22, 0.0, 0.55)
		if damage_flash_timer <= 0 and damage_flash:
			damage_flash.visible = false
			damage_flash.modulate.a = 0.0
	if spawn_flash_timer > 0:
		spawn_flash_timer -= delta
		if spawn_flash:
			spawn_flash.visible = true
			spawn_flash.modulate.a = clampf(spawn_flash_timer / 0.35, 0.0, 0.45)
		if spawn_flash_timer <= 0 and spawn_flash:
			spawn_flash.visible = false
			spawn_flash.modulate.a = 0.0
	if streak_flash_timer > 0:
		streak_flash_timer -= delta
		if streak_flash:
			streak_flash.visible = true
			streak_flash.modulate.a = clampf(streak_flash_timer / 0.4, 0.0, 0.5)
		if streak_flash_timer <= 0 and streak_flash:
			streak_flash.visible = false
			streak_flash.modulate.a = 0.0
	if hit_marker_timer > 0:
		hit_marker_timer -= delta
		if hit_marker:
			hit_marker.visible = true
			hit_marker.modulate.a = clampf(hit_marker_timer / 0.18, 0.0, 1.0)
		if hit_marker_timer <= 0 and hit_marker:
			hit_marker.visible = false
			hit_marker.modulate.a = 0.0
	if fp_kick_timer > 0:
		fp_kick_timer -= delta
	if fp_muzzle_timer > 0:
		fp_muzzle_timer -= delta
		if fp_muzzle:
			# Fades and shrinks over its short life rather than blinking off.
			var m: float = clampf(fp_muzzle_timer / FP_MUZZLE_SECONDS, 0.0, 1.0)
			fp_muzzle.modulate.a = m
			fp_muzzle.scale = Vector2.ONE * (0.75 + 0.35 * m) * (0.45 if current_fp_weapon == "Tack" else 1.0)
		if fp_muzzle_timer <= 0 and fp_muzzle:
			fp_muzzle.visible = false
	_update_floating_damage(delta)
	if fp_juice_enabled and fp_weapon and (fp_weapon.visible or melee_view.visible):
		var walking: float = clampf(fp_walk_speed / MoveStep.TOP_SPEED, 0.0, 1.0)
		fp_bob_weight = move_toward(fp_bob_weight, walking, delta * 8.0)
		fp_bob_t += delta * 9.0 * walking
		_layout_fp_weapon()

func set_fp_walk_speed(speed: float) -> void:
	fp_walk_speed = maxf(speed, 0.0) if is_finite(speed) else 0.0

func _layout_fp_weapon() -> void:
	var bob_scale: float = 1.0
	match current_fp_weapon:
		"Rail": bob_scale = 0.55
		"Scatter": bob_scale = 1.35
	var weight: float = fp_bob_weight if head_bob_enabled else 0.0
	var bob: Vector2 = Vector2(cos(fp_bob_t * 0.5) * 2.0, sin(fp_bob_t) * 4.0) * bob_scale * weight
	var kick: Vector2 = fp_kick_amount * clampf(fp_kick_timer / 0.12, 0.0, 1.0)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var base: Vector2 = (viewport_size - fp_weapon.size) * Vector2(0.5, 1.0)
	var lowering: float = equipment_hud.lowering() if equipment_hud.visible else 0.0
	fp_weapon.position = (base + Vector2(0.0, FP_BOTTOM_OVERLAP + lowering) + bob + kick).round()
	if current_fp_weapon == "Fists":
		melee_view.pose((base + Vector2(0.0, FP_BOTTOM_OVERLAP) + bob).round(), fp_weapon.size)
	if fp_muzzle:
		var barrel_y: float = 25.0 if current_fp_weapon == "Flechette" else 14.0
		if current_fp_weapon == "Tack":
			barrel_y = 8.0
		var barrel_x: float = fp_weapon.size.x * 0.5 if current_fp_weapon == "Tack" else 224.0
		fp_muzzle.position = fp_weapon.position + Vector2(barrel_x, barrel_y * 2.0) - fp_muzzle.size * 0.5

func set_fp_juice(enabled: bool) -> void:
	if fp_juice_enabled == enabled:
		return
	fp_juice_enabled = enabled
	if vitals:
		vitals.visible = enabled
	if crosshair:
		crosshair.visible = enabled
	if not enabled:
		melee_view.reset()
		equipment_hud.visible = false
		if fp_muzzle:
			fp_muzzle.visible = false
		fp_muzzle_timer = 0.0
		if fp_weapon:
			fp_weapon.visible = false
		if damage_flash:
			damage_flash.visible = false
			damage_flash.modulate.a = 0.0
		if spawn_flash:
			spawn_flash.visible = false
			spawn_flash.modulate.a = 0.0
		if hit_marker:
			hit_marker.visible = false
		damage_flash_timer = 0.0
		spawn_flash_timer = 0.0
		hit_marker_timer = 0.0
		fp_kick_timer = 0.0
		fp_bob_t = 0.0
		fp_walk_speed = 0.0
		fp_bob_weight = 0.0
		current_fp_weapon = ""
		_clear_floating_damage()

func set_fp_weapon(weapon_name: String) -> void:
	if not fp_weapon:
		return
	if not fp_juice_enabled or not viewmodel_textures.has(weapon_name):
		fp_weapon.visible = false
		melee_view.reset()
		return
	var changed = weapon_name != current_fp_weapon
	current_fp_weapon = weapon_name
	fp_weapon.texture = viewmodel_textures[weapon_name]
	# Distinct viewmodel pose per role (bone/gunmetal, not neon).
	if changed:
		melee_view.reset()
		fp_muzzle_timer = 0.0
		fp_muzzle.visible = false
		fp_weapon.modulate = Color.WHITE
		fp_weapon.scale = Vector2.ONE
		_apply_crosshair_for_weapon(weapon_name)
	_layout_fp_weapon()
	fp_weapon.visible = weapon_name != "Fists"
	melee_view.visible = weapon_name == "Fists"

## Keep every crosshair edge matching the part it sits behind: same visibility,
## same rectangle grown by a couple of pixels on each side.
func _sync_crosshair_edges() -> void:
	for part in crosshair_edges:
		var edge = crosshair_edges[part]
		if part == null or edge == null:
			continue
		edge.visible = part.visible
		if not edge.visible:
			continue
		edge.offset_left = part.offset_left - CROSSHAIR_EDGE_PAD
		edge.offset_top = part.offset_top - CROSSHAIR_EDGE_PAD
		edge.offset_right = part.offset_right + CROSSHAIR_EDGE_PAD
		edge.offset_bottom = part.offset_bottom + CROSSHAIR_EDGE_PAD

func _apply_crosshair_for_weapon(weapon_name: String) -> void:
	if not crosshair or not fp_juice_enabled:
		return
	# Bone grit crosshair shapes per role.
	var bone: Color = reticle_colour
	var ember: Color = reticle_colour
	var gun: Color = reticle_colour
	if crosshair_hbar:
		crosshair_hbar.visible = true
		crosshair_hbar.color = bone
	if crosshair_vbar:
		crosshair_vbar.visible = true
		crosshair_vbar.color = bone
	if crosshair_dot:
		crosshair_dot.visible = false
	match weapon_name:
		"Rail":
			if crosshair_hbar:
				crosshair_hbar.visible = false
			if crosshair_vbar:
				crosshair_vbar.visible = false
			if crosshair_dot:
				crosshair_dot.visible = true
				crosshair_dot.color = gun
				crosshair_dot.offset_left = -2.0
				crosshair_dot.offset_top = -2.0
				crosshair_dot.offset_right = 2.0
				crosshair_dot.offset_bottom = 2.0
		"Scatter":
			if crosshair_hbar:
				crosshair_hbar.offset_left = -18.0
				crosshair_hbar.offset_right = 18.0
				crosshair_hbar.offset_top = -1.0
				crosshair_hbar.offset_bottom = 1.0
				crosshair_hbar.color = ember
			if crosshair_vbar:
				crosshair_vbar.offset_top = -18.0
				crosshair_vbar.offset_bottom = 18.0
				crosshair_vbar.offset_left = -1.0
				crosshair_vbar.offset_right = 1.0
				crosshair_vbar.color = ember
		_:
			if crosshair_hbar:
				crosshair_hbar.offset_left = -11.0
				crosshair_hbar.offset_right = 11.0
				crosshair_hbar.offset_top = -1.5
				crosshair_hbar.offset_bottom = 1.5
			if crosshair_vbar:
				crosshair_vbar.offset_top = -11.0
				crosshair_vbar.offset_bottom = 11.0
				crosshair_vbar.offset_left = -1.5
				crosshair_vbar.offset_right = 1.5
	# Whatever shape this weapon chose, put a dark edge behind it. A cream
	# crosshair over a tan floor is a crosshair nobody can see.
	_sync_crosshair_edges()

func show_hit_marker(damage: int = 0, weapon_name: String = "") -> void:
	# Light grit confirm when local / followed player scores a hit.
	if not fp_juice_enabled and client_mode == "SPECTATING":
		# Spectator follow path still gets a brief marker.
		pass
	hit_marker_timer = 0.18
	if hit_marker:
		hit_marker.visible = true
		var col = Color(0.91, 0.82, 0.7, 0.95)
		match weapon_name:
			"Rail":
				col = Color(0.72, 0.78, 0.82, 0.95)
				hit_marker_timer = 0.28
			"Scatter":
				col = Color(0.9, 0.55, 0.32, 0.95)
				hit_marker_timer = 0.14
			_:
				col = Color(0.91, 0.82, 0.7, 0.95)
		hit_marker.modulate = col
	if damage > 0:
		_spawn_floating_damage(damage, weapon_name)
	# Shot acknowledgement already owns recoil. A hit must not kick twice.

## How close a player is to dying, which is the one thing the HUD never said.
## A number for the exact figure and a bar for the glance, in the corner, read
## without looking away from the crosshair.
func set_vitals(hp: int, armor: int) -> void:
	if not vitals:
		return
	vitals.visible = fp_juice_enabled
	var hp_shown: int = maxi(hp, 0)
	if health_value:
		health_value.text = str(hp_shown)
		# Low health is the one place the HUD is allowed to shout.
		health_value.modulate = Color(1, 0.55, 0.55) if hp_shown <= 35 else Color.WHITE
	if health_bar:
		var hp_fill: float = clampf(float(hp_shown) / float(PLAYER_MAX_HP), 0.0, 1.0)
		health_bar.size.x = HEALTH_BAR_WIDTH * hp_fill
	var armor_shown: int = maxi(armor, 0)
	if armor_value:
		armor_value.text = str(armor_shown)
		# Armour at zero is not worth the ink.
		armor_value.modulate.a = 1.0 if armor_shown > 0 else 0.35
	if armor_bar:
		var armor_fill: float = clampf(float(armor_shown) / float(PLAYER_MAX_ARMOR), 0.0, 1.0)
		armor_bar.size.x = ARMOR_BAR_WIDTH * armor_fill

func show_fire_juice(weapon_name: String = "") -> void:
	_fp_fire_kick(weapon_name if weapon_name != "" else current_fp_weapon)

## The flash a player sees for their own shot. The pawn has had one all along,
## but in first person the pawn is not what anyone is looking at, so until now
## the only feedback for pulling the trigger was the sound.
func _fp_muzzle_flash(weapon_name: String) -> void:
	if weapon_name == "Fists":
		return
	if not fp_juice_enabled or not fp_muzzle or fp_muzzle_texture == null:
		return
	# Same colours the fighter's own flash uses, so the two read as one weapon.
	match weapon_name:
		"Rail":
			fp_muzzle.modulate = Color(0.72, 0.78, 0.82, 1.0)
		"Scatter":
			fp_muzzle.modulate = Color(0.95, 0.55, 0.28, 1.0)
		_:
			fp_muzzle.modulate = Color(0.92, 0.78, 0.55, 1.0)
	fp_muzzle.scale = Vector2.ONE * (0.5 if weapon_name == "Tack" else 1.1)
	fp_muzzle.visible = true
	fp_muzzle_timer = FP_MUZZLE_SECONDS

func _fp_fire_kick(weapon_name: String) -> void:
	if not fp_juice_enabled:
		return
	if weapon_name == "Fists":
		melee_view.punch()
		return
	_fp_muzzle_flash(weapon_name)
	fp_kick_timer = 0.12
	match weapon_name:
		"Tack":
			fp_kick_amount = Vector2(0, 18)
		"Rail":
			fp_kick_amount = Vector2(8, 22)
			fp_kick_timer = 0.18
		"Scatter":
			fp_kick_amount = Vector2(14, 10)
			fp_kick_timer = 0.10
		_:
			fp_kick_amount = Vector2(6, 8)

func _spawn_floating_damage(damage: int, weapon_name: String) -> void:
	if not damage_numbers:
		return
	var label = Label.new()
	label.text = str(damage)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col = Color(0.91, 0.82, 0.7, 1)
	match weapon_name:
		"Rail":
			col = Color(0.75, 0.82, 0.86, 1)
		"Scatter":
			col = Color(0.92, 0.55, 0.3, 1)
		_:
			col = Color(0.95, 0.78, 0.45, 1)
	label.add_theme_color_override("font_color", col)
	label.add_theme_font_size_override("font_size", 22 if weapon_name != "Rail" else 28)
	var ox = randf_range(-28.0, 28.0)
	label.position = Vector2(ox, -20.0)
	damage_numbers.add_child(label)
	floating_damage_nodes.append({"node": label, "t": 0.0, "life": 0.55, "ox": ox})

func _update_floating_damage(delta: float) -> void:
	var keep = []
	for entry in floating_damage_nodes:
		var node = entry.get("node")
		if node == null or not is_instance_valid(node):
			continue
		entry["t"] += delta
		var t = float(entry["t"])
		var life = float(entry["life"])
		var progress = clampf(t / life, 0.0, 1.0)
		node.position = Vector2(float(entry["ox"]), -20.0 - progress * 48.0)
		node.modulate.a = 1.0 - progress
		if t < life:
			keep.append(entry)
		else:
			node.queue_free()
	floating_damage_nodes = keep

func _clear_floating_damage() -> void:
	for entry in floating_damage_nodes:
		var node = entry.get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	floating_damage_nodes = []

func show_damage_flash() -> void:
	if not fp_juice_enabled:
		return
	damage_flash_timer = 0.22
	if damage_flash:
		damage_flash.visible = true
		damage_flash.modulate = Color(0.55, 0.08, 0.06, 0.55)

func show_spawn_flash() -> void:
	if not fp_juice_enabled:
		return
	spawn_flash_timer = 0.35
	if spawn_flash:
		spawn_flash.visible = true
		# Ember grit flash on spawn / join.
		spawn_flash.modulate = Color(0.85, 0.45, 0.18, 0.45)


var radio_label: Label = null
var radio_tween: Tween = null

## Bottom-right radio toast: station on switch, title on each new track, then fade.
func show_radio(station: String, title: String) -> void:
	if radio_label == null:
		radio_label = Label.new()
		radio_label.name = "RadioLabel"
		radio_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		radio_label.anchor_left = 1.0
		radio_label.anchor_top = 1.0
		radio_label.anchor_right = 1.0
		radio_label.anchor_bottom = 1.0
		radio_label.offset_left = -520.0
		radio_label.offset_top = -44.0
		radio_label.offset_right = -16.0
		radio_label.offset_bottom = -16.0
		radio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		radio_label.add_theme_color_override("font_color", Color(0.91, 0.89, 0.84))
		radio_label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.05))
		radio_label.add_theme_constant_override("outline_size", 4)
		add_child(radio_label)
	var text := "ON AIR: " + station
	if title != "":
		text += "  //  " + title
	radio_label.text = text
	radio_label.modulate.a = 1.0
	radio_label.visible = true
	if radio_tween != null and radio_tween.is_valid():
		radio_tween.kill()
	radio_tween = create_tween()
	radio_tween.tween_interval(3.5)
	radio_tween.tween_property(radio_label, "modulate:a", 0.0, 1.0)


var radio_card: Control = null
var radio_card_badge: ColorRect = null
var radio_card_mark: Label = null
var radio_card_name: Label = null
var radio_card_tagline: Label = null
var radio_card_tween: Tween = null

## Station card above the radio toast: badge, name, tagline. Shown on every
## station switch and radio toggle, then fades.
func show_station_card(card: Dictionary) -> void:
	if radio_card == null:
		radio_card = Control.new()
		radio_card.name = "RadioCard"
		radio_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		radio_card.anchor_left = 1.0
		radio_card.anchor_top = 1.0
		radio_card.anchor_right = 1.0
		radio_card.anchor_bottom = 1.0
		radio_card.offset_left = -420.0
		radio_card.offset_top = -150.0
		radio_card.offset_right = -16.0
		radio_card.offset_bottom = -56.0
		radio_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var back := ColorRect.new()
		back.color = Color(0.04, 0.04, 0.05, 0.82)
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		radio_card.add_child(back)
		radio_card_badge = ColorRect.new()
		radio_card_badge.position = Vector2(8, 8)
		radio_card_badge.size = Vector2(78, 78)
		radio_card_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		radio_card.add_child(radio_card_badge)
		radio_card_mark = Label.new()
		radio_card_mark.position = Vector2(8, 8)
		radio_card_mark.size = Vector2(78, 78)
		radio_card_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		radio_card_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		radio_card_mark.add_theme_font_size_override("font_size", 34)
		radio_card_mark.add_theme_color_override("font_color", Color(0.91, 0.89, 0.84))
		radio_card_mark.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.05))
		radio_card_mark.add_theme_constant_override("outline_size", 6)
		radio_card.add_child(radio_card_mark)
		radio_card_name = Label.new()
		radio_card_name.position = Vector2(98, 12)
		radio_card_name.size = Vector2(300, 34)
		radio_card_name.add_theme_font_size_override("font_size", 24)
		radio_card_name.add_theme_color_override("font_color", Color(0.91, 0.89, 0.84))
		radio_card_name.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.05))
		radio_card_name.add_theme_constant_override("outline_size", 4)
		radio_card.add_child(radio_card_name)
		radio_card_tagline = Label.new()
		radio_card_tagline.position = Vector2(98, 48)
		radio_card_tagline.size = Vector2(300, 40)
		radio_card_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD
		radio_card_tagline.add_theme_font_size_override("font_size", 13)
		radio_card_tagline.add_theme_color_override("font_color", Color(0.72, 0.70, 0.66))
		radio_card.add_child(radio_card_tagline)
		add_child(radio_card)
	radio_card_badge.color = Color.html(str(card.get("color", "#5A554F")))
	radio_card_mark.text = str(card.get("badge", "CF"))
	radio_card_name.text = str(card.get("name", "RADIO")).to_upper()
	var tagline := str(card.get("tagline", ""))
	if not bool(card.get("enabled", true)):
		tagline = "RADIO OFF"
	elif not bool(card.get("has_tracks", true)):
		tagline = "OFF THE AIR (no tracks yet)"
	radio_card_tagline.text = tagline
	radio_card.modulate.a = 1.0
	radio_card.visible = true
	if radio_card_tween != null and radio_card_tween.is_valid():
		radio_card_tween.kill()
	radio_card_tween = create_tween()
	radio_card_tween.tween_interval(4.0)
	radio_card_tween.tween_property(radio_card, "modulate:a", 0.0, 0.8)
