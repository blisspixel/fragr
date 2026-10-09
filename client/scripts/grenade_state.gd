class_name GrenadeFacts
extends RefCounted

const MAX_ACTIVE: int = 64
const MAX_RESULTS: int = 256
const MAX_HITS: int = 256
const INVALID: String = "Invalid grenade snapshot."

static func point(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for number: Variant in value:
		if not MapGeometry._number(number) or absf(float(number)) > 8192.0:
			return false
	return true

static func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func validation_error(snapshot: Dictionary) -> String:
	if not EquipmentState.integer(snapshot.get("tick"), EquipmentState.MAX_EXACT_INTEGER):
		return INVALID
	var live: Variant = snapshot.get("grenades", [])
	var results: Variant = snapshot.get("explosions", [])
	if not live is Array or live.size() > MAX_ACTIVE or not results is Array or results.size() > MAX_RESULTS:
		return INVALID
	var seen: Array[int] = []
	for grenade: Variant in live:
		if not M03MissionState._exact(grenade, ["id", "owner_id", "position", "fuse_ticks", "bounce_count"]) \
			or not EquipmentState.integer(grenade["id"], 4294967295) or int(grenade["id"]) < 1 or int(grenade["id"]) in seen \
			or not MissionState._uuid(grenade["owner_id"]) or not point(grenade["position"]) \
			or not EquipmentState.integer(grenade["fuse_ticks"], 40) or int(grenade["fuse_ticks"]) < 1 \
			or not EquipmentState.integer(grenade["bounce_count"], 640):
			return INVALID
		seen.append(int(grenade["id"]))
	seen.clear()
	for result: Variant in results:
		if not M03MissionState._exact(result, ["id", "owner_id", "position", "radius", "hits"]) \
			or not EquipmentState.integer(result["id"], 4294967295) or int(result["id"]) < 1 or int(result["id"]) in seen \
			or not MissionState._uuid(result["owner_id"]) or not point(result["position"]) \
			or not MapGeometry._number(result["radius"]) \
			or float(result["radius"]) not in [CustodyFacts.GRENADE_RADIUS, CustodyFacts.MINE_RADIUS, 3.0, 1.5] \
			or not result["hits"] is Array or result["hits"].size() > MAX_HITS:
			return INVALID
		seen.append(int(result["id"]))
		# A mine blast peaks higher than a grenade's; its radius names it.
		var peak: int = CustodyFacts.MINE_PEAK if float(result["radius"]) == CustodyFacts.MINE_RADIUS else 100
		if float(result["radius"]) in [3.0, 1.5]:
			peak = 45
		var targets: Array[String] = []
		for hit: Variant in result["hits"]:
			if not M03MissionState._exact(hit, ["target_id", "hp_damage", "armor_damage", "target_hp_after", "killed"]) \
				or not MissionState._uuid(hit["target_id"]) or hit["target_id"] in targets \
				or not EquipmentState.integer(hit["hp_damage"], peak) or not EquipmentState.integer(hit["armor_damage"], peak) \
				or int(hit["hp_damage"]) + int(hit["armor_damage"]) > peak \
				or not MapGeometry._number(hit["target_hp_after"]) or float(hit["target_hp_after"]) != floorf(float(hit["target_hp_after"])) \
				or float(hit["target_hp_after"]) < -float(peak) or float(hit["target_hp_after"]) > 240.0 or not hit["killed"] is bool \
				or hit["killed"] != (int(hit["target_hp_after"]) <= 0) \
				or int(hit["hp_damage"]) + int(hit["armor_damage"]) == 0:
				return INVALID
			targets.append(hit["target_id"])
	return ""
