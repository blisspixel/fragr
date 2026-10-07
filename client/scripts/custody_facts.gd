class_name CustodyFacts
extends RefCounted

## Strict readers for the custody devices: placed proximity mines and living
## Auditors' repair channels. Presentation only; the server owns every trip,
## blast, channel and repair.
const MAX_MINES: int = 32
const MAX_AUDITORS: int = 16
const MINE_PHASES: Array[String] = ["flying", "arming", "armed", "tripped"]
const REMOTE_PHASES: Array[String] = ["flying", "arming", "armed", "triggered"]
## Matches the server: arming, trip and the longest channel window.
const ARMING_TICKS: int = 40
const TRIP_TICKS: int = 4
const MAX_REPAIRS: int = 2
## A blast radius names its device: grenades are 4 m, mines 4.5 m.
const GRENADE_RADIUS: float = 4.0
const MINE_RADIUS: float = 4.5
const MINE_PEAK: int = 130
const INVALID: String = "The server sent invalid custody devices. Connection closed."

## Boundary for the separately counted deliberate charge contract. Its distinct
## trigger phase never acquires a proximity trip from the local presenter.
## Runtime snapshot delivery is added with the complete M11 capability.
static func remote_state_valid(value: Variant, tick: int) -> bool:
	if not EquipmentState.integer(tick, EquipmentState.MAX_EXACT_INTEGER) \
		or not M03MissionState._exact(value, ["id", "owner_id", "position", "normal", "phase", "phase_started", "phase_ends"]) \
		or not EquipmentState.integer(value["id"], 4294967295) or int(value["id"]) < 1 \
		or not MissionState._uuid(value["owner_id"]) or not _remote_point(value["position"]) \
		or not _remote_point(value["normal"]) or not value["phase"] is String or value["phase"] not in REMOTE_PHASES \
		or not EquipmentState.integer(value["phase_started"], tick) \
		or not EquipmentState.integer(value["phase_ends"], EquipmentState.MAX_EXACT_INTEGER):
		return false
	var length: float = GrenadeFacts.vector(value["normal"]).length()
	var window: int = int(value["phase_ends"]) - int(value["phase_started"])
	match str(value["phase"]):
		"flying":
			return length == 0.0 and window == 0
		"armed":
			return absf(length - 1.0) <= 0.001 and window == 0
		"arming":
			return absf(length - 1.0) <= 0.001 and window == ARMING_TICKS
		"triggered":
			return absf(length - 1.0) <= 0.001 and window == TRIP_TICKS
	return false

static func _remote_point(value: Variant) -> bool:
	if not GrenadeFacts.point(value):
		return false
	for number: Variant in value:
		if absf(float(number)) > 1024.0:
			return false
	return true

static func validation_error(snapshot: Dictionary) -> String:
	if not EquipmentState.integer(snapshot.get("tick"), EquipmentState.MAX_EXACT_INTEGER):
		return INVALID
	var tick: int = int(snapshot["tick"])
	var mines: Variant = snapshot.get("mines", [])
	var remotes: Variant = snapshot.get("remote_mines", [])
	var auditors: Variant = snapshot.get("auditors", [])
	if not mines is Array or mines.size() > MAX_MINES or not remotes is Array or remotes.size() > MAX_MINES \
		or not auditors is Array or auditors.size() > MAX_AUDITORS:
		return INVALID
	var seen: Array[int] = []
	for mine: Variant in mines:
		if not M03MissionState._exact(mine, ["id", "owner_id", "position", "normal", "phase", "phase_started", "phase_ends"]) \
			or not EquipmentState.integer(mine["id"], 4294967295) or int(mine["id"]) < 1 or int(mine["id"]) in seen \
			or not MissionState._uuid(mine["owner_id"]) or not GrenadeFacts.point(mine["position"]) \
			or not GrenadeFacts.point(mine["normal"]) or not mine["phase"] is String or mine["phase"] not in MINE_PHASES \
			or not EquipmentState.integer(mine["phase_started"], tick) \
			or not EquipmentState.integer(mine["phase_ends"], EquipmentState.MAX_EXACT_INTEGER):
			return INVALID
		seen.append(int(mine["id"]))
		var length: float = GrenadeFacts.vector(mine["normal"]).length()
		var window: int = int(mine["phase_ends"]) - int(mine["phase_started"])
		match str(mine["phase"]):
			"flying":
				if length != 0.0 or window != 0:
					return INVALID
			"armed":
				if absf(length - 1.0) > 0.001 or window != 0:
					return INVALID
			"arming":
				if absf(length - 1.0) > 0.001 or window != ARMING_TICKS:
					return INVALID
			"tripped":
				if absf(length - 1.0) > 0.001 or window != TRIP_TICKS:
					return INVALID
	var remote_owners: Dictionary[String, int] = {}
	for remote: Variant in remotes:
		if not remote_state_valid(remote, tick) or int(remote["id"]) in seen:
			return INVALID
		seen.append(int(remote["id"]))
		var owner: String = str(remote["owner_id"])
		remote_owners[owner] = int(remote_owners.get(owner, 0)) + 1
		if remote_owners[owner] > 4:
			return INVALID
	var ids: Array[String] = []
	for auditor: Variant in auditors:
		if not auditor is Dictionary or auditor.size() not in [2, 3] or not auditor.has("id") or not auditor.has("repairs_left") \
			or not MissionState._uuid(auditor["id"]) or auditor["id"] in ids \
			or not EquipmentState.integer(auditor["repairs_left"], MAX_REPAIRS):
			return INVALID
		if auditor.size() == 3 and (not auditor.has("channel_target") or not MissionState._uuid(auditor["channel_target"]) \
			or auditor["channel_target"] == auditor["id"]):
			return INVALID
		ids.append(auditor["id"])
	return ""

## The channel target of one Auditor, or empty while it is not channeling.
static func channel_target(snapshot: Dictionary, auditor_id: String) -> String:
	for auditor: Dictionary in snapshot.get("auditors", []):
		if auditor["id"] == auditor_id:
			return str(auditor.get("channel_target", ""))
	return ""

## Lamp lit for this tick: steady while arming, a slow blink once armed and a
## fast one once tripped. Ticks are server ticks, so every viewer agrees.
static func lamp_lit(mine: Dictionary, tick: int) -> bool:
	match str(mine.get("phase", "")):
		"arming":
			return true
		"armed":
			return posmod(tick - int(mine["phase_started"]), 20) < 3
		"tripped":
			return posmod(tick, 2) == 0
	return false
