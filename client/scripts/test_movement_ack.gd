extends SceneTree

var failures: Array[String] = []


func _check(ok: bool, description: String) -> void:
	if not ok:
		failures.append(description)


func _initialize() -> void:
	var legacy: Variant = JSON.parse_string('{"type":"ack","seq":4,"tick":10,"x":1.0,"z":2.0,"yaw":0.5,"pitch":0.0}')
	_check(legacy is Dictionary, "legacy Ack parses")
	if not legacy is Dictionary:
		quit(1)
		return
	_check(MovementAck.validation_error(legacy) == "", "legacy Ack remains valid")
	_check(not MovementAck.has_replay_body(legacy), "legacy Ack has no replay body")
	var full_value: Variant = JSON.parse_string('{"type":"ack","seq":4,"tick":10,"x":1.0,"z":2.0,"yaw":0.5,"pitch":0.0,"movement":{"version":1,"epoch":2,"applied":true,"y":1.5,"vx":0.0,"vy":6.0,"vz":3.0,"effective_speed":5.0,"jump_input":true}}')
	_check(full_value is Dictionary, "full Ack parses from JSON")
	if not full_value is Dictionary:
		quit(1)
		return
	var full: Dictionary = full_value
	_check(MovementAck.validation_error(full) == "", "finite parsed 3D Ack is valid")
	_check(MovementAck.has_replay_body(full), "version 1 is replay capable")
	var repeated: Dictionary = full.duplicate(true)
	repeated["tick"] = 11.0
	_check(MovementAck.validation_error(repeated, full) == "", "same seq on a newer tick is valid")
	var stale: Dictionary = full.duplicate(true)
	_check(MovementAck.validation_error(stale, full) != "", "repeated tick is invalid")
	stale["tick"] = 9.0
	_check(MovementAck.validation_error(stale, full) != "", "older tick is invalid")
	var reset: Dictionary = repeated.duplicate(true)
	reset["movement"]["epoch"] = 3.0
	reset["movement"]["applied"] = false
	reset["movement"]["vx"] = 0.0
	reset["movement"]["vy"] = 0.0
	reset["movement"]["vz"] = 0.0
	reset["movement"]["effective_speed"] = 0.0
	reset["movement"]["jump_input"] = false
	_check(MovementAck.validation_error(reset, full) == "", "epoch change is a valid reset")
	reset["movement"]["epoch"] = 1.0
	_check(MovementAck.validation_error(reset, full) != "", "epoch regression is invalid")
	var missing: Dictionary = full.duplicate(true)
	missing["movement"].erase("y")
	_check(MovementAck.validation_error(missing) != "", "missing vertical position is invalid")
	var nonfinite: Dictionary = full.duplicate(true)
	nonfinite["movement"]["vy"] = INF
	_check(MovementAck.validation_error(nonfinite) != "", "infinite velocity is invalid")
	var fractional: Dictionary = full.duplicate(true)
	fractional["tick"] = 10.5
	_check(MovementAck.validation_error(fractional) != "", "fractional tick is invalid")
	var rounded_yaw: Dictionary = full.duplicate(true)
	rounded_yaw["yaw"] = 6.2831855
	_check(MovementAck.validation_error(rounded_yaw) == "", "valid f32 yaw near TAU is accepted")
	rounded_yaw["yaw"] = 7.0
	_check(MovementAck.validation_error(rounded_yaw) != "", "out of range yaw is invalid")
	var bad_rest: Dictionary = reset.duplicate(true)
	bad_rest["movement"]["epoch"] = 3.0
	bad_rest["movement"]["vx"] = 1.0
	_check(MovementAck.validation_error(bad_rest) != "", "unapplied tick cannot carry motion")
	var old_seq: Dictionary = full.duplicate(true)
	old_seq["seq"] = 9.0
	var backwards: Dictionary = old_seq.duplicate(true)
	backwards["seq"] = 8.0
	backwards["tick"] = 11.0
	_check(MovementAck.validation_error(backwards, old_seq) != "", "sequence regression is invalid")
	var wrap_before: Dictionary = full.duplicate(true)
	wrap_before["seq"] = 4294967295.0
	var wrap_after: Dictionary = wrap_before.duplicate(true)
	wrap_after["seq"] = 0.0
	wrap_after["tick"] = 11.0
	_check(MovementAck.validation_error(wrap_after, wrap_before) == "", "u32 wrap advances")
	var future: Dictionary = full.duplicate(true)
	future["movement"]["version"] = 2.0
	_check(MovementAck.validation_error(future) == "", "future schema falls back")
	_check(not MovementAck.has_replay_body(future), "future schema is not replayed")
	if failures.is_empty():
		print("test_movement_ack: PASS")
		quit(0)
	else:
		for failure: String in failures:
			printerr("test_movement_ack: FAIL " + failure)
		quit(1)
