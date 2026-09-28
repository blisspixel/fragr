class_name InputAckProbe
extends RefCounted

# Diagnostic send-to-first-matching-Ack timing. This is not RTT: the server
# chooses one Action at each tick and may never acknowledge intervening sends.
# A send enters the sample only when WebSocketPeer queues it successfully;
# this does not prove server receipt.
const MAX_PENDING: int = 512
const MAX_BUCKET_MS: int = 1000
const MAX_ACTION_SEQ: int = 4294967295

var active: bool = false
var interrupted: bool = false
var _started_usec: int = 0
var _pending: Dictionary[int, int] = {}
var _pending_order: Array[int] = []
var _last_sent_seq: int = 0
var _first_sent_seq: int = 0
var _last_ack_seq: int = 0
var _has_ack: bool = false
var _last_snapshot_tick: int = 0
var _last_snapshot_usec: int = 0
var _has_snapshot: bool = false
var _first_ack_usec: int = -1
var _last_ack_usec: int = -1
var _first_snapshot_usec: int = -1
var _max_ack_gap_usec: int = 0
var _max_snapshot_gap_usec: int = 0
var _ack_bins: PackedInt32Array = PackedInt32Array()
var _snapshot_bins: PackedInt32Array = PackedInt32Array()
var sent: int = 0
var failed_sends: int = 0
var invalid_sends: int = 0
var matched_acks: int = 0
var skipped_sends: int = 0
var repeated_acks: int = 0
var stale_acks: int = 0
var unknown_acks: int = 0
var pre_probe_acks: int = 0
var invalid_acks: int = 0
var expired_sends: int = 0
var snapshots: int = 0
var snapshot_tick_gaps: int = 0
var repeated_snapshots: int = 0
var stale_snapshots: int = 0
var invalid_snapshots: int = 0

func begin(now_usec: int) -> void:
	active = true
	interrupted = false
	_started_usec = now_usec
	_pending.clear()
	_pending_order.clear()
	_last_sent_seq = 0
	_first_sent_seq = 0
	_last_ack_seq = 0
	_has_ack = false
	_last_snapshot_tick = 0
	_last_snapshot_usec = 0
	_has_snapshot = false
	_first_ack_usec = -1
	_last_ack_usec = -1
	_first_snapshot_usec = -1
	_max_ack_gap_usec = 0
	_max_snapshot_gap_usec = 0
	_ack_bins.resize(MAX_BUCKET_MS + 2)
	_ack_bins.fill(0)
	_snapshot_bins.resize(MAX_BUCKET_MS + 2)
	_snapshot_bins.fill(0)
	sent = 0
	failed_sends = 0
	invalid_sends = 0
	matched_acks = 0
	skipped_sends = 0
	repeated_acks = 0
	stale_acks = 0
	unknown_acks = 0
	pre_probe_acks = 0
	invalid_acks = 0
	expired_sends = 0
	snapshots = 0
	snapshot_tick_gaps = 0
	repeated_snapshots = 0
	stale_snapshots = 0
	invalid_snapshots = 0

func record_send(seq: int, now_usec: int) -> void:
	if not active:
		return
	if _last_sent_seq == MAX_ACTION_SEQ and seq == 1:
		# The probe's ordered sample window cannot span a wrapped sequence.
		interrupted = true
		active = false
		return
	if seq <= 0 or seq <= _last_sent_seq or now_usec < _started_usec:
		invalid_sends += 1
		return
	if _first_sent_seq == 0:
		_first_sent_seq = seq
	_last_sent_seq = seq
	if _pending_order.size() == MAX_PENDING:
		_pending.erase(_pending_order.pop_front())
		expired_sends += 1
	_pending[seq] = now_usec
	_pending_order.append(seq)
	sent += 1

func record_ack(data: Dictionary, now_usec: int) -> void:
	if not active:
		return
	if not _wire_integer(data.get("seq")) or not _wire_integer(data.get("tick")) or \
		int(data["seq"]) <= 0 or int(data["tick"]) < 0 or now_usec < _started_usec:
		invalid_acks += 1
		return
	var seq: int = int(data["seq"])
	if _first_sent_seq == 0 or seq < _first_sent_seq:
		pre_probe_acks += 1
		return
	if seq > _last_sent_seq:
		invalid_acks += 1
		return
	if _has_ack and seq == _last_ack_seq:
		repeated_acks += 1
		return
	if _has_ack and seq < _last_ack_seq:
		stale_acks += 1
		return
	_has_ack = true
	_last_ack_seq = seq
	if _pending.has(seq):
		var latency_usec: int = now_usec - _pending[seq]
		if latency_usec >= 0:
			matched_acks += 1
			if _first_ack_usec < 0:
				_first_ack_usec = now_usec
			if _last_ack_usec >= 0:
				_max_ack_gap_usec = maxi(_max_ack_gap_usec, now_usec - _last_ack_usec)
			_last_ack_usec = now_usec
			var bucket: int = mini(MAX_BUCKET_MS + 1, latency_usec / 1000)
			_ack_bins[bucket] += 1
		else:
			invalid_acks += 1
	else:
		unknown_acks += 1
	while not _pending_order.is_empty() and _pending_order[0] <= seq:
		var consumed: int = _pending_order.pop_front()
		_pending.erase(consumed)
		if consumed < seq:
			skipped_sends += 1

func record_snapshot(tick: Variant, now_usec: int) -> void:
	if not active:
		return
	if not _wire_integer(tick) or int(tick) < 0 or now_usec < _started_usec:
		invalid_snapshots += 1
		return
	var next_tick: int = int(tick)
	if _has_snapshot:
		if next_tick == _last_snapshot_tick:
			repeated_snapshots += 1
			return
		if next_tick < _last_snapshot_tick:
			stale_snapshots += 1
			return
		snapshot_tick_gaps += next_tick - _last_snapshot_tick - 1
		if now_usec >= _last_snapshot_usec:
			_max_snapshot_gap_usec = maxi(_max_snapshot_gap_usec, now_usec - _last_snapshot_usec)
			var bucket: int = mini(MAX_BUCKET_MS + 1, (now_usec - _last_snapshot_usec) / 1000)
			_snapshot_bins[bucket] += 1
		else:
			invalid_snapshots += 1
	_has_snapshot = true
	if _first_snapshot_usec < 0:
		_first_snapshot_usec = now_usec
	_last_snapshot_tick = next_tick
	_last_snapshot_usec = now_usec
	snapshots += 1

func finish(now_usec: int) -> Dictionary:
	active = false
	return {
		"interrupted": interrupted,
		"duration_seconds": maxf(0.0, float(now_usec - _started_usec) / 1000000.0),
		"sent": sent,
		"failed_sends": failed_sends,
		"invalid_sends": invalid_sends,
		"matched_acks": matched_acks,
		"skipped_sends": skipped_sends,
		"repeated_acks": repeated_acks,
		"stale_acks": stale_acks,
		"unknown_acks": unknown_acks,
		"pre_probe_acks": pre_probe_acks,
		"invalid_acks": invalid_acks,
		"expired_sends": expired_sends,
		"outstanding_sends": _pending_order.size(),
		"action_to_ack_ms": _distribution(_ack_bins),
		"first_matched_ack_ms": _offset_ms(_first_ack_usec, _started_usec),
		"last_matched_ack_ms": _offset_ms(_last_ack_usec, _started_usec),
		"max_matched_ack_gap_ms": _max_ack_gap_usec / 1000,
		"snapshots": snapshots,
		"snapshot_tick_gaps": snapshot_tick_gaps,
		"repeated_snapshots": repeated_snapshots,
		"stale_snapshots": stale_snapshots,
		"invalid_snapshots": invalid_snapshots,
		"snapshot_interval_ms": _distribution(_snapshot_bins),
		"first_snapshot_ms": _offset_ms(_first_snapshot_usec, _started_usec),
		"last_snapshot_ms": _offset_ms(_last_snapshot_usec, _started_usec),
		"max_snapshot_gap_ms": _max_snapshot_gap_usec / 1000,
	}

static func _offset_ms(sample_usec: int, start_usec: int) -> Variant:
	if sample_usec < 0:
		return null
	return (sample_usec - start_usec) / 1000

static func _distribution(bins: PackedInt32Array) -> Dictionary:
	var count: int = 0
	for value: int in bins:
		count += value
	if count == 0:
		return {"samples": 0, "p50": null, "p95": null, "p99": null, "overflow": 0}
	return {"samples": count, "p50": _percentile(bins, count, 50),
		"p95": _percentile(bins, count, 95), "p99": _percentile(bins, count, 99),
		"overflow": bins[MAX_BUCKET_MS + 1]}

static func _wire_integer(value: Variant) -> bool:
	if value is int:
		return value >= -9007199254740991 and value <= 9007199254740991
	if value is float:
		var number: float = value
		return is_finite(number) and number >= -9007199254740991.0 and \
			number <= 9007199254740991.0 and number == floorf(number)
	return false

static func _percentile(bins: PackedInt32Array, count: int, percentage: int) -> int:
	var target: int = (count * percentage + 99) / 100
	var seen: int = 0
	for bucket: int in range(bins.size()):
		seen += bins[bucket]
		if seen >= target:
			return bucket
	return MAX_BUCKET_MS + 1
