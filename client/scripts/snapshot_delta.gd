class_name SnapshotDelta
extends RefCounted

## A `snapshot_delta` names the world this client holds (`base`) and carries
## only what changed; the server owns the shape (`protocol::delta`). Applying
## it rebuilds the full snapshot, which then passes the same boundary checks
## as a snapshot sent whole. Anything that does not fit closes the connection.

const INVALID: String = "The server sent an invalid world update. Connection closed."
const TYPE: String = "snapshot_delta"
const FIELDS: Array[String] = ["type", "base", "tick", "set", "unset", "players"]
## Snapshot fields a delta carries outside `set`.
const FRAMED: Array[String] = ["type", "tick", "players"]
## A carried roster entry's position in the base roster.
const AT: String = "at"
## Far above any snapshot's own field count, so a flood is refused early.
const MAX_FIELDS: int = 128

## The full snapshot `delta` produces from `base`, or an empty Dictionary
## when the delta does not apply. `base` is never changed.
static func apply(base: Dictionary, delta: Dictionary) -> Dictionary:
	if delta.get("type") != TYPE or base.get("type") != "snapshot":
		return {}
	for key: Variant in delta.keys():
		if not key is String or not key in FIELDS:
			return {}
	var held: Variant = base.get("tick")
	var named: Variant = delta.get("base")
	var tick: Variant = delta.get("tick")
	if not EquipmentState.integer(held, EquipmentState.MAX_EXACT_INTEGER) \
			or not EquipmentState.integer(named, EquipmentState.MAX_EXACT_INTEGER) \
			or not EquipmentState.integer(tick, EquipmentState.MAX_EXACT_INTEGER):
		return {}
	if int(named) != int(held) or int(tick) <= int(held):
		return {}
	var held_players: Variant = base.get("players")
	var entries: Variant = delta.get("players")
	if not held_players is Array or not entries is Array or (entries as Array).size() > ActorState.MAX_PLAYERS:
		return {}
	var world: Dictionary = base.duplicate(true)
	world["tick"] = tick
	var changed: Variant = delta.get("set", {})
	if not changed is Dictionary or (changed as Dictionary).size() > MAX_FIELDS:
		return {}
	for key: Variant in (changed as Dictionary).keys():
		if not key is String or key in FRAMED:
			return {}
		world[key] = (changed as Dictionary)[key]
	var dropped: Variant = _names(delta.get("unset", []))
	if dropped == null:
		return {}
	for name: String in dropped:
		if name in FRAMED:
			return {}
		world.erase(name)
	var held_rows: Array = held_players
	var known: Dictionary = {}
	for entry: Variant in held_rows:
		if not entry is Dictionary or not (entry as Dictionary).get("id") is String \
				or known.has(entry["id"]):
			return {}
		known[entry["id"]] = true
	# An entry with an `id` is a whole arrival. Any other entry carries the
	# base entry at position `at`, which defaults to one past the previous
	# carried entry's position.
	var carried: Dictionary = {}
	var cursor: int = 0
	var seen: Dictionary = {}
	var players: Array = []
	for entry: Variant in entries:
		if not entry is Dictionary or (entry as Dictionary).size() > MAX_FIELDS:
			return {}
		var row: Dictionary = entry
		if row.has("id"):
			if not row["id"] is String or row.has(AT) or row.has("unset"):
				return {}
			players.append(row)
			continue
		var at: Variant = row.get(AT, cursor)
		if not EquipmentState.integer(at, held_rows.size() - 1) or carried.has(int(at)):
			return {}
		carried[int(at)] = true
		cursor = int(at) + 1
		var merged: Dictionary = (held_rows[int(at)] as Dictionary).duplicate(true)
		for key: Variant in row.keys():
			if key != "unset" and key != AT:
				merged[key] = row[key]
		var gone: Variant = _names(row.get("unset", []))
		if gone == null or "id" in gone:
			return {}
		for name: String in gone:
			merged.erase(name)
		players.append(merged)
	for row: Dictionary in players:
		if seen.has(row["id"]):
			return {}
		seen[row["id"]] = true
	world["players"] = players
	return world

## A list of field names, or null when it is anything else.
static func _names(list: Variant) -> Variant:
	if not list is Array or (list as Array).size() > MAX_FIELDS:
		return null
	var names: Array[String] = []
	for name: Variant in list:
		if not name is String:
			return null
		names.append(name)
	return names
