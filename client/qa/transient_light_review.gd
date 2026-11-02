extends "res://scripts/qa_tour.gd"

## Transient light review (#521). While the tour watches a live match, every
## frame on which a transient light is up (the eye's muzzle light, a pawn's
## muzzle glow, a blast light) freezes the tree the way a still does, reads
## the frame back and measures how much of the world is blown out to white.
## A frame over the limit is saved with the lights that were up. Observation
## only: the match, the route and the captures are the tour's own.
##
## Run with `LOCALEXCEPTION_QA_SCRIPT=res://qa/transient_light_review.gd
## LOCALEXCEPTION_QA_MANIFEST=res://qa/transient-lights.json tools/qa_tour.sh <out>`.
## `transient-lights.json` lands in <out>.

## A pixel this bright on every channel reads as blown-out white.
const WHITE_LEVEL: float = 0.92
## Share of sampled pixels over WHITE_LEVEL that counts as a washed frame.
const WASH_LIMIT: float = 0.08
const SAMPLE_STEP: int = 4
const MAX_SAMPLES: int = 400
const MAX_SAVED: int = 12

var _light_rows: Array[Dictionary] = []
var _light_busy: bool = false
var _light_saved: int = 0
var _light_worst: float = 0.0
## Frames with no transient light up are sampled too, as the control.
const CONTROL_SECONDS: float = 2.0
var _control_since: float = 0.0


func _process(delta: float) -> bool:
	super._process(delta)
	if _light_busy or _out_dir.is_empty() or _light_rows.size() >= MAX_SAMPLES:
		return false
	_control_since += delta
	var lit: Array[Dictionary] = _transient_lights()
	if not lit.is_empty() or _control_since >= CONTROL_SECONDS:
		_control_since = 0.0 if lit.is_empty() else _control_since
		_light_busy = true
		_sample.call_deferred(lit)
	return false


## Every transient light up this frame: name, energy, range and where.
func _transient_lights() -> Array[Dictionary]:
	var lit: Array[Dictionary] = []
	for light: Node in root.find_children("*", "OmniLight3D", true, false):
		var omni: OmniLight3D = light as OmniLight3D
		if not omni.is_visible_in_tree() or omni.light_energy <= 0.0:
			continue
		var kind: String = ""
		if omni.name == ViewLight.MUZZLE_NAME:
			kind = "view_muzzle"
		elif omni.name == "MuzzleGlow":
			kind = "pawn_muzzle"
		elif String(omni.name).begins_with("BlastLight"):
			kind = "blast"
		if kind.is_empty():
			continue
		lit.append({"kind": kind, "energy": omni.light_energy, "range": omni.omni_range,
			"attenuation": omni.omni_attenuation, "scale": omni.global_transform.basis.get_scale().x,
			"position": [omni.global_position.x, omni.global_position.y, omni.global_position.z]})
	return lit


func _sample(lit: Array[Dictionary]) -> void:
	paused = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var frame: Image = _grab()
	var share: float = washed_share(frame)
	if share <= WASH_LIMIT:
		paused = false
	_light_worst = maxf(_light_worst, share)
	var row: Dictionary = {"lights": lit, "washed": share, "ms": Time.get_ticks_msec() - _clock_ms, "positional": positional_lights(root)}
	if share > WASH_LIMIT and _light_saved < MAX_SAVED and frame != null:
		_light_saved += 1
		var file_name: String = "washed_%02d.png" % _light_saved
		frame.save_png(_out_dir.path_join(file_name))
		row["file"] = file_name
		row["culprits"] = await _culprits()
	paused = false
	_light_rows.append(row)
	_write_light_report()
	# Leave a few ordinary frames between samples so the match keeps moving.
	for _frame: int in range(6):
		await process_frame
	_light_busy = false


## With the tree still frozen on a washed frame, hide each lit light in turn
## and read the frame again: the lights whose absence clears the wash.
func _culprits() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	paused = true
	for node: Node in root.find_children("*", "Light3D", true, false):
		var light: Light3D = node as Light3D
		if not light.is_visible_in_tree() or light.light_energy <= 0.0:
			continue
		light.visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var share: float = washed_share(_grab())
		light.visible = true
		var entry: Dictionary = {"light": String(light.get_path()), "type": light.get_class(), "energy": light.light_energy,
			"shadow": light.shadow_enabled, "fade": light.distance_fade_enabled, "washed_without": share}
		if light.shadow_enabled:
			light.shadow_enabled = false
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			entry["washed_unshadowed"] = washed_share(_grab())
			light.shadow_enabled = true
		if light.distance_fade_enabled:
			light.distance_fade_enabled = false
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			entry["washed_unfaded"] = washed_share(_grab())
			light.distance_fade_enabled = true
		found.append(entry)
	await RenderingServer.frame_post_draw
	paused = false
	return found


## Omni and spot lights lit anywhere in the tree this frame: the count the
## Compatibility renderer's frame light buffer has to hold.
static func positional_lights(tree_root: Node) -> int:
	var count: int = 0
	for light: Node in tree_root.find_children("*", "Light3D", true, false):
		if (light is OmniLight3D or light is SpotLight3D) and (light as Light3D).is_visible_in_tree() and (light as Light3D).light_energy > 0.0:
			count += 1
	return count


## Share of sampled pixels at or above WHITE_LEVEL on every channel.
static func washed_share(frame: Image) -> float:
	if frame == null or frame.is_empty():
		return 0.0
	var total: int = 0
	var white: int = 0
	for y: int in range(0, frame.get_height(), SAMPLE_STEP):
		for x: int in range(0, frame.get_width(), SAMPLE_STEP):
			var pixel: Color = frame.get_pixel(x, y)
			total += 1
			if pixel.r >= WHITE_LEVEL and pixel.g >= WHITE_LEVEL and pixel.b >= WHITE_LEVEL:
				white += 1
	return float(white) / float(maxi(total, 1))


func _write_light_report() -> void:
	var file: FileAccess = FileAccess.open(_out_dir.path_join("transient-lights.json"), FileAccess.WRITE)
	if file == null:
		return
	var lit_samples: int = 0
	var lit_washed: int = 0
	var control_washed: int = 0
	for row: Dictionary in _light_rows:
		var washed: bool = float(row["washed"]) > WASH_LIMIT
		if (row["lights"] as Array).is_empty():
			control_washed += int(washed)
		else:
			lit_samples += 1
			lit_washed += int(washed)
	file.store_string(JSON.stringify({"schema": 1, "renderer": RenderingServer.get_current_rendering_method(),
		"wash_limit": WASH_LIMIT, "white_level": WHITE_LEVEL, "samples": _light_rows.size(),
		"lit_samples": lit_samples, "lit_washed": lit_washed, "control_samples": _light_rows.size() - lit_samples,
		"control_washed": control_washed, "washed": _light_saved, "worst": _light_worst, "rows": _light_rows}, "\t") + "\n")
	file.close()
