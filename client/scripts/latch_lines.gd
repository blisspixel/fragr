class_name LatchLines
extends Node

## Latch's few spoken lines in Levels 12, 13, 14 and 16, said once a server
## fact makes them true: the habitat's workers come out of their frames, the
## foundry overseer drops his baton, the workers answer, the launch depot is
## taken and the jeep is free, and Latch walks onto the avenue forecourt from
## the back lane. A late join or a resume that finds a fact already true says
## nothing about it. Presentation only; the server places Latch.

const LINES: Dictionary[String, String] = {
	"m12_frames": "M12_LATCH_FRAMES",
	"m13_ask": "M13_LATCH_ASK",
	"m13_answered": "M13_LATCH_THEIR_CALL",
	"m14_drive": "M14_LATCH_YOU_DRIVE",
	"m16_arrived": "M16_LATCH_NO_STEERING",
}

var caption: SpeakerCaption
var _identity: String = ""
## Facts already true when this client first saw the attempt, or said.
var _settled: Dictionary[String, bool] = {}
var _mission: String = ""
var _in_progress: bool = false
## A snapshot of this attempt has been seen (Level 16's arrival).
var _snapshot_seen: bool = false

func _init() -> void:
	caption = SpeakerCaption.new()
	caption.name = "LatchCaptions"
	add_child(caption)

func clear() -> void:
	_identity = ""
	_mission = ""
	_in_progress = false
	_snapshot_seen = false
	_settled.clear()
	caption.clear()

## The facts this state makes true, by line key.
static func facts(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var id: String = str(state.get("id", ""))
	match id:
		MissionState.M12_ID:
			var m12: Variant = state.get("m12")
			if m12 is Dictionary and m12.get("challenges") is Dictionary and m12["challenges"].get("workers_released") == true:
				result.append("m12_frames")
		MissionState.M13_ID:
			var m13: Variant = state.get("m13")
			if m13 is Dictionary:
				if m13.get("overseer_surrendered") == true:
					result.append("m13_ask")
				if m13.get("challenges") is Dictionary and m13["challenges"].has("workers"):
					result.append("m13_answered")
		MissionState.M14_ID:
			var m14: Variant = state.get("m14")
			if m14 is Dictionary and m14.get("completed") is Array and "depot_secured" in m14["completed"]:
				result.append("m14_drive")
	return result

func apply_state(state: Dictionary) -> void:
	var id: String = str(state.get("id", ""))
	if id not in [MissionState.M12_ID, MissionState.M13_ID, MissionState.M14_ID, MissionState.M16_ID]:
		if not _identity.is_empty():
			clear()
		return
	var identity: String = "%s:%s" % [id, str(state.get("attempt", 0))]
	var fresh: bool = identity != _identity
	if fresh:
		# A retry starts the level over; whatever was said is said again.
		_identity = identity
		_snapshot_seen = false
		_settled.clear()
		caption.clear()
	_mission = id
	_in_progress = str(state.get("phase", "")) == "in_progress"
	for key: String in facts(state):
		_settle(key, fresh or not _in_progress)

## Latch says the arrival line on reaching the party, not out of sight in
## the lane the server placed them in.
const ARRIVAL_REACH: float = 8.0

func apply_snapshot(snapshot: Dictionary) -> void:
	if _mission != MissionState.M16_ID or _identity.is_empty():
		return
	var players: Variant = snapshot.get("players")
	if not players is Array:
		return
	var latch: Vector2 = Vector2.INF
	var party: Array[Vector2] = []
	for actor: Variant in players:
		if not actor is Dictionary or not actor.get("x") is float or not actor.get("z") is float:
			continue
		var at: Vector2 = Vector2(float(actor["x"]), float(actor["z"]))
		if ActorState.is_companion(actor):
			latch = at
		elif ActorState.is_participant(actor):
			party.append(at)
	if latch != Vector2.INF:
		var near: bool = party.any(func(at: Vector2) -> bool: return at.distance_to(latch) <= ARRIVAL_REACH)
		# Already here at first sight: a resume, not an arrival.
		if not _snapshot_seen:
			_settle("m16_arrived", true)
		elif near:
			_settle("m16_arrived", not _in_progress)
	_snapshot_seen = true

## Mark a fact true; say its line unless it was already true when seen.
func _settle(key: String, silently: bool) -> void:
	if _settled.has(key):
		return
	_settled[key] = true
	if not silently:
		caption.say([tr(LINES[key])])

func showing() -> String:
	return caption.showing()
