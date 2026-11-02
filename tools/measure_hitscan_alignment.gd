extends SceneTree

## Export actual client interpolation samples for the native shot-volume probe.
const Timeline = preload("res://scripts/remote_presentation.gd")
const Movement = preload("res://scripts/movement.gd")
const FRAME_HZ: int = 60
const TOTAL_TICKS: int = 100


func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")


func _feet(tick: float, distance: float, speed: float) -> Vector3:
	return Vector3(distance, 0.0, (tick - 50.0) * speed / 20.0)


func _array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1 or not arguments[0].is_absolute_path():
		push_error("measure_hitscan_alignment: require one absolute output path")
		quit(1)
		return
	var rows: Array[Dictionary] = []
	for distance: float in [5.0, 15.0, 30.0]:
		for speed: float in [0.0, Movement.TOP_SPEED * Movement.DUCK_SPEED_SCALE, Movement.TOP_SPEED]:
			for delay_ms: int in [0, 40, 80]:
				var timeline: RefCounted = Timeline.new()
				var next_tick: int = 0
				var delay_usec: int = delay_ms * 1000
				for frame: int in range(TOTAL_TICKS * FRAME_HZ / 20):
					var now_usec: int = roundi(float(frame) * 1000000.0 / FRAME_HZ)
					while next_tick * Timeline.TICK_USEC + delay_usec <= now_usec:
						var arrival_usec: int = next_tick * Timeline.TICK_USEC + delay_usec
						timeline.accept(next_tick, _feet(next_tick, distance, speed), 0.0, 0.0, true, arrival_usec)
						next_tick += 1
					var shown: Dictionary = timeline.sample(now_usec)
					# Discard startup and compare against the next 20 Hz input step.
					if shown.is_empty() or frame < FRAME_HZ:
						continue
					var resolve_tick: int = ceili(float(now_usec + delay_usec) / Timeline.TICK_USEC)
					rows.append({"distance_m": distance, "speed_m_s": speed,
						"snapshot_delay_ms": delay_ms, "input_delay_ms": delay_ms,
						"render_tick": shown["tick"], "resolve_tick": resolve_tick,
						"shown_feet": _array(shown["position"]),
						"current_feet": _array(_feet(resolve_tick, distance, speed))})
	var document: Dictionary = {"schema": 1, "buffer_ticks": Timeline.BUFFER_TICKS,
		"frame_hz": FRAME_HZ, "tick_usec": Timeline.TICK_USEC, "samples": rows}
	var output: FileAccess = FileAccess.open(arguments[0], FileAccess.WRITE)
	if output == null:
		push_error("measure_hitscan_alignment: cannot open output")
		quit(1)
		return
	output.store_string(JSON.stringify(document) + "\n")
	output.close()
	print("measure_hitscan_alignment: PASS %d samples from RemotePresentation" % rows.size())
	quit(0)
