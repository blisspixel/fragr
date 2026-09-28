extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	var probe: InputAckProbe = InputAckProbe.new()
	probe.begin(0)
	probe.record_ack({"seq": 9, "tick": 1}, 100)
	probe.record_send(10, 1000)
	probe.record_send(11, 2000)
	probe.record_send(12, 3000)
	probe.record_ack({"seq": 9, "tick": 2}, 4000)
	var wire_ack: Variant = JSON.parse_string('{"seq":12,"tick":3,"x":0,"z":0,"yaw":0}')
	probe.record_ack(wire_ack, 12300)
	probe.record_ack({"seq": 12, "tick": 4}, 13000)
	probe.record_ack({"seq": 11, "tick": 5}, 14000)
	probe.record_ack({"seq": 13, "tick": 6}, 15000)
	probe.record_ack({"seq": "12", "tick": 7}, 16000)
	probe.record_ack({"seq": 12.5, "tick": 7}, 16500)
	probe.record_ack({"seq": 12, "tick": INF}, 16600)
	probe.record_send(12, 17000)
	probe.record_snapshot(50, 1000)
	var wire_snapshot: Variant = JSON.parse_string('{"tick":52,"players":[]}')
	probe.record_snapshot(wire_snapshot["tick"], 51000)
	probe.record_snapshot(52, 52000)
	probe.record_snapshot(51, 53000)
	probe.record_snapshot("53", 54000)
	probe.record_snapshot(53.5, 55000)
	var report: Dictionary = probe.finish(61000000)
	_expect(report["sent"] == 3 and report["matched_acks"] == 1 and report["skipped_sends"] == 2,
		"newest Ack matches one send and counts sequences without individual Acks")
	_expect(report["pre_probe_acks"] == 2 and report["repeated_acks"] == 1 and report["stale_acks"] == 1,
		"pre-probe, repeated and stale Acks stay distinct")
	_expect(report["invalid_acks"] == 4 and report["invalid_sends"] == 1,
		"invalid wire values and duplicate sends cannot enter timing samples")
	_expect(report["action_to_ack_ms"] == {"samples": 1, "p50": 9, "p95": 9,
		"p99": 9, "overflow": 0}, "send-to-Ack histogram uses first matching Ack only")
	_expect(report["snapshots"] == 2 and report["snapshot_tick_gaps"] == 1 and
		report["repeated_snapshots"] == 1 and report["stale_snapshots"] == 1 and
		report["invalid_snapshots"] == 2 and report["snapshot_interval_ms"]["p99"] == 50,
		"snapshot intervals and observed tick gaps stay distinct from packet loss")
	_expect(report["first_matched_ack_ms"] == 12 and report["last_matched_ack_ms"] == 12 and
		report["first_snapshot_ms"] == 1 and report["last_snapshot_ms"] == 51 and
		report["max_snapshot_gap_ms"] == 50,
		"sample offsets and maximum gaps cover the observation window")
	probe.begin(100)
	for seq: int in range(1, InputAckProbe.MAX_PENDING + 3):
		probe.record_send(seq, 100 + seq * 1000)
	probe.record_ack({"seq": 1, "tick": 1}, 1000000)
	probe.record_ack({"seq": InputAckProbe.MAX_PENDING + 2, "tick": 2}, 1010000)
	report = probe.finish(1020000)
	_expect(report["expired_sends"] == 2 and report["unknown_acks"] == 1 and
		report["outstanding_sends"] == 0 and report["matched_acks"] == 1 and
		report["skipped_sends"] == InputAckProbe.MAX_PENDING - 1,
		"bounded history expires old sends without matching a later Ack to the wrong time")
	probe.begin(200)
	report = probe.finish(200)
	_expect(report["sent"] == 0 and report["action_to_ack_ms"]["p99"] == null and
		report["snapshot_interval_ms"]["samples"] == 0,
		"new sessions clear all samples and report missing percentiles honestly")
	if _failures == 0:
		print("test_input_ack_probe: PASS")
	quit(1 if _failures > 0 else 0)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		push_error("test_input_ack_probe: " + message)
		_failures += 1
