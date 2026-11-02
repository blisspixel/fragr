extends RefCounted
class_name AutoTune

## The auto settings search (docs/plans/graphics-autotune.md, docs/GRAPHICS.md).
## Pure decisions over measurements: BenchmarkRun replays one recorded local
## fight with the local server still running, measures each candidate this
## object asks for, and hands the figures back. Tests drive it with fake
## figures. Tier and 3D resolution are searched separately: tiers first, then
## render scale with the pixel look off, or at most one coarser world-pixel
## suggestion with it on. The pixel look and the dither are art, never spent.

## Pass when the 1% low is at least the target times this, and no frame took
## 50 ms or more. The headroom covers heavier venues than the benchmark scene,
## heat, and the noise of a short window.
const HEADROOM: float = 1.10
## A pass whose GPU time is under this share of the frame budget tries two
## tiers up instead of one.
const SKIP_SHARE: float = 0.40
## A fail whose slowest frames spent less than this share of their interval
## on the GPU is limited by the processor or presentation: lower graphics
## would not help.
const CPU_SHARE: float = 0.60
## Within this share of the threshold, a candidate earns one more window,
## at most MAX_EXTRA per run.
const NEAR: float = 0.05
const MAX_EXTRA: int = 2
## Confirm windows further apart than this share are labelled variable.
const VARIANCE: float = 0.10
const SCORE_SECONDS: float = 8.0
const CONFIRM_SECONDS: float = 12.0
## Warm-up per candidate: until no pipeline compiled for WARMUP_QUIET seconds,
## never longer than WARMUP_MAX.
const WARMUP_QUIET: float = 1.0
const WARMUP_MAX: float = 6.0
## The recorded fight: long enough that the longest warm-up plus the confirm
## window replays new frames rather than a frozen tail.
const CAPTURE_TICKS: int = 400
const SCALES_UP: Array[int] = [125, 150]
const SCALES_DOWN: Array[int] = [83, 67, 50]
const FLOOR_HEIGHT: int = 720
## Kept with a saved record so a stale or foreign one is never read as current.
const RECORD_VERSION: int = 1
const TARGETS: Array[int] = [60, 90, 120, 144]

var target: int = 60
var threshold: float = 66.0
var seed_tier: int = RenderQuality.MEDIUM
var min_tier: int = RenderQuality.POTATO
var max_tier: int = RenderQuality.ULTRA
## A tier the player chose by hand: measured, never moved.
var tier_pinned: bool = false
## Render scale or render height chosen by hand: never moved.
var scale_pinned: bool = false
var start_tier: int = RenderQuality.MEDIUM
var start_scale: int = 100
var start_height: int = 0
var output_height: int = 1080
## The world-pixel choice (0 off) and the factor it gives on this output.
var pixel_choice: int = 0
var pixel_look: bool = false
var renderer: String = "forward_plus"
## On battery or integrated graphics: heat and power slow these down later.
var fragile: bool = false

var phase: String = "idle"
var history: Array[Dictionary] = []
var _pending: Dictionary = {}
var _best: Dictionary = {}
var _best_measure: Dictionary = {}
var _lowest_fail: int = 99
var _extras: int = 0
var _extra_for: String = ""
var _first_window: Dictionary = {}
var _floor_steps: Array[Dictionary] = []
var _confirm_drop_done: bool = false
var limiter: String = ""
var variable: bool = false
var suggestion: Dictionary = {}
var offer_compatibility: bool = false
var passed: bool = false
var final_low_1: float = 0.0

## A tuner for this player's settings and machine.
static func for_settings(preferences: LocalExceptionSettings, fingerprint: Dictionary, output: Vector2i, power: String) -> AutoTune:
	var tune: AutoTune = AutoTune.new()
	tune.renderer = str(fingerprint.get("renderer", RenderingServer.get_current_rendering_method()))
	tune.target = preferences.target_fps()
	tune.output_height = maxi(1, output.y)
	tune.pixel_choice = int(preferences.get_value("video", "pixel_scale"))
	tune.pixel_look = RenderQuality.pixel_factor(tune.pixel_choice, output) > 1
	tune.fragile = power == "battery" or HardwareProfile.integrated(fingerprint)
	tune.tier_pinned = preferences.pinned("quality")
	tune.scale_pinned = preferences.pinned("render_scale") or preferences.pinned("resolution_height")
	tune.start_scale = int(preferences.get_value("video", "render_scale")) if tune.scale_pinned else 100
	tune.start_height = int(preferences.get_value("video", "resolution_height")) if tune.scale_pinned else 0
	var seeded: Dictionary = HardwareProfile.seed(fingerprint)
	tune.seed_tier = int(preferences.get_value("video", "quality")) if tune.tier_pinned else int(seeded["tier"])
	tune.max_tier = RenderQuality.effective_tier(RenderQuality.ULTRA, tune.renderer)
	if HardwareProfile.is_steam_deck(fingerprint):
		# Ultra is never chosen on a Deck; the Deck's target is its own.
		tune.max_tier = RenderQuality.HIGH
		tune.target = 40 if int(fingerprint.get("refresh", 60)) != 90 else 45
	tune.configure()
	return tune

## Derive the threshold and the first candidate from the fields above.
func configure() -> void:
	threshold = float(target) * HEADROOM
	seed_tier = clampi(seed_tier, min_tier, max_tier)
	start_tier = seed_tier
	history.clear()
	_best = {}
	_best_measure = {}
	_lowest_fail = 99
	_extras = 0
	limiter = ""
	variable = false
	suggestion = {}
	offer_compatibility = false
	passed = false
	_confirm_drop_done = false
	phase = "tier"
	_pending = _candidate(start_tier, start_scale, start_height, "tier")

func _candidate(tier: int, scale: int, height: int, kind: String, pixels: int = -1) -> Dictionary:
	return {"tier": tier, "render_scale": scale, "resolution_height": height, "kind": kind,
		"pixel_scale": pixel_choice if pixels < 0 else pixels,
		"seconds": CONFIRM_SECONDS if kind == "confirm" else SCORE_SECONDS}

static func candidate_key(candidate: Dictionary) -> String:
	return "%d:%d:%d:%d" % [int(candidate.get("tier", 0)), int(candidate.get("render_scale", 100)), int(candidate.get("resolution_height", 0)), int(candidate.get("pixel_scale", 0))]

static func label(candidate: Dictionary) -> String:
	var text: String = RenderQuality.tier_name(int(candidate.get("tier", 0)))
	var scale: int = int(candidate.get("render_scale", 100))
	var height: int = int(candidate.get("resolution_height", 0))
	if scale != 100:
		text += " %d%%" % scale
	if height > 0:
		text += " %dp" % height
	if str(candidate.get("kind", "")) == "suggest":
		text += " " + pixel_name(int(candidate.get("pixel_scale", 0)))
	if str(candidate.get("kind", "")) == "confirm":
		text += " confirm"
	return text

static func pixel_name(choice: int) -> String:
	return (["native pixels", "Fine pixels", "Medium pixels", "Chunky pixels"] as Array)[clampi(choice, 0, 3)]

## The candidate to measure next, or {} once the search is done.
func next() -> Dictionary:
	return _pending.duplicate()

func done() -> bool:
	return phase == "done"

## The frame budget at the target, in milliseconds.
func budget_ms() -> float:
	return 1000.0 / float(maxi(1, target))

func passes(measure: Dictionary) -> bool:
	return float(measure.get("low_1_count_fps", 0.0)) >= threshold and int(measure.get("over_50_count", 0)) == 0

## Limited by the processor or presentation: the slowest frames spent little
## of their time on the GPU. Unknown GPU time (0) never counts as CPU bound.
func cpu_bound(measure: Dictionary) -> bool:
	var share: float = float(measure.get("gpu_slow_share", 0.0))
	return share > 0.0 and share < CPU_SHARE

## GPU figures for one scored window: the mean GPU time of every frame and
## the share of the slowest 1% of frames' intervals their GPU time filled.
## Frames whose GPU time was not reported (0) are left out; with none, both
## are 0, which reads as unknown, never as processor bound.
static func gpu_figures(intervals: PackedFloat32Array, gpu_ms: PackedFloat32Array) -> Dictionary:
	var count: int = mini(intervals.size(), gpu_ms.size())
	var total: float = 0.0
	var reported: int = 0
	var order: Array[int] = []
	for index: int in range(count):
		order.append(index)
		if gpu_ms[index] > 0.0:
			total += gpu_ms[index]
			reported += 1
	if reported == 0:
		return {"gpu_ms_mean": 0.0, "gpu_slow_share": 0.0}
	order.sort_custom(func(a: int, b: int) -> bool: return intervals[a] > intervals[b])
	var slow: int = maxi(1, ceili(float(count) * 0.01))
	var gpu_sum: float = 0.0
	var frame_sum: float = 0.0
	for rank: int in range(mini(slow, order.size())):
		var index: int = order[rank]
		if gpu_ms[index] > 0.0:
			gpu_sum += gpu_ms[index]
			frame_sum += intervals[index] * 1000.0
	return {"gpu_ms_mean": total / float(reported), "gpu_slow_share": gpu_sum / frame_sum if frame_sum > 0.0 else 0.0}

## Record the figures for the candidate `next()` returned and choose the next.
func record(measure: Dictionary) -> void:
	if _pending.is_empty():
		return
	var candidate: Dictionary = _pending
	var key: String = candidate_key(candidate)
	var low: float = float(measure.get("low_1_count_fps", 0.0))
	# One more window for a result this close to the line, then the mean.
	if str(candidate["kind"]) != "confirm" and _extra_for != key and _extras < MAX_EXTRA \
			and absf(low - threshold) <= threshold * NEAR and int(measure.get("over_50_count", 0)) == 0:
		_extras += 1
		_extra_for = key
		_first_window = measure.duplicate()
		_pending = candidate.duplicate()
		_pending["kind"] = str(candidate["kind"])
		_pending["extra"] = true
		history.append(_row(candidate, measure, "near the line, measured again"))
		return
	var scored: Dictionary = measure.duplicate()
	if _extra_for == key and not _first_window.is_empty():
		scored["low_1_count_fps"] = (float(_first_window.get("low_1_count_fps", 0.0)) + low) * 0.5
		scored["over_50_count"] = int(_first_window.get("over_50_count", 0)) + int(measure.get("over_50_count", 0))
		_first_window = {}
		_extra_for = ""
	var good: bool = passes(scored)
	history.append(_row(candidate, scored, "passed" if good else "below the line"))
	match str(candidate["kind"]):
		"tier":
			_after_tier(candidate, scored, good)
		"scale_up":
			_after_scale_up(candidate, scored, good)
		"floor", "suggest":
			_after_floor(candidate, scored, good)
		"confirm":
			_after_confirm(candidate, scored)

func _row(candidate: Dictionary, measure: Dictionary, outcome: String) -> Dictionary:
	return {"label": label(candidate), "candidate": candidate.duplicate(), "low_1_count_fps": float(measure.get("low_1_count_fps", 0.0)),
		"fps": float(measure.get("fps", 0.0)), "over_50_count": int(measure.get("over_50_count", 0)),
		"gpu_ms_mean": float(measure.get("gpu_ms_mean", 0.0)), "gpu_slow_share": float(measure.get("gpu_slow_share", 0.0)),
		"pass": passes(measure), "outcome": outcome}

func _keep(candidate: Dictionary, measure: Dictionary) -> void:
	_best = candidate.duplicate()
	_best["kind"] = "best"
	_best_measure = measure.duplicate()

func _after_tier(candidate: Dictionary, measure: Dictionary, good: bool) -> void:
	var tier: int = int(candidate["tier"])
	if good:
		if _best.is_empty() or tier > int(_best["tier"]):
			_keep(candidate, measure)
		if tier_pinned or tier >= max_tier:
			_begin_scale()
			return
		var gpu: float = float(measure.get("gpu_ms_mean", 0.0))
		var step: int = 2 if gpu > 0.0 and gpu < budget_ms() * SKIP_SHARE else 1
		var up: int = mini(mini(tier + step, max_tier), _lowest_fail - 1)
		if up <= tier:
			_begin_scale()
			return
		_pending = _candidate(up, start_scale, start_height, "tier")
		return
	_lowest_fail = mini(_lowest_fail, tier)
	if cpu_bound(measure):
		limiter = "cpu"
		if _best.is_empty():
			# Lowering graphics would not help: keep the highest tier that
			# measured the same, which is this one.
			_keep(candidate, measure)
		_begin_confirm()
		return
	limiter = "gpu"
	if not _best.is_empty():
		var below: int = int(_best["tier"])
		if tier - below >= 2:
			_pending = _candidate(below + 1, start_scale, start_height, "tier")
		else:
			_begin_scale()
		return
	if not tier_pinned and tier > min_tier:
		_pending = _candidate(tier - 1, start_scale, start_height, "tier")
		return
	# Nothing passes at the lowest tier allowed: the floor path.
	_keep(candidate, measure)
	_begin_floor(tier)

## Resolution within the tier found: supersample on a machine that holds the
## top tier with the pixel look off; nothing to search with it on.
func _begin_scale() -> void:
	if scale_pinned or pixel_look or int(_best["tier"]) < max_tier or limiter == "gpu":
		_begin_confirm()
		return
	phase = "scale"
	_pending = _candidate(int(_best["tier"]), SCALES_UP[0], start_height, "scale_up")

func _after_scale_up(candidate: Dictionary, measure: Dictionary, good: bool) -> void:
	if not good:
		limiter = "gpu"
		_begin_confirm()
		return
	_keep(candidate, measure)
	var index: int = SCALES_UP.find(int(candidate["render_scale"]))
	if index >= 0 and index + 1 < SCALES_UP.size():
		_pending = _candidate(int(candidate["tier"]), SCALES_UP[index + 1], start_height, "scale_up")
	else:
		_begin_confirm()

## Potato (or the pinned tier) fails at native output. Pixel look off: lower
## render scales, then a 720-line render where that is fewer lines. Pixel look
## on: one coarser world-pixel step, measured and only suggested. If still
## short, offer the Compatibility renderer on Forward+, unless the processor
## is the limit.
func _begin_floor(tier: int) -> void:
	phase = "floor"
	_floor_steps.clear()
	if not scale_pinned:
		if pixel_look:
			if pixel_choice + 1 < RenderQuality.PIXEL_TARGETS.size():
				_floor_steps.append(_candidate(tier, 100, start_height, "suggest", pixel_choice + 1))
		else:
			var lines: float = float(output_height)
			for scale: int in SCALES_DOWN:
				_floor_steps.append(_candidate(tier, scale, start_height, "floor"))
				lines = float(output_height) * float(scale) / 100.0
			if lines > float(FLOOR_HEIGHT) and output_height > FLOOR_HEIGHT:
				_floor_steps.append(_candidate(tier, 100, FLOOR_HEIGHT, "floor"))
	_next_floor()

func _next_floor() -> void:
	if _floor_steps.is_empty():
		offer_compatibility = renderer == "forward_plus" and limiter != "cpu"
		_begin_confirm()
		return
	_pending = _floor_steps.pop_front()

func _after_floor(candidate: Dictionary, measure: Dictionary, good: bool) -> void:
	if str(candidate["kind"]) == "suggest":
		suggestion = {"pixel_scale": int(candidate["pixel_scale"]), "low_1_count_fps": float(measure.get("low_1_count_fps", 0.0)), "pass": good}
		if not good:
			offer_compatibility = renderer == "forward_plus" and not cpu_bound(measure)
		_begin_confirm()
		return
	if good:
		_keep(candidate, measure)
		_begin_confirm()
		return
	if float(measure.get("low_1_count_fps", 0.0)) > float(_best_measure.get("low_1_count_fps", 0.0)):
		_keep(candidate, measure)
	if cpu_bound(measure):
		limiter = "cpu"
		_begin_confirm()
		return
	_next_floor()

## Measure the choice again for longer. Two windows more than VARIANCE apart
## are labelled variable and the lower figure is kept; a choice whose lower
## figure no longer passes drops one tier (once), unless the processor is the
## limit and a lower tier would not help.
func _begin_confirm() -> void:
	phase = "confirm"
	var chosen: Dictionary = _best.duplicate()
	chosen["kind"] = "confirm"
	chosen["seconds"] = CONFIRM_SECONDS
	_pending = chosen

func _after_confirm(candidate: Dictionary, measure: Dictionary) -> void:
	var first: float = float(_best_measure.get("low_1_count_fps", 0.0))
	var second: float = float(measure.get("low_1_count_fps", 0.0))
	if first <= 0.0:
		# A tier the drop reached without an earlier window: this is its first.
		first = second
	var high: float = maxf(first, second)
	if high > 0.0 and absf(first - second) / high > VARIANCE:
		variable = true
	var lower: float = minf(first, second)
	var over: int = maxi(int(_best_measure.get("over_50_count", 0)), int(measure.get("over_50_count", 0)))
	var holds: bool = lower >= threshold and over == 0
	var was_passing: bool = passes(_best_measure)
	if was_passing and not holds and not _confirm_drop_done and not tier_pinned and int(candidate["tier"]) > min_tier \
			and limiter != "cpu" and (fragile or lower < float(target)):
		_confirm_drop_done = true
		var below: Dictionary = _measured(int(candidate["tier"]) - 1)
		_best = candidate.duplicate()
		_best["tier"] = int(candidate["tier"]) - 1
		_best["render_scale"] = start_scale
		_best["kind"] = "best"
		_best_measure = below if not below.is_empty() else {"low_1_count_fps": 0.0}
		if below.is_empty():
			_pending = _candidate(int(_best["tier"]), start_scale, start_height, "confirm")
			return
		final_low_1 = float(below.get("low_1_count_fps", 0.0))
		passed = float(below.get("low_1_count_fps", 0.0)) >= threshold
		_finish()
		return
	final_low_1 = lower
	passed = holds
	if limiter.is_empty():
		limiter = "none" if int(_best["tier"]) >= max_tier else "gpu"
	_finish()

func _measured(tier: int) -> Dictionary:
	for row: Dictionary in history:
		var candidate: Dictionary = row["candidate"]
		if int(candidate["tier"]) == tier and int(candidate["render_scale"]) == start_scale and str(candidate["kind"]) == "tier":
			return {"low_1_count_fps": row["low_1_count_fps"], "over_50_count": row["over_50_count"]}
	return {}

func _finish() -> void:
	phase = "done"
	_pending = {}
	if limiter.is_empty():
		limiter = "gpu"

## The choice and its reasons, once done.
func result() -> Dictionary:
	if not done():
		return {}
	var others: Array = []
	for row: Dictionary in history:
		if str(row["candidate"]["kind"]) == "tier" and int(row["candidate"]["tier"]) != int(_best["tier"]) and not str(row["outcome"]).begins_with("near"):
			others.append({"label": row["label"], "low_1_count_fps": row["low_1_count_fps"]})
	return {"tier": int(_best["tier"]), "render_scale": int(_best.get("render_scale", 100)), "resolution_height": int(_best.get("resolution_height", 0)),
		"target": target, "threshold": threshold, "low_1_count_fps": final_low_1, "passed": passed, "limiter": limiter, "variable": variable,
		"suggestion": suggestion.duplicate(), "offer_compatibility": offer_compatibility, "tier_pinned": tier_pinned, "scale_pinned": scale_pinned,
		"pixel_scale": pixel_choice, "others": others, "candidates": history.duplicate(true), "fragile": fragile}

## The result card in plain words. `context` names the machine: adapter,
## driver, size [w, h], refresh, date, power, deck (Dictionary or empty).
static func describe(result: Dictionary, context: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if result.is_empty():
		return lines
	var tier: String = RenderQuality.tier_name(int(result["tier"]))
	var target: int = int(result["target"])
	var choice: String = tier
	if int(result["render_scale"]) != 100:
		choice += ", %d%% 3D resolution" % int(result["render_scale"])
	if int(result["resolution_height"]) > 0:
		choice += ", %d-line 3D resolution" % int(result["resolution_height"])
	choice += ", " + pixel_name(int(result["pixel_scale"]))
	lines.append("Auto settings: %s, %d fps target." % [choice, target])
	var others: PackedStringArray = PackedStringArray()
	for other: Variant in result.get("others", []):
		if other is Dictionary:
			others.append("%s %d" % [str(other["label"]), roundi(float(other["low_1_count_fps"]))])
	var measured: String = "Measured 1%% low %d fps" % roundi(float(result["low_1_count_fps"]))
	lines.append(measured + (" (%s)." % ", ".join(others) if not others.is_empty() else "."))
	var limit: String = str(result["limiter"])
	var higher: String = RenderQuality.tier_name(mini(int(result["tier"]) + 1, RenderQuality.ULTRA))
	if not bool(result["passed"]):
		if limit == "cpu":
			lines.append("Limited by the processor; lower graphics would not help. Fights may dip below %d." % target)
		else:
			lines.append("Even these settings measured below %d. The game stays playable; fights will dip." % target)
	elif limit == "cpu":
		lines.append("Limited by the processor; lower graphics would not help.")
	elif limit == "none":
		lines.append("This computer holds %d at the highest settings." % target)
	elif bool(result.get("tier_pinned", false)):
		lines.append("You chose %s by hand; auto settings only tuned around it." % tier)
	else:
		lines.append("Limited by the graphics chip. %s would drop below %d in busy fights." % [higher, target])
	if bool(result["variable"]):
		lines.append("The figures varied between runs, so the lower one counts. Background work or heat can do that.")
	var hint: Dictionary = result.get("suggestion", {})
	if not hint.is_empty():
		lines.append("%s measured %d fps. Your world pixels are an art choice, so the tuner left them: change World Pixels on the Graphics page if you want the frames." % [
			pixel_name(int(hint["pixel_scale"])), roundi(float(hint["low_1_count_fps"]))])
	if bool(result["offer_compatibility"]):
		lines.append("The Compatibility renderer may run better on this graphics chip. Try it: the game restarts, measures again and keeps it only if it is faster.")
	var deck: Dictionary = context.get("deck", {}) if context.get("deck") is Dictionary else {}
	if not deck.is_empty():
		lines.append("Steam Deck: %s" % str(deck.get("reason", "")))
		if not str(deck.get("advice", "")).is_empty():
			lines.append(str(deck["advice"]))
	elif context.has("cap_offer") and int(context["cap_offer"]) > 0:
		lines.append("Your display refreshes faster than %d. A frame cap of %d on the Display page keeps the pace even." % [target, int(context["cap_offer"])])
	if str(context.get("power", "")) == "battery":
		lines.append("Tuned on battery. Plugged in, this computer may hold more; tune again on power.")
	var size: Array = context.get("size", [0, 0]) if context.get("size") is Array else [0, 0]
	var refresh: int = int(context.get("refresh", -1))
	lines.append("%s, %s, %d x %d%s. Tuned %s." % [str(context.get("adapter", "Graphics adapter")), str(context.get("driver", "")),
		int(size[0]) if size.size() > 0 else 0, int(size[1]) if size.size() > 1 else 0, ", %d Hz" % refresh if refresh > 0 else "", str(context.get("date", ""))])
	return lines

## The frame cap auto settings offer: the target, when V-Sync is off and the
## display refreshes faster (a VRR display a little under it, r - r*r/3600).
static func cap_offer(target: int, refresh: int, vsync: bool, vrr: bool = false) -> int:
	if vsync or refresh <= 0:
		return 0
	if vrr and target >= refresh:
		return int(float(refresh) - float(refresh * refresh) / 3600.0)
	return target if refresh > target else 0

## Put a choice into settings, leaving every pinned option alone.
static func apply_record(preferences: LocalExceptionSettings, record: Dictionary) -> void:
	if not preferences.pinned("quality") and record.has("tier"):
		preferences.set_value("video", "quality", int(record["tier"]))
	if not preferences.pinned("render_scale") and record.has("render_scale"):
		preferences.set_value("video", "render_scale", int(record["render_scale"]))
	if not preferences.pinned("resolution_height") and record.has("resolution_height"):
		preferences.set_value("video", "resolution_height", int(record["resolution_height"]))
	var deck: Variant = record.get("deck")
	if deck is Dictionary and not (deck as Dictionary).is_empty():
		if not preferences.pinned("fps_cap"):
			preferences.set_value("video", "fps_cap", int(deck.get("fps_cap", 0)))
		if not preferences.pinned("vsync"):
			preferences.set_value("video", "vsync", bool(deck.get("vsync", false)))

## The saved record as the settings file keeps it: known keys of the right
## type only. Anything else (a hand edit, another version) reads as no tune.
static func clean_record(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source: Dictionary = value
	if source.is_empty() or int(source.get("version", -1)) != RECORD_VERSION or not str(source.get("source", "")) in ["measured", "lookup"]:
		return {}
	var out: Dictionary = {"version": RECORD_VERSION, "source": str(source["source"])}
	for key: String in ["tier", "render_scale", "resolution_height", "target", "revision"]:
		var number: Variant = source.get(key)
		if not (number is int or number is float) or not is_finite(float(number)):
			return {}
		out[key] = int(number)
	if out["tier"] < RenderQuality.POTATO or out["tier"] > RenderQuality.ULTRA or not RenderQuality.scale_valid(out["render_scale"]):
		return {}
	for key: String in ["hardware_key", "display_key", "date", "limiter", "power", "renderer"]:
		out[key] = str(source.get(key, "")).left(64)
	var low: Variant = source.get("low_1_count_fps", 0.0)
	out["low_1_count_fps"] = float(low) if (low is float or low is int) and is_finite(float(low)) else 0.0
	out["variable"] = source.get("variable") == true
	out["retune_advised"] = source.get("retune_advised") == true
	var lines: Array = []
	if source.get("lines") is Array:
		for line: Variant in source["lines"]:
			if line is String and lines.size() < 12:
				lines.append((line as String).left(400))
	out["lines"] = lines
	var deck: Variant = source.get("deck")
	if deck is Dictionary and (deck as Dictionary).has("fps_cap"):
		out["deck"] = {"fps_cap": int(deck.get("fps_cap", 40)), "vsync": deck.get("vsync") == true, "target": int(deck.get("target", 40))}
	var trial: Variant = source.get("compat_trial")
	if trial is Dictionary and (trial as Dictionary).has("forward_low_1"):
		out["compat_trial"] = {"forward_low_1": float(trial.get("forward_low_1", 0.0))}
	return out

## A record for this result and machine.
static func make_record(result: Dictionary, fingerprint: Dictionary, lines: PackedStringArray, source: String, power: String, deck: Dictionary) -> Dictionary:
	var record: Dictionary = {"version": RECORD_VERSION, "source": source, "tier": int(result.get("tier", RenderQuality.MEDIUM)),
		"render_scale": int(result.get("render_scale", 100)), "resolution_height": int(result.get("resolution_height", 0)),
		"target": int(result.get("target", 60)), "revision": RenderQuality.RENDER_COST_REVISION,
		"hardware_key": HardwareProfile.hardware_key(fingerprint), "display_key": HardwareProfile.display_key(fingerprint),
		"date": Time.get_date_string_from_system(), "limiter": str(result.get("limiter", "")), "power": power,
		"renderer": str(fingerprint.get("renderer", "")), "low_1_count_fps": float(result.get("low_1_count_fps", 0.0)),
		"variable": bool(result.get("variable", false)), "lines": Array(lines)}
	if not deck.is_empty():
		record["deck"] = {"fps_cap": int(deck["fps_cap"]), "vsync": bool(deck["vsync"]), "target": int(deck["target"])}
	return clean_record(record)

## Why a saved tune should be run again on this machine, in plain words, or
## "" when it still describes it. Never runs anything by itself.
static func stale_reason(record: Dictionary, fingerprint: Dictionary) -> String:
	if record.is_empty():
		return ""
	if str(record.get("hardware_key", "")) != HardwareProfile.hardware_key(fingerprint):
		return "Your graphics hardware, driver or renderer changed since the last tune."
	if int(record.get("revision", -1)) != RenderQuality.RENDER_COST_REVISION:
		return "This version of localexception draws differently from the one that tuned your settings."
	if bool(record.get("retune_advised", false)):
		return "Frames fell short of your target in recent play."
	if str(record.get("display_key", "")) != HardwareProfile.display_key(fingerprint):
		return "Tuned for another display."
	return ""

## The guess a Skip applies: the hardware list's tier, not measured.
static func lookup_record(fingerprint: Dictionary, target: int) -> Dictionary:
	var seeded: Dictionary = HardwareProfile.seed(fingerprint)
	var lines: PackedStringArray = PackedStringArray([
		"Auto settings: %s from the hardware list (%s), not measured." % [RenderQuality.tier_name(int(seeded["tier"])), str(seeded["note"])],
		"Run Auto settings on the Benchmark page to measure this computer."])
	return make_record({"tier": seeded["tier"], "target": target, "limiter": "lookup"}, fingerprint, lines, "lookup", HardwareProfile.power_state(), {})
