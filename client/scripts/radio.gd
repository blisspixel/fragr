extends Node
## Contested Frequency radio: station list from stations.json, tracks from the
## audiogen manifest, shuffle without repeats, ducking under Host lines and combat.
## Presentation only. Missing assets are fine: the radio stays silent.
##
## The dial works like a car radio in a crime caper: previous and next station
## wrap through one extra stop, RADIO OFF. On a gamepad the D-pad left and
## right arms turn the dial on release; holding right skips the track and
## holding left switches the radio off or on.

signal track_started(station_name: String, title: String)
## After every change a listener can see: station, track, power, missing file,
## scene hold. Carries `now_playing()`.
signal now_playing_changed(info: Dictionary)

const STATIONS_PATH := "res://assets/audio/radio/stations.json"
const MANIFEST_PATH := "res://assets/audio/audiogen-manifest.json"
const AUDIO_ROOT := "res://assets/audio/"
const RADIO_PREFIX := "radio/"
const NO_REPEAT_WINDOW := 12
const SPECTATE_DB := -6.0
const PLAYING_DB := -8.0
const DUCK_DB := -9.0
const MUTE_DB := -80.0
const DUCK_SECONDS := 3.0
const DUCK_RECOVER_SECONDS := 1.5
const DEFAULT_BADGE_COLOR := "#5A554F"
## A gamepad station arm held this long becomes its second control.
const HOLD_SECONDS := 0.45
## Station dial actions and their direction.
const STATION_ACTIONS := {"radio_prev_station": -1, "radio_next_station": 1}

var stations: Array = []
var station_index := 0
var enabled := true
var human_mode := false
var duck_timer := 0.0
var history: Dictionary = {}
var player: AudioStreamPlayer
var rng := RandomNumberGenerator.new()
var current_title := ""
## The last chosen track did not load; the radio is silent until the next pick.
var unavailable := false
## A story scene owns the music for now.
var scene_hold := false
## The match menu is open: its own Music / Radio buttons drive the radio, and
## the D-pad moves the menu focus instead of turning the dial behind it.
var shortcuts_blocked := false
var _holds: Dictionary = {}


func _ready() -> void:
	rng.randomize()
	player = AudioStreamPlayer.new()
	player.name = "Player"
	player.bus = "Radio"
	add_child(player)
	player.finished.connect(_on_track_finished)
	load_catalog()
	if stations.is_empty():
		return
	choose_start_station()
	_apply_volume(0.0, true)
	play_random()
	# Signals connected by the parent after add_child would miss an emit here.
	call_deferred("announce_station")


func _exit_tree() -> void:
	# Release an active decoder before the scene retires. The mixer can outlive
	# the node for a frame, especially when a saved run returns to the menu.
	if is_instance_valid(player):
		player.stop()
		player.stream = null


## Build the station list. Texts can be injected for headless tests.
func load_catalog(stations_text: String = "", manifest_text: String = "") -> void:
	var stations_data: Variant = _parse_json(stations_text if stations_text != "" else _read_text(STATIONS_PATH))
	var manifest_data: Variant = _parse_json(manifest_text if manifest_text != "" else _read_text(MANIFEST_PATH))
	var station_list: Array = stations_data.get("stations", []) if stations_data is Dictionary else []
	var entries: Dictionary = manifest_data.get("entries", {}) if manifest_data is Dictionary else {}
	stations = build_stations(station_list, entries)
	station_index = clampi(station_index, 0, maxi(stations.size() - 1, 0))


## Group manifest entries by station folder. Pure so tests can call it directly.
static func build_stations(station_list: Array, entries: Dictionary) -> Array:
	var result: Array = []
	for raw in station_list:
		if not (raw is Dictionary) or not raw.has("id"):
			continue
		var id := str(raw["id"])
		var prefix := RADIO_PREFIX + id + "/"
		var tracks: Array = []
		var names := entries.keys()
		names.sort()
		for name in names:
			var name_str := str(name)
			if not name_str.begins_with(prefix):
				continue
			var entry: Dictionary = entries[name]
			var file := str(entry.get("file", ""))
			if file == "":
				continue
			var title := str(entry.get("title", ""))
			if title == "":
				title = name_str.substr(prefix.length())
			tracks.append({
				"name": name_str,
				"path": AUDIO_ROOT + file,
				"title": title,
				"length_ms": int(entry.get("length_ms", 0)),
			})
		var badge := str(raw.get("badge", ""))
		if badge == "":
			badge = id.substr(0, 2).to_upper()
		result.append({
			"id": id,
			"name": str(raw.get("name", id)),
			"dj": str(raw.get("dj", "")),
			"badge": badge,
			"color": str(raw.get("color", DEFAULT_BADGE_COLOR)),
			"tagline": str(raw.get("tagline", "")),
			"ducks_in_combat": bool(raw.get("ducks_in_combat", true)),
			"tracks": tracks,
		})
	return result


func current_station() -> Dictionary:
	if stations.is_empty():
		return {}
	return stations[station_index]


## Normal launches start on a varied populated station, then shuffle its tracks.
## Manual cycling still exposes stations that currently have no tracks.
func choose_start_station() -> void:
	var populated: Array[int] = []
	for index: int in range(stations.size()):
		if not stations[index].get("tracks", []).is_empty():
			populated.append(index)
	station_index = populated[rng.randi_range(0, populated.size() - 1)] if not populated.is_empty() else 0


## Everything the now-playing toast and the match menu show. One answer for
## every surface, so a label can never claim a song the player is not hearing.
## state: "playing", "held" (paused under a story scene), "off", "off_air"
## (station has no tracks), "unavailable" (the chosen file did not load),
## "idle" (on, between tracks) or "none" (no catalog at all).
func now_playing() -> Dictionary:
	var station := current_station()
	var state := "playing"
	if stations.is_empty():
		state = "none"
	elif not enabled:
		state = "off"
	elif station.get("tracks", []).is_empty():
		state = "off_air"
	elif unavailable:
		state = "unavailable"
	elif current_title == "":
		state = "idle"
	elif scene_hold:
		state = "held"
	return {
		"state": state,
		"id": str(station.get("id", "")),
		"station": str(station.get("name", "")),
		"badge": str(station.get("badge", "")),
		"dj": str(station.get("dj", "")),
		"tagline": str(station.get("tagline", "")),
		"title": current_title if state in ["playing", "held"] else "",
		"index": station_index,
		"count": stations.size(),
		"ducked": duck_timer > 0.0,
	}


func announce_station() -> void:
	if stations.is_empty():
		return
	now_playing_changed.emit(now_playing())


## Pick a track not heard in the last NO_REPEAT_WINDOW plays for this station.
func pick_next(station: Dictionary) -> Dictionary:
	var tracks: Array = station.get("tracks", [])
	if tracks.is_empty():
		return {}
	var id := str(station.get("id", ""))
	var recent: Array = history.get(id, [])
	var window := mini(NO_REPEAT_WINDOW, tracks.size() - 1)
	var candidates: Array = []
	for track in tracks:
		if not recent.has(track["name"]):
			candidates.append(track)
	if candidates.is_empty():
		candidates = tracks
	var chosen: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	recent.append(chosen["name"])
	while recent.size() > window:
		recent.pop_front()
	history[id] = recent
	return chosen


func play_random() -> void:
	var station := current_station()
	unavailable = false
	var track := pick_next(station)
	if track.is_empty():
		# Off the air: the toast says so instead of naming a song.
		_stop_stream()
		announce_station()
		return
	var path := str(track["path"])
	var stream: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	if stream == null:
		# Never leave the previous song running under a new station's name.
		_stop_stream()
		unavailable = true
		announce_station()
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	if player:
		# One player owns radio playback; replacing its stream stops the old one.
		player.stream = stream
		player.play()
		player.stream_paused = scene_hold
	current_title = str(track["title"])
	track_started.emit(str(station.get("name", "")), current_title)
	announce_station()


func _stop_stream() -> void:
	current_title = ""
	if player:
		player.stop()
		player.stream = null


func next_station() -> void:
	_step_station(1)


func prev_station() -> void:
	_step_station(-1)


## Turn the dial. The dial has one extra stop after the last station,
## RADIO OFF, so both directions wrap through silence.
func _step_station(delta: int) -> void:
	if stations.is_empty():
		return
	var off_slot := stations.size()
	var position := station_index if enabled else off_slot
	position = posmod(position + delta, off_slot + 1)
	if position == off_slot:
		enabled = false
		unavailable = false
		_stop_stream()
		announce_station()
		return
	station_index = position
	enabled = true
	play_random()


func next_track() -> void:
	if stations.is_empty():
		return
	if not enabled:
		announce_station()
		return
	play_random()


## Power. Off stops the song; on returns to the same station with a fresh
## track, because the player does not keep a position inside a song.
func toggle() -> void:
	if stations.is_empty():
		return
	enabled = not enabled
	unavailable = false
	if enabled:
		play_random()
	else:
		_stop_stream()
		announce_station()


## Story scenes own the music while they play: pause the song where it is and
## pick it up afterwards, so a scene bed never plays over a station.
func set_scene_hold(on: bool) -> void:
	if scene_hold == on:
		return
	scene_hold = on
	if player:
		player.stream_paused = on
	announce_station()


func set_human_mode(on: bool) -> void:
	human_mode = on


## Lower the music for a moment while the Host talks.
func duck(seconds: float = DUCK_SECONDS) -> void:
	duck_timer = maxf(duck_timer, seconds)


## Volume for the current state. Pure so tests can check the table.
static func target_db(is_human: bool, is_ducked: bool, ducks_in_combat: bool) -> float:
	var db := PLAYING_DB if is_human else SPECTATE_DB
	if is_ducked and (ducks_in_combat or not is_human):
		db += DUCK_DB
	return db


func _process(delta: float) -> void:
	advance_holds(delta)
	if duck_timer > 0.0:
		duck_timer = maxf(duck_timer - delta, 0.0)
	_apply_volume(delta, false)


func _apply_volume(delta: float, immediate: bool) -> void:
	if player == null:
		return
	if not enabled:
		player.volume_db = MUTE_DB
		return
	var station := current_station()
	var target := target_db(human_mode, duck_timer > 0.0, bool(station.get("ducks_in_combat", true)))
	if immediate:
		player.volume_db = target
		return
	var rate := 60.0 if target < player.volume_db else (DUCK_DB * -1.0) / DUCK_RECOVER_SECONDS
	player.volume_db = move_toward(player.volume_db, target, rate * delta)


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event) and is_inside_tree():
		get_viewport().set_input_as_handled()


## Keys act on press. A gamepad station arm acts on release, so the same arm
## can also be held: hold next to skip the track, hold previous for power.
## Returns true when the event was a radio control.
func handle_input(event: InputEvent) -> bool:
	if shortcuts_blocked:
		# A hold begun before the menu opened loses its release and is dropped.
		return false
	for action: String in STATION_ACTIONS:
		if not InputMap.has_action(action):
			continue
		if event.is_action_pressed(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				_holds[action] = {"seconds": 0.0, "fired": false}
			else:
				_step_station(int(STATION_ACTIONS[action]))
			return true
		if event.is_action_released(action) and _holds.has(action):
			var hold: Dictionary = _holds[action]
			_holds.erase(action)
			if not bool(hold["fired"]):
				_step_station(int(STATION_ACTIONS[action]))
			return true
	if InputMap.has_action("radio_next_track") and event.is_action_pressed("radio_next_track"):
		next_track()
		return true
	if InputMap.has_action("radio_toggle") and event.is_action_pressed("radio_toggle"):
		toggle()
		return true
	return false


## Advance held station arms. A hold whose release was lost (focus change, a
## menu taking the event) is dropped without acting.
func advance_holds(delta: float) -> void:
	for action: String in _holds.keys():
		var hold: Dictionary = _holds[action]
		if not Input.is_action_pressed(action):
			_holds.erase(action)
			continue
		if bool(hold["fired"]):
			continue
		hold["seconds"] = float(hold["seconds"]) + delta
		if float(hold["seconds"]) >= HOLD_SECONDS:
			hold["fired"] = true
			if int(STATION_ACTIONS[action]) > 0:
				next_track()
			else:
				toggle()


func _on_track_finished() -> void:
	if enabled:
		play_random()


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _parse_json(text: String) -> Variant:
	if text.strip_edges() == "":
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed != null else {}
