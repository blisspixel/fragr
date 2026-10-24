class_name StutterReport
extends RefCounted

## Reads a saved client StutterTrace and, when given, the server's tick trace,
## and separates the kinds of stutter a player cannot tell apart by feel:
## a slow drawn frame (with what was busy behind it), a late or missing
## Snapshot (with whether the server stalled, skipped, or sent on time), a
## visible prediction correction or reset, a remote pawn whose interpolation
## ran dry, and a camera that moved unevenly while the player walked steadily.
##
## Attribution is evidence, not proof: a cause is named only when a measured
## share of the slow interval sits in that stage. Anything else is reported as
## unattributed rather than guessed.

const CLIENT_VERSION: int = 1
const SERVER_VERSION: int = 1
const TICK_US: int = 50000
## A spike is half again the median frame and at least 4 ms longer than it.
const SPIKE_RATIO: float = 1.5
const SPIKE_MIN_EXCESS_US: int = 4000
## A hitch long enough to see on any display.
const HITCH_US: int = 50000
## Half of the 100 ms remote interpolation buffer spent waiting.
const SNAPSHOT_GAP_US: int = 75000
## Half a tick late, or a handler over budget, is a server-side stall.
const SERVER_LATE_US: int = 25000
const CORRECTION_VISIBLE_M: float = 0.05
## A stage explains a slow interval when it took this share of the excess.
const CAUSE_SHARE: float = 0.5
## Horizontal camera speed above which a frame counts as moving.
const MOVING_MPS: float = 1.0
## Faster than any fighter or vehicle: a discontinuity, counted apart.
const JUMP_MPS: float = 60.0
const TICK_FIELDS: Array[String] = ["tick", "unix_us", "late_us", "skipped", "sim_us",
	"measure_us", "fanout_us", "total_us", "clients", "messages", "bytes", "overflows"]
const COMPLETE_FIELDS: Array[String] = ["ticks", "dropped", "over_budget", "skipped_periods"]


## Strict NDJSON reader for `--tick-trace` output. A missing footer is allowed
## (a killed server still flushed its ticks) and reported as incomplete.
static func parse_tick_trace(text: String) -> Dictionary:
	var result: Dictionary = {"error": "", "header": {}, "ticks": {}, "complete": {}, "records": 0}
	var ticks: Dictionary = {}
	var last_tick: int = -1
	var lines: PackedStringArray = text.split("\n", false)
	for index: int in range(lines.size()):
		var line: String = lines[index].strip_edges()
		if line.is_empty():
			continue
		var where: String = "line %d" % (index + 1)
		if not (result["complete"] as Dictionary).is_empty():
			return _failed(result, where + ": record after the completion footer")
		var parser: JSON = JSON.new()
		if parser.parse(line) != OK or not parser.data is Dictionary:
			return _failed(result, where + ": not a JSON object")
		var record: Dictionary = parser.data
		var kind: Variant = record.get("record")
		if index == 0 or (result["header"] as Dictionary).is_empty():
			if kind != "header":
				return _failed(result, where + ": the first record must be the header")
			if not _whole(record.get("version")) or int(record["version"]) != SERVER_VERSION:
				return _failed(result, where + ": unsupported tick trace version")
			if not _whole(record.get("tick_us")) or int(record["tick_us"]) <= 0 \
					or not _whole(record.get("started_unix_us")) or not record.get("build") is Dictionary:
				return _failed(result, where + ": malformed header")
			result["header"] = record
			continue
		if kind == "tick":
			var sample: Dictionary = {}
			for field: String in TICK_FIELDS:
				if not _whole(record.get(field)):
					return _failed(result, where + ": tick field %s is not a whole number" % field)
				sample[field] = int(record[field])
			if record.size() != TICK_FIELDS.size() + 1:
				return _failed(result, where + ": unknown tick field")
			if int(sample["tick"]) <= last_tick:
				return _failed(result, where + ": ticks must increase")
			last_tick = int(sample["tick"])
			ticks[last_tick] = sample
		elif kind == "complete":
			var footer: Dictionary = {}
			for field: String in COMPLETE_FIELDS:
				if not _whole(record.get(field)):
					return _failed(result, where + ": footer field %s is not a whole number" % field)
				footer[field] = int(record[field])
			result["complete"] = footer
		else:
			return _failed(result, where + ": unknown record " + str(kind))
		result["records"] = int(result["records"]) + 1
	if (result["header"] as Dictionary).is_empty():
		return _failed(result, "no header")
	result["ticks"] = ticks
	return result


## `server` is a parse_tick_trace result or an empty Dictionary. Returns
## {"error": ""} plus a "session" summary and one per marked phase.
static func analyze(client: Dictionary, server: Dictionary = {}) -> Dictionary:
	var trace: Dictionary = _read_client(client)
	if not str(trace.get("error", "")).is_empty():
		return {"error": trace["error"]}
	var server_ticks: Dictionary = {}
	if not server.is_empty():
		if not str(server.get("error", "")).is_empty():
			return {"error": "server trace: " + str(server["error"])}
		server_ticks = server.get("ticks", {})
	var frames: Dictionary = trace["frames"]
	var median_us: float = _percentile(_floats(frames["interval_us"]), 0.5)
	var start: int = int(trace["started_usec"])
	var end: int = int(trace["stopped_usec"])
	var usec: PackedInt64Array = frames["usec"]
	if end <= start:
		end = usec[usec.size() - 1] if not usec.is_empty() else start
	var report: Dictionary = {
		"error": "",
		"median_frame_ms": _ms(median_us),
		"spike_threshold_ms": _ms(_spike_threshold(median_us)),
		"server_joined": not server_ticks.is_empty(),
		"server_complete": not (server.get("complete", {}) as Dictionary).is_empty(),
		"dropped": client.get("dropped", {}),
		"session": _window(trace, server_ticks, median_us, start, end),
		"phases": [],
	}
	for phase: Dictionary in _phases(trace, start, end):
		var summary: Dictionary = _window(trace, server_ticks, median_us, int(phase["start"]), int(phase["end"]))
		summary["label"] = phase["label"]
		(report["phases"] as Array).append(summary)
	return report


## One Markdown row per phase, then the session total.
static func table(report: Dictionary) -> PackedStringArray:
	var rows: PackedStringArray = PackedStringArray([
		"| Phase | Frames | Frame p50 / p99 / max ms | Spikes | Hitches >=50 ms | Spike causes | Snapshots | Gap p99 / max ms | Gaps >75 ms | Gap causes | Corrections p99 / max m | Visible >0.05 m | Prediction resets | Camera changes | Remote starved frames | Walk speed p5 / p50 / p95 m/s | Server late p99 / max ms | Server handler p99 / max ms | Server skipped | Main thread script / receive / snapshot share | Max messages per poll |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
	])
	var windows: Array = (report.get("phases", []) as Array).duplicate()
	var session: Dictionary = report.get("session", {}).duplicate()
	session["label"] = "whole session"
	windows.append(session)
	for window: Dictionary in windows:
		var f: Dictionary = window["frames"]
		var s: Dictionary = window["snapshots"]
		var c: Dictionary = window["corrections"]
		var v: Dictionary = window["camera_speed"]
		var srv: Dictionary = window["server"]
		var main: Dictionary = window["main_thread"]
		rows.append("| %s | %d | %s / %s / %s | %d | %d | %s | %d | %s / %s | %d | %s | %s / %s | %d | %s | %d | %d | %s / %s / %s | %s / %s | %s / %s | %s | %s / %s / %s | %d |" % [
			window["label"], f["count"], _cell(f["p50_ms"]), _cell(f["p99_ms"]), _cell(f["max_ms"]),
			f["spikes"], f["hitches"], _causes(f["causes"]), s["count"], _cell(s["gap_p99_ms"]),
			_cell(s["gap_max_ms"]), s["gaps"], _causes(s["causes"]), _cell(c["p99_m"]), _cell(c["max_m"]),
			c["visible"], _causes(window["prediction_resets"]), window["camera_changes"],
			window["remote_starved_frames"], _cell(v["p5"]), _cell(v["p50"]), _cell(v["p95"]),
			_cell(srv["late_p99_ms"]), _cell(srv["late_max_ms"]), _cell(srv["total_p99_ms"]),
			_cell(srv["total_max_ms"]), _cell(srv["skipped"]),
			_cell(main["script_share"]), _cell(main["receive_share"]), _cell(main["snapshot_handler_share"]),
			main["max_messages_per_poll"],
		])
	return rows


static func _window(trace: Dictionary, server_ticks: Dictionary, median_us: float, start: int, end: int) -> Dictionary:
	return {
		"start_ms": _ms(float(start - int(trace["started_usec"]))),
		"duration_ms": _ms(float(end - start)),
		"frames": _frame_summary(trace, median_us, start, end),
		"snapshots": _snapshot_summary(trace, server_ticks, start, end),
		"corrections": _correction_summary(trace, start, end),
		"prediction_resets": _event_counts(trace, "prediction_reset", "reason", start, end),
		"camera_changes": (_event_counts(trace, "camera", "to", start, end).values() as Array).reduce(func(a: int, b: int) -> int: return a + b, 0),
		"remote_starved_frames": _starved(trace, start, end),
		"camera_speed": _camera_speed(trace, start, end),
		"server": _server_summary(trace, server_ticks, start, end),
		"main_thread": _main_thread(trace, start, end),
	}


## Where the main thread's wall time went: all _process work, the share spent
## draining the socket (parse, validation and every handler), the Snapshot
## handler alone, and how often messages queued up behind a slow frame.
static func _main_thread(trace: Dictionary, start: int, end: int) -> Dictionary:
	var frames: Dictionary = trace["frames"]
	var usec: PackedInt64Array = frames["usec"]
	var script: PackedInt64Array = frames["script_us"]
	var script_total: int = 0
	for index: int in range(usec.size()):
		if usec[index] > start and usec[index] <= end and script[index] > 0:
			script_total += script[index]
	var polls: Dictionary = trace["polls"]
	var poll_usec: PackedInt64Array = polls["usec"]
	var elapsed: PackedInt64Array = polls["elapsed_us"]
	var packets: PackedInt64Array = polls["packets"]
	var receive_total: int = 0
	var bunched: int = 0
	var most: int = 0
	for index: int in range(poll_usec.size()):
		if poll_usec[index] > start and poll_usec[index] <= end:
			receive_total += elapsed[index]
			most = maxi(most, packets[index])
			if packets[index] > 2:
				bunched += 1
	var snapshots: Dictionary = trace["snapshots"]
	var snapshot_usec: PackedInt64Array = snapshots["usec"]
	var handler: PackedInt64Array = snapshots["handler_us"]
	var handler_total: int = 0
	for index: int in range(snapshot_usec.size()):
		if snapshot_usec[index] > start and snapshot_usec[index] <= end:
			handler_total += handler[index]
	var span: float = maxf(1.0, float(end - start))
	return {"script_share": _round(float(script_total) / span, 3),
		"receive_share": _round(float(receive_total) / span, 3),
		"snapshot_handler_share": _round(float(handler_total) / span, 3),
		"other_receive_share": _round(float(maxi(0, receive_total - handler_total)) / span, 3),
		"max_messages_per_poll": most, "polls_over_two_messages": bunched}


static func _frame_summary(trace: Dictionary, median_us: float, start: int, end: int) -> Dictionary:
	var frames: Dictionary = trace["frames"]
	var usec: PackedInt64Array = frames["usec"]
	var interval: PackedInt64Array = frames["interval_us"]
	var threshold: float = _spike_threshold(median_us)
	var picked: PackedFloat64Array = PackedFloat64Array()
	var spikes: int = 0
	var hitches: int = 0
	var causes: Dictionary = {}
	var worst: Array[Dictionary] = []
	for index: int in range(usec.size()):
		if usec[index] <= start or usec[index] > end:
			continue
		picked.append(float(interval[index]))
		if float(interval[index]) < threshold:
			continue
		spikes += 1
		if interval[index] >= HITCH_US:
			hitches += 1
		var named: PackedStringArray = _frame_causes(trace, index, median_us)
		for cause: String in named:
			causes[cause] = int(causes.get(cause, 0)) + 1
		worst.append({"at_ms": _ms(float(usec[index] - int(trace["started_usec"]))),
			"interval_ms": _ms(float(interval[index])), "causes": named})
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["interval_ms"]) > float(b["interval_ms"]))
	return {"count": picked.size(), "p50_ms": _ms(_percentile(picked, 0.5)),
		"p95_ms": _ms(_percentile(picked, 0.95)), "p99_ms": _ms(_percentile(picked, 0.99)),
		"max_ms": _ms(_percentile(picked, 1.0)), "spikes": spikes, "hitches": hitches,
		"causes": causes, "worst": worst.slice(0, 5)}


## The slow interval runs from usec - interval to usec. Stages are compared
## with its excess over the median, so an ordinary busy frame is not blamed.
static func _frame_causes(trace: Dictionary, index: int, median_us: float) -> PackedStringArray:
	var frames: Dictionary = trace["frames"]
	var end: int = (frames["usec"] as PackedInt64Array)[index]
	var interval: int = (frames["interval_us"] as PackedInt64Array)[index]
	var begin: int = end - interval
	var excess: float = maxf(1.0, float(interval) - median_us)
	var causes: PackedStringArray = PackedStringArray()
	if (frames["compiles"] as PackedInt64Array)[index] > 0:
		causes.append("pipeline_compile")
	var script: int = (frames["script_us"] as PackedInt64Array)[index]
	if script >= 0 and float(script) >= CAUSE_SHARE * excess:
		var polls: Dictionary = trace["polls"]
		var poll_usec: PackedInt64Array = polls["usec"]
		var poll_elapsed: PackedInt64Array = polls["elapsed_us"]
		var receive: int = 0
		for poll: int in range(poll_usec.size()):
			if poll_usec[poll] > begin and poll_usec[poll] <= end:
				receive += poll_elapsed[poll]
		causes.append("network_apply" if float(receive) >= CAUSE_SHARE * excess else "script")
	var render: int = maxi((frames["render_cpu_us"] as PackedInt64Array)[index], (frames["render_gpu_us"] as PackedInt64Array)[index])
	if float(render) >= CAUSE_SHARE * excess:
		causes.append("render")
	if causes.is_empty():
		causes.append("unattributed")
	for event: Dictionary in trace["events"]:
		var at: int = int(event["usec"])
		if at > begin and at <= end:
			if event["kind"] == "camera" and not causes.has("camera_change"):
				causes.append("camera_change")
			elif event["kind"] == "prediction_reset" and not causes.has("prediction_reset"):
				causes.append("prediction_reset")
	return causes


static func _snapshot_summary(trace: Dictionary, server_ticks: Dictionary, start: int, end: int) -> Dictionary:
	var snapshots: Dictionary = trace["snapshots"]
	var usec: PackedInt64Array = snapshots["usec"]
	var ticks: PackedInt64Array = snapshots["tick"]
	var handler: PackedInt64Array = snapshots["handler_us"]
	var gaps: PackedFloat64Array = PackedFloat64Array()
	var handlers: PackedFloat64Array = PackedFloat64Array()
	var count: int = 0
	var missing: int = 0
	var late: int = 0
	var causes: Dictionary = {}
	var delivery: PackedFloat64Array = PackedFloat64Array()
	for index: int in range(usec.size()):
		if usec[index] <= start or usec[index] > end:
			continue
		count += 1
		handlers.append(float(handler[index]))
		var sample: Variant = server_ticks.get(ticks[index])
		if sample is Dictionary:
			var sent_unix: int = int(sample["unix_us"]) + int(sample["total_us"])
			var arrived_unix: int = int(trace["started_unix_us"]) + int(usec[index] - int(trace["started_usec"]))
			delivery.append(float(arrived_unix - sent_unix))
		if index == 0:
			continue
		var gap: int = usec[index] - usec[index - 1]
		gaps.append(float(gap))
		var skipped_ticks: int = maxi(0, int(ticks[index] - ticks[index - 1]) - 1)
		missing += skipped_ticks
		if gap <= SNAPSHOT_GAP_US:
			continue
		late += 1
		for cause: String in _gap_causes(trace, server_ticks, index):
			causes[cause] = int(causes.get(cause, 0)) + 1
	return {"count": count, "gap_p50_ms": _ms(_percentile(gaps, 0.5)),
		"gap_p99_ms": _ms(_percentile(gaps, 0.99)), "gap_max_ms": _ms(_percentile(gaps, 1.0)),
		"gaps": late, "missing_ticks": missing, "causes": causes,
		"handler_p99_ms": _ms(_percentile(handlers, 0.99)), "handler_max_ms": _ms(_percentile(handlers, 1.0)),
		"same_clock_delivery_p50_ms": _ms(_percentile(delivery, 0.5)),
		"same_clock_delivery_p99_ms": _ms(_percentile(delivery, 0.99)),
		"same_clock_delivery_max_ms": _ms(_percentile(delivery, 1.0)),
		"delivery_samples": delivery.size()}


## Why Snapshot `index` arrived long after the one before it.
static func _gap_causes(trace: Dictionary, server_ticks: Dictionary, index: int) -> PackedStringArray:
	var snapshots: Dictionary = trace["snapshots"]
	var usec: PackedInt64Array = snapshots["usec"]
	var ticks: PackedInt64Array = snapshots["tick"]
	var before: int = usec[index - 1]
	var after: int = usec[index]
	var causes: PackedStringArray = PackedStringArray()
	if ticks[index] - ticks[index - 1] > 1:
		var sent: bool = true
		for tick: int in range(ticks[index - 1] + 1, ticks[index]):
			if not server_ticks.has(tick):
				sent = false
				break
		if server_ticks.is_empty():
			causes.append("missing_ticks")
		else:
			causes.append("ticks_not_received" if sent else "server_skipped")
	var sample: Variant = server_ticks.get(ticks[index])
	if sample is Dictionary:
		if int(sample["skipped"]) > 0 and not causes.has("server_skipped"):
			causes.append("server_skipped")
		if int(sample["late_us"]) >= SERVER_LATE_US or int(sample["total_us"]) >= TICK_US:
			causes.append("server_stall")
	# The client reads its socket once per drawn frame. A frame that took half
	# the gap or more delays the arrival stamp even when the bytes were already
	# waiting, however slow the median frame is.
	var frames: Dictionary = trace["frames"]
	var frame_usec: PackedInt64Array = frames["usec"]
	var frame_interval: PackedInt64Array = frames["interval_us"]
	for frame: int in range(frame_usec.size()):
		if frame_usec[frame] <= before:
			continue
		if frame_usec[frame] - frame_interval[frame] >= after:
			break
		if float(frame_interval[frame]) >= 0.5 * float(after - before):
			causes.append("client_frame")
			break
	if causes.is_empty():
		causes.append("delivery" if not server_ticks.is_empty() else "unknown")
	return causes


static func _correction_summary(trace: Dictionary, start: int, end: int) -> Dictionary:
	var corrections: Dictionary = trace["corrections"]
	var usec: PackedInt64Array = corrections["usec"]
	var metres: PackedFloat64Array = corrections["metres"]
	var picked: PackedFloat64Array = PackedFloat64Array()
	var visible: int = 0
	for index: int in range(usec.size()):
		if usec[index] <= start or usec[index] > end or metres[index] < 0.0:
			continue
		picked.append(metres[index])
		if metres[index] > CORRECTION_VISIBLE_M:
			visible += 1
	return {"count": picked.size(), "p50_m": _round(_percentile(picked, 0.5), 4),
		"p95_m": _round(_percentile(picked, 0.95), 4), "p99_m": _round(_percentile(picked, 0.99), 4),
		"max_m": _round(_percentile(picked, 1.0), 4), "visible": visible}


static func _event_counts(trace: Dictionary, kind: String, field: String, start: int, end: int) -> Dictionary:
	var counts: Dictionary = {}
	for event: Dictionary in trace["events"]:
		var at: int = int(event["usec"])
		if event["kind"] != kind or at <= start or at > end:
			continue
		var key: String = str(event.get(field, ""))
		counts[key] = int(counts.get(key, 0)) + int(event.get("count", 1))
	return counts


static func _starved(trace: Dictionary, start: int, end: int) -> int:
	var frames: Dictionary = trace["frames"]
	var usec: PackedInt64Array = frames["usec"]
	var starved: PackedInt64Array = frames["remote_starved"]
	var count: int = 0
	for index: int in range(usec.size()):
		if usec[index] > start and usec[index] <= end and starved[index] > 0:
			count += 1
	return count


## Horizontal camera speed per drawn frame while moving. Steady walking gives
## a narrow band; a hitch, catch-up or correction widens it.
static func _camera_speed(trace: Dictionary, start: int, end: int) -> Dictionary:
	var frames: Dictionary = trace["frames"]
	var usec: PackedInt64Array = frames["usec"]
	var interval: PackedInt64Array = frames["interval_us"]
	var camera: PackedFloat64Array = frames["camera"]
	var speeds: PackedFloat64Array = PackedFloat64Array()
	var jumps: int = 0
	for index: int in range(1, usec.size()):
		if usec[index] <= start or usec[index] > end or interval[index] <= 0:
			continue
		var a: Vector2 = Vector2(camera[(index - 1) * 4], camera[(index - 1) * 4 + 2])
		var b: Vector2 = Vector2(camera[index * 4], camera[index * 4 + 2])
		if not a.is_finite() or not b.is_finite():
			continue
		var speed: float = a.distance_to(b) / (float(interval[index]) / 1000000.0)
		if speed > JUMP_MPS:
			# A respawn, teleport or camera switch, not motion.
			jumps += 1
		elif speed >= MOVING_MPS:
			speeds.append(speed)
	return {"moving_frames": speeds.size(), "jumps": jumps, "p5": _round(_percentile(speeds, 0.05), 2),
		"p50": _round(_percentile(speeds, 0.5), 2), "p95": _round(_percentile(speeds, 0.95), 2)}


static func _server_summary(trace: Dictionary, server_ticks: Dictionary, start: int, end: int) -> Dictionary:
	var late: PackedFloat64Array = PackedFloat64Array()
	var total: PackedFloat64Array = PackedFloat64Array()
	var skipped: int = 0
	var over: int = 0
	if server_ticks.is_empty():
		return {"joined": 0, "late_p99_ms": null, "late_max_ms": null, "total_p99_ms": null,
			"total_max_ms": null, "skipped": null, "over_budget": null}
	var snapshots: Dictionary = trace["snapshots"]
	var usec: PackedInt64Array = snapshots["usec"]
	var ticks: PackedInt64Array = snapshots["tick"]
	var first_tick: int = -1
	var last_tick: int = -1
	for index: int in range(usec.size()):
		if usec[index] > start and usec[index] <= end:
			if first_tick < 0:
				first_tick = ticks[index]
			last_tick = ticks[index]
	# Every server tick between the first and last Snapshot seen in the window,
	# so a tick the client never received still counts against the server.
	if first_tick >= 0:
		for tick: int in range(first_tick, last_tick + 1):
			var sample: Variant = server_ticks.get(tick)
			if not sample is Dictionary:
				continue
			late.append(float(sample["late_us"]))
			total.append(float(sample["total_us"]))
			skipped += int(sample["skipped"])
			if int(sample["total_us"]) >= TICK_US:
				over += 1
	return {"joined": late.size(), "late_p99_ms": _ms(_percentile(late, 0.99)),
		"late_max_ms": _ms(_percentile(late, 1.0)), "total_p99_ms": _ms(_percentile(total, 0.99)),
		"total_max_ms": _ms(_percentile(total, 1.0)), "skipped": skipped, "over_budget": over}


static func _phases(trace: Dictionary, start: int, end: int) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	for event: Dictionary in trace["events"]:
		if event["kind"] == "mark":
			marks.append(event)
	var phases: Array[Dictionary] = []
	for index: int in range(marks.size()):
		var from: int = int(marks[index]["usec"])
		var to: int = int(marks[index + 1]["usec"]) if index + 1 < marks.size() else end
		phases.append({"label": str(marks[index]["label"]), "start": from, "end": maxi(from, to)})
	return phases


## Validates the saved shape and narrows JSON numbers to packed arrays.
static func _read_client(client: Dictionary) -> Dictionary:
	if not _whole(client.get("version")) or int(client["version"]) != CLIENT_VERSION \
			or client.get("kind") != "fragr_client_stutter_trace":
		return {"error": "not a version 1 client stutter trace"}
	for field: String in ["started_usec", "started_unix_us", "stopped_usec"]:
		if not _whole(client.get(field)):
			return {"error": "client field %s is not a whole number" % field}
	var shape: Dictionary = {
		"frames": ["usec", "interval_us", "script_us", "render_cpu_us", "render_gpu_us", "compiles", "remote_starved"],
		"polls": ["usec", "elapsed_us", "packets", "bytes"],
		"snapshots": ["usec", "tick", "handler_us"],
		"acks": ["usec", "seq", "tick"],
		"corrections": ["usec", "tick"],
	}
	var trace: Dictionary = {"started_usec": int(client["started_usec"]),
		"started_unix_us": int(client["started_unix_us"]), "stopped_usec": int(client["stopped_usec"])}
	for group: String in shape:
		if not client.get(group) is Dictionary:
			return {"error": "client group %s is missing" % group}
		var source: Dictionary = client[group]
		var narrowed: Dictionary = {}
		var length: int = -1
		for field: String in shape[group]:
			var values: Variant = _integers(source.get(field))
			if values == null:
				return {"error": "client %s.%s is not a list of whole numbers" % [group, field]}
			if length >= 0 and (values as PackedInt64Array).size() != length:
				return {"error": "client %s lists differ in length" % group}
			length = (values as PackedInt64Array).size()
			narrowed[field] = values
		trace[group] = narrowed
	var camera: Variant = _numbers(client["frames"].get("camera"))
	if camera == null or (camera as PackedFloat64Array).size() != (trace["frames"]["usec"] as PackedInt64Array).size() * 4:
		return {"error": "client frames.camera must hold four numbers per frame"}
	trace["frames"]["camera"] = camera
	for field: String in ["metres", "offset_m"]:
		var values: Variant = _numbers(client["corrections"].get(field))
		if values == null or (values as PackedFloat64Array).size() != (trace["corrections"]["usec"] as PackedInt64Array).size():
			return {"error": "client corrections.%s is malformed" % field}
		trace["corrections"][field] = values
	if not client.get("events") is Array:
		return {"error": "client events must be a list"}
	var events: Array[Dictionary] = []
	for event: Variant in client["events"]:
		if not event is Dictionary or not _whole(event.get("usec")) or not event.get("kind") is String:
			return {"error": "client event is malformed"}
		var copy: Dictionary = event.duplicate()
		copy["usec"] = int(event["usec"])
		events.append(copy)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["usec"]) < int(b["usec"]))
	trace["events"] = events
	var times: PackedInt64Array = trace["frames"]["usec"]
	for index: int in range(1, times.size()):
		if times[index] <= times[index - 1]:
			return {"error": "client frame times must increase"}
	var arrivals: PackedInt64Array = trace["snapshots"]["usec"]
	for index: int in range(1, arrivals.size()):
		if arrivals[index] < arrivals[index - 1]:
			return {"error": "client snapshot arrivals must not go back"}
	trace["error"] = ""
	return trace


static func _integers(value: Variant) -> Variant:
	if not (value is Array or value is PackedInt64Array or value is PackedInt32Array):
		return null
	var out: PackedInt64Array = PackedInt64Array()
	for item: Variant in value:
		if not _signed_whole(item):
			return null
		out.append(int(item))
	return out


static func _numbers(value: Variant) -> Variant:
	if not (value is Array or value is PackedFloat32Array or value is PackedFloat64Array):
		return null
	var out: PackedFloat64Array = PackedFloat64Array()
	for item: Variant in value:
		if item is int or item is float:
			out.append(float(item))
		elif item == null:
			# JSON has no NaN. Godot writes it as null; keep it as unknown.
			out.append(NAN)
		else:
			return null
	return out


static func _floats(values: PackedInt64Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = PackedFloat64Array()
	for value: int in values:
		out.append(float(value))
	return out


## Nearest rank. Empty input has no percentile.
static func _percentile(values: PackedFloat64Array, fraction: float) -> float:
	if values.is_empty():
		return NAN
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	var rank: int = clampi(int(ceilf(clampf(fraction, 0.0, 1.0) * sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[rank]


static func _spike_threshold(median_us: float) -> float:
	if is_nan(median_us):
		return INF
	return maxf(median_us * SPIKE_RATIO, median_us + float(SPIKE_MIN_EXCESS_US))


static func _ms(usec: float) -> Variant:
	return null if is_nan(usec) or is_inf(usec) else snappedf(usec / 1000.0, 0.01)


static func _round(value: float, places: int) -> Variant:
	return null if is_nan(value) or is_inf(value) else snappedf(value, pow(10.0, -places))


static func _cell(value: Variant) -> String:
	return "n/a" if value == null else str(value)


static func _causes(counts: Dictionary) -> String:
	if counts.is_empty():
		return "none"
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(counts[a]) > int(counts[b]) or (int(counts[a]) == int(counts[b]) and str(a) < str(b)))
	var parts: PackedStringArray = PackedStringArray()
	for key: Variant in keys:
		parts.append("%s %d" % [str(key), int(counts[key])])
	return ", ".join(parts)


static func _whole(value: Variant) -> bool:
	return _signed_whole(value) and float(value) >= 0.0


static func _signed_whole(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var number: float = value
		return is_finite(number) and absf(number) <= 9007199254740991.0 and number == floorf(number)
	return false


static func _failed(result: Dictionary, message: String) -> Dictionary:
	result["error"] = message
	result["ticks"] = {}
	return result
