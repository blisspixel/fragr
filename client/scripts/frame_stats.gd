extends RefCounted
class_name FrameStats

## Scored frame times. Compute in seconds and turn into frames per second only
## when a line is printed. The mean of per-frame rates is not this report.
##
## Percentiles use the inclusive linear rank `(count - 1) * (percent / 100)`
## on frame times sorted fastest first. The three 1 percent lows are the 99th
## percentile, the mean of the slowest 1 percent of frames by count, and the
## mean of the slowest frames whose durations add up to 1 percent of the run.
## The 0.1 percent lows use the same three definitions. A run keeps the raw
## intervals; a histogram would not be able to name all three.

const SLOW_FRAME_S: float = 0.033
const STALL_FRAME_S: float = 0.050
const FAST_MEDIAN_MS: float = 8.0
const SLOW_MEDIAN_MS: float = 16.0
const EVEN_RATIO: float = 1.5
const HITCH_RATIO: float = 2.0
const HITCH_SHARE: float = 0.02

const EMPTY_VERDICT: String = "No frames were scored."
const FAST_VERDICT: String = "Frames are fast and even. With sync off, the picture can tear, and the match still moves at 20 snapshots a second."
const HITCH_VERDICT: String = "Frames are fast on average and then hitch. A fast graphics card does not hide a stall between frames."
const SLOW_VERDICT: String = "Frames themselves are slow."
const SLOW_HITCH_VERDICT: String = "Frames are slow, and some of them hitch. The graphics card is not the only limit."
const KEEPING_UP_VERDICT: String = "Frames are keeping up. Read the 99th percentile against the median before blaming the graphics card."

static func report(intervals: PackedFloat32Array) -> Dictionary:
	var clean: PackedFloat32Array = PackedFloat32Array()
	var dropped: int = 0
	for interval: float in intervals:
		if not is_finite(interval) or interval <= 0.0:
			dropped += 1
			continue
		clean.append(interval)
	if clean.is_empty():
		return _empty(dropped)
	var elapsed: float = 0.0
	for interval: float in clean:
		elapsed += interval
	var count: int = clean.size()
	var mean: float = elapsed / float(count)
	var sorted: PackedFloat32Array = clean.duplicate()
	sorted.sort()
	var median: float = _percentile(sorted, 50.0)
	var p99: float = _percentile(sorted, 99.0)
	var deltas: PackedFloat32Array = _deltas(clean)
	var delta_median: float = 0.0
	var delta_p99: float = 0.0
	var delta_max: float = 0.0
	if not deltas.is_empty():
		var sorted_deltas: PackedFloat32Array = deltas.duplicate()
		sorted_deltas.sort()
		delta_median = _percentile(sorted_deltas, 50.0)
		delta_p99 = _percentile(sorted_deltas, 99.0)
		delta_max = sorted_deltas[sorted_deltas.size() - 1]
	return {
		"count": count,
		"dropped": dropped,
		"elapsed_s": elapsed,
		"fps": float(count) / elapsed,
		"mean_ms": mean * 1000.0,
		"min_ms": sorted[0] * 1000.0,
		"p1_ms": _percentile(sorted, 1.0) * 1000.0,
		"p5_ms": _percentile(sorted, 5.0) * 1000.0,
		"median_ms": median * 1000.0,
		"p95_ms": _percentile(sorted, 95.0) * 1000.0,
		"p99_ms": p99 * 1000.0,
		"p999_ms": _percentile(sorted, 99.9) * 1000.0,
		"max_ms": sorted[count - 1] * 1000.0,
		"stdev_ms": _stdev(clean, mean) * 1000.0,
		"mad_ms": _mad(sorted, median) * 1000.0,
		"smoothness": p99 / median if median > 0.0 else 0.0,
		"low_1_percentile_fps": _invert(p99),
		"low_01_percentile_fps": _invert(_percentile(sorted, 99.9)),
		"low_1_count_fps": _invert(_worst_count_mean(sorted, 100)),
		"low_01_count_fps": _invert(_worst_count_mean(sorted, 1000)),
		"low_1_time_fps": _invert(_worst_time_mean(sorted, elapsed, 0.01)),
		"low_01_time_fps": _invert(_worst_time_mean(sorted, elapsed, 0.001)),
		"over_33_share": _share_at_or_above(clean, elapsed, SLOW_FRAME_S),
		"over_50_share": _share_at_or_above(clean, elapsed, STALL_FRAME_S),
		"over_33_count": _count_at_or_above(clean, SLOW_FRAME_S),
		"over_50_count": _count_at_or_above(clean, STALL_FRAME_S),
		"stutter_median_ms": delta_median * 1000.0,
		"stutter_p99_ms": delta_p99 * 1000.0,
		"stutter_max_ms": delta_max * 1000.0,
		"stutter_count": _stutter_count(clean),
	}

static func verdict(summary: Dictionary) -> String:
	if int(summary.get("count", 0)) <= 0:
		return EMPTY_VERDICT
	var median: float = float(summary.get("median_ms", 0.0))
	var ratio: float = float(summary.get("smoothness", 0.0))
	var hitch: float = float(summary.get("over_33_share", 0.0))
	var slow: bool = median > SLOW_MEDIAN_MS
	var uneven: bool = ratio > HITCH_RATIO or hitch >= HITCH_SHARE
	if slow and uneven:
		return SLOW_HITCH_VERDICT
	if slow:
		return SLOW_VERDICT
	if uneven:
		return HITCH_VERDICT
	if median <= FAST_MEDIAN_MS and ratio <= EVEN_RATIO and hitch < HITCH_SHARE:
		return FAST_VERDICT
	return KEEPING_UP_VERDICT

static func _empty(dropped: int) -> Dictionary:
	return {
		"count": 0,
		"dropped": dropped,
		"elapsed_s": 0.0,
		"fps": 0.0,
		"mean_ms": 0.0,
		"min_ms": 0.0,
		"p1_ms": 0.0,
		"p5_ms": 0.0,
		"median_ms": 0.0,
		"p95_ms": 0.0,
		"p99_ms": 0.0,
		"p999_ms": 0.0,
		"max_ms": 0.0,
		"stdev_ms": 0.0,
		"mad_ms": 0.0,
		"smoothness": 0.0,
		"low_1_percentile_fps": 0.0,
		"low_01_percentile_fps": 0.0,
		"low_1_count_fps": 0.0,
		"low_01_count_fps": 0.0,
		"low_1_time_fps": 0.0,
		"low_01_time_fps": 0.0,
		"over_33_share": 0.0,
		"over_50_share": 0.0,
		"over_33_count": 0,
		"over_50_count": 0,
		"stutter_median_ms": 0.0,
		"stutter_p99_ms": 0.0,
		"stutter_max_ms": 0.0,
		"stutter_count": 0,
	}

static func _percentile(sorted: PackedFloat32Array, percent: float) -> float:
	var count: int = sorted.size()
	if count == 1:
		return sorted[0]
	var rank: float = (float(count) - 1.0) * (percent / 100.0)
	var lower: int = int(floor(rank))
	var upper: int = int(ceil(rank))
	return lerpf(sorted[lower], sorted[upper], rank - float(lower))

static func _worst_count_mean(sorted: PackedFloat32Array, divisor: int) -> float:
	var take: int = maxi(1, ceili(float(sorted.size()) / float(divisor)))
	var total: float = 0.0
	for index: int in range(sorted.size() - take, sorted.size()):
		total += sorted[index]
	return total / float(take)

static func _worst_time_mean(sorted: PackedFloat32Array, elapsed: float, fraction: float) -> float:
	var budget: float = elapsed * fraction
	var total: float = 0.0
	var taken: int = 0
	for index: int in range(sorted.size() - 1, -1, -1):
		total += sorted[index]
		taken += 1
		if total >= budget:
			break
	return total / float(taken)

static func _share_at_or_above(intervals: PackedFloat32Array, elapsed: float, limit: float) -> float:
	if elapsed <= 0.0:
		return 0.0
	var total: float = 0.0
	for interval: float in intervals:
		if interval >= limit:
			total += interval
	return total / elapsed

static func _count_at_or_above(intervals: PackedFloat32Array, limit: float) -> int:
	var count: int = 0
	for interval: float in intervals:
		if interval >= limit:
			count += 1
	return count

static func _stdev(intervals: PackedFloat32Array, mean: float) -> float:
	if intervals.size() < 2:
		return 0.0
	var square: float = 0.0
	for interval: float in intervals:
		var delta: float = interval - mean
		square += delta * delta
	return sqrt(square / float(intervals.size()))

static func _mad(sorted: PackedFloat32Array, median: float) -> float:
	var deviations: PackedFloat32Array = PackedFloat32Array()
	deviations.resize(sorted.size())
	for index: int in sorted.size():
		deviations[index] = absf(sorted[index] - median)
	deviations.sort()
	return _percentile(deviations, 50.0)

static func _deltas(intervals: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for index: int in range(1, intervals.size()):
		out.append(absf(intervals[index] - intervals[index - 1]))
	return out

## A frame counts when it is slower than twice the median of the frames that
## ended in the previous second. The frame itself is not part of that median,
## so one hitch counts and a slow stretch does not count forever.
static func _stutter_count(intervals: PackedFloat32Array) -> int:
	var count: int = intervals.size()
	if count < 2:
		return 0
	var ends: PackedFloat32Array = PackedFloat32Array()
	ends.resize(count)
	var cursor: float = 0.0
	for index: int in count:
		cursor += intervals[index]
		ends[index] = cursor
	var stutter: int = 0
	var window: int = 0
	for index: int in count:
		var window_start: float = ends[index] - intervals[index] - 1.0
		while window < index and ends[window] <= window_start:
			window += 1
		if window >= index:
			continue
		var sample: PackedFloat32Array = PackedFloat32Array()
		for earlier: int in range(window, index):
			sample.append(intervals[earlier])
		sample.sort()
		if intervals[index] > _percentile(sample, 50.0) * 2.0:
			stutter += 1
	return stutter

static func _invert(seconds: float) -> float:
	return 1.0 / seconds if seconds > 0.0 else 0.0
