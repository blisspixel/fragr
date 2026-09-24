class_name ActorState
extends RefCounted

## Campaign identity comes from the server, never a callsign or control role.
const KINDS: Array[String] = ["clerk", "sweeper", "heavy_sweeper", "turret"]
const PHASES: Array[String] = ["idle", "moving", "windup", "firing", "recovery", "hit", "dead"]

static func is_participant(actor: Dictionary) -> bool:
	var campaign: Variant = actor.get("campaign")
	return campaign == null or (campaign is Dictionary and campaign.get("side") == "participant")

static func participants(actors: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor: Variant in actors:
		if actor is Dictionary and is_participant(actor):
			result.append(actor)
	return result

static func validation_error(snapshot: Dictionary) -> String:
	const INVALID: String = "The server sent invalid campaign actors. Connection closed."
	var actors: Variant = snapshot.get("players")
	if not actors is Array:
		return INVALID
	for actor: Variant in actors:
		if not actor is Dictionary:
			return INVALID
		var campaign: Variant = actor.get("campaign")
		if campaign == null:
			continue
		if not campaign is Dictionary or not campaign.get("side") is String:
			return INVALID
		if campaign["side"] == "participant":
			if campaign.size() != 1:
				return INVALID
			continue
		if campaign["side"] != "union" or campaign.size() != 5 \
			or not campaign.get("kind") is String or campaign["kind"] not in KINDS \
			or not campaign.get("phase") is String or campaign["phase"] not in PHASES:
			return INVALID
		if not EquipmentState.integer(snapshot.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
			or not EquipmentState.integer(campaign.get("phase_started"), EquipmentState.MAX_EXACT_INTEGER) \
			or not EquipmentState.integer(campaign.get("phase_ends"), EquipmentState.MAX_EXACT_INTEGER):
			return INVALID
		var started: int = int(campaign["phase_started"])
		var ends: int = int(campaign["phase_ends"])
		if started > int(snapshot["tick"]) or ends < started or ends - started > 100:
			return INVALID
		var health: Variant = actor.get("hp")
		if not (health is int or health is float) or not is_finite(float(health)) \
			or float(health) != floorf(float(health)):
			return INVALID
		if (campaign["phase"] == "dead") != (float(health) <= 0.0):
			return INVALID
	return ""
