extends SceneTree

## Latch's lines in Levels 12, 13, 14 and 16 follow server facts: said once
## when a fact turns true in play, never for a fact already true when this
## client first saw the attempt, and again after a retry.
var failures: int = 0

func _initialize() -> void:
	set_meta("localexception_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_latch_lines: " + message)

static func state(id: String, attempt: int, facts: Dictionary) -> Dictionary:
	return {"id": id, "attempt": attempt, "phase": "in_progress", facts.keys()[0]: facts.values()[0]}

func _said(lines: LatchLines) -> Array[String]:
	var said: Array[String] = []
	lines.caption.line_said.connect(func(text: String) -> void: said.append(text))
	return said

func _run() -> void:
	var lines := LatchLines.new()
	root.add_child(lines)
	var said: Array[String] = _said(lines)
	var line := func(key: String) -> String: return TranslationServer.translate(key)

	# Level 12: the workers come out of their frames in play.
	var closed: Dictionary = state(MissionState.M12_ID, 1, {"m12": {"challenges": {"workers_released": false}}})
	var open: Dictionary = state(MissionState.M12_ID, 1, {"m12": {"challenges": {"workers_released": true}}})
	lines.apply_state(closed)
	_check(said.is_empty(), "nothing is said before the workers are out")
	lines.apply_state(open)
	lines.apply_state(open)
	_check(said == [line.call("M12_LATCH_FRAMES")], "the frames line is said once: %s" % [said])
	_check(not str(said[0] if not said.is_empty() else "").is_empty() and said[0] != "M12_LATCH_FRAMES", "the line is translated")
	# A retry says it again when it happens again.
	said.clear()
	var retry_closed: Dictionary = closed.duplicate(true)
	retry_closed["attempt"] = 2
	var retry_open: Dictionary = open.duplicate(true)
	retry_open["attempt"] = 2
	lines.apply_state(retry_closed)
	lines.apply_state(retry_open)
	_check(said.size() == 1, "a retry earns the line again")

	# A late join that finds the workers already out says nothing.
	said.clear()
	lines.clear()
	lines.apply_state(open)
	_check(said.is_empty(), "a late join restages nothing")

	# Level 13: the overseer surrenders, then the workers answer.
	said.clear()
	lines.clear()
	lines.apply_state(state(MissionState.M13_ID, 1, {"m13": {"overseer_surrendered": false, "challenges": {}}}))
	lines.apply_state(state(MissionState.M13_ID, 1, {"m13": {"overseer_surrendered": true, "challenges": {}}}))
	lines.apply_state(state(MissionState.M13_ID, 1, {"m13": {"overseer_surrendered": true, "challenges": {"workers": ["volunteer", "leave", "stay"]}}}))
	_check(said == [line.call("M13_LATCH_ASK"), line.call("M13_LATCH_THEIR_CALL")], "the quarters lines in order: %s" % [said])

	# Level 14: the depot is taken and the jeep is the party's.
	said.clear()
	lines.apply_state(state(MissionState.M14_ID, 1, {"m14": {"completed": ["arrival"]}}))
	lines.apply_state(state(MissionState.M14_ID, 1, {"m14": {"completed": ["arrival", "depot_secured"]}}))
	_check(said == [line.call("M14_LATCH_YOU_DRIVE")], "the jeep line: %s" % [said])

	# Level 16: Latch walks onto the forecourt; a snapshot that already has
	# Latch at first sight is a resume and says nothing.
	said.clear()
	var avenue: Dictionary = state(MissionState.M16_ID, 1, {"m16": {}})
	var latch: Dictionary = {"x": 16.0, "z": 16.0, "campaign": {"side": "companion", "phase": "following", "phase_started": 0}}
	var near_latch: Dictionary = {"x": 25.0, "z": 2.0, "campaign": {"side": "companion", "phase": "following", "phase_started": 0}}
	var party: Dictionary = {"x": 26.5, "z": 0.0, "campaign": {"side": "participant"}}
	lines.apply_state(avenue)
	lines.apply_snapshot({"players": [party]})
	_check(said.is_empty(), "nobody rides with the party")
	lines.apply_snapshot({"players": [party, latch]})
	_check(said.is_empty(), "Latch says nothing out of sight in the lane")
	lines.apply_snapshot({"players": [party, near_latch]})
	lines.apply_snapshot({"players": [party, near_latch]})
	_check(said == [line.call("M16_LATCH_NO_STEERING")], "the arrival line once, on reaching the party: %s" % [said])
	said.clear()
	lines.clear()
	lines.apply_state(avenue)
	lines.apply_snapshot({"players": [party, near_latch]})
	_check(said.is_empty(), "a resume past the arrival says nothing")

	# Another level clears it; malformed facts say nothing.
	said.clear()
	lines.apply_state({"id": MissionState.M17_ID, "attempt": 1, "phase": "in_progress"})
	lines.apply_state(state(MissionState.M12_ID, 1, {"m12": "broken"}))
	lines.apply_snapshot({"players": [party, near_latch]})
	_check(said.is_empty(), "malformed or foreign facts say nothing")

	lines.queue_free()
	if failures == 0:
		print("test_latch_lines: PASS")
	quit(1 if failures > 0 else 0)
