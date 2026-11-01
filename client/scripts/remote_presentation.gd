class_name RemotePresentation
extends RefCounted

## Transform history only. Combat outcomes and campaign phases stay authoritative.
##
## Other fighters are drawn on a timeline that trails the newest snapshot by an
## adaptive buffer. The base is one tick, the least that always has a newer
## snapshot to interpolate toward, plus a small margin for frame and tick
## phase. The buffer widens only by what the arrivals themselves show: the
## 90th percentile of how late each snapshot of the window came against the
## earliest. A steady link draws 60 to 75 ms behind; jitter or a TCP stall
## widens it toward two ticks (100 ms), and it narrows again once the window is
## calm. Changes are slewed, so the drawn clock runs a few percent slow or fast
## and never jumps. Nothing is ever extrapolated: a starved timeline holds the
## newest pose. The mirror for the probes is tools/playtest/src/presentation.rs;
## client/golden/presentation_vectors.json pins both to the same numbers.
const TICK_USEC: int = 50000
## The base the adaptive buffer starts from: one tick plus this margin.
const BASE_TICKS: float = 1.0
const MARGIN_TICKS: float = 0.2
const MIN_BUFFER_TICKS: float = BASE_TICKS + MARGIN_TICKS
const MAX_BUFFER_TICKS: float = 2.0
## Before any arrival is measured the buffer is the safe two ticks.
const START_BUFFER_TICKS: float = MAX_BUFFER_TICKS
## Slew limits in ticks per second of wall time: widening plays 10 percent
## slow, narrowing 2.5 percent fast, both below what a moving fighter shows.
const WIDEN_PER_SECOND: float = 2.0
const NARROW_PER_SECOND: float = 0.5
## Share of the arrival window the buffer covers. A lone late snapshot is
## held through; a run of them (a stall) widens the buffer.
const JITTER_QUANTILE: float = 0.9
const MAX_SAMPLES: int = 32
const GAP_TICKS: int = 8
const SNAP_DISTANCE: float = 3.0

var samples: Array[Dictionary] = []
var arrival_offsets: Array[int] = []
var discontinuity: bool = false
## True when the last sample() wanted a tick newer than any received, so the
## pawn held its newest pose instead of moving. Diagnostic only.
var starved: bool = false
## The buffer, in ticks, the timeline currently draws behind its newest
## arrival schedule. Slewed toward target_buffer_ticks().
var buffer_ticks: float = START_BUFFER_TICKS
## The shared clock. Every fighter is drawn at one render time, the same one
## the client reports as `Action.view_tick`, so a timeline with a clock takes
## its desired tick from it. Null: the timeline is its own clock.
var clock: RemotePresentation = null
var _render_tick: float = -1.0
var _adapted_usec: int = -1


func reset() -> void:
	samples.clear()
	arrival_offsets.clear()
	_render_tick = -1.0
	discontinuity = false
	starved = false
	buffer_ticks = START_BUFFER_TICKS
	_adapted_usec = -1


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


## Feed the timeline as a clock: one call per snapshot, with its tick and no
## pose. Anything but a whole, non-negative tick is ignored.
func observe(tick: Variant, arrival_usec: int) -> bool:
	if not (tick is float or tick is int):
		return false
	var value: float = float(tick)
	if not is_finite(value) or value < 0.0 or value != floorf(value) or value > 9.0e15:
		return false
	return accept(int(value), Vector3.ZERO, 0.0, 0.0, true, arrival_usec)


## The fractional server tick this timeline draws at now, never newer than the
## newest tick received; -1 before any snapshot.
func view_tick(now_usec: int) -> float:
	var shown: Dictionary = sample(now_usec)
	return float(shown["tick"]) if shown.has("tick") else -1.0


## The buffer the arrival window asks for, before slewing: one tick, the
## margin, and the window's 90th percentile lateness, within the bounds.
func target_buffer_ticks() -> float:
	if arrival_offsets.is_empty():
		return START_BUFFER_TICKS
	var base: int = arrival_offsets.min()
	var late: Array[int] = []
	for observed: int in arrival_offsets:
		late.append(observed - base)
	late.sort()
	var index: int = clampi(ceili(JITTER_QUANTILE * float(late.size())) - 1, 0, late.size() - 1)
	return clampf(BASE_TICKS + MARGIN_TICKS + float(late[index]) / float(TICK_USEC),
		MIN_BUFFER_TICKS, MAX_BUFFER_TICKS)


## The server tick this clock wants drawn now, before clamping to the history;
## NAN before any arrival. Slews the buffer by the wall time since the last call.
func desired_tick(now_usec: int) -> float:
	if arrival_offsets.is_empty():
		return NAN
	var elapsed: float = 0.0 if _adapted_usec < 0 else float(maxi(0, now_usec - _adapted_usec)) / 1000000.0
	_adapted_usec = maxi(_adapted_usec, now_usec)
	var target: float = target_buffer_ticks()
	var rate: float = WIDEN_PER_SECOND if target > buffer_ticks else NARROW_PER_SECOND
	buffer_ticks = move_toward(buffer_ticks, target, rate * elapsed)
	var offset: int = arrival_offsets.min()
	return float(now_usec - offset) / float(TICK_USEC) - buffer_ticks


func sample(now_usec: int) -> Dictionary:
	if samples.is_empty():
		return {}
	var desired: float = NAN
	if clock != null and clock != self:
		desired = clock.desired_tick(now_usec)
	if is_nan(desired):
		desired = desired_tick(now_usec)
	var newest: Dictionary = samples.back()
	starved = desired > float(newest["tick"])
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
