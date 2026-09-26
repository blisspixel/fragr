extends RefCounted
class_name FragrSettings

## Canonical, validated preferences. Unimplemented historical keys are ignored.
signal changed

const PATH: String = "user://settings.cfg"
## Affectionate local slang. The network role remains `human` for compatibility.
const DEFAULT_CALLSIGN: String = "Meat Proxy"

## Section, key, default. Persistence is shared; menus wire supported keys explicitly.
const DEFAULTS: Dictionary = {
	"profile": {
		"name": DEFAULT_CALLSIGN,
		"reticle_colour": "bone",
	},
	"video": {
		"display_mode": 2,      # 0 windowed, 2 fullscreen
		"vertical_fov": 75.0,   # Preserves the original camera's rendered default.
		"fps_cap": 0,           # 0 is uncapped
		"vsync": false,
		"resolution_height": 0, # Native fullscreen; automatic size when windowed.
		"quality": 1,           # Performance, Balanced, High.
		"upscaling": 0,         # Standard, FSR1, FSR2; renderer gates capability.
		"pixel_scale": 0,       # Off, fine, medium, chunky world pixels (nearest).
		"dither": false,        # Ordered dither to the locked palette.
	},
	"audio": {
		"master": 0.9,
		"music": 0.7,
		"effects": 0.5,
		"voice": 0.9,       # Story narration; its own bus so speech stays level.
	},
	"controls": {
		"mouse_sensitivity": 1.5, # 0.022 degrees per unscaled mouse count.
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
		"strafe": "", "jump": "", "turn_left": "", "turn_right": "",
		"look_up": "", "look_down": "", "center_view": "", "fire": "",
		"interact": "", "weapon_next": "", "weapon_prev": "", "weapon_1": "",
		"weapon_2": "", "weapon_3": "", "weapon_4": "", "weapon_5": "",
		"scoreboard": "", "speak": "", "pause": "", "leave_match": "",
		"join_as_human": "", "cycle_cam": "", "toggle_follow": "",
		"radio_next_station": "", "radio_next_track": "", "radio_toggle": "",
	},
	"gameplay": {
		"stat_commentary": true,
		"head_bob": true,
		# The broadcast ident: the top strip, the red ON AIR box, the station
		# badge. Off, because it is right for a let's-play capture and wrong
		# for playing, and it was the loudest thing on screen in every
		# spectator frame the visual QA tour took.
		"broadcast_chrome": false,
		# Connection status, wall clock and head count. Debug furniture.
		"debug_telemetry": false,
		# Scene captions while narration speaks. Text-only shots always show.
		"story_captions": true,
	},
}

var _values: Dictionary = {}
var storage_path: String

const RANGES: Dictionary = {
	"video/vertical_fov": Vector2(60.0, 110.0),
	"video/fps_cap": Vector2(0.0, 1000.0),
	"audio/master": Vector2(0.0, 1.0),
	"audio/music": Vector2(0.0, 1.0),
	"audio/effects": Vector2(0.0, 1.0),
	"audio/voice": Vector2(0.0, 1.0),
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
		if not value is int or value not in [0, 1, 2]:
			value = fallback
		elif value == 1:
			value = 2 # Legacy exclusive request uses portable fullscreen now.
	elif path == "video/resolution_height":
		if not value is int or value not in RenderQuality.RESOLUTION_HEIGHTS:
			value = fallback
	elif path in ["video/quality", "video/upscaling", "controls/aim_assist"]:
		if not value is int or value not in [0, 1, 2]:
			value = fallback
	elif section == "bindings":
		if not value is String or (not (value as String).is_empty() and InputBindings.parse(value).size() != InputBindings.SLOTS):
			value = fallback
	elif path == "video/pixel_scale":
		if not value is int or value < 0 or value >= RenderQuality.PIXEL_TARGETS.size():
			value = fallback
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

func save_to_disk() -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	for section in _values:
		for key in (_values[section] as Dictionary):
			cfg.set_value(section, key, (_values[section] as Dictionary)[key])
	# Write beside the destination so failed writes cannot truncate the last save.
	var temporary: String = storage_path + ".%d.tmp" % OS.get_process_id()
	var result: Error = cfg.save(temporary)
	if result == OK:
		result = DirAccess.rename_absolute(temporary, storage_path)
	if result != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return result

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
