class_name ActorState
extends RefCounted

## Campaign identity comes from the server, never a callsign or control role.
const KINDS: Array[String] = ["clerk", "sweeper", "heavy_sweeper", "turret", "crawler", "jammer", "notary", "auditor", "ranged_sweeper", "enforcer", "redactor", "assessor"]
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

const MAX_PLAYERS: int = 64
const MAX_PICKUPS: int = 256
const MAX_NODES: int = 320
const MAX_LABEL: int = 64

static func validation_error(snapshot: Dictionary) -> String:
	const INVALID: String = "The server sent invalid campaign actors. Connection closed."
	var crowded: String = collection_error(snapshot)
	if not crowded.is_empty():
		return crowded
	var actors: Variant = snapshot.get("players")
	if not actors is Array:
		return INVALID
	if (actors as Array).size() > MAX_PLAYERS:
		return INVALID
	var companions: int = 0
	var seen: Dictionary = {}
	for actor: Variant in actors:
		if not actor is Dictionary:
			return INVALID
		if actor.has("collidable") and typeof(actor["collidable"]) != TYPE_BOOL:
			return INVALID
		if not _row_ok(actor):
			return INVALID
		var identity: String = str(actor.get("id", ""))
		if seen.has(identity):
			return INVALID
		seen[identity] = true
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
		if campaign["kind"] == "assessor" and (campaign["phase"] not in ["idle", "moving", "windup", "firing", "recovery", "hit", "dead"] or actor.get("weapon") != "Fists"):
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
		if campaign["kind"] == "assessor" and float(health) > 240.0:
			return INVALID
	return ""

static func collection_error(snapshot: Dictionary) -> String:
	const INVALID: String = "The server sent invalid campaign actors. Connection closed."
	var players: Variant = snapshot.get("players", [])
	var pickups: Variant = snapshot.get("pickups", [])
	if not players is Array or not pickups is Array:
		return INVALID
	if (players as Array).size() > MAX_PLAYERS or (pickups as Array).size() > MAX_PICKUPS:
		return INVALID
	var nodes: int = (players as Array).size() + (pickups as Array).size()
	for key: String in ["vehicles", "grenades", "mines", "projectiles"]:
		var extra: Variant = snapshot.get(key, [])
		if extra == null:
			continue
		if not extra is Array:
			return INVALID
		nodes += (extra as Array).size()
	if nodes > MAX_NODES:
		return INVALID
	if not _labels_fit(players) or not _labels_fit(pickups):
		return INVALID
	return ""

static func _labels_fit(rows: Variant) -> bool:
	if not rows is Array:
		return false
	for row: Variant in rows:
		if not row is Dictionary:
			continue
		for key: String in ["name", "kind", "id", "weapon"]:
			if not (row as Dictionary).has(key):
				continue
			var value: Variant = (row as Dictionary)[key]
			if value is String and (value as String).length() > MAX_LABEL:
				return false
	return true

static func _row_ok(actor: Dictionary) -> bool:
	var identity: Variant = actor.get("id")
	var label: Variant = actor.get("name")
	if not identity is String or (identity as String).is_empty() or (identity as String).length() > MAX_LABEL:
		return false
	if not label is String or (label as String).is_empty() or (label as String).length() > MAX_LABEL:
		return false
	for axis: String in ["x", "y", "z", "yaw", "pitch"]:
		if not actor.has(axis):
			continue
		var coordinate: Variant = actor[axis]
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
			return false
	if actor.has("hp") and not _whole(actor["hp"]):
		return false
	if actor.has("score") and not _whole(actor["score"]):
		return false
	if actor.has("weapon"):
		var weapon: Variant = actor["weapon"]
		if not weapon is String or not str(weapon).to_lower() in EquipmentState.WEAPONS:
			return false
	if actor.has("team"):
		var team: Variant = actor["team"]
		if not team is String or not str(team) in ["union", "coalition"]:
			return false
	if actor.has("body") and not PlayerBody.valid(actor["body"]):
		return false
	return true

static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
