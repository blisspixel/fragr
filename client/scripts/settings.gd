extends RefCounted
class_name FragrSettings

## Canonical, validated preferences. Unknown keys are ignored.
signal changed

const PATH: String = "user://settings.cfg"
## Affectionate local slang. The network role remains `human` for compatibility.
const DEFAULT_CALLSIGN: String = "Meat Proxy"

## Section, key, default. Persistence is shared; menus wire supported keys explicitly.
const DEFAULTS: Dictionary = {
	"profile": {
		"name": DEFAULT_CALLSIGN,
		"reticle_colour": "bone",
		# Human or free agent; see PlayerBody. The next join uses it.
		"body": "human",
		# A roster look on that body and a personal accent (FighterLooks);
		# -1 lets the server choose a look and leaves the accent off.
		"look": -1,
		"accent": -1,
	},
	"video": {
		"display_mode": 2,      # 0 windowed, 2 fullscreen
		"vertical_fov": 75.0,   # Preserves the original camera's rendered default.
		"fps_cap": 0,           # 0 is uncapped
		"vsync": false,
		"show_fps": 0,          # 0 off, 1 FPS, 2 FPS with frame time and 1% low.
		"resolution_height": 0, # Native fullscreen; automatic size when windowed.
		# Potato, Low, Medium, High, Ultra (RenderQuality tiers). Low, Medium
		# and High are the earlier Performance, Balanced and High presets.
		"quality": RenderQuality.DEFAULT_TIER,
		"upscaling": 0,         # Standard, FSR1, FSR2; renderer gates capability.
		# 3D render scale in percent of the output, pixel look off only
		# (RenderQuality.RENDER_SCALES); above 100 supersamples.
		"render_scale": 100,
		# Auto settings (AutoTune): on, the tuner and the in-match governor
		# may move any option the player has not pinned.
		"auto": true,
		# Frame rate the tuner holds as a 1% low: 60, 90, 120, 144, or 0 for
		# the display's refresh.
		"target_fps": 60,
		# Options the player set by hand (PINNABLE); auto works around them.
		"pinned": [],
		# In-match safety valve (FrameGovernor): may lower costly effects at a
		# death, respawn, checkpoint or round end when frames fall short.
		"governor": true,
		# The last auto-tune: what it chose, why, and the machine it measured
		# (AutoTune.clean_record). Empty until the first tune or Skip.
		"tune": {},
		# Off, fine, medium, chunky world pixels (nearest). Fine is 540 world
		# lines: 2x at 1080p, 3x at 1440p, 4x at 2160p, native at 720p. It
		# keeps fighters at range, the held gun and large signs, costs less GPU
		# than Off and gives the world one pixel grid. Small placard text does
		# not survive it. Chosen from Larak Lot and Recall Notice captures on
		# both renderers (wave 4); Nick's call to confirm.
		"pixel_scale": 1,
		"dither": false,        # Ordered dither in value steps; keeps every hue.
	},
	"audio": {
		"master": 0.9,
		"music": 0.7,
		"effects": 0.5,
		"voice": 0.9,       # Story narration; its own bus so speech stays level.
		# The Host's match calls: 0 On, 1 Big moments only, 2 Off.
		"announcer": 0,
		"announcer_volume": 0.9, # The Announcer bus, for the Host's voiced calls.
		# Which take of Crackpot's benchmark certificate plays (BenchmarkJingle),
		# picked on the benchmark results screen while all six ship.
		"benchmark_jingle": "1a",
	},
	"controls": {
		"mouse_sensitivity": 1.5, # 0.022 degrees per unscaled mouse count.
		"scope_mode": 0,       # Hold 4x, toggle 4x, cycle 2x / 4x / open.
		"invert_y": false,      # Mouse and stick pitch. Look keys are literal.
		"turn_speed": 2.8,      # Radians per second for keyboard turning
		"auto_centre": false,   # Keyboard pitch eases level while walking.
		"stick_yaw_speed": 240.0,   # Degrees per second at full deflection.
		"stick_pitch_speed": 150.0, # Degrees per second at full deflection.
		"stick_deadzone": 0.12, # Radial, rescaled.
		"stick_curve": 1.8,     # Response exponent on stick magnitude.
		"stick_accel": true,    # Faster turning once the stick sits at its edge.
		"aim_assist": 2,        # 0 off, 1 light, 2 standard. Never applies to mouse look.
	},
	# One entry per rebindable action (InputBindings.ACTIONS). Empty keeps the
	# project default; otherwise three slots, see input_bindings.gd.
	"bindings": {
		"move_forward": "", "move_back": "", "move_left": "", "move_right": "",
		"strafe": "", "jump": "", "dodge": "", "duck": "", "turn_left": "", "turn_right": "",
		"look_up": "", "look_down": "", "center_view": "", "fire": "", "reload": "",
		"interact": "", "throw_grenade": "", "place_mine": "", "place_remote_mine": "", "trigger_remote_mines": "", "weapon_next": "", "weapon_prev": "", "weapon_1": "",
		"weapon_2": "", "weapon_3": "", "weapon_4": "", "weapon_5": "", "weapon_6": "", "weapon_7": "", "scope": "",
		"scoreboard": "", "speak": "", "pause": "", "leave_match": "",
		"join_as_human": "", "cycle_cam": "", "toggle_follow": "",
		"radio_prev_station": "", "radio_next_station": "", "radio_next_track": "", "radio_toggle": "",
	},
	"gameplay": {
		"stat_commentary": true,
		"head_bob": true,
		# Connection status, wall clock and head count. Debug furniture.
		"debug_telemetry": false,
		# Scene captions while narration speaks. Text-only shots always show.
		"story_captions": true,
		# Set once the first join has shown the in-match controls hint. Not a
		# menu option; Settings > Controls is the full reference.
		"controls_hint_seen": false,
	},
	"accessibility": {
		"screen_flashes": 1,    # 0 Full, 1 Reduced, 2 Off
		"reduced_motion": false,
		"hud_scale": 100,       # 75 to 150 percent
		"text_size": 0,         # 0 Standard, 1 Large
		"team_colours": 0,      # 0 Standard, 1 High contrast, 2 Colour blind (red-green)
		# Human bodies bleed when hit. Off shows a neutral dust puff and a
		# bone damage edge instead; machines still spark and leak oil.
		"blood": true,
	},
	# The desktop host's rotation (Multiplayer > Run a match): whether a
	# free-for-all, team or flag match moves map with a podium vote, and the
	# roster maps it skips. No map is removed; switching one off keeps it out
	# of the rotation and the vote. Every map starts on: hosts choose, and
	# the rotation itself skips a map that cannot host the mode.
	"host": {
		"rotate": true,
		"maps_off": [],
		# The rule bots' rung (LocalHost.BOT_SKILLS); Regular is the league's
		# ordinary night.
		"bot_skill": "regular",
	},
	# The optional campaign score (CampaignScore): on or off, and the take
	# chosen per slot while both takes ship. A missing slot plays take A.
	"score": {
		"enabled": true,
		"takes": {},
	},
	# Which generated footstep set plays (Footsteps): "a" or "b", until Nick
	# picks one by ear and the other is pruned.
	"footsteps": {
		"take": "a",
	},
}

const FLASHES_FULL: int = 0
const FLASHES_REDUCED: int = 1
const FLASHES_OFF: int = 2

const TEXT_STANDARD: int = 0
const TEXT_LARGE: int = 1

const ANNOUNCER_ON: int = 0
const ANNOUNCER_BIG_MOMENTS: int = 1
const ANNOUNCER_OFF: int = 2
const ANNOUNCER_MODES: Array[int] = [ANNOUNCER_ON, ANNOUNCER_BIG_MOMENTS, ANNOUNCER_OFF]

const TEAM_STANDARD: int = 0
const TEAM_HIGH_CONTRAST: int = 1
const TEAM_COLOUR_BLIND: int = 2

var _values: Dictionary = {}
var storage_path: String
## The default input layout the stored bindings were made against. Bump it
## whenever a default binding moves; older custom bindings are then refused.
const CONTROLS_LAYOUT: int = 20261024
## The last load found custom bindings from another layout and dropped them.
var controls_refused: bool = false

## Graphics options a player choice pins against auto settings.
const PINNABLE: Array[String] = ["quality", "render_scale", "resolution_height", "upscaling", "fps_cap", "vsync"]
const TARGET_FPS: Array[int] = [60, 90, 120, 144, 0]
## The meaning of the saved graphics tier. Files from earlier builds stored a
## three-preset index; they are refused (tier, pins and tune reset to auto),
## never migrated, and the Graphics page says so until the player saves.
const VIDEO_LAYOUT: int = 20261101
var video_refused: bool = false

const RANGES: Dictionary = {
	"accessibility/hud_scale": Vector2(75.0, 150.0),
	"video/vertical_fov": Vector2(60.0, 110.0),
	"video/fps_cap": Vector2(0.0, 1000.0),
	"audio/master": Vector2(0.0, 1.0),
	"audio/music": Vector2(0.0, 1.0),
	"audio/effects": Vector2(0.0, 1.0),
	"audio/voice": Vector2(0.0, 1.0),
	"audio/announcer_volume": Vector2(0.0, 1.0),
	"controls/mouse_sensitivity": Vector2(0.1, 10.0),
	"controls/turn_speed": Vector2(0.5, 6.0),
	"controls/stick_yaw_speed": Vector2(60.0, 720.0),
	"controls/stick_pitch_speed": Vector2(40.0, 480.0),
	"controls/stick_deadzone": Vector2(0.02, 0.4),
	"controls/stick_curve": Vector2(1.0, 3.0),
}

## Harnesses supply an isolated path before scenes enter the tree.
static func for_tree(tree: SceneTree) -> FragrSettings:
	return FragrSettings.new(str(tree.get_meta("fragr_settings_path", PATH)))

func _init(path: String = PATH) -> void:
	storage_path = path
	_values = _copy_defaults()

static func _copy_defaults() -> Dictionary:
	var out: Dictionary = {}
	for section in DEFAULTS:
		out[section] = (DEFAULTS[section] as Dictionary).duplicate(true)
	return out

## Read a setting, falling back to the default rather than to null, so a config
## file written by an older build can never produce a missing value.
func get_value(section: String, key: String) -> Variant:
	if _values.has(section) and (_values[section] as Dictionary).has(key):
		return (_values[section] as Dictionary)[key]
	if DEFAULTS.has(section) and (DEFAULTS[section] as Dictionary).has(key):
		return (DEFAULTS[section] as Dictionary)[key]
	return null

func set_value(section: String, key: String, value: Variant) -> void:
	if not DEFAULTS.has(section) or not (DEFAULTS[section] as Dictionary).has(key):
		return
	var fallback: Variant = DEFAULTS[section][key]
	var path: String = section + "/" + key
	if path == "profile/name":
		value = clean_player_name(value)
	elif path == "profile/reticle_colour":
		if not value is String or value not in ["bone", "amber", "cyan"]:
			value = fallback
	elif path == "profile/body":
		value = PlayerBody.preference(value)
	elif path == "profile/look":
		var most: int = maxi(FighterLooks.count(PlayerBody.HUMAN), FighterLooks.count(PlayerBody.SYNTHETIC))
		if not value is int or value < FighterLooks.AUTO or value >= most:
			value = fallback
	elif path == "profile/accent":
		if not value is int or (value != FighterLooks.AUTO and not FighterLooks.valid_accent(value)):
			value = fallback
	elif typeof(fallback) == TYPE_BOOL:
		if not value is bool:
			value = fallback
	elif RANGES.has(path):
		if (not value is int and not value is float) or not is_finite(float(value)):
			value = fallback
		var limits: Vector2 = RANGES[path]
		value = clampf(float(value), limits.x, limits.y)
		if typeof(fallback) == TYPE_INT:
			value = int(value)
	elif path == "video/display_mode":
		if not value is int or value not in [0, 2]:
			value = fallback
	elif path == "video/resolution_height":
		if not value is int or value not in RenderQuality.RESOLUTION_HEIGHTS:
			value = fallback
	elif path == "video/quality":
		if not value is int or value < RenderQuality.POTATO or value > RenderQuality.ULTRA:
			value = fallback
	elif path == "video/render_scale":
		if not RenderQuality.scale_valid(value):
			value = fallback
	elif path == "video/target_fps":
		if not value is int or value not in TARGET_FPS:
			value = fallback
	elif path == "video/pinned":
		value = clean_pinned(value)
	elif path == "video/tune":
		value = AutoTune.clean_record(value)
	elif path in ["video/upscaling", "video/show_fps", "controls/aim_assist", "controls/scope_mode", "accessibility/screen_flashes", "audio/announcer"]:
		if not value is int or value not in [0, 1, 2]:
			value = fallback
	elif path == "accessibility/team_colours":
		if not value is int or value not in [TEAM_STANDARD, TEAM_HIGH_CONTRAST, TEAM_COLOUR_BLIND]:
			value = fallback
	elif path == "accessibility/text_size":
		if not value is int or value not in [0, 1]:
			value = fallback
	elif section == "bindings":
		if not value is String or (not (value as String).is_empty() and InputBindings.parse(value).size() != InputBindings.SLOTS):
			value = fallback
	elif path == "video/pixel_scale":
		if not value is int or value < 0 or value >= RenderQuality.PIXEL_TARGETS.size():
			value = fallback
	if path == "host/maps_off":
		value = clean_maps_off(value, fallback)
	if path == "audio/benchmark_jingle":
		value = BenchmarkJingle.clean_take(value)
	if path == "host/bot_skill" and (not value is String or value not in LocalHost.BOT_SKILLS):
		value = fallback
	if path == "score/takes":
		value = CampaignScore.clean_takes(value)
	if path == "footsteps/take":
		value = Footsteps.valid_take(value)
	(_values[section] as Dictionary)[key] = value

func draft() -> FragrSettings:
	var copy: FragrSettings = FragrSettings.new(storage_path)
	copy._values = _values.duplicate(true)
	return copy

## Keep active values unchanged on failed writes. The owner applies on changed.
func commit(candidate: FragrSettings) -> Error:
	var result: Error = candidate.save_to_disk()
	if result != OK:
		return result
	_values = candidate._values.duplicate(true)
	# The file now carries the current controls and graphics layouts.
	controls_refused = false
	video_refused = false
	changed.emit()
	return OK

func reset_section(section: String) -> void:
	if DEFAULTS.has(section):
		_values[section] = (DEFAULTS[section] as Dictionary).duplicate(true)

func reset_all() -> void:
	_values = _copy_defaults()

func load_from_disk() -> void:
	_values = _copy_defaults()
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(storage_path) != OK:
		return
	for section in DEFAULTS:
		for key in (DEFAULTS[section] as Dictionary):
			var fallback: Variant = (DEFAULTS[section] as Dictionary)[key]
			set_value(section, key, cfg.get_value(section, key, fallback))
	# One current controls layout, no migration: bindings saved against another
	# layout are refused whole, and the Controls page says so until the player
	# saves. Everything else in the file is validated key by key above.
	controls_refused = false
	if _has_custom_bindings(cfg) and cfg.get_value("meta", "controls_layout", 0) != CONTROLS_LAYOUT:
		reset_section("bindings")
		controls_refused = true
	# The same rule for the graphics tier: an index saved under the older
	# three-preset meaning would now name a different tier.
	video_refused = false
	if cfg.has_section_key("video", "quality") and cfg.get_value("meta", "video_layout", 0) != VIDEO_LAYOUT:
		for key: String in ["quality", "auto", "pinned", "tune", "render_scale"]:
			set_value("video", key, DEFAULTS["video"][key])
		video_refused = true

static func _has_custom_bindings(cfg: ConfigFile) -> bool:
	if not cfg.has_section("bindings"):
		return false
	for key: String in cfg.get_section_keys("bindings"):
		if cfg.get_value("bindings", key, "") != "":
			return true
	return false

func save_to_disk() -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	for section in _values:
		for key in (_values[section] as Dictionary):
			cfg.set_value(section, key, (_values[section] as Dictionary)[key])
	cfg.set_value("meta", "controls_layout", CONTROLS_LAYOUT)
	cfg.set_value("meta", "video_layout", VIDEO_LAYOUT)
	# Write beside the destination so failed writes cannot truncate the last save.
	var temporary: String = storage_path + ".%d.tmp" % OS.get_process_id()
	var result: Error = cfg.save(temporary)
	if result == OK:
		result = DirAccess.rename_absolute(temporary, storage_path)
	if result != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return result

## Known pinnable keys, each once, in PINNABLE order. Anything else is dropped.
static func clean_pinned(value: Variant) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for key: String in PINNABLE:
		if (value as Array).has(key):
			out.append(key)
	return out

func pinned(key: String) -> bool:
	return (get_value("video", "pinned") as Array).has(key)

## Pin every pinnable option that differs from `previous`: the player chose it
## by hand, so auto settings work around it from now on.
func pin_changes(previous: FragrSettings) -> void:
	var pins: Array = (get_value("video", "pinned") as Array).duplicate()
	for key: String in PINNABLE:
		if get_value("video", key) != previous.get_value("video", key) and not pins.has(key):
			pins.append(key)
	set_value("video", "pinned", pins)

## Reset to auto: clear the pins, turn auto back on, and put the last tune's
## choice back where one exists.
func reset_to_auto() -> void:
	set_value("video", "pinned", [])
	set_value("video", "auto", true)
	var record: Dictionary = get_value("video", "tune")
	if not record.is_empty():
		AutoTune.apply_record(self, record)

## The frame rate auto settings hold: the chosen target, or the display's
## refresh (60 when the display does not report one).
func target_fps() -> int:
	var target: int = int(get_value("video", "target_fps"))
	if target > 0:
		return target
	if DisplayServer.get_name() == "headless":
		return 60
	var refresh: float = DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
	return roundi(refresh) if refresh >= 30.0 else 60

## Roster map ids (1 to 8), each once, in roster order, never all eight.
## Anything else falls back whole.
static func clean_maps_off(value: Variant, fallback: Variant) -> Array:
	if not value is Array:
		return (fallback as Array).duplicate()
	var out: Array = []
	for entry: Variant in value:
		if not (entry is int or entry is float) or not is_finite(float(entry)) or float(entry) != floorf(float(entry)) \
			or int(entry) < 1 or int(entry) > 8 or out.has(int(entry)):
			return (fallback as Array).duplicate()
		out.append(int(entry))
	if out.size() >= 8:
		return (fallback as Array).duplicate()
	out.sort()
	return out

static func clean_player_name(value: Variant) -> String:
	if not value is String:
		return DEFAULT_CALLSIGN
	var clean: String = ""
	for character in value:
		var code: int = character.unicode_at(0)
		if code >= 32 and code != 127:
			clean += character
	clean = clean.strip_edges().left(24)
	return DEFAULT_CALLSIGN if clean.is_empty() else clean

func player_name() -> String:
	return clean_player_name(get_value("profile", "name"))

func player_body() -> String:
	return PlayerBody.preference(get_value("profile", "body"))

## The saved look when the saved body has it, else AUTO.
func player_look() -> int:
	var value: Variant = get_value("profile", "look")
	return int(value) if FighterLooks.valid_look(player_body(), value) else FighterLooks.AUTO

func player_accent() -> int:
	var value: Variant = get_value("profile", "accent")
	return int(value) if FighterLooks.valid_accent(value) else FighterLooks.AUTO

## The Hello `dress` for the saved choice: only the parts that are set.
func player_dress() -> Dictionary:
	return FighterLooks.request(player_look(), player_accent(), player_body())

func reticle_colour() -> Color:
	match get_value("profile", "reticle_colour"):
		"amber": return Color("ffc568")
		"cyan": return Color("8ee9df")
		_: return Color("e8e2d6")

## Push everything at the engine. Safe to call repeatedly.
func apply() -> void:
	apply_video()
	apply_audio()
	apply_controls()
	apply_accessibility()

## The team colour choice reaches every side colour through one owner.
func apply_accessibility() -> void:
	FactionPalette.palette = team_colours()

## Rebuild the InputMap from the saved bindings.
func apply_controls() -> void:
	InputBindings.apply(self)

func apply_video() -> void:
	Engine.max_fps = int(get_value("video", "fps_cap"))
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = int(get_value("video", "display_mode"))
	match mode:
		0:
			var was_windowed: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var height: int = int(get_value("video", "resolution_height"))
			if height > 0 or not was_windowed:
				var usable: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
				var size: Vector2i = RenderQuality.window_size(height, usable.size)
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(get_value("video", "vsync")) else DisplayServer.VSYNC_DISABLED
	)

func apply_audio() -> void:
	_set_bus("Master", float(get_value("audio", "master")))
	_set_bus("Radio", float(get_value("audio", "music")))
	_set_bus("Effects", float(get_value("audio", "effects")))
	_set_bus("Voice", float(get_value("audio", "voice")))
	_set_bus("Announcer", float(get_value("audio", "announcer_volume")))
	Footsteps.take = Footsteps.valid_take(get_value("footsteps", "take"))

static func _set_bus(name: String, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(name)
	if index < 0:
		push_error("settings: missing audio bus " + name)
		return
	AudioServer.set_bus_mute(index, linear == 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0001, 1.0)))

## Vertical FOV, with horizontal coverage expanding on wider viewports.
func fov() -> float:
	return float(get_value("video", "vertical_fov"))

func announcer() -> int:
	return int(get_value("audio", "announcer"))

## The three announcer choices, in ANNOUNCER_MODES order, for every menu.
static func announcer_labels() -> Array[String]:
	var labels: Array[String] = []
	for key: String in ["SETTINGS_ANNOUNCER_ON", "SETTINGS_ANNOUNCER_BIG", "SETTINGS_ANNOUNCER_OFF"]:
		labels.append(TranslationServer.translate(key))
	return labels

func screen_flashes() -> int:
	return int(get_value("accessibility", "screen_flashes"))

func reduced_motion() -> bool:
	return bool(get_value("accessibility", "reduced_motion"))

func hud_scale() -> int:
	return int(get_value("accessibility", "hud_scale"))

func text_size() -> int:
	return int(get_value("accessibility", "text_size"))

func team_colours() -> int:
	return int(get_value("accessibility", "team_colours"))

## Presentation only: whether a struck human body shows blood.
func blood() -> bool:
	return bool(get_value("accessibility", "blood"))
