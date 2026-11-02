extends "res://scripts/qa_tour.gd"

## Fighter contrast scan (#528, docs/plans/fun-craft-targets.md "Silhouette
## and contrast"). While any tour route plays, every SCAN_SECONDS the scan
## takes a sightline to an actor 10 to 40 m away with nothing solid between:
## from the tour's own placed eye when it sees one, else from one live
## fighter's eye to another. It freezes the tree, hides the HUD and reads
## the frame, once more with the subject's rim of light off, then once with
## the subject's figure hidden. The pixels that change are the visible
## silhouette, occlusion included; a ring round it, dilated by a quarter of
## its height, is the local background. Contrast is the WCAG ratio of the
## two mean relative luminances, with and without the rim, on the same
## pixels. Nameplates, the subject's shadow and its own lights are off for
## every read, so the mask is the figure alone. Observation only.
##
## Run with `LOCALEXCEPTION_QA_SCRIPT=res://qa/contrast_scan.gd` and a manifest:
## `contrast-scan.json` with `LOCALEXCEPTION_QA_MAP=1..8 LOCALEXCEPTION_QA_BOTS=9` for the
## multiplayer maps, `contrast-scan-m01.json` or `contrast-scan-m06.json`
## with `LOCALEXCEPTION_QA_BOTS=0` and that level's `LOCALEXCEPTION_QA_MAP_FILE`.
## `contrast-scan.json` (the report) and crops land in the tour's output.

const SCAN_SECONDS: float = 0.5
const NEAR_METRES: float = 10.0
const FAR_METRES: float = 40.0
## The gate: fighter against background at or above this ratio.
const TARGET_RATIO: float = 3.0
## A channel change this large marks a fighter pixel.
const MASK_DELTA: float = 0.04
## A silhouette smaller than this many pixels is too small to judge.
const MIN_MASK_PIXELS: int = 24
## Ring width as a share of the silhouette's screen height, at least RING_MIN.
const RING_SHARE: float = 0.25
const RING_MIN: int = 3
const MAX_SAMPLES: int = 240
const MAX_CROPS: int = 24
const CROP_PADDING: int = 12
## Where a sightline lands on the subject: the chest, this far below the eye.
const CHEST_BELOW_EYE: float = 0.45

var _scan_rows: Array[Dictionary] = []
var _scan_busy: bool = false
var _scan_since: float = 0.0
var _scan_crops: int = 0
var _scan_turn: int = 0
## Actors already read from the tour's current eye, by instance, per view.
var _camera_seen: Dictionary[int, int] = {}
## Sightlines read, and those too small or unclear to measure.
var _scan_reads: int = 0
var _scan_empty: int = 0


func _process(delta: float) -> bool:
	super._process(delta)
	_scan_since += delta
	if _scan_busy or paused or _out_dir.is_empty() or _scan_since < SCAN_SECONDS or _scan_rows.size() >= MAX_SAMPLES:
		return false
	var camera: Camera3D = root.get_camera_3d()
	if camera == null or _game_manager() == null:
		return false
	var pair: Array = _sightline()
	if pair.is_empty():
		return false
	_scan_since = 0.0
	_scan_busy = true
	_scan.call_deferred(pair[0], pair[1])
	return false


## The tour's own stills wait for a sightline read to finish, so neither
## photographs the other's frozen frame.
func _measure(state: Dictionary) -> Dictionary:
	while _scan_busy:
		await process_frame
	return await super._measure(state)


static func _eye(pawn: Node3D) -> Vector3:
	return pawn.global_position + Vector3(0.0, MoveStep.EYE_HEIGHT - LocalPrediction.FLOOR_OFFSET, 0.0)


static func _chest(pawn: Node3D) -> Vector3:
	return _eye(pawn) - Vector3(0.0, CHEST_BELOW_EYE, 0.0)


## Live fighters and campaign actors.
func _live() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var manager: Node = _game_manager()
	for id: Variant in manager.players:
		var pawn: Variant = manager.players[id]
		if not pawn is Node3D or not is_instance_valid(pawn):
			continue
		var hp: Variant = (pawn as Node3D).get("hp")
		if (hp is int or hp is float) and float(hp) > 0.0:
			found.append(pawn as Node3D)
	return found


## One fighter's eye and another fighter 10 to 40 m away with nothing solid
## between them, chosen in turn so every fighter is seen and sees: the view a
## player has of an opponent at fighting range, wherever the fight is.
func _sightline() -> Array:
	var live: Array[Node3D] = _live()
	var solids: Array = _view_solids()
	# The tour's own eye first, when it is a placed view (campaign art routes
	# stand it at eye height in each room): any actor it sees in the band.
	var camera: Camera3D = root.get_camera_3d()
	if camera != null and _scan_turn % 2 == 0:
		for pawn: Node3D in live:
			var chest: Vector3 = _chest(pawn)
			var reach: float = camera.global_position.distance_to(chest)
			if reach < NEAR_METRES or reach > FAR_METRES or camera.is_position_behind(chest) or not pawn.is_visible_in_tree():
				continue
			var screen: Vector2 = camera.unproject_position(chest)
			if not camera.get_viewport().get_visible_rect().has_point(screen) or _blocked(camera.global_position, chest, solids):
				continue
			if _camera_seen.get(pawn.get_instance_id(), -1) == _scan_turn_epoch():
				continue
			_camera_seen[pawn.get_instance_id()] = _scan_turn_epoch()
			_scan_turn += 1
			return [null, pawn]
	_scan_turn += 1
	if live.size() < 2:
		return []
	var count: int = live.size()
	for attempt: int in range(count * count):
		_scan_turn += 1
		var viewer: Node3D = live[_scan_turn % count]
		var subject: Node3D = live[(floori(float(_scan_turn) / float(count)) + 1 + _scan_turn) % count]
		if viewer == subject:
			continue
		var from: Vector3 = _eye(viewer)
		var to: Vector3 = _chest(subject)
		var metres: float = from.distance_to(to)
		if metres < NEAR_METRES or metres > FAR_METRES or _blocked(from, to, solids):
			continue
		return [viewer, subject]
	return []


## The nodes that draw the fighter: a live body and its held gun, or the
## whole actor when it has no live body.
static func _figure(pawn: Node3D) -> Array[Node3D]:
	var parts: Array[Node3D] = []
	var body: Variant = pawn.get("character_view")
	if body is Node3D and is_instance_valid(body):
		parts.append(body as Node3D)
		var held: Node3D = pawn.get_node_or_null("Body") as Node3D
		if held != null:
			parts.append(held)
	else:
		parts.append(pawn)
	return parts


## One number per placed view of the tour's camera, so each actor is read
## once from each view rather than on every tick.
func _scan_turn_epoch() -> int:
	var camera: Camera3D = root.get_camera_3d()
	if camera == null:
		return 0
	var at: Vector3 = camera.global_position.snapped(Vector3.ONE * 0.5)
	return hash([at, camera.global_transform.basis.z.snapped(Vector3.ONE * 0.1)])


static func _blocked(from: Vector3, to: Vector3, solids: Array) -> bool:
	for solid: Variant in solids:
		var box: AABB = ViewLight.solid_box(solid)
		if box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0 and box.intersects_segment(from, to):
			return true
	return false


## Freeze, stand the eye in the viewer's head looking at the subject, and read
## the frame with and without the subject's body.
func _scan(viewer: Variant, subject: Node3D) -> void:
	var camera: Camera3D = root.get_camera_3d()
	var placed: bool = viewer == null
	if camera == null or (not placed and not is_instance_valid(viewer)) or not is_instance_valid(subject):
		_scan_busy = false
		return
	var hud: Node = _find_hud()
	var hud_was: bool = hud != null and bool(hud.get("visible"))
	paused = true
	if hud != null:
		hud.set("visible", false)
	var held: Transform3D = camera.global_transform
	var viewer_was: bool = true if placed else (viewer as Node3D).visible
	if not placed:
		(viewer as Node3D).visible = false
	var plates: Dictionary[Node3D, bool] = {}
	for pawn: Node3D in _live():
		if pawn.has_method("set_nameplate_enabled"):
			plates[pawn] = bool(pawn.get("nameplate_enabled"))
			pawn.set_nameplate_enabled(false)
	var from: Vector3 = camera.global_position if placed else _eye(viewer as Node3D)
	var to: Vector3 = _chest(subject)
	if not placed:
		camera.global_transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), from)
	var shadows: Dictionary[GeometryInstance3D, int] = {}
	for node: Node in subject.find_children("*", "GeometryInstance3D", true, false):
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		shadows[geometry] = geometry.cast_shadow
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The subject's own lights (a muzzle glow) would light the floor in one
	# read and not the other; they stay dark for both.
	var lights: Dictionary[Light3D, bool] = {}
	for node: Node in subject.find_children("*", "Light3D", true, false):
		lights[node as Light3D] = (node as Light3D).visible
		(node as Light3D).visible = false
	# Only the figure itself is hidden for the second read: the live body and
	# its held gun. Ground rings and contact shade under it stay put.
	var figure: Array[Node3D] = _figure(subject)
	var figure_was: Array[bool] = []
	for part: Node3D in figure:
		figure_was.append(part.visible)
	var subject_was: bool = subject.visible
	subject.visible = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var with_body: Image = _grab()
	# The same frame with the subject's rim of light off: the before beside
	# the after, on identical pixels.
	var no_rim: Image = null
	var rims: Array[ShaderMaterial] = []
	for node: Node in subject.find_children("*", "", true, false):
		if FighterRim.of(node) != null:
			rims.append(FighterRim.of(node))
	if not rims.is_empty():
		var strengths: Array[float] = []
		for rim: ShaderMaterial in rims:
			strengths.append(float(rim.get_shader_parameter("rim_strength")))
			rim.set_shader_parameter("rim_strength", 0.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		no_rim = _grab()
		for index: int in range(rims.size()):
			rims[index].set_shader_parameter("rim_strength", strengths[index])
	for part: Node3D in figure:
		part.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var without: Image = _grab()
	var region: Rect2i = _screen_region(camera, subject, with_body.get_size()) if with_body != null else Rect2i()
	var metres: float = from.distance_to(to)
	# Put everything back before the match moves again.
	for index: int in range(figure.size()):
		if is_instance_valid(figure[index]):
			figure[index].visible = figure_was[index]
	if is_instance_valid(subject):
		subject.visible = subject_was
	for light: Light3D in lights:
		if is_instance_valid(light):
			light.visible = lights[light]
	for geometry: GeometryInstance3D in shadows:
		if is_instance_valid(geometry):
			geometry.cast_shadow = shadows[geometry] as GeometryInstance3D.ShadowCastingSetting
	if not placed and is_instance_valid(viewer):
		(viewer as Node3D).visible = viewer_was
	for pawn: Node3D in plates:
		if is_instance_valid(pawn):
			pawn.set_nameplate_enabled(plates[pawn])
	camera.global_transform = held
	if hud != null:
		hud.set("visible", hud_was)
	await RenderingServer.frame_post_draw
	paused = false
	var row: Dictionary = measure(with_body, without, region, no_rim)
	_scan_reads += 1
	_scan_empty += int(row.is_empty())
	if not row.is_empty():
		row["metres"] = snappedf(metres, 0.1)
		row["fighter"] = _fighter_kind(subject) if is_instance_valid(subject) else ""
		row["view"] = "tour" if placed else "fighter"
		row["ms"] = Time.get_ticks_msec() - _clock_ms
		var box: Rect2i = row["box"]
		if _scan_crops < MAX_CROPS:
			_scan_crops += 1
			var file_name: String = "contrast_%02d.png" % _scan_crops
			var crop: Rect2i = box.grow(CROP_PADDING).intersection(Rect2i(Vector2i.ZERO, with_body.get_size()))
			with_body.get_region(crop).save_png(_out_dir.path_join(file_name))
			row["crop"] = file_name
		row["box"] = box_array(box)
		_scan_rows.append(row)
	_write_scan()
	_scan_busy = false


static func box_array(box: Rect2i) -> Array[int]:
	return [box.position.x, box.position.y, box.size.x, box.size.y]


## Where the body can be on screen: a generous box round it, projected.
static func _screen_region(camera: Camera3D, pawn: Node3D, size: Vector2i) -> Rect2i:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for corner: int in range(8):
		var offset: Vector3 = Vector3(1.2 if corner & 1 else -1.2, 1.2 if corner & 2 else -2.4, 1.2 if corner & 4 else -1.2)
		var point: Vector3 = pawn.global_position + offset
		if camera.is_position_behind(point):
			return Rect2i(Vector2i.ZERO, size)
		var screen: Vector2 = camera.unproject_position(point)
		low = low.min(screen)
		high = high.max(screen)
	# Projection is in the viewport's visible rect; the read image may be a
	# different size (content scale), so carry the box into image pixels.
	var visible: Vector2 = camera.get_viewport().get_visible_rect().size
	var scale: Vector2 = Vector2(size) / visible if visible.x > 0.0 and visible.y > 0.0 else Vector2.ONE
	low *= scale
	high *= scale
	return Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil()) + Vector2i.ONE).intersection(Rect2i(Vector2i.ZERO, size))


## What kind of fighter: a campaign actor's kind, else its side and body.
static func _fighter_kind(pawn: Node3D) -> String:
	var campaign: Variant = pawn.get("campaign_actor")
	if campaign is Dictionary and not (campaign as Dictionary).is_empty():
		return "campaign:" + str((campaign as Dictionary).get("kind", "actor"))
	var team: Variant = pawn.get("team")
	var side: String = str(team) if team is String and not (team as String).is_empty() else "ffa"
	var body_kind: Variant = pawn.get("body_kind")
	return side + ":" + (str(body_kind) if body_kind is String and not (body_kind as String).is_empty() else "fighter")


## WCAG relative luminance of an sRGB colour.
static func luminance(colour: Color) -> float:
	var linear: Color = colour.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


static func ratio(a: float, b: float) -> float:
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


## Fighter mask from the two reads, the background ring around it, and the
## contrast between their mean luminances. Empty when the body is too small.
static func measure(with_body: Image, without: Image, region: Rect2i = Rect2i(), no_rim: Image = null) -> Dictionary:
	if with_body == null or without == null or with_body.get_size() != without.get_size():
		return {}
	var width: int = with_body.get_width()
	var height: int = with_body.get_height()
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(width * height)
	var low: Vector2i = Vector2i(width, height)
	var high: Vector2i = Vector2i(-1, -1)
	var count: int = 0
	var body_sum: float = 0.0
	var plain_sum: float = 0.0
	var scan: Rect2i = region if region.has_area() else Rect2i(0, 0, width, height)
	for y: int in range(scan.position.y, scan.end.y):
		for x: int in range(scan.position.x, scan.end.x):
			var a: Color = with_body.get_pixel(x, y)
			var b: Color = without.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > MASK_DELTA:
				mask[y * width + x] = 1
				count += 1
				body_sum += luminance(a)
				if no_rim != null:
					plain_sum += luminance(no_rim.get_pixel(x, y))
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	if count < MIN_MASK_PIXELS:
		return {}
	var box: Rect2i = Rect2i(low, high - low + Vector2i.ONE)
	var ring: int = maxi(RING_MIN, int(roundf(float(box.size.y) * RING_SHARE)))
	var area: Rect2i = box.grow(ring).intersection(Rect2i(0, 0, width, height))
	var ring_sum: float = 0.0
	var ring_count: int = 0
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			if mask[y * width + x] == 1:
				continue
			var near: bool = false
			for dy: int in range(maxi(y - ring, box.position.y), mini(y + ring + 1, box.end.y)):
				for dx: int in range(maxi(x - ring, box.position.x), mini(x + ring + 1, box.end.x)):
					if mask[dy * width + dx] == 1:
						near = true
						break
				if near:
					break
			if near:
				ring_sum += luminance(with_body.get_pixel(x, y))
				ring_count += 1
	if ring_count == 0:
		return {}
	var body: float = body_sum / float(count)
	var background: float = ring_sum / float(ring_count)
	var row: Dictionary = {"pixels": count, "box": box, "body_luminance": snappedf(body, 0.0001),
		"background_luminance": snappedf(background, 0.0001), "ratio": snappedf(ratio(body, background), 0.01)}
	if no_rim != null and no_rim.get_size() == with_body.get_size():
		row["ratio_no_rim"] = snappedf(ratio(plain_sum / float(count), background), 0.01)
	return row


func _write_scan() -> void:
	var passing: int = 0
	var passing_no_rim: int = 0
	var paired: int = 0
	var lowest: float = INF
	for row: Dictionary in _scan_rows:
		passing += int(float(row["ratio"]) >= TARGET_RATIO)
		if row.has("ratio_no_rim"):
			paired += 1
			passing_no_rim += int(float(row["ratio_no_rim"]) >= TARGET_RATIO)
		lowest = minf(lowest, float(row["ratio"]))
	var file: FileAccess = FileAccess.open(_out_dir.path_join("contrast-scan.json"), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"schema": 1, "renderer": RenderingServer.get_current_rendering_method(),
		"band_metres": [NEAR_METRES, FAR_METRES], "target_ratio": TARGET_RATIO, "reads": _scan_reads,
		"unmeasured": _scan_empty, "samples": _scan_rows.size(),
		"passing": passing, "pass_share": snappedf(float(passing) / float(maxi(_scan_rows.size(), 1)), 0.001),
		"paired": paired, "pass_share_no_rim": snappedf(float(passing_no_rim) / float(maxi(paired, 1)), 0.001),
		"lowest": lowest if _scan_rows.size() > 0 else 0.0, "rows": _scan_rows}, "\t") + "\n")
	file.close()
