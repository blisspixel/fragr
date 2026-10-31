class_name CampaignScore
extends Node

## The optional ambient campaign score: one quiet bed per campaign level and a
## few short story cues (docs: client/assets/audio/README.md, "Campaign score").
## Presentation only. It never plays in multiplayer, never decides anything,
## and a missing file is silence.
##
## Every slot ships two takes, `score/<slot>/a.mp3` and `b.mp3`, until Nick
## picks one per slot while playing. The take a player hears is the
## `score/takes` setting for that slot (default A); a missing take falls back
## to the other one, and a slot with neither stays silent.
##
## The radio rule, one line: a radio tuned to a station replaces the score;
## the radio switched off gives the air back to it. A campaign that starts
## with the score on starts with the radio off, and the dial still works.

## Emitted when the bed or cue a player hears changes, for the pause menu.
signal now_scoring_changed

const SLOTS_PATH: String = "res://assets/audio/score/slots.json"
const SCORE_ROOT: String = "res://assets/audio/score/"
const BUS: StringName = &"Radio"
const TAKES: Array[String] = ["a", "b"]
const DEFAULT_TAKE: String = "a"
const SETTINGS_SECTION: String = "score"
const KINDS: Array[String] = ["bed", "cue"]
## The bed sits well under a station at the same Music volume (radio plays at -8 dB).
const BED_DB: float = -15.0
const CUE_DB: float = -11.0
const SILENT_DB: float = -80.0
## Host lines, Latch and Union barks.
const DUCK_DB: float = -9.0
const DUCK_SECONDS: float = 3.0
## Heavy combat lowers the bed by up to this much.
const COMBAT_DUCK_DB: float = -7.0
## Heat added per resolved shot and lost per second; at 1.0 the duck is full.
const COMBAT_HEAT_PER_SHOT: float = 0.08
const COMBAT_COOL_PER_SECOND: float = 0.35
## A bed's loop overlaps its own start this long, so it never lands on a seam.
const CROSSFADE_SECONDS: float = 6.0
const FADE_IN_DB_PER_SECOND: float = 18.0
const FADE_OUT_DB_PER_SECOND: float = 40.0
const SLOT_PATTERN: String = "^[a-z0-9][a-z0-9-]{0,31}$"
## The most a take's level match may lift or lower it.
const MAX_GAIN_DB: float = 12.0

var enabled: bool = true
## Mission id from the current MapInfo; empty outside the campaign.
var mission_id: String = ""
## The radio is tuned to a station (playing, or between two of its tracks).
var radio_playing: bool = false
## A story page owns the music for now.
var scene_hold: bool = false
var duck_timer: float = 0.0
var combat_heat: float = 0.0
## The last cue the player heard in a scene or a level, for the take control.
var last_cue: String = ""
var slots: Array[Dictionary] = []
var preferences: FragrSettings = null

var _bed_slot: String = ""
var _bed_path: String = ""
## Two players so a bed can overlap its own loop point.
var _beds: Array[AudioStreamPlayer] = []
var _active: int = 0
var _cue: AudioStreamPlayer
var _cue_slot: String = ""
var _gain_db: float = SILENT_DB
## The playing bed take's level match.
var _bed_gain_db: float = 0.0
static var _shipped: Array[Dictionary] = []


func _ready() -> void:
	if slots.is_empty():
		slots = parse_slots(_read(SLOTS_PATH))
	for index: int in 2:
		var bed: AudioStreamPlayer = AudioStreamPlayer.new()
		bed.name = "Bed%d" % index
		bed.bus = BUS if AudioServer.get_bus_index(BUS) >= 0 else &"Master"
		bed.volume_db = SILENT_DB
		add_child(bed)
		_beds.append(bed)
	_cue = AudioStreamPlayer.new()
	_cue.name = "Cue"
	_cue.bus = _beds[0].bus
	add_child(_cue)
	_cue.finished.connect(func() -> void:
		_cue_slot = ""
		now_scoring_changed.emit())
	if preferences != null:
		preferences.changed.connect(_on_settings_changed)
	_on_settings_changed()


func _exit_tree() -> void:
	for player: AudioStreamPlayer in _players():
		player.stop()
		player.stream = null


# --- Pure rules, covered by test_campaign_score -----------------------------

## Validated slot list from slots.json text. Bad rows are dropped, never guessed.
static func parse_slots(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(text) if not text.strip_edges().is_empty() else null
	if not parsed is Dictionary or not (parsed as Dictionary).get("slots") is Array:
		return out
	var pattern: RegEx = RegEx.create_from_string(SLOT_PATTERN)
	var seen: Dictionary[String, bool] = {}
	for raw: Variant in (parsed as Dictionary)["slots"]:
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		var id: Variant = row.get("id")
		var kind: Variant = row.get("kind")
		if not id is String or pattern.search(id) == null or seen.has(id) or not kind is String or not kind in KINDS:
			continue
		var slot: Dictionary = {"id": id, "kind": kind, "name": str(row.get("name", id))}
		for key: String in ["mission", "scene", "moment"]:
			if row.get(key) is String:
				slot[key] = row[key]
		# Per-take level match, measured when the takes were made (slots.json gain_note).
		var gains: Dictionary = {}
		if row.get("gain_db") is Dictionary:
			for take: String in TAKES:
				var gain: Variant = (row["gain_db"] as Dictionary).get(take)
				if (gain is float or gain is int) and is_finite(float(gain)):
					gains[take] = clampf(float(gain), -MAX_GAIN_DB, MAX_GAIN_DB)
		slot["gain_db"] = gains
		seen[id] = true
		out.append(slot)
	return out


## The bed slot for a mission id, or "" when the level has none.
static func bed_slot_for(mission: String, slot_list: Array[Dictionary]) -> String:
	if mission.is_empty():
		return ""
	for slot: Dictionary in slot_list:
		if slot["kind"] == "bed" and str(slot.get("mission", "")) == mission:
			return str(slot["id"])
	return ""


static func take_path(slot: String, take: String) -> String:
	return SCORE_ROOT + slot + "/" + take + ".mp3"


## The file a slot plays for a chosen take: the take itself, else the other
## take, else "". `exists` is injectable so tests need no files.
static func resolve_path(slot: String, take: String, exists: Callable = Callable()) -> String:
	if slot.is_empty():
		return ""
	var check: Callable = exists if exists.is_valid() else func(path: String) -> bool: return ResourceLoader.exists(path)
	var order: Array[String] = [take if take in TAKES else DEFAULT_TAKE]
	for other: String in TAKES:
		if not other in order:
			order.append(other)
	for candidate: String in order:
		var path: String = take_path(slot, candidate)
		if bool(check.call(path)):
			return path
	return ""


## A score file's level match from the slot list, 0 dB when it has none.
static func gain_for_path(path: String, slot_list: Array[Dictionary]) -> float:
	var slot: String = slot_from_path(path)
	var take: String = path.get_file().get_basename()
	for row: Dictionary in slot_list:
		if row["id"] == slot:
			return float((row.get("gain_db", {}) as Dictionary).get(take, 0.0))
	return 0.0


## The shipped slot list, read once.
static func shipped_slots() -> Array[Dictionary]:
	if _shipped.is_empty():
		_shipped = parse_slots(_read(SLOTS_PATH))
	return _shipped


## The slot a score file belongs to, or "" for any other path.
static func slot_from_path(path: String) -> String:
	if not path.begins_with(SCORE_ROOT):
		return ""
	var rest: PackedStringArray = path.substr(SCORE_ROOT.length()).split("/")
	return rest[0] if rest.size() == 2 else ""


## The take a player chose for a slot, A unless the setting says otherwise.
static func chosen_take(settings: FragrSettings, slot: String) -> String:
	if settings == null:
		return DEFAULT_TAKE
	var takes: Variant = settings.get_value(SETTINGS_SECTION, "takes")
	if takes is Dictionary and str((takes as Dictionary).get(slot, "")) in TAKES:
		return str((takes as Dictionary)[slot])
	return DEFAULT_TAKE


static func score_enabled(settings: FragrSettings) -> bool:
	return settings == null or bool(settings.get_value(SETTINGS_SECTION, "enabled"))


## A scene's music bed path through the score rules: "" when the score is off,
## the chosen take (or the other one) for a score cue, any other path unchanged.
static func scene_music_path(path: String, settings: FragrSettings, exists: Callable = Callable()) -> String:
	var slot: String = slot_from_path(path)
	if slot.is_empty():
		return path
	if not score_enabled(settings):
		return ""
	return resolve_path(slot, chosen_take(settings, slot), exists)


## Bed level for the current state. Pure so tests can check the table.
static func target_db(is_enabled: bool, has_bed: bool, is_radio_playing: bool, is_held: bool, cue_playing: bool, ducked: bool, heat: float) -> float:
	if not is_enabled or not has_bed or is_radio_playing or is_held or cue_playing:
		return SILENT_DB
	var db: float = BED_DB
	if ducked:
		db += DUCK_DB
	return db + COMBAT_DUCK_DB * clampf(heat, 0.0, 1.0)


## Accepts only known slot ids with an A or B value.
static func clean_takes(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not value is Dictionary:
		return out
	var pattern: RegEx = RegEx.create_from_string(SLOT_PATTERN)
	for key: Variant in (value as Dictionary):
		var take: Variant = (value as Dictionary)[key]
		if key is String and pattern.search(key) != null and take is String and take in TAKES:
			out[key] = take
	return out


# --- Live state ---------------------------------------------------------------

func set_mission(id: String) -> void:
	mission_id = id
	_refresh_bed()


func bed_slot() -> String:
	return _bed_slot


func bed_path() -> String:
	return _bed_path


func cue_slot() -> String:
	return _cue_slot


func duck(seconds: float = DUCK_SECONDS) -> void:
	duck_timer = maxf(duck_timer, seconds)


## Resolved shots this tick, from the same results the shot effects use.
func combat(shots: int) -> void:
	combat_heat = minf(combat_heat + COMBAT_HEAT_PER_SHOT * float(maxi(shots, 0)), 1.5)


## A short cue in a level; the bed rests until it ends. Returns whether it plays.
func play_cue(slot: String) -> bool:
	last_cue = slot
	now_scoring_changed.emit()
	if not enabled or _cue == null:
		return false
	var stream: AudioStream = _load(_cue_path_for(slot))
	if stream == null:
		return false
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	_cue.stream = stream
	_cue.volume_db = CUE_DB + gain_for_path(_cue_path_for(slot), slots)
	_cue.play()
	_cue_slot = slot
	now_scoring_changed.emit()
	return true


## Remember a story page's score cue so its take can be switched later.
func note_scene(manifest: Dictionary) -> void:
	var music: Variant = manifest.get("music")
	if music is Dictionary:
		var slot: String = slot_from_path(str((music as Dictionary).get("path", "")))
		if not slot.is_empty():
			last_cue = slot
			now_scoring_changed.emit()


func _cue_path_for(slot: String) -> String:
	return resolve_path(slot, chosen_take(preferences, slot))


func take_for(slot: String) -> String:
	return chosen_take(preferences, slot)


## Pick A or B for a slot, persist it, and hear it at once.
func set_take(slot: String, take: String) -> void:
	if preferences == null or slot.is_empty() or not take in TAKES:
		return
	var candidate: FragrSettings = preferences.draft()
	var takes: Dictionary = clean_takes(candidate.get_value(SETTINGS_SECTION, "takes")).duplicate()
	takes[slot] = take
	candidate.set_value(SETTINGS_SECTION, "takes", takes)
	if preferences.commit(candidate) != OK:
		push_warning("campaign_score: the take could not be saved")
	# commit() emits changed, which reloads the bed when its file differs.
	if slot == _cue_slot and _cue.playing:
		var position: float = _cue.get_playback_position()
		_cue_slot = ""
		if play_cue(slot):
			_cue.seek(minf(position, maxf(_cue.stream.get_length() - 0.1, 0.0)))


func toggle_take(slot: String) -> void:
	set_take(slot, "b" if take_for(slot) == "a" else "a")


func set_enabled(on: bool) -> void:
	if preferences == null:
		enabled = on
		_refresh_bed()
		return
	var candidate: FragrSettings = preferences.draft()
	candidate.set_value(SETTINGS_SECTION, "enabled", on)
	if preferences.commit(candidate) != OK:
		push_warning("campaign_score: the setting could not be saved")


func audible() -> bool:
	return _gain_db > SILENT_DB + 1.0 and _beds.any(func(bed: AudioStreamPlayer) -> bool: return bed.playing)


func _on_settings_changed() -> void:
	enabled = score_enabled(preferences)
	if not enabled and _cue != null and _cue.playing:
		_cue.stop()
		_cue_slot = ""
	_refresh_bed()


func _refresh_bed() -> void:
	var slot: String = bed_slot_for(mission_id, slots)
	var path: String = resolve_path(slot, chosen_take(preferences, slot)) if enabled else ""
	if slot == _bed_slot and path == _bed_path:
		return
	_bed_slot = slot
	_bed_path = path
	_bed_gain_db = gain_for_path(path, slots)
	for bed: AudioStreamPlayer in _beds:
		bed.stop()
		bed.stream = null
	_gain_db = SILENT_DB
	var stream: AudioStream = _load(path)
	if stream != null and not _beds.is_empty():
		if stream is AudioStreamMP3:
			# The overlap below loops it; a hard loop would land on the seam.
			(stream as AudioStreamMP3).loop = false
		_active = 0
		_beds[0].stream = stream
		_beds[1].stream = stream
		_beds[0].volume_db = SILENT_DB
		_beds[0].play()
	now_scoring_changed.emit()


func _process(delta: float) -> void:
	duck_timer = maxf(duck_timer - delta, 0.0)
	combat_heat = maxf(combat_heat - COMBAT_COOL_PER_SECOND * delta, 0.0)
	if _beds.is_empty():
		return
	var target: float = target_db(enabled, not _bed_path.is_empty(), radio_playing, scene_hold, _cue != null and _cue.playing, duck_timer > 0.0, combat_heat)
	if target > SILENT_DB:
		target += _bed_gain_db
	var rate: float = FADE_OUT_DB_PER_SECOND if target < _gain_db else FADE_IN_DB_PER_SECOND
	_gain_db = move_toward(_gain_db, target, rate * delta)
	var current: AudioStreamPlayer = _beds[_active]
	if current.stream == null:
		return
	var length: float = current.stream.get_length()
	var position: float = current.get_playback_position()
	var overlap: float = minf(CROSSFADE_SECONDS, length * 0.25)
	if current.playing and length > 0.0 and position >= length - overlap:
		# Start the twin from the top and hand over across the overlap.
		_active = 1 - _active
		_beds[_active].play()
		current = _beds[_active]
		position = 0.0
	for index: int in _beds.size():
		var bed: AudioStreamPlayer = _beds[index]
		if not bed.playing:
			continue
		var fade: float = 1.0
		var bed_position: float = bed.get_playback_position()
		if index == _active:
			fade = clampf(bed_position / maxf(overlap, 0.01), 0.0, 1.0) if _beds[1 - index].playing else 1.0
		else:
			fade = clampf((length - bed_position) / maxf(overlap, 0.01), 0.0, 1.0)
		bed.volume_db = _gain_db + linear_to_db(maxf(fade, 0.0001))
	# Silence the bed fully while it rests, and wake it again with the gain.
	if _gain_db <= SILENT_DB and not _beds.any(func(bed: AudioStreamPlayer) -> bool: return bed.stream_paused):
		for bed: AudioStreamPlayer in _beds:
			bed.stream_paused = true
	elif _gain_db > SILENT_DB:
		for bed: AudioStreamPlayer in _beds:
			bed.stream_paused = false


func _players() -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for bed: AudioStreamPlayer in _beds:
		if is_instance_valid(bed):
			out.append(bed)
	if is_instance_valid(_cue):
		out.append(_cue)
	return out


static func _load(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
