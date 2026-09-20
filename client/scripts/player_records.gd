class_name PlayerRecords
extends RefCounted

## Bounded local history, not identity authentication or a public reward ledger.
const PATH: String = "user://service-record"
const VERSION: int = 1
const LIMIT: int = 256
const MAX_BYTES: int = 4 * 1024 * 1024
var entries: Array[Dictionary] = []
var profile_id: String = ""
var error: Error = OK
var storage_path: String
var _generation: int = 0
var _blocked: bool = false
var _dirty: bool = false
var _last_saved_tick: int = -1

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
		if data.get("version") != VERSION:
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

static func _valid_document(data: Dictionary) -> bool:
	if data.size() != 4 or not data.get("profile_id") is String or data["profile_id"].length() != 32 \
		or not data["profile_id"].is_valid_hex_number() \
		or not EquipmentState.integer(data.get("generation"), EquipmentState.MAX_EXACT_INTEGER - 1) \
		or int(data["generation"]) < 1 or not data.get("entries") is Array or data["entries"].size() > LIMIT:
		return false
	var seen: Dictionary = {}
	for entry: Variant in data["entries"]:
		if not entry is Dictionary or entry.size() != 2 or entry.get("origin") not in ["local", "external"] or not entry.get("record") is Dictionary:
			return false
		var record: Dictionary = entry["record"]
		if not PlayerRecord.validation_error(record, record.get("player_id")).is_empty():
			return false
		var identity: String = PlayerRecord.key(record)
		if seen.has(identity):
			return false
		seen[identity] = true
	return true

func accept(record: Dictionary, origin: String) -> Error:
	if origin not in ["local", "external"] or not PlayerRecord.validation_error(record, record.get("player_id")).is_empty():
		return ERR_INVALID_DATA
	var canonical: Dictionary = record.duplicate(true)
	canonical.erase("type")
	var found: int = -1
	for index: int in range(entries.size()):
		var old: Dictionary = entries[index]["record"]
		if PlayerRecord.key(old) == PlayerRecord.key(canonical):
			if not PlayerRecord.validation_error(canonical, canonical["player_id"], old).is_empty() or origin != entries[index]["origin"]:
				return ERR_INVALID_DATA
			if canonical == old or PlayerRecord.terminal(old):
				return OK
			found = index
			break
	var urgent: bool = found < 0 or PlayerRecord.terminal(canonical)
	if found >= 0:
		urgent = urgent or entries[found]["record"]["scope"] != canonical["scope"]
		entries.remove_at(found)
	entries.push_front({"record": canonical, "origin": origin})
	if entries.size() > LIMIT:
		entries.pop_back()
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
		return OK
	if _generation >= EquipmentState.MAX_EXACT_INTEGER - 1:
		return ERR_UNAVAILABLE
	var next: int = _generation + 1
	var data: Dictionary = {"version": VERSION, "profile_id": profile_id, "generation": next, "entries": entries}
	var text: String = JSON.stringify(data)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return ERR_OUT_OF_MEMORY
	var destination: String = _slot(next)
	var temporary: String = destination + ".%d.tmp" % OS.get_process_id()
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
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

func totals(kind: String) -> Dictionary:
	var counts: Dictionary = PlayerRecord.empty_counts()
	for entry: Dictionary in entries:
		if entry["record"]["scope"]["kind"] == kind:
			PlayerRecord.add_counts(counts, entry["record"]["total"])
	return counts

func export_json(path: String) -> Error:
	if FileAccess.file_exists(path):
		return ERR_ALREADY_EXISTS
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var document: Dictionary = {"version": VERSION, "profile_id": profile_id, "generation": maxi(1, _generation), "entries": entries}
	var stored: bool = file.store_string(JSON.stringify(document, "\t"))
	file.flush()
	var result: Error = file.get_error() if stored else ERR_FILE_CANT_WRITE
	file.close()
	if result != OK:
		DirAccess.remove_absolute(path)
	return result
