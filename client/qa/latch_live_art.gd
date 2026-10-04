extends "res://scripts/qa_tour.gd"

## Passive receipt of real pickups for the separately labelled live art route.
var _pickup_network: Node = null
var _finite_pickups: Array[Dictionary] = []

func _process(delta: float) -> bool:
	var manager: Node = _game_manager()
	if manager != null and is_instance_valid(manager.net_client) and _pickup_network != manager.net_client:
		_pickup_network = manager.net_client
		_pickup_network.event_received.connect(_pickup_received)
	return super._process(delta)

func _pickup_received(data: Dictionary) -> void:
	if data.get("event") != "pickup" or not is_instance_valid(_pickup_network) \
		or data.get("player_id") != _pickup_network.player_id:
		return
	var manager: Node = _game_manager()
	var snapshot: Dictionary = manager.latest_snapshot
	var receipt: Dictionary = data.duplicate(true)
	for player: Dictionary in snapshot.get("players", []):
		if player.get("id") == _pickup_network.player_id:
			receipt["arrival_feet"] = [player.x, player.y - CameraScript.FP_SERVER_REFERENCE_Y, player.z]
			receipt["snapshot_tick"] = snapshot.get("tick")
			receipt["snapshot_hp"] = player.hp
			break
	if _finite_pickups.size() < 32:
		_finite_pickups.append(receipt)
	print("latch_live_art: actual pickup ", JSON.stringify(receipt))

func _observed_state() -> Dictionary:
	var observed: Dictionary = super._observed_state()
	observed["finite_pickups"] = _finite_pickups.duplicate(true)
	return observed

func _write_manifest(tour: Dictionary) -> void:
	var required: Dictionary = {"guard_room_shells": {"kind": "ammo", "amount": 8},
		"floor_shells": {"kind": "ammo", "amount": 8},
		"floor_medkit": {"kind": "health", "amount": 40}}
	for id: String in required:
		var found: bool = false
		for pickup: Dictionary in _finite_pickups:
			if pickup.get("pickup_id") == id and pickup.get("kind") == required[id]["kind"] \
				and pickup.get("amount") == required[id]["amount"] and pickup.has("arrival_feet"):
				found = true
		if not found:
			_failed = true
			push_error("latch_live_art: missing actual finite pickup arrival " + id)
	super._write_manifest(tour)
	var receipt: FileAccess = FileAccess.open(_out_dir.path_join("finite-pickups.json"), FileAccess.WRITE)
	if receipt != null:
		receipt.store_string(JSON.stringify(_finite_pickups, "  "))
		receipt.close()
