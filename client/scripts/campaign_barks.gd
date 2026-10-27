class_name CampaignBarks
extends RefCounted

## Campaign chatter facts from the server: Union squad radio (`enemy_bark`)
## and Latch's callouts (`companion_bark`). The server sends the kind, the
## register or subject, a variant and the speaker's position; the client owns
## the caption, the speaker label and the recording slot. Anything outside
## the known shape is ignored.

const VARIANTS: int = 3
const ENEMY_EVENT: String = "enemy_bark"
const COMPANION_EVENT: String = "companion_bark"
const ENEMY_KINDS: Array[String] = ["sighting", "flanking", "officer_down"]
const REGISTERS: Array[String] = ["personnel", "unit"]
const COMPANION_KINDS: Array[String] = ["flank_warning", "priority_target", "low_health"]
const SUBJECTS: Array[String] = ["auditor", "turret"]
const SLOT_DIR: String = "res://assets/audio/barks/"
const SLOT_EXTENSION: String = ".mp3"
## Positions further out than this are not a world point.
const WORLD_LIMIT: float = 10000.0


static func _text(data: Dictionary, field: String) -> String:
	var value: Variant = data.get(field)
	return value if value is String else ""


static func _variant(data: Dictionary) -> int:
	var value: Variant = data.get("variant")
	if value is int or value is float:
		var number: float = float(value)
		if number == floorf(number) and number >= 0.0 and number < float(VARIANTS):
			return int(number)
	return -1


## The world point a bark comes from, or Vector3.INF when malformed.
static func position(data: Dictionary) -> Vector3:
	var value: Variant = data.get("position")
	if not value is Array:
		return Vector3.INF
	var coords: Array = value
	if coords.size() != 3:
		return Vector3.INF
	var out: Array[float] = []
	for item: Variant in coords:
		if not (item is int or item is float):
			return Vector3.INF
		var number: float = float(item)
		if not is_finite(number) or absf(number) > WORLD_LIMIT:
			return Vector3.INF
		out.append(number)
	return Vector3(out[0], out[1], out[2])


static func is_union(data: Dictionary) -> bool:
	return _text(data, "event") == ENEMY_EVENT


## The validated parts of a bark: event, kind, register or subject, variant.
## Empty when anything is outside the known shape.
static func _parts(data: Dictionary) -> Dictionary:
	var variant: int = _variant(data)
	var kind: String = _text(data, "kind")
	if variant < 0 or not position(data).is_finite():
		return {}
	match _text(data, "event"):
		ENEMY_EVENT:
			var register: String = _text(data, "register")
			if kind in ENEMY_KINDS and register in REGISTERS:
				return {"union": true, "kind": kind, "detail": register, "variant": variant}
		COMPANION_EVENT:
			if not kind in COMPANION_KINDS:
				return {}
			var subject: Variant = data.get("subject")
			if kind == "priority_target":
				if subject is String and subject in SUBJECTS:
					return {"union": false, "kind": kind, "detail": subject, "variant": variant}
				return {}
			if subject == null:
				return {"union": false, "kind": kind, "detail": "", "variant": variant}
	return {}


static func caption_key(data: Dictionary) -> String:
	var parts: Dictionary = _parts(data)
	if parts.is_empty():
		return ""
	var kind: String = str(parts["kind"]).to_upper()
	var detail: String = str(parts["detail"]).to_upper()
	var variant: String = str(parts["variant"])
	if parts["union"]:
		return "BARK_ENEMY_%s_%s_%s" % [detail, kind, variant]
	if detail.is_empty():
		return "BARK_LATCH_%s_%s" % [kind, variant]
	return "BARK_LATCH_%s_%s_%s" % [kind, detail, variant]


static func speaker_key(data: Dictionary) -> String:
	var parts: Dictionary = _parts(data)
	if parts.is_empty():
		return ""
	if not parts["union"]:
		return "BARK_SPEAKER_LATCH"
	return "BARK_SPEAKER_UNION" if parts["detail"] == "personnel" else "BARK_SPEAKER_UNIT"


## The recording slot for this bark; a missing file is silence.
static func slot_path(data: Dictionary) -> String:
	var parts: Dictionary = _parts(data)
	if parts.is_empty():
		return ""
	var kind: String = str(parts["kind"])
	var detail: String = str(parts["detail"])
	var variant: String = str(parts["variant"])
	if parts["union"]:
		return SLOT_DIR + "union_" + detail + "/" + kind + "_" + variant + SLOT_EXTENSION
	var stem: String = kind if detail.is_empty() else kind + "_" + detail
	return SLOT_DIR + "latch/" + stem + "_" + variant + SLOT_EXTENSION
