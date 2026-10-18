class_name FragIdentity
extends RefCounted

## A bounded compatibility index. An omitted dead body cannot erase a known
## ambiguity. Exhaustion disables legacy lookup until connection retirement.
const LIMIT: int = 512
var _names: Dictionary = {}
var _exhausted: bool = false

func clear() -> void:
	_names.clear()
	_exhausted = false

func observe(rows: Array) -> void:
	for row: Variant in rows:
		if not row is Dictionary:
			continue
		var id: Variant = row.get("id")
		var callsign: Variant = row.get("name")
		if not id is String or id.is_empty() or id.length() > 64 \
			or not callsign is String or callsign.is_empty() or callsign.length() > 64:
			continue
		if not _names.has(callsign):
			if _names.size() >= LIMIT:
				_exhausted = true
				continue
			_names[callsign] = id
		elif _names[callsign] != id:
			_names[callsign] = ""

func unique(callsign: String) -> String:
	return "" if _exhausted else str(_names.get(callsign, ""))

func observe_event(data: Dictionary) -> void:
	for role: String in ["killer", "victim"]:
		var supplied: Variant = data.get(role + "_id")
		if MissionState._uuid(supplied):
			observe([{"id": supplied.to_lower(), "name": data.get(role)}])

func resolve(data: Dictionary, field: String, callsign: String) -> String:
	var value: Variant = data.get(field)
	if value != null:
		# Supplied malformed identities never become absent compatibility input.
		return value.to_lower() if MissionState._uuid(value) else ""
	return unique(callsign)
