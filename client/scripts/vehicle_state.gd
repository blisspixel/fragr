class_name VehicleState
extends RefCounted

## Registered jeep facts. Geometry, seats, damage and safe exits belong to Rust.
const MAX_VEHICLES: int = 32
const MAX_HP: int = 400
const MAX_SPEED: float = 36.0
const MAX_BURN_TICKS: int = 40
const SEATS: Array[String] = ["driver", "gunner"]
const KINDS: Array[String] = ["jeep", "boat", "light_aircraft"]
const INVALID: String = "The server sent invalid vehicles. Connection closed."
const KEYS: Array[String] = ["id", "kind", "position", "yaw", "speed", "vy", "hp", "driver", "gunner", "gun_heat", "burning_ticks", "control_ready_tick"]

static func validation_error(snapshot: Dictionary) -> String:
	var shots: Variant = snapshot.get("shot_results", [])
	if shots is Array:
		for shot: Variant in shots:
			if not shot is Dictionary or not shot.get("trace") is Dictionary:
				continue
			var trace: Dictionary = shot["trace"]
			if trace.has("vehicle_id") and (not EquipmentState.integer(trace["vehicle_id"], 4294967295) or int(trace["vehicle_id"]) < 1 or trace.get("weapon") != "flechette"):
				return INVALID
	var rows: Variant = snapshot.get("vehicles", [])
	if not rows is Array or rows.size() > MAX_VEHICLES:
		return INVALID
	if rows.is_empty():
		return ""
	if not EquipmentState.integer(snapshot.get("tick"), EquipmentState.MAX_EXACT_INTEGER) or not snapshot.get("players") is Array:
		return INVALID
	var players: Dictionary = {}
	for player: Variant in snapshot["players"]:
		if player is Dictionary and player.get("id") is String:
			players[player["id"]] = player
	var identities: Dictionary = {}
	var occupants: Dictionary = {}
	for row: Variant in rows:
		if not M03MissionState._exact(row, KEYS) or not EquipmentState.integer(row["id"], 4294967295) \
			or int(row["id"]) < 1 or identities.has(int(row["id"])) or not row["kind"] is String or not KINDS.has(row["kind"]) \
			or not GrenadeFacts.point(row["position"]) or not _number(row["yaw"], TAU) or float(row["yaw"]) < 0.0 or float(row["yaw"]) >= TAU \
			or not _number(row["speed"], MAX_SPEED) or not _number(row["vy"], 1000.0) or not EquipmentState.integer(row["hp"], MAX_HP) \
			or not _number(row["gun_heat"], 1.0) or float(row["gun_heat"]) < 0.0 \
			or not EquipmentState.integer(row["burning_ticks"], MAX_BURN_TICKS):
			return INVALID
		if int(row["hp"]) > 0 and int(row["burning_ticks"]) > 0:
			return INVALID
		if row["kind"] == "light_aircraft" and (row["gunner"] != null or float(row["gun_heat"]) != 0.0):
			return INVALID
		if row["kind"] != "light_aircraft" and absf(float(row["speed"])) > 20.0:
			return INVALID
		if not EquipmentState.integer(row["control_ready_tick"], EquipmentState.MAX_EXACT_INTEGER) or int(row["control_ready_tick"]) > int(snapshot["tick"]) + 10:
			return INVALID
		identities[int(row["id"])] = true
		for seat: String in SEATS:
			var occupant: Variant = row[seat]
			if occupant == null:
				continue
			if not MissionState._uuid(occupant) or occupants.has(occupant) or not players.has(occupant):
				return INVALID
			var pawn: Dictionary = players[occupant]
			if not _number(pawn.get("hp"), 1000000.0):
				return INVALID
			if float(pawn["hp"]) <= 0.0:
				return INVALID
			occupants[occupant] = true
	return ""

static func _number(value: Variant, limit: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= limit

static func shot_vehicle(shot: Dictionary) -> int:
	var trace: Variant = shot.get("trace")
	if not trace is Dictionary or not EquipmentState.integer(trace.get("vehicle_id"), 4294967295):
		return 0
	return int(trace["vehicle_id"])

static func occupied(snapshot: Dictionary, player_id: String) -> Dictionary:
	if player_id.is_empty():
		return {}
	for row: Dictionary in snapshot.get("vehicles", []):
		for seat: String in SEATS:
			if row[seat] == player_id:
				return {"vehicle": row, "seat": seat}
	return {}

## Conservative registered hull, matching vehicles::hull for every kind.
static func hull(row: Dictionary) -> Dictionary:
	var at: Vector3 = GrenadeFacts.vector(row["position"])
	var c: float = absf(cos(float(row["yaw"])))
	var s: float = absf(sin(float(row["yaw"])))
	var size: Vector3 = VehicleMediumStep.dimensions(str(row["kind"]))
	var width: float = c * size.x + s * size.y
	var depth: float = s * size.x + c * size.y
	return {"min_x": at.x - width, "max_x": at.x + width, "min_z": at.z - depth,
		"max_z": at.z + depth, "bottom": at.y, "top": at.y + size.z}

static func hulls(snapshot: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in snapshot.get("vehicles", []):
		result.append(hull(row))
	return result

## The same two metre entry range, speed guard and driver-first ordering as
## the server, used only to choose a prompt. Use can still be refused there.
static func nearby(snapshot: Dictionary, feet: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var distance: float = INF
	for row: Dictionary in snapshot.get("vehicles", []):
		if int(row["hp"]) <= 0 or absf(float(row["speed"])) > 2.0:
			continue
		var point: Vector3 = GrenadeFacts.vector(row["position"])
		var away: float = Vector2(point.x - feet.x, point.z - feet.z).length()
		var reach: float = 6.0 if row["kind"] == "light_aircraft" else 2.0
		if away > reach or away >= distance or absf(point.y - feet.y) > 2.0:
			continue
		for seat: String in SEATS:
			if row["kind"] == "light_aircraft" and seat == "gunner":
				continue
			if row[seat] == null:
				best = {"vehicle": row, "seat": seat}
				distance = away
				break
	return best
