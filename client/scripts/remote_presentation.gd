class_name RemotePresentation
extends RefCounted

## Transform history only. Combat outcomes and campaign phases stay authoritative.
const TICK_USEC: int = 50000
const BUFFER_TICKS: float = 2.0
const MAX_SAMPLES: int = 32
const GAP_TICKS: int = 8
const SNAP_DISTANCE: float = 3.0

var samples: Array[Dictionary] = []
var arrival_offsets: Array[int] = []
var discontinuity: bool = false
var _render_tick: float = -1.0


func reset() -> void:
	samples.clear()
	arrival_offsets.clear()
	_render_tick = -1.0
	discontinuity = false


func accept(tick: int, position: Vector3, yaw: float, pitch: float,
		alive: bool, arrival_usec: int) -> bool:
	discontinuity = false
	if tick < 0 or arrival_usec < 0 or not position.is_finite() or not is_finite(yaw) or not is_finite(pitch):
		return false
	if not samples.is_empty():
		var previous: Dictionary = samples.back()
		if tick <= int(previous["tick"]):
			return false
		if alive != bool(previous["alive"]) or tick - int(previous["tick"]) > GAP_TICKS \
				or position.distance_to(previous["position"]) > SNAP_DISTANCE:
			reset()
	if samples.is_empty():
		discontinuity = true
		_render_tick = float(tick)
	samples.append({"tick": tick, "position": position, "yaw": wrapf(yaw, 0.0, TAU),
		"pitch": clampf(pitch, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT), "alive": alive})
	arrival_offsets.append(arrival_usec - tick * TICK_USEC)
	if samples.size() > MAX_SAMPLES:
		samples.pop_front()
	if arrival_offsets.size() > MAX_SAMPLES:
		arrival_offsets.pop_front()
	return true


func sample(now_usec: int) -> Dictionary:
	if samples.is_empty():
		return {}
	var offset: int = arrival_offsets[0]
	for observed: int in arrival_offsets:
		offset = mini(offset, observed)
	var desired: float = float(now_usec - offset) / float(TICK_USEC) - BUFFER_TICKS
	var newest: Dictionary = samples.back()
	_render_tick = clampf(maxf(_render_tick, desired), float(samples[0]["tick"]), float(newest["tick"]))
	for index: int in range(1, samples.size()):
		var next: Dictionary = samples[index]
		if float(next["tick"]) < _render_tick:
			continue
		var previous: Dictionary = samples[index - 1]
		var weight: float = clampf((_render_tick - float(previous["tick"])) \
			/ float(int(next["tick"]) - int(previous["tick"])), 0.0, 1.0)
		var from: Vector3 = previous["position"]
		return {"position": from.lerp(next["position"], weight),
			"yaw": lerp_angle(float(previous["yaw"]), float(next["yaw"]), weight),
			"pitch": lerpf(float(previous["pitch"]), float(next["pitch"]), weight),
			"tick": _render_tick}
	return {"position": newest["position"], "yaw": newest["yaw"],
		"pitch": newest["pitch"], "tick": _render_tick}
