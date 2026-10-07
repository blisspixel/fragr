class_name ActorContact
extends RefCounted

## Presentation mirror of movement/contact.rs. The server owns accepted motion.
const EPSILON: float = 0.0001
const PASSES: int = 8
const MAX_BODIES: int = 256
const FLOOR_OFFSET: float = 1.5
const INVALID: String = "Invalid character collision state."

static func sweep_time(a: Dictionary, b: Dictionary) -> float:
	var x: float = float(a["from"]["x"]) - float(b["from"]["x"])
	var z: float = float(a["from"]["z"]) - float(b["from"]["z"])
	var dx: float = (float(a["proposed"]["x"]) - float(a["from"]["x"])) - (float(b["proposed"]["x"]) - float(b["from"]["x"]))
	var dz: float = (float(a["proposed"]["z"]) - float(a["from"]["z"])) - (float(b["proposed"]["z"]) - float(b["from"]["z"]))
	var radius: float = float(a["radius"]) + float(b["radius"])
	var c: float = x * x + z * z - radius * radius
	var dot: float = x * dx + z * dz
	var initially_overlapping: bool = float(a["from"]["y"]) + float(a["height"]) > float(b["from"]["y"]) + EPSILON and float(b["from"]["y"]) + float(b["height"]) > float(a["from"]["y"]) + EPSILON
	if c < EPSILON and dot >= -EPSILON and initially_overlapping:
		return -1.0
	var speed: float = dx * dx + dz * dz
	if speed <= EPSILON * EPSILON:
		return -1.0
	var discriminant: float = dot * dot - speed * c
	if discriminant <= 0.0:
		return -1.0
	var root: float = sqrt(discriminant)
	var enter: float = maxf((-dot - root) / speed, 0.0)
	var leave: float = minf((-dot + root) / speed, 1.0)
	var intervals: Array[Vector2] = [
		Vector2(float(a["from"]["y"]) + float(a["height"]) - float(b["from"]["y"]), float(a["proposed"]["y"]) + float(a["height"]) - float(b["proposed"]["y"])),
		Vector2(float(b["from"]["y"]) + float(b["height"]) - float(a["from"]["y"]), float(b["proposed"]["y"]) + float(b["height"]) - float(a["proposed"]["y"]))]
	for interval: Vector2 in intervals:
		if interval.x <= EPSILON and interval.y <= EPSILON:
			return -1.0
		var delta: float = interval.y - interval.x
		if absf(delta) > EPSILON:
			var crossing: float = (EPSILON - interval.x) / delta
			if delta > 0.0:
				enter = maxf(enter, crossing)
			else:
				leave = minf(leave, crossing)
	return enter if enter < leave - EPSILON and enter < 1.0 - EPSILON else -1.0

static func _reintegrate(body: Dictionary, dx: float, dz: float, dt: float, arena: Dictionary) -> Dictionary:
	var start: Dictionary = body["from"].duplicate()
	start["vx"] = dx / dt
	start["vz"] = dz / dt
	var result: Dictionary = MoveStep.integrate_with_height(start, body["jump"], dt, arena, float(body["height"]))
	result["vx"] = (float(result["x"]) - float(body["from"]["x"])) / dt
	result["vz"] = (float(result["z"]) - float(body["from"]["z"])) / dt
	return result

static func resolve(bodies: Array[Dictionary], dt: float, arena: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_finite(dt) or dt <= 0.0:
		for body: Dictionary in bodies:
			result.append(body["from"].duplicate())
		return result
	var work: Array[Dictionary] = bodies.duplicate(true)
	var order: Array[int] = []
	for index: int in range(work.size()):
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool: return str(work[a]["key"]) < str(work[b]["key"]))
	for _pass: int in range(PASSES):
		var changed: bool = false
		for offset: int in range(order.size()):
			var i: int = order[offset]
			for peer: int in range(offset + 1, order.size()):
				var j: int = order[peer]
				var time: float = sweep_time(work[i], work[j])
				if time < 0.0:
					continue
				var a: Dictionary = work[i]
				var b: Dictionary = work[j]
				var ad: Vector2 = Vector2(float(a["proposed"]["x"]) - float(a["from"]["x"]), float(a["proposed"]["z"]) - float(a["from"]["z"]))
				var bd: Vector2 = Vector2(float(b["proposed"]["x"]) - float(b["from"]["x"]), float(b["proposed"]["z"]) - float(b["from"]["z"]))
				var normal: Vector2 = Vector2(float(a["from"]["x"]), float(a["from"]["z"])) + ad * time - Vector2(float(b["from"]["x"]), float(b["from"]["z"])) - bd * time
				normal = normal.normalized() if normal.length() > EPSILON else Vector2.RIGHT
				for slot: int in range(2):
					var index: int = i if slot == 0 else j
					var delta: Vector2 = ad if slot == 0 else bd
					var sign_value: float = 1.0 if slot == 0 else -1.0
					var inward: float = delta.dot(normal) * sign_value
					if inward < -EPSILON:
						var accepted: Vector2 = delta - normal * sign_value * inward * (1.0 - time)
						work[index]["proposed"] = _reintegrate(work[index], accepted.x, accepted.y, dt, arena)
						changed = true
		if not changed:
			break
	for _pass: int in range(work.size()):
		var changed: bool = false
		for offset: int in range(order.size()):
			var i: int = order[offset]
			for peer: int in range(offset + 1, order.size()):
				var j: int = order[peer]
				if sweep_time(work[i], work[j]) >= 0.0:
					for index: int in [i, j]:
						if absf(float(work[index]["proposed"]["x"]) - float(work[index]["from"]["x"])) > EPSILON or absf(float(work[index]["proposed"]["z"]) - float(work[index]["from"]["z"])) > EPSILON:
							work[index]["proposed"] = _reintegrate(work[index], 0.0, 0.0, dt, arena)
							changed = true
		if not changed:
			break
	for body: Dictionary in work:
		result.append(body["proposed"].duplicate())
	return result

static func stationary(key: String, feet: Vector3, height: float = MoveStep.BODY_HEIGHT) -> Dictionary:
	var state: Dictionary = MoveStep.make_state(feet.x, feet.z, 0.0)
	state["y"] = feet.y
	return {"key": key, "from": state, "proposed": state.duplicate(), "height": height, "radius": MoveStep.RADIUS, "jump": false}

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= MapGeometry.MAX_HALF * 2.0

static func _alive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) > 0.0 and float(value) <= 2147483647.0

static func _active(actor: Dictionary, mission: Dictionary) -> bool:
	if mission.is_empty():
		return true
	if mission.get("phase") == "briefing" or (mission.get("run") is Dictionary and mission["run"].get("status") != "playing"):
		return false
	var identity: Variant = actor.get("campaign")
	if not identity is Dictionary or identity.get("side") != "participant":
		return true
	var party: Variant = mission.get("party")
	if not party is Array:
		return false
	for member: Variant in party:
		if member is Dictionary and member.get("id") == actor["id"]:
			return member.get("ready") == true
	return false

## Narrow live snapshot inputs before using them as speculative obstacles.
static func read_snapshot(snapshot: Dictionary, mission: Dictionary = {}, archive_neutrals: Dictionary = {}, residents: Array[Dictionary] = []) -> Dictionary:
	var bodies: Array[Dictionary] = []
	var rows: Variant = snapshot.get("players")
	if not EquipmentState.integer(snapshot.get("tick"), EquipmentState.MAX_EXACT_INTEGER) or not rows is Array or rows.size() > MAX_BODIES or not ActorState.validation_error(snapshot).is_empty():
		return {"error": INVALID, "bodies": bodies}
	var seen: Dictionary = {}
	for raw: Variant in rows:
		if not raw is Dictionary or not raw.get("id") is String or raw["id"].is_empty() or raw["id"].length() > 64 or seen.has(raw["id"]):
			return {"error": INVALID, "bodies": []}
		var actor: Dictionary = raw
		seen[actor["id"]] = true
		for axis: String in ["x", "y", "z"]:
			if not _number(actor.get(axis)):
				return {"error": INVALID, "bodies": []}
		var health: Variant = actor.get("hp")
		if not (health is int or health is float) or not is_finite(float(health)) or float(health) != floorf(float(health)) or float(health) < -2147483648.0 or float(health) > 2147483647.0:
			return {"error": INVALID, "bodies": []}
		if not _alive(health) or not actor.get("collidable", true) or not _active(actor, mission):
			continue
		var height: float = MoveStep.BODY_HEIGHT
		if ActorState.is_union(actor):
			if actor["campaign"]["kind"] == "crawler":
				height = 0.8
			elif actor["campaign"]["kind"] == "notary":
				height = 0.7
		bodies.append(stationary(str(actor["id"]), Vector3(float(actor["x"]), float(actor["y"]) - FLOOR_OFFSET, float(actor["z"])), height))
	if not _append_civilians(mission, bodies, archive_neutrals, residents):
		return {"error": INVALID, "bodies": []}
	return {"error": "", "bodies": bodies}

static func _append_feet(key: String, value: Variant, bodies: Array[Dictionary]) -> bool:
	if bodies.size() >= MAX_BODIES or not value is Array or value.size() != 3:
		return false
	for coordinate: Variant in value:
		if not _number(coordinate):
			return false
	bodies.append(stationary(key, Vector3(float(value[0]), float(value[1]), float(value[2]))))
	return true

## Mission boundaries already validate authored routes. Narrow the retained
## feet again here, and use exactly the server's deterministic body keys.
static func _append_civilians(mission: Dictionary, bodies: Array[Dictionary], archive_neutrals: Dictionary = {}, residents: Array[Dictionary] = []) -> bool:
	if mission.get("phase") != "in_progress":
		return true
	var m02: Variant = mission.get("m02")
	if m02 is Dictionary and m02.get("evacuation") is Dictionary:
		var captives: Variant = m02["evacuation"].get("captives")
		if not captives is Array or captives.size() != 2:
			return false
		for index: int in range(captives.size()):
			if not _append_feet("m02/captive/%d" % index, captives[index], bodies):
				return false
	var m03: Variant = mission.get("m03")
	if m03 is Dictionary:
		var cars: Variant = m03.get("cars")
		if not cars is Array or cars.size() > MAX_BODIES:
			return false
		var seen: Dictionary = {}
		for car: Variant in cars:
			if not car is Dictionary or not _civilian_id(car.get("id")) or seen.has(car["id"]) or not car.get("captives") is Array or car["captives"].size() != 2:
				return false
			seen[car["id"]] = true
			for index: int in range(car["captives"].size()):
				if not _append_feet("m03/%s/%d" % [car["id"], index], car["captives"][index], bodies):
					return false
	for field: String in ["m04", "m05"]:
		var progress: Variant = mission.get(field)
		if not progress is Dictionary:
			continue
		var rows: Variant = progress.get("patients" if field == "m04" else "captives")
		if not rows is Array or rows.size() > MAX_BODIES:
			return false
		var seen: Dictionary = {}
		for row: Variant in rows:
			if not row is Dictionary or not _civilian_id(row.get("id")) or seen.has(row["id"]):
				return false
			seen[row["id"]] = true
			if not _append_feet(field + "/" + str(row["id"]), row.get("feet"), bodies):
				return false
	var m08: Variant = mission.get("m08")
	if m08 is Dictionary:
		if archive_neutrals.is_empty() or not m08.get("custodian_joined") is bool or not m08.get("custody_released") is bool:
			return false
		for person: Dictionary in M08NeutralBodies.people(archive_neutrals, m08["custodian_joined"], m08["custody_released"]):
			var feet: Vector3 = person["feet"]
			if not _append_feet(person["key"], [feet.x, feet.y, feet.z], bodies):
				return false
	if mission.get("m06") is Dictionary or mission.get("m07") is Dictionary or mission.get("m11") is Dictionary:
		for resident: Dictionary in residents:
			var feet: Vector3 = resident["feet"]
			if not _append_feet(resident["key"], [feet.x, feet.y, feet.z], bodies):
				return false
	return true

static func _civilian_id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 64
