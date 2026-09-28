class_name MovementAck
extends RefCounted
## Validates the optional 3D body block on a human Ack. An absent or newer
## block leaves the existing snapshot path usable; version 1 must be complete.

const MAX_EXACT_INTEGER: int = 9007199254740991
const MAX_SEQUENCE: int = 4294967295
const MAX_BODY_VALUE: float = 1000.0
const MAX_SERVER_YAW: float = TAU + 0.000001 # Rust f32 TAU can round above Godot's float TAU.
const INVALID: String = "The server sent invalid movement state. Connection closed."


static func _integer(value: Variant, maximum: int) -> bool:
	if not value is int and not value is float:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 and number <= float(maximum) and number == floorf(number)


static func _finite_range(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) >= low and float(value) <= high


static func has_replay_body(data: Dictionary) -> bool:
	var body: Variant = data.get("movement")
	return body is Dictionary and _integer(body.get("version"), MAX_EXACT_INTEGER) \
		and int(body["version"]) == 1


static func validation_error(data: Dictionary, previous: Dictionary = {}) -> String:
	if not _integer(data.get("seq"), MAX_SEQUENCE) or not _integer(data.get("tick"), MAX_EXACT_INTEGER):
		return INVALID
	for field: String in ["x", "z"]:
		if not _finite_range(data.get(field), -MAX_BODY_VALUE, MAX_BODY_VALUE):
			return INVALID
	if not _finite_range(data.get("yaw"), 0.0, MAX_SERVER_YAW):
		return INVALID
	if data.has("pitch") and not _finite_range(data.get("pitch"), -PI / 2.0, PI / 2.0):
		return INVALID
	if not data.has("movement") or data.get("movement") == null:
		return ""
	var body: Variant = data["movement"]
	if not body is Dictionary or not _integer(body.get("version"), MAX_EXACT_INTEGER):
		return INVALID
	if int(body["version"]) != 1:
		return "" # A future schema is an authoritative-snapshot fallback.
	if not _integer(body.get("epoch"), MAX_EXACT_INTEGER) or int(body["epoch"]) < 1:
		return INVALID
	if not body.get("applied") is bool or not body.get("jump_input") is bool:
		return INVALID
	for field: String in ["y", "vx", "vy", "vz"]:
		if not _finite_range(body.get(field), -MAX_BODY_VALUE, MAX_BODY_VALUE):
			return INVALID
	if not _finite_range(body.get("effective_speed"), 0.0, MoveStep.TOP_SPEED):
		return INVALID
	if not bool(body["applied"]) and (float(body["vx"]) != 0.0 or float(body["vz"]) != 0.0 \
			or float(body["effective_speed"]) != 0.0 or bool(body["jump_input"])):
		return INVALID
	if not previous.is_empty() and has_replay_body(previous):
		if int(data["tick"]) <= int(previous["tick"]) or int(body["epoch"]) < int(previous["movement"]["epoch"]):
			return INVALID
		var seq: int = int(data["seq"])
		var old_seq: int = int(previous["seq"])
		var distance: int = (seq - old_seq) & MAX_SEQUENCE
		if distance >= 2147483648:
			return INVALID
	return ""
