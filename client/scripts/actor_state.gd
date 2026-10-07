class_name ActorState
extends RefCounted

## Campaign identity comes from the server, never a callsign or control role.
const KINDS: Array[String] = ["clerk", "sweeper", "heavy_sweeper", "turret", "crawler", "jammer", "notary", "auditor", "ranged_sweeper", "enforcer", "redactor"]
const PHASES: Array[String] = ["idle", "moving", "windup", "leaping", "firing", "recovery", "hit", "dead", "channeling", "charging"]
const COMPANION_PHASES: Array[String] = ["releasing", "following", "firing"]

static func is_union(actor: Dictionary) -> bool:
	var campaign: Variant = actor.get("campaign")
	return campaign is Dictionary and campaign.get("side") == "union"

static func is_companion(actor: Dictionary) -> bool:
	var campaign: Variant = actor.get("campaign")
	return campaign is Dictionary and campaign.get("side") == "companion"

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
	var companions: int = 0
	for actor: Variant in actors:
		if not actor is Dictionary:
			return INVALID
		if actor.has("collidable") and typeof(actor["collidable"]) != TYPE_BOOL:
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
		if campaign["side"] == "companion":
			companions += 1
			if companions > 1 or campaign.size() != 4 or campaign.get("kind") != "latch" \
				or campaign.get("phase") not in COMPANION_PHASES \
				or not EquipmentState.integer(snapshot.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
				or not EquipmentState.integer(campaign.get("phase_started"), int(snapshot["tick"])) \
				or actor.has("body") or actor.get("weapon") != "Tack" \
				or typeof(actor.get("just_fired")) != TYPE_BOOL \
				or (campaign["phase"] == "releasing" and actor["just_fired"]) \
				or not EquipmentState.integer(actor.get("hp"), 100) or int(actor["hp"]) < 1:
				return INVALID
			for axis: String in ["x", "y", "z", "yaw"]:
				var coordinate: Variant = actor.get(axis)
				if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
					return INVALID
			continue
		if campaign["side"] != "union" or campaign.size() not in [5, 6] \
			or not campaign.get("kind") is String or campaign["kind"] not in KINDS \
			or not campaign.get("phase") is String or campaign["phase"] not in PHASES:
			return INVALID
		if campaign.size() == 6 and not campaign.has("seated"):
			return INVALID
		# Only an Auditor holds a repair channel.
		if campaign["phase"] == "channeling" and campaign["kind"] != "auditor":
			return INVALID
		if campaign["phase"] == "charging" and campaign["kind"] != "enforcer":
			return INVALID
		if campaign["kind"] == "redactor" and campaign["phase"] not in ["idle", "moving", "windup", "firing", "recovery", "hit", "dead"]:
			return INVALID
		if campaign.has("seated") and (campaign.size() != 6 \
			or typeof(campaign["seated"]) != TYPE_BOOL or campaign["seated"] != true \
			or campaign["kind"] != "clerk" or campaign["phase"] != "idle"):
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
