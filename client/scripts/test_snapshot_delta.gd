extends SceneTree

## Snapshot deltas rebuild exactly the world the server encoded
## (`client/golden/snapshot_delta_vectors.json`, written by the server's
## `protocol::delta` tests), and every malformed delta is refused.
const NET = preload("res://scripts/net_client.gd")
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_snapshot_delta: " + reason)

func _golden() -> Array:
	var file: FileAccess = FileAccess.open("res://golden/snapshot_delta_vectors.json", FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not (parsed as Dictionary).get("cases") is Array:
		return []
	return parsed["cases"]

func _run() -> void:
	var cases: Array = _golden()
	_check(cases.size() >= 3, "golden vectors load")
	for index: int in cases.size():
		var case: Dictionary = cases[index]
		var base: Dictionary = case["base"]
		var before: Dictionary = base.duplicate(true)
		var rebuilt: Dictionary = SnapshotDelta.apply(base, case["delta"])
		_check(rebuilt == case["world"], "case %d rebuilds the server's world" % index)
		_check(base == before, "case %d leaves the held world unchanged" % index)
		if index > 0:
			_check(ActorState.validation_error(rebuilt).is_empty(), "case %d rebuilds a valid fought world" % index)
	_refusals(cases[0]["base"] if not cases.is_empty() else {})
	_net_client()
	if _failures == 0:
		print("test_snapshot_delta: PASS")
	quit(1 if _failures > 0 else 0)

func _refusals(base: Dictionary) -> void:
	var good: Dictionary = {"type": "snapshot_delta", "base": 7, "tick": 8, "players": []}
	_check(not SnapshotDelta.apply(base, good).is_empty(), "a minimal delta applies")
	var bad: Array[Dictionary] = [
		{"type": "snapshot", "base": 7, "tick": 8, "players": []},
		{"type": "snapshot_delta", "base": 6, "tick": 8, "players": []},
		{"type": "snapshot_delta", "base": 7, "tick": 7, "players": []},
		{"type": "snapshot_delta", "base": 7, "tick": -1, "players": []},
		{"type": "snapshot_delta", "base": 7, "tick": 8.5, "players": []},
		{"type": "snapshot_delta", "base": 7, "tick": 8},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [], "extra": 1},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [], "set": []},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [], "set": {"tick": 9}},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [], "set": {"players": []}},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [], "unset": "mvp"},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [], "unset": [1]},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [], "unset": ["type"]},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [3]},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [{"x": 1}]},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [{"id": "z"}, {"id": "z"}]},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [{"id": "a", "unset": ["id"]}]},
		{"type": "snapshot_delta", "base": 7, "tick": 8, "players": [{"id": "a", "unset": "ping"}]},
	]
	for index: int in bad.size():
		_check(SnapshotDelta.apply(base, bad[index]).is_empty(), "bad delta %d is refused" % index)
	var crowd: Array = []
	for index: int in ActorState.MAX_PLAYERS + 1:
		crowd.append({"id": "p%d" % index})
	_check(SnapshotDelta.apply(base, {"type": "snapshot_delta", "base": 7, "tick": 8, "players": crowd}).is_empty(), "an oversized roster is refused")
	_check(SnapshotDelta.apply({}, good).is_empty(), "no held world refuses a delta")

## The connection boundary: a delta needs a held world, and a held world
## rebuilds into an ordinary snapshot signal.
func _net_client() -> void:
	var client: Node = NET.new()
	root.add_child(client)
	var errors: Array[String] = []
	var worlds: Array[Dictionary] = []
	client.server_error.connect(func(message: String) -> void: errors.append(message))
	client.snapshot_received.connect(func(data: Variant) -> void: worlds.append(data))
	var cases: Array = _golden()
	var fought: Dictionary = cases[1] if cases.size() > 1 else {}
	client._handle_message(JSON.stringify(fought.get("delta", {}), "", true, true))
	_check(errors.size() == 1 and errors[0] == SnapshotDelta.INVALID, "a delta before any world closes the connection")
	_check(worlds.is_empty(), "a refused delta presents nothing")
	errors.clear()
	client._handle_message(JSON.stringify(fought.get("base", {}), "", true, true))
	client._handle_message(JSON.stringify(fought.get("delta", {}), "", true, true))
	_check(errors.is_empty(), "a held world takes its delta: %s" % [errors])
	_check(worlds.size() == 2 and worlds[1] == fought.get("world"), "the rebuilt world is presented whole")
	# A map starts a new world: the held one is forgotten.
	client._handle_message(JSON.stringify(fought.get("base", {}), "", true, true))
	var map: FileAccess = FileAccess.open("res://golden/larak_lot_map_info.json", FileAccess.READ)
	_check(map != null, "the Larak Lot map golden loads")
	if map != null:
		client._handle_message(map.get_as_text())
	_check(errors.is_empty(), "the map is accepted: %s" % [errors])
	client._handle_message(JSON.stringify(fought.get("delta", {}), "", true, true))
	_check(errors.size() == 1 and errors[0] == SnapshotDelta.INVALID, "no delta reaches across a new map")
	client.queue_free()
