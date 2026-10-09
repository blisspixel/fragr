class_name PlayerRecords
extends RefCounted

## Bounded local history, not identity authentication or a public reward ledger.
const PATH: String = "user://service-record"
const VERSION: int = 3
const LEGACY_VERSION: int = 1
const PROVENANCE_VERSION: int = 2
const LIMIT: int = 256
const MAX_BYTES: int = 4 * 1024 * 1024
var entries: Array[Dictionary] = []
var unlocks: Array[Dictionary] = []
var customization: Dictionary = PlayerRewards.DEFAULTS.duplicate()
var profile_id: String = ""
var error: Error = OK
var storage_path: String
var _generation: int = 0
var _blocked: bool = false
var _dirty: bool = false
var _last_saved_tick: int = -1
var _award_notices: Array[String] = []

static func for_tree(tree: SceneTree) -> PlayerRecords:
	var fallback: String = "" if tree.get_meta("fragr_automated", false) else PATH
	return PlayerRecords.new(str(tree.get_meta("fragr_records_path", fallback)))

func _init(path: String = PATH) -> void:
	storage_path = path
	profile_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_load()

func _slot(generation: int) -> String:
	return "%s.%d.json" % [storage_path, generation % 2]

func _load() -> void:
	if storage_path.is_empty():
		return
	var candidates: Array[Dictionary] = []
	var existing: int = 0
	for slot: int in range(2):
		var path: String = _slot(slot)
		if not FileAccess.file_exists(path):
			continue
		existing += 1
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES:
			continue
		var parser: JSON = JSON.new()
		var parsed: Error = parser.parse(file.get_as_text())
		file.close()
		if parsed != OK or not parser.data is Dictionary:
			continue
		var data: Dictionary = parser.data
		# A future format is preserved even if the other slot is readable.
		if not _supported_version(data.get("version")):
			_blocked = true
			error = ERR_FILE_UNRECOGNIZED
			return
		if _valid_document(data) and int(data["generation"]) % 2 == slot:
			candidates.append(data)
	if candidates.is_empty():
		if existing > 0:
			_blocked = true
			error = ERR_FILE_CORRUPT
		return
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["generation"]) > int(b["generation"]))
	var selected: Dictionary = candidates[0]
	if candidates.size() == 2 and candidates[1]["profile_id"] != selected["profile_id"]:
		_blocked = true
		error = ERR_FILE_CORRUPT
		return
	profile_id = selected["profile_id"]
	_generation = int(selected["generation"])
	entries.assign(selected["entries"])
	if int(selected["version"]) == VERSION:
		unlocks.assign(selected["unlocks"])
		customization = selected["customization"].duplicate()

static func _valid_document(data: Dictionary) -> bool:
	if not _supported_version(data.get("version")) \
		or data.size() != (6 if data["version"] == VERSION else 4) or not data.get("profile_id") is String or data["profile_id"].length() != 32 \
		or not data["profile_id"].is_valid_hex_number() \
		or not EquipmentState.integer(data.get("generation"), EquipmentState.MAX_EXACT_INTEGER - 1) \
		or int(data["generation"]) < 1 or not data.get("entries") is Array or data["entries"].size() > LIMIT:
		return false
	var seen: Dictionary = {}
	for entry: Variant in data["entries"]:
		if not entry is Dictionary or entry.size() != 2 + int(entry.has("server_sha256")) or entry.get("origin") not in ["local", "external"] or not entry.get("record") is Dictionary:
			return false
		if entry.has("server_sha256") and (data["version"] == LEGACY_VERSION or entry["origin"] != "local" or not _valid_server_hash(entry["server_sha256"])):
			return false
		var record: Dictionary = entry["record"]
		if not PlayerRecord.validation_error(record, record.get("player_id")).is_empty():
			return false
		var identity: String = PlayerRecord.key(record)
		if seen.has(identity):
			return false
		seen[identity] = true
	if data["version"] == VERSION:
		if not PlayerRewards.valid_unlocks(data.get("unlocks")):
			return false
		var proofs: Array[Dictionary] = []
		proofs.assign(data["unlocks"])
		if not PlayerRewards.valid_selection(data.get("customization"), proofs):
			return false
	return true

static func _supported_version(value: Variant) -> bool:
	return EquipmentState.integer(value, VERSION) and int(value) in [LEGACY_VERSION, PROVENANCE_VERSION, VERSION]

static func _valid_server_hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number() and value == value.to_lower()

func accept(record: Dictionary, origin: String, server_hash: String = "") -> Error:
	if _blocked:
		return error
	if origin not in ["local", "external"] or not PlayerRecord.validation_error(record, record.get("player_id")).is_empty() \
		or (not server_hash.is_empty() and (origin != "local" or not _valid_server_hash(server_hash))):
		return ERR_INVALID_DATA
	var canonical: Dictionary = record.duplicate(true)
	canonical.erase("type")
	var found: int = -1
	for index: int in range(entries.size()):
		var old: Dictionary = entries[index]["record"]
		if PlayerRecord.key(old) == PlayerRecord.key(canonical):
			if not PlayerRecord.validation_error(canonical, canonical["player_id"], old).is_empty() or origin != entries[index]["origin"] \
				or server_hash != entries[index].get("server_sha256", ""):
				return ERR_INVALID_DATA
			if canonical == old or PlayerRecord.terminal(old):
				return save()
			found = index
			break
	var urgent: bool = found < 0 or PlayerRecord.terminal(canonical)
	if found >= 0:
		urgent = urgent or entries[found]["record"]["scope"] != canonical["scope"]
		entries.remove_at(found)
	var entry: Dictionary = {"record": canonical, "origin": origin}
	if not server_hash.is_empty():
		entry["server_sha256"] = server_hash
	entries.push_front(entry)
	if entries.size() > LIMIT:
		entries.pop_back()
	for award: String in PlayerRewards.eligible(canonical, origin, server_hash):
		if not PlayerRewards.owns(unlocks, award):
			unlocks.append({"id": award, "record": canonical.duplicate(true), "server_sha256": server_hash})
			_award_notices.append(award)
			urgent = true
	_dirty = true
	if urgent or _last_saved_tick < 0 or int(canonical["tick"]) - _last_saved_tick >= 200:
		error = save()
		if error == OK:
			_last_saved_tick = int(canonical["tick"])
	return error

func save() -> Error:
	if _blocked:
		return error
	if not _dirty or storage_path.is_empty():
		error = OK
		return OK
	if _generation >= EquipmentState.MAX_EXACT_INTEGER - 1:
		error = ERR_UNAVAILABLE
		return error
	var next: int = _generation + 1
	var data: Dictionary = _document(next)
	var text: String = JSON.stringify(data)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		error = ERR_OUT_OF_MEMORY
		return error
	var destination: String = _slot(next)
	var temporary: String = destination + ".%d.tmp" % OS.get_process_id()
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		error = FileAccess.get_open_error()
		return error
	var stored: bool = file.store_string(text)
	file.flush()
	var result: Error = file.get_error() if stored else ERR_FILE_CANT_WRITE
	file.close()
	# Godot's Windows replacement removes the destination before moving. The
	# other slot is the last committed generation and survives either failure.
	if result == OK:
		result = DirAccess.rename_absolute(temporary, destination)
	if result == OK:
		_generation = next
		_dirty = false
	elif FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	error = result
	return result

func _document(generation: int) -> Dictionary:
	return {"version": VERSION, "profile_id": profile_id, "generation": generation,
		"entries": entries, "unlocks": unlocks, "customization": customization}

func select_customization(candidate: Dictionary) -> Error:
	if not PlayerRewards.valid_selection(candidate, unlocks):
		return ERR_INVALID_DATA
	if _blocked:
		return error
	var previous: Dictionary = customization
	var was_dirty: bool = _dirty
	customization = candidate.duplicate()
	_dirty = true
	var result: Error = save()
	if result != OK:
		customization = previous
		_dirty = was_dirty
	return result

func writing_blocked() -> bool:
	return _blocked

func take_award_notices() -> Array[String]:
	if error != OK:
		return []
	var pending: Array[String] = _award_notices.duplicate()
	_award_notices.clear()
	return pending

func totals(kind: String) -> Dictionary:
	var counts: Dictionary = PlayerRecord.empty_counts()
	for entry: Dictionary in entries:
		if entry["record"]["scope"]["kind"] == kind:
			PlayerRecord.add_counts(counts, entry["record"]["total"])
	return counts

## Exact local server builds form separate cohorts. Historical records without
## this provenance remain readable but cannot establish a comparable time.
func mission_comparison(record: Dictionary, server_hash: String) -> Dictionary:
	if not _valid_server_hash(server_hash) or not PlayerRecord.validation_error(record, record.get("player_id")).is_empty() \
		or record["role"] != "human" or record["status"] != "complete" or record["scope"]["kind"] != "mission" \
		or not record.has("mission_elapsed_ticks"):
		return {}
	var scope: Dictionary = record["scope"]
	var previous_ticks: int = -1
	var count: int = 1
	for entry: Dictionary in entries:
		var other: Dictionary = entry["record"]
		var other_scope: Dictionary = other["scope"]
		if entry["origin"] != "local" or entry.get("server_sha256", "") != server_hash \
			or PlayerRecord.key(other) == PlayerRecord.key(record) or other["status"] != "complete" \
			or other["role"] != "human" or other_scope["kind"] != "mission" or not other.has("mission_elapsed_ticks") \
			or other["map_id"] != record["map_id"] or other_scope["mission"] != scope["mission"] \
			or other_scope["rules"]["difficulty"] != scope["rules"]["difficulty"] \
			or int(other_scope["rules"]["revision"]) != int(scope["rules"]["revision"]) \
			or other["ticks_per_second"] != record["ticks_per_second"] \
			or (other_scope["run"] == null) != (scope["run"] == null):
			continue
		var ticks: int = int(other["mission_elapsed_ticks"])
		previous_ticks = ticks if previous_ticks < 0 else mini(previous_ticks, ticks)
		count += 1
	var elapsed: int = int(record["mission_elapsed_ticks"])
	return {"best_ticks": elapsed if previous_ticks < 0 else mini(elapsed, previous_ticks),
		"previous_ticks": previous_ticks, "count": count,
		"delta_ticks": 0 if previous_ticks < 0 else elapsed - previous_ticks}

func export_json(path: String) -> Error:
	if FileAccess.file_exists(path):
		return ERR_ALREADY_EXISTS
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var document: Dictionary = _document(maxi(1, _generation))
	var stored: bool = file.store_string(JSON.stringify(document, "\t"))
	file.flush()
	var result: Error = file.get_error() if stored else ERR_FILE_CANT_WRITE
	file.close()
	if result != OK:
		DirAccess.remove_absolute(path)
	return result
