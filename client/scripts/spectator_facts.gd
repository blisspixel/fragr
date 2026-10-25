class_name SpectatorFacts
extends RefCounted

## The booth's facts (`spectator_facts`): live pad clocks, the Custody Plate,
## sprees and open multikill chains. The server sends them only to a
## connection that watches and holds no fighter. Presentation only: the panel
## and the director read them, nothing decides a fight from them.
const MAX_PADS: int = 64
const MAX_RUNS: int = 16
const MAX_TICKS: int = 4294967295
const MAX_ID: int = 64

## The facts as typed rows, or an empty dictionary when anything is off.
## Readers refuse unknown fields, as the server's own type does.
static func parse(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var root: Dictionary = data
	for key: Variant in root.keys():
		if not key in ["type", "tick", "spree_step", "pads", "plate", "sprees", "chains"]:
			return {}
	if root.get("type") != "spectator_facts" or not EquipmentState.integer(root.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not EquipmentState.integer(root.get("spree_step"), 1000):
		return {}
	var pads: Array[Dictionary] = []
	var raw_pads: Variant = root.get("pads", [])
	if not raw_pads is Array or (raw_pads as Array).size() > MAX_PADS:
		return {}
	for raw: Variant in raw_pads:
		var pad: Dictionary = _pad(raw)
		if pad.is_empty():
			return {}
		pads.append(pad)
	var plate: Dictionary = {}
	if root.has("plate"):
		plate = _plate(root["plate"])
		if plate.is_empty():
			return {}
	var sprees: Array[Dictionary] = _runs(root.get("sprees", []), ["id", "frags"])
	var chains: Array[Dictionary] = _runs(root.get("chains", []), ["id", "frags", "open_for"])
	if sprees.size() == 1 and sprees[0].is_empty() or chains.size() == 1 and chains[0].is_empty():
		return {}
	return {"tick": int(root["tick"]), "spree_step": int(root["spree_step"]), "pads": pads,
		"plate": plate, "sprees": sprees, "chains": chains}

static func _short_text(value: Variant) -> bool:
	return value is String and not (value as String).is_empty() and (value as String).length() <= MAX_ID

static func _pad(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var pad: Dictionary = value
	for key: Variant in pad.keys():
		if not key in ["id", "kind", "weapon", "power", "back_in"]:
			return {}
	if not _short_text(pad.get("id")) or not _short_text(pad.get("kind")) \
		or not EquipmentState.integer(pad.get("back_in"), MAX_TICKS):
		return {}
	var weapon: Variant = pad.get("weapon", "")
	var power: Variant = pad.get("power", false)
	if not weapon is String or (weapon as String).length() > MAX_ID or not power is bool:
		return {}
	return {"id": pad["id"], "kind": pad["kind"], "weapon": weapon, "power": power, "back_in": int(pad["back_in"])}

static func _plate(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var plate: Dictionary = value
	for key: Variant in plate.keys():
		if not key in ["id", "up", "back_in", "holder", "armor"]:
			return {}
	if not _short_text(plate.get("id")) or not plate.get("up") is bool:
		return {}
	var back_in: int = -1
	if plate.has("back_in"):
		if not EquipmentState.integer(plate["back_in"], MAX_TICKS):
			return {}
		back_in = int(plate["back_in"])
	var holder: String = ""
	var armor: int = 0
	if plate.has("holder") or plate.has("armor"):
		if not MissionState._uuid(plate.get("holder")) or not EquipmentState.integer(plate.get("armor"), 1000):
			return {}
		holder = str(plate["holder"])
		armor = int(plate["armor"])
	return {"id": plate["id"], "up": plate["up"], "back_in": back_in, "holder": holder, "armor": armor}

## Rows of `{id, frags[, open_for]}`. A single empty row marks a refusal.
static func _runs(value: Variant, keys: Array[String]) -> Array[Dictionary]:
	var refused: Array[Dictionary] = [{}]
	if not value is Array or (value as Array).size() > MAX_RUNS:
		return refused
	var rows: Array[Dictionary] = []
	for raw: Variant in value:
		if not M03MissionState._exact(raw, keys) or not MissionState._uuid(raw["id"]) \
			or not EquipmentState.integer(raw["frags"], 100000):
			return refused
		var row: Dictionary = {"id": str(raw["id"]), "frags": int(raw["frags"])}
		if keys.has("open_for"):
			if not EquipmentState.integer(raw["open_for"], MAX_TICKS):
				return refused
			row["open_for"] = int(raw["open_for"])
		rows.append(row)
	return rows
