class_name M01Intake
extends Node3D

## Recall Notice presenter: the intake annex's lived detail, warm service lamps,
## the street skyline and the looped address on the records screen.
##
## Everything here is presentation over the server's authored MapInfo. Props sit
## on registered solids, flush on walls or flat on floors; the few that look
## solid enough to stop a pawn (queue barriers, confiscation bins) are server
## solids, and this only dresses them. Words live in client/i18n/world.en.po.
## Design sources: docs/campaign/m01-recall-notice.md, docs/design/earth.md,
## docs/lore/the-chancellery.md (official captions) and the art bible.

const Geometry = preload("res://scripts/model_geometry.gd")

## The records screen face (z = 6) the address plays on, for shot impacts.
const SCREEN_LOW: Vector3 = Vector3(-3.85, 0.05, 5.6)
const SCREEN_HIGH: Vector3 = Vector3(3.85, 2.35, 6.3)
## Official caption track, in the order the loop shows them. The last one is
## the caption that survives the screen.
const CAPTIONS: Array[String] = [
	"WORLD_M01_CAPTION_PRIORITIES", "WORLD_M01_CAPTION_REGISTRY",
	"WORLD_M01_CAPTION_WELLBEING", "WORLD_M01_CAPTION_GUIDANCE",
	"WORLD_M01_CAPTION_CONTINUITY",
]
const SURVIVING_CAPTION: String = "WORLD_M01_CAPTION_CONTINUITY"
## The confiscated set on the bay bench: the only place the station is heard.
const RADIO_POINT: Vector3 = Vector3(-7.2, 1.15, -23.5)
const RADIO_NEAR_DB: float = -12.0
const RADIO_SILENT_DB: float = -60.0
## Registered strip fixtures (map decorations) that carry a ballast hum.
const HUM_POINTS: Array[Vector3] = [
	Vector3(0, 5.6, -29.75), Vector3(0, 5.6, -20), Vector3(-6, 7.6, -5.5),
	Vector3(-18, 5.6, -14.5), Vector3(-18.5, 7.6, 18), Vector3(-34, 7.6, 21),
	Vector3(-7, 7.6, 20), Vector3(-20.5, 7.6, 37),
]
static var _hum: AudioStreamWAV = null
## Calm, speaking and angry beats of the loop, in seconds.
const MOOD_BEATS: Array[float] = [2.4, 2.2, 1.6, 2.0]
const MOOD_ORDER: Array[int] = [0, 1, 2, 1]
const CAPTION_SECONDS: float = 3.6
## The Turn: once the record is read, the custody lift camera beside the
## console shows Latch's car sink toward the correction ward. A beat to look
## over, then one feed frame per step.
const FEED_DELAY_SECONDS: float = 1.2
const FEED_STEP_SECONDS: float = 0.25
## Where the feed hangs on transfer control's back wall: beside the record
## console, low enough to sit in view while the record is read and clear of
## the file monitor from the console, so the Turn plays where the player looks.
const FEED_POINT: Vector3 = Vector3(-10.9, 6.15, 26.72)
static var _motor: AudioStreamWAV = null

var _shape: RefCounted = Geometry.new()
var _screen_materials: Array[StandardMaterial3D] = []
var _caption: WorldSign = null
var _address: Array[Texture2D] = []
var _static: Array[Texture2D] = []
var _clock: float = 0.0
var _caption_clock: float = 0.0
var _caption_index: int = 0
var _beat: int = 0
var _attempt: int = -1
## True once a shot has broken the looped address. Reset by a new attempt.
var broken: bool = false
## True once this attempt's record is read and the custody car has left (or
## is leaving). Reset by a new attempt.
var transport_left: bool = false
var _feed_material: StandardMaterial3D = null
var _feed_frames: Array[Texture2D] = []
var _feed_step: int = 0
var _feed_clock: float = 0.0
var _feed_running: bool = false
var _motor_player: AudioStreamPlayer3D = null
## Count of lamps and dressed rooms, for tests and the QA manifest.
var lamps: int = 0
var rooms: Array[String] = []
## Rooms built off-tree, attached once their visuals carry the world layer.
var _unattached: Array[Node3D] = []

func _ready() -> void:
	set_process(false)

func clear_map() -> void:
	set_process(false)
	_screen_materials.clear()
	_caption = null
	broken = false
	transport_left = false
	_feed_material = null
	_feed_frames.clear()
	_feed_step = 0
	_feed_running = false
	_motor_player = null
	_attempt = -1
	lamps = 0
	rooms.clear()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

## Recall Notice's own authored layout only. A custom map that reuses the id
## with different furniture gets no dressing rather than floating props.
static func authored(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != 1001 or not info.get("solids") is Array:
		return false
	var wanted: Array = [
		[Vector3(-10, 0, -26), Vector3(-6, 1, -23)],
		[Vector3(-4, 0, 6), Vector3(4, 2.4, 7)],
		[Vector3(-9, 3, 23), Vector3(-6, 4.2, 25)],
		[Vector3(-11.9, 0, -26.8), Vector3(-10.4, 0.95, -23.2)],
	]
	var found: int = 0
	for raw: Variant in info["solids"]:
		if not raw is Dictionary:
			continue
		var solid: Dictionary = raw
		var low: Vector3 = Vector3(float(solid.get("min_x", 0.0)), float(solid.get("bottom", 0.0)), float(solid.get("min_z", 0.0)))
		var high: Vector3 = Vector3(float(solid.get("max_x", 0.0)), float(solid.get("top", 0.0)), float(solid.get("max_z", 0.0)))
		for pair: Array in wanted:
			if low.is_equal_approx(pair[0]) and high.is_equal_approx(pair[1]):
				found += 1
	return found == wanted.size()

func configure_map(info: Dictionary) -> void:
	# The server repeats MapInfo when the lift gate opens. A rebuild of the
	# same building keeps what this attempt already did to it: a broken
	# screen stays broken and a car already leaving keeps sinking.
	var kept: Dictionary = {}
	if active() and authored(info):
		kept = {"attempt": _attempt, "broken": broken, "left": transport_left,
			"step": _feed_step, "clock": _feed_clock, "running": _feed_running}
	clear_map()
	if not authored(info):
		return
	_address = M01IntakeArt.address_frames()
	_static = M01IntakeArt.static_frames()
	_build_skyline()
	_build_street()
	_build_bay()
	_build_hall()
	_build_service()
	_build_records()
	_build_room_tone()
	# Final layers before attachment. Changing a lit instance's layers in the
	# tree leaves the Forward+ light pairing stale, and retiring the room then
	# logs Godot's "indexing did not unpair geometries from light" (#121989).
	for room: Node3D in _unattached:
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()
	set_process(true)
	if not kept.is_empty():
		_attempt = int(kept["attempt"])
		if bool(kept["broken"]):
			break_screen()
		transport_left = bool(kept["left"])
		_feed_step = int(kept["step"])
		_feed_clock = float(kept["clock"])
		_feed_running = bool(kept["running"])
		_show_feed()
		if _feed_running and _feed_step >= 1 and _motor_player.is_inside_tree():
			# The hoist was already running; pick the sound up mid-descent.
			_motor_player.play(float(_feed_step - 1) * FEED_STEP_SECONDS)

func active() -> bool:
	return not rooms.is_empty()

## The station's level for a listener: faint beside the confiscated set and
## silent through the rest of the building. Zero when this is not the intake.
func radio_level_db(listener: Vector3) -> float:
	if not active():
		return 0.0
	if not listener.is_finite():
		return RADIO_SILENT_DB
	var reach: float = clampf((listener.distance_to(RADIO_POINT) - 1.0) / 9.0, 0.0, 1.0)
	return lerpf(RADIO_NEAR_DB, RADIO_SILENT_DB, sqrt(reach))

## A seamless two-second ballast hum: mains fundamental and harmonics with a
## soft buzz, built once in memory. Quiet room tone, not a musical cue.
static func hum_stream() -> AudioStreamWAV:
	if _hum != null:
		return _hum
	var rate: int = 22050
	var count: int = rate * 2
	var data: PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	for index: int in range(count):
		var t: float = float(index) / float(rate)
		var value: float = 0.42 * sin(TAU * 50.0 * t) + 0.24 * sin(TAU * 100.0 * t) \
			+ 0.1 * sin(TAU * 150.0 * t) + 0.05 * sin(TAU * 250.0 * t) + 0.07 * signf(sin(TAU * 100.0 * t))
		data.encode_s16(index * 2, int(clampf(value * 0.55, -1.0, 1.0) * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	_hum = stream
	return stream

func _build_room_tone() -> void:
	var room: Node3D = Node3D.new()
	room.name = "RoomTone"
	add_child(room)
	for index: int in range(HUM_POINTS.size()):
		var hum: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		hum.name = "BallastHum%d" % index
		hum.stream = hum_stream()
		hum.position = HUM_POINTS[index]
		hum.bus = &"Effects"
		hum.volume_db = -22.0
		hum.unit_size = 2.5
		hum.max_distance = 16.0
		hum.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		room.add_child(hum)
		if hum.is_inside_tree():
			hum.play(float(index) * 0.27)

func apply_state(state: Dictionary) -> void:
	if state.get("id") != MissionState.ID:
		return
	var attempt: int = int(state.get("attempt", 1))
	var first_seen: bool = _attempt < 0
	if _attempt >= 0 and attempt != _attempt:
		# A continue restores the building: the loop resumes and the custody
		# car waits at the landing again.
		if broken:
			broken = false
			_caption_index = 0
			_set_caption(CAPTIONS[0])
		_reset_feed()
		first_seen = true
	_attempt = attempt
	var phase: String = str(state.get("phase", ""))
	if phase in ["reach_lift", "departed"] and not transport_left:
		transport_left = true
		if first_seen or _feed_frames.is_empty():
			# Joined or resumed after the record: the shaft is already empty.
			_feed_step = maxi(_feed_frames.size() - 1, 0)
			_show_feed()
		else:
			_feed_running = true
			_feed_clock = -FEED_DELAY_SECONDS
	elif phase in ["briefing", "find_transfer"] and transport_left:
		_reset_feed()

func _reset_feed() -> void:
	transport_left = false
	_feed_running = false
	_feed_step = 0
	_feed_clock = 0.0
	_show_feed()
	if _motor_player != null and _motor_player.is_inside_tree():
		_motor_player.stop()

func _show_feed() -> void:
	if _feed_material != null and _feed_step < _feed_frames.size():
		_feed_material.albedo_texture = _feed_frames[_feed_step]
		_feed_material.emission_texture = _feed_frames[_feed_step]

## The feed's current frame, for tests: 0 at the landing, last when empty.
func feed_frame() -> int:
	return _feed_step

func _advance_feed(delta: float) -> void:
	if not _feed_running:
		return
	_feed_clock += delta
	while _feed_clock >= FEED_STEP_SECONDS and _feed_step < _feed_frames.size() - 1:
		_feed_clock -= FEED_STEP_SECONDS
		_feed_step += 1
		if _feed_step == 1 and _motor_player != null and _motor_player.is_inside_tree():
			_motor_player.play()
		_show_feed()
	if _feed_step >= _feed_frames.size() - 1:
		_feed_running = false

## The car leaving: a release clunk, then a low hoist motor that winds down.
## Built once in memory, played from the feed so it draws the eye up.
static func motor_stream() -> AudioStreamWAV:
	if _motor != null:
		return _motor
	var rate: int = 22050
	var count: int = int(rate * 3.2)
	var data: PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	var phase: float = 0.0
	for index: int in range(count):
		var t: float = float(index) / float(rate)
		var clunk: float = 0.0
		if t < 0.14:
			var grit: float = float(((index * 1103515245 + 12345) >> 8) & 0xffff) / 32768.0 - 1.0
			clunk = (grit * 0.5 + sin(TAU * 70.0 * t)) * pow(1.0 - t / 0.14, 2.0)
		var pitch: float = lerpf(96.0, 58.0, clampf(t / 3.2, 0.0, 1.0))
		phase += TAU * pitch / float(rate)
		var envelope: float = clampf(t / 0.35, 0.0, 1.0) * clampf((3.2 - t) / 1.2, 0.0, 1.0)
		var motor: float = (0.5 * sin(phase) + 0.22 * sin(phase * 2.0) + 0.08 * signf(sin(phase * 3.0))) * envelope
		var value: float = clunk * 0.8 + motor * 0.55
		data.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	_motor = stream
	return stream

## Server-confirmed shot traces. A solid impact on the records screen breaks
## the loop to static; the caption keeps scrolling over the noise.
func observe_shots(results: Variant) -> void:
	if _screen_materials.is_empty() or broken or not results is Array:
		return
	for result: Variant in results:
		if not result is Dictionary or not result.get("trace") is Dictionary:
			continue
		var trace: Dictionary = result["trace"]
		if not trace.get("impact") is Dictionary or trace["impact"].get("kind") != "solid":
			continue
		var end: Variant = trace.get("end")
		if not end is Array or end.size() != 3:
			continue
		var point: Vector3 = Vector3(float(end[0]), float(end[1]), float(end[2]))
		if point.x >= SCREEN_LOW.x and point.x <= SCREEN_HIGH.x and point.y >= SCREEN_LOW.y \
				and point.y <= SCREEN_HIGH.y and point.z >= SCREEN_LOW.z and point.z <= SCREEN_HIGH.z:
			break_screen()
			return

func break_screen() -> void:
	if broken or _screen_materials.is_empty():
		return
	broken = true
	_clock = 0.0
	_set_caption(SURVIVING_CAPTION)
	_show(_static[0])

func _process(delta: float) -> void:
	_advance_feed(delta)
	if _screen_materials.is_empty():
		return
	_clock += delta
	if broken:
		_show(_static[int(_clock * 12.0) % _static.size()])
		return
	if _clock >= MOOD_BEATS[_beat]:
		_clock = 0.0
		_beat = (_beat + 1) % MOOD_ORDER.size()
		_show(_address[MOOD_ORDER[_beat]])
	_caption_clock += delta
	if _caption_clock >= CAPTION_SECONDS:
		_caption_clock = 0.0
		_caption_index = (_caption_index + 1) % CAPTIONS.size()
		_set_caption(CAPTIONS[_caption_index])

func _show(frame: Texture2D) -> void:
	for material: StandardMaterial3D in _screen_materials:
		material.albedo_texture = frame
		material.emission_texture = frame

func _set_caption(key: String) -> void:
	if _caption != null:
		_caption.configure(key, _caption.bounds, M01IntakeArt.BONE)

# --- shared builders -------------------------------------------------------

func _room(label: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = label
	_unattached.append(node)
	rooms.append(label)
	return node

func _finish(room: Node3D) -> void:
	# One merged mesh per room keeps draw calls low and each room's light list
	# local, which the Compatibility renderer's per-object limit needs.
	var props: Node3D = room.get_node_or_null("Props") as Node3D
	if props != null and props.get_child_count() > 0:
		_shape.merge(props)

func _props(room: Node3D) -> Node3D:
	var props: Node3D = room.get_node_or_null("Props") as Node3D
	if props == null:
		props = Node3D.new()
		props.name = "Props"
		room.add_child(props)
	return props

func _mat(key: String, tint: Color, metallic: float = 0.0, roughness: float = 0.82) -> StandardMaterial3D:
	return _shape.material("m01_" + key, tint, metallic, roughness)

func _glow(key: String, tint: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = _mat(key, tint)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = energy
	return material

## A picture on a face. `face` names the host side as MapDecoration does:
## west faces -X, east +X, north -Z, south +Z, up +Y.
func _picture(parent: Node3D, label: String, image: Texture2D, size: Vector2, at: Vector3, face: String, glow: float = 0.0) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = image
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	if glow > 0.0:
		material.emission_enabled = true
		material.emission_texture = image
		material.emission_energy_multiplier = glow
	node.material_override = material
	node.transform = Transform3D(MapDecoration.face_basis(face), at)
	parent.add_child(node)
	return node

## An opaque repeating picture across a wall face, `tile` repeats of the image.
## An optional glow texture lights only its window pixels.
func _tiled(parent: Node3D, label: String, key: String, size: Vector2, at: Vector3, face: String, tile: Vector2, glow: Texture2D = null) -> MeshInstance3D:
	var node: MeshInstance3D = _picture(parent, label, M01IntakeArt.texture(key), size, at, face, 0.0)
	var material: StandardMaterial3D = node.material_override as StandardMaterial3D
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.uv1_scale = Vector3(tile.x, tile.y, 1.0)
	if glow != null:
		material.emission_enabled = true
		material.emission_texture = glow
		material.emission_energy_multiplier = 1.4
	return node

func _sign(parent: Node3D, key: String, size: Vector2, at: Vector3, face: String, ink: Color) -> WorldSign:
	var label: WorldSign = WorldSign.new()
	label.name = "Copy_" + key
	label.configure(key, size, ink)
	label.transform = Transform3D(MapDecoration.face_basis(face), at)
	parent.add_child(label)
	return label

## A plain quad in the shader the venue's solids use, for room floors and
## street paving. Separate floor pieces keep lamp lists per room.
func _floor(parent: Node3D, label: String, low: Vector2, high: Vector2, y: float, material: Material) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = high - low
	node.mesh = mesh
	node.position = Vector3((low.x + high.x) * 0.5, y, (low.y + high.y) * 0.5)
	node.material_override = material
	parent.add_child(node)

## A warm caged service lamp: bulb, cage, optional cable and a short light.
func _lamp(room: Node3D, at: Vector3, energy: float = 1.8, reach: float = 6.0, cable_to: float = -1.0, colour: Color = ArenaSky.SERVICE_LAMP_COLOR) -> OmniLight3D:
	var props: Node3D = _props(room)
	var bulb: StandardMaterial3D = _glow("lamp_bulb_%s" % colour.to_html(false), colour.lightened(0.25), 2.6)
	var cage: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	_shape.cylinder(props, "LampBulb", 0.075, 0.16, bulb, at, 10).rotation.x = PI * 0.5
	_shape.cylinder(props, "LampShade", 0.17, 0.05, cage, at + Vector3(0, 0.1, 0), 12).rotation.x = PI * 0.5
	for side: int in range(4):
		var angle: float = TAU * float(side) / 4.0
		var offset: Vector3 = Vector3(cos(angle), 0, sin(angle)) * 0.11
		_shape.rod(props, "LampCage", at + offset + Vector3(0, 0.09, 0), at + offset * 0.6 + Vector3(0, -0.12, 0), 0.008, cage, 4)
	if cable_to > at.y:
		_shape.rod(props, "LampCable", at + Vector3(0, 0.12, 0), Vector3(at.x, cable_to, at.z), 0.012, cage, 4)
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "ServiceLamp"
	light.position = at + Vector3(0, -0.12, 0)
	light.light_color = colour
	light.light_energy = energy
	light.light_specular = 0.1
	light.omni_range = reach
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 8.0
	room.add_child(light)
	lamps += 1
	return light

## A small desk lamp standing on a counter top, angled toward the work.
func _desk_lamp(room: Node3D, base: Vector3, toward: Vector3) -> void:
	var props: Node3D = _props(room)
	var arm: StandardMaterial3D = _mat("desk_lamp", Color("3d4441"), 0.35, 0.6)
	var shade: StandardMaterial3D = _mat("desk_lamp_shade", Color("4e5844"), 0.2, 0.7)
	_shape.cylinder(props, "DeskLampBase", 0.1, 0.03, arm, base + Vector3(0, 0.015, 0), 10).rotation.x = PI * 0.5
	var elbow: Vector3 = base + Vector3(0, 0.38, 0) + (toward - base).normalized() * -0.05
	var head: Vector3 = elbow + (Vector3(toward.x, elbow.y, toward.z) - elbow).normalized() * 0.28 + Vector3(0, 0.04, 0)
	_shape.rod(props, "DeskLampArm", base, elbow, 0.012, arm, 6)
	_shape.rod(props, "DeskLampArm", elbow, head, 0.012, arm, 6)
	_shape.cylinder(props, "DeskLampShade", 0.09, 0.14, shade, head, 10).rotation.x = PI * 0.5
	var bulb: StandardMaterial3D = _glow("desk_bulb", Color("ffd9a0"), 2.4)
	_shape.cylinder(props, "DeskLampBulb", 0.05, 0.03, bulb, head + Vector3(0, -0.08, 0), 8).rotation.x = PI * 0.5
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "DeskLamp"
	light.position = head + Vector3(0, -0.15, 0)
	light.light_color = ArenaSky.SERVICE_LAMP_COLOR
	light.light_energy = 1.3
	light.light_specular = 0.05
	light.omni_range = 3.6
	light.omni_attenuation = 1.8
	light.shadow_enabled = false
	room.add_child(light)
	lamps += 1

func _papers(props: Node3D, at: Vector3, count: int, seed_value: int) -> void:
	var paper: StandardMaterial3D = _mat("paper", Color("e3dccb"), 0.0, 0.95)
	var form: StandardMaterial3D = _mat("form_green", Color("b8c4a6"), 0.0, 0.95)
	for index: int in range(count):
		var height: float = 0.03 + float((seed_value + index * 7) % 5) * 0.012
		var piece: MeshInstance3D = _shape.block(props, "FormStack", Vector3(0.24, height, 0.32), form if (index + seed_value) % 3 == 0 else paper, at + Vector3(float(index) * 0.29, height * 0.5, float((index * 3 + seed_value) % 4) * 0.03))
		piece.rotation.y = float((index * 5 + seed_value) % 7 - 3) * 0.06

func _stamp(props: Node3D, at: Vector3) -> void:
	var handle: StandardMaterial3D = _mat("stamp_handle", Color("2e2a26"), 0.0, 0.6)
	var pad: StandardMaterial3D = _mat("ink_pad", Color("1e1e22"), 0.0, 0.7)
	var red: StandardMaterial3D = _mat("union_red_paint", Color("8c1a1e"), 0.0, 0.8)
	_shape.block(props, "InkPad", Vector3(0.16, 0.025, 0.11), pad, at + Vector3(0.14, 0.0125, 0))
	_shape.block(props, "InkPadFelt", Vector3(0.13, 0.006, 0.085), red, at + Vector3(0.14, 0.028, 0))
	_shape.block(props, "StampFoot", Vector3(0.08, 0.03, 0.06), handle, at + Vector3(0, 0.015, 0))
	_shape.cylinder(props, "StampHandle", 0.025, 0.1, handle, at + Vector3(0, 0.08, 0), 8).rotation.x = PI * 0.5

# --- skyline -------------------------------------------------------------------

func _build_skyline() -> void:
	var room: Node3D = _room("Skyline")
	var props: Node3D = _props(room)
	var dark: StandardMaterial3D = _mat("tenement_side", Color("3a3733"), 0.0, 0.95)
	var roof: StandardMaterial3D = _mat("tenement_roof", Color("2a2928"), 0.0, 0.95)
	# Homes and repair shops press against the service street. Their upper
	# floors rise above the street walls with warm, ordinary lit windows.
	var blocks: Array = [
		# low corner, high corner, facade face, office
		[Vector3(-26, 0, -39), Vector3(-13, 15, -24), "east", false],
		[Vector3(13, 0, -40), Vector3(26, 12.5, -24), "west", false],
		[Vector3(-14, 0, -52), Vector3(14, 17, -39), "south", false],
		[Vector3(-40, 0, -70), Vector3(-24, 30, -56), "south", true],
		[Vector3(22, 0, -74), Vector3(36, 26, -60), "south", true],
	]
	for entry: Array in blocks:
		var low: Vector3 = entry[0]
		var high: Vector3 = entry[1]
		var size: Vector3 = high - low
		var centre: Vector3 = (low + high) * 0.5
		_shape.block(props, "TenementMass", size, dark, centre)
		_shape.block(props, "TenementParapet", Vector3(size.x + 0.4, 0.5, size.z + 0.4), roof, Vector3(centre.x, high.y + 0.25, centre.z))
		var face: String = entry[2]
		var office: bool = entry[3]
		var facade_low: float = 6.2 if not office else 0.0
		var height: float = high.y - facade_low
		var width: float = size.z if face in ["east", "west"] else size.x
		var at: Vector3 = Vector3(centre.x, facade_low + height * 0.5, centre.z)
		match face:
			"east": at.x = high.x + 0.02
			"west": at.x = low.x - 0.02
			"south": at.z = high.z + 0.02
		var facade: MeshInstance3D = _picture(room, "Facade", M01IntakeArt.texture("windows_office" if office else "windows_home"), Vector2(width, height), at, face, 0.0)
		var material: StandardMaterial3D = facade.material_override as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		material.uv1_scale = Vector3(width / 16.0, height / 12.0, 1.0)
		material.emission_enabled = true
		material.emission_texture = M01IntakeArt.window_glow(office)
		material.emission_energy_multiplier = 1.4
	# Rooftop water tanks and an aerial: people live up there.
	var tank: StandardMaterial3D = _mat("roof_tank", Color("5d5a52"), 0.2, 0.8)
	for at: Vector3 in [Vector3(-20, 15.6, -30), Vector3(18, 13.1, -33), Vector3(6, 17.6, -47)]:
		_shape.cylinder(props, "RoofTank", 1.1, 1.6, tank, at + Vector3(0, 0.8, 0), 12).rotation.x = PI * 0.5
	_shape.rod(props, "Aerial", Vector3(-5, 17.5, -46), Vector3(-5, 21.5, -46), 0.04, tank, 4)
	_shape.rod(props, "Aerial", Vector3(-5.6, 20.6, -46), Vector3(-4.4, 20.6, -46), 0.02, tank, 4)
	# Sagging service cables across the open street.
	var cable: StandardMaterial3D = _mat("cable", Color("1b1b1d"), 0.0, 0.7)
	for line: Array in [[Vector3(-13, 10.5, -37), Vector3(13, 9.8, -35)], [Vector3(-13, 11.2, -33.5), Vector3(13, 10.6, -36.5)]]:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var points: PackedVector3Array = []
		for step: int in range(9):
			var t: float = float(step) / 8.0
			points.append(a.lerp(b, t) + Vector3(0, -sin(t * PI) * 1.1, 0))
		_shape.pipe(props, "StreetCable", points, 0.025, cable)
	# The annex itself rises over its own door: bone enamel, the institutional
	# band, and two issued banners either side of the seal.
	var enamel: Material = ArenaMaterials.authored("enamel", "earth_intake")
	var facade_node: MeshInstance3D = MeshInstance3D.new()
	facade_node.name = "AnnexUpperFacade"
	var mass: BoxMesh = BoxMesh.new()
	mass.size = Vector3(26.0, 6.5, 1.2)
	facade_node.mesh = mass
	facade_node.position = Vector3(0, 6.25 + 3.25, -27.6)
	facade_node.material_override = enamel
	room.add_child(facade_node)
	var glass: StandardMaterial3D = _mat("annex_glass", Color("1d2426"), 0.1, 0.4)
	var lit: StandardMaterial3D = _glow("annex_glass_lit", Color("b8c8c0"), 0.9)
	for index: int in range(10):
		var x: float = -11.25 + float(index) * 2.5
		if absf(x) < 3.0:
			continue
		_shape.block(props, "AnnexWindow", Vector3(1.0, 1.7, 0.06), lit if index in [1, 7] else glass, Vector3(x, 10.4, -28.22))
	_picture(room, "AnnexSeal", M01IntakeArt.texture("emblem"), Vector2(2.4, 2.4), Vector3(0, 10.1, -28.23), "north", 0.0)
	_sign(room, "WORLD_M01_ANNEX_NUMBER", Vector2(5.0, 0.7), Vector3(0, 12.15, -28.24), "north", M01IntakeArt.BONE)
	for x: float in [-3.3, 3.3]:
		_picture(room, "AnnexBanner", M01IntakeArt.texture("banner"), Vector2(1.3, 5.0), Vector3(x, 9.9, -28.25), "north", 0.0)
		_shape.rod(props, "BannerRod", Vector3(x - 0.75, 12.45, -28.3), Vector3(x + 0.75, 12.45, -28.3), 0.035, tank, 6)
	_finish(room)

# --- service street --------------------------------------------------------------

func _build_street() -> void:
	var room: Node3D = _room("Street")
	var props: Node3D = _props(room)
	var paving: ShaderMaterial = ArenaMaterials.scenery_tile(EnvironmentTextures.EARTH + "earth_yard_cast_concrete.png", Color("34332f"))
	paving.set_shader_parameter("tile_floor_strength", 0.42)
	paving.set_shader_parameter("tile_strength", 0.42)
	_floor(room, "StreetPaving", Vector2(-12, -38), Vector2(12, -28), 0.01, paving)
	# The street walls are the tenements' own ground floors: a shuttered shop,
	# a front door and lit flats above, rather than a blank enclosure.
	_tiled(room, "TenementFrontage", "frontage", Vector2(24.0, 6.0), Vector3(0, 3.0, -37.98), "south", Vector2(2.0, 1.0), M01IntakeArt.frontage_glow())
	for side: float in [-1.0, 1.0]:
		_tiled(room, "TenementFlats", "frontage", Vector2(11.0, 2.2), Vector3(side * 11.98, 4.9, -33.5), "west" if side > 0.0 else "east", Vector2(11.0 / 12.0, 0.367), M01IntakeArt.frontage_glow())
	var kerb: StandardMaterial3D = _mat("kerb", Color("57544e"), 0.0, 0.95)
	var grate: StandardMaterial3D = _mat("drain_grate", Color("1f2021"), 0.5, 0.5)
	_shape.block(props, "Gutter", Vector3(24.0, 0.04, 0.5), kerb, Vector3(0, 0.02, -37.7))
	for x: float in [-7.0, 5.0]:
		_shape.block(props, "DrainGrate", Vector3(0.9, 0.012, 0.42), grate, Vector3(x, 0.045, -37.7))
	# Queue lane: two registered barriers with posts and a worn painted lane.
	var post: StandardMaterial3D = _mat("barrier_post", Color("2b2c2e"), 0.5, 0.5)
	var rail: StandardMaterial3D = _mat("barrier_rail", Color("8b8d86"), 0.6, 0.45)
	var paint: StandardMaterial3D = _mat("lane_paint", Color("cfc7ac"), 0.0, 0.9)
	for x: float in [-3.675, 3.675]:
		for index: int in range(5):
			var z: float = -37.0 + float(index) * 1.85
			_shape.cylinder(props, "QueuePost", 0.055, 1.1, post, Vector3(x, 0.55, z), 10).rotation.x = PI * 0.5
			_shape.cylinder(props, "QueueFoot", 0.17, 0.035, post, Vector3(x, 0.018, z), 12).rotation.x = PI * 0.5
		_shape.rod(props, "QueueRail", Vector3(x, 1.03, -37.0), Vector3(x, 1.03, -29.6), 0.03, rail, 8)
		# Barred bays on both faces of the registered barrier solid, so it reads
		# as an issued queue rail rather than a plain slab.
		for side: float in [-1.0, 1.0]:
			var face: String = "east" if side > 0.0 else "west"
			_tiled(room, "QueueBarrierBay", "queue_barrier", Vector2(7.4, 1.0), Vector3(x + side * 0.08, 0.5, -33.3), face, Vector2(4.0, 1.0))
	for z: float in [-36.0, -34.4, -32.8, -31.2, -29.6]:
		for x: float in [-0.16, 0.16]:
			_shape.block(props, "QueueFootMark", Vector3(0.12, 0.006, 0.26), paint, Vector3(x, 0.016, z))
	# The lane sign stands at the door end, facing the people arriving.
	_shape.block(props, "QueueSignPost", Vector3(0.05, 1.5, 0.05), post, Vector3(-3.675, 0.75, -29.3))
	var plate: StandardMaterial3D = _mat("sign_plate_green", Color("2f3a30"), 0.2, 0.7)
	_shape.block(props, "QueueSignPlate", Vector3(0.95, 0.55, 0.03), plate, Vector3(-3.675, 1.62, -29.34))
	_sign(room, "WORLD_M01_QUEUE_HERE", Vector2(0.86, 0.46), Vector3(-3.675, 1.62, -29.36), "north", M01IntakeArt.BONE)
	# Sealed repair stalls: free people's work, shut by notice.
	_stall(room, Vector3(-11.98, 0, -35.4), "east", Color("4f6f68"), "WORLD_M01_STALL_RADIO")
	_stall(room, Vector3(-11.98, 0, -31.9), "east", Color("8a5a3a"), "WORLD_M01_STALL_PARTS")
	_stall(room, Vector3(11.98, 0, -36.2), "west", Color("6a5f7e"), "WORLD_M01_STALL_CHARGE")
	# The recall notice pasted over an old advert for a helpful home robot.
	_picture(room, "HomeHelperAdvert", M01IntakeArt.texture("advert"), Vector2(2.0, 2.8), Vector3(11.985, 2.35, -32.4), "west", 0.0)
	_sign(room, "WORLD_M01_ADVERT", Vector2(0.95, 0.42), Vector3(11.98, 1.32, -32.85), "west", Color("3a3330"))
	_notice(room, Vector3(11.975, 1.85, -31.85), "west", 1.0, true)
	_notice(room, Vector3(-3.0 - 0.75, 2.0, -28.02), "north", 0.9, false)
	# Warm lamps: two under the door canopy and a bracket lamp down the street.
	_lamp(room, Vector3(-6.5, 5.25, -29.8), 2.2, 7.5, 6.0)
	_lamp(room, Vector3(6.5, 5.25, -29.8), 2.2, 7.5, 6.0)
	var bracket: StandardMaterial3D = _mat("lamp_bracket", Color("2f3030"), 0.4, 0.6)
	_shape.rod(props, "StreetLampBracket", Vector3(-12, 4.6, -37.0), Vector3(-11.2, 4.6, -37.0), 0.03, bracket, 6)
	_lamp(room, Vector3(-11.2, 4.45, -37.0), 2.4, 9.0, 4.6, Color(1.0, 0.68, 0.38))
	_finish(room)

func _stall(room: Node3D, at: Vector3, face: String, paint: Color, name_key: String) -> void:
	var props: Node3D = _props(room)
	var basis: Basis = MapDecoration.face_basis(face)
	var out: Vector3 = basis.z
	var along: Vector3 = basis.x
	var shutter: StandardMaterial3D = _mat("shutter_%s" % paint.to_html(false), paint, 0.3, 0.7)
	var slat: StandardMaterial3D = _mat("shutter_slat_%s" % paint.to_html(false), paint.darkened(0.3), 0.3, 0.7)
	var frame: StandardMaterial3D = _mat("stall_frame", Color("3b3a37"), 0.4, 0.6)
	var wood: StandardMaterial3D = _mat("stall_fascia_wood", Color("6d5238"), 0.0, 0.85)
	var tape: StandardMaterial3D = _mat("seal_tape", Color("8c1a1e"), 0.0, 0.8)
	var depth_size: Vector3 = Vector3(0.05, 2.6, 3.0) if face in ["east", "west"] else Vector3(3.0, 2.6, 0.05)
	_shape.block(props, "StallShutter", depth_size, shutter, at + out * 0.03 + Vector3(0, 1.3, 0))
	for index: int in range(19):
		var y: float = 0.12 + float(index) * 0.135
		var slat_size: Vector3 = Vector3(0.02, 0.03, 2.94) if face in ["east", "west"] else Vector3(2.94, 0.03, 0.02)
		_shape.block(props, "ShutterSlat", slat_size, slat, at + out * 0.065 + Vector3(0, y, 0))
	for side: float in [-1.0, 1.0]:
		_shape.block(props, "StallJamb", Vector3(0.1, 2.75, 0.1), frame, at + out * 0.05 + along * side * 1.55 + Vector3(0, 1.375, 0))
	var fascia_size: Vector3 = Vector3(0.08, 0.6, 3.3) if face in ["east", "west"] else Vector3(3.3, 0.6, 0.08)
	_shape.block(props, "StallFascia", fascia_size, wood, at + out * 0.06 + Vector3(0, 3.05, 0))
	_sign(room, name_key, Vector2(3.0, 0.48), at + out * 0.105 + Vector3(0, 3.05, 0), face, Color("e8d9b0"))
	# Two seal tapes crossing the shutter, and the sealing notice where they meet.
	for tilt: float in [-0.62, 0.62]:
		var strip: MeshInstance3D = _shape.block(props, "SealTape", Vector3(0.012, 0.13, 3.3) if face in ["east", "west"] else Vector3(3.3, 0.13, 0.012), tape, at + out * 0.09 + Vector3(0, 1.35, 0))
		strip.rotate(out, tilt)
	_picture(room, "SealNotice", M01IntakeArt.texture("recall_notice"), Vector2(0.5, 0.7), at + out * 0.1 + Vector3(0, 1.35, 0), face, 0.0)
	_sign(room, "WORLD_M01_SEALED", Vector2(0.42, 0.42), at + out * 0.106 + Vector3(0, 1.28, 0), face, Color("1e1e22"))
	# Personal stickers on the shutter's edge: someone's choices, not issue.
	var colours: Array[Color] = [Color("8a3a58"), Color("c45a20"), Color("d8c08a")]
	for index: int in range(3):
		var sticker: StandardMaterial3D = _mat("sticker_%d" % index, colours[index], 0.0, 0.8)
		_shape.block(props, "Sticker", Vector3(0.008, 0.16, 0.2) if face in ["east", "west"] else Vector3(0.2, 0.16, 0.008), sticker, at + out * 0.095 + along * (1.1 - float(index) * 0.27) + Vector3(0, 0.55 + float(index % 2) * 0.22, 0))

## An issued recall notice. The defaced copy carries a chalked reply.
func _notice(room: Node3D, at: Vector3, face: String, scale: float, defaced: bool) -> void:
	var size: Vector2 = Vector2(1.05, 1.5) * scale
	var out: Vector3 = MapDecoration.face_basis(face).z
	_picture(room, "RecallNotice", M01IntakeArt.texture("recall_notice"), size, at, face, 0.0)
	_sign(room, "WORLD_M01_NOTICE_TITLE", Vector2(0.84, 0.17) * scale, at + out * 0.004 + Vector3(0, size.y * 0.41, 0), face, M01IntakeArt.BONE)
	_sign(room, "WORLD_M01_NOTICE_BODY", Vector2(0.88, 0.8) * scale, at + out * 0.004 + Vector3(0, -0.05 * scale, 0), face, Color("1e1e22"))
	if defaced:
		_sign(room, "WORLD_M01_CHALK_NAMES", Vector2(1.5, 0.36), at + out * 0.008 + Vector3(0, -0.85, 0), face, Color("dcd8cc"))

# --- seized-property bay ----------------------------------------------------------

func _build_bay() -> void:
	var room: Node3D = _room("Bay")
	var props: Node3D = _props(room)
	_floor(room, "BayFloor", Vector2(-12, -27), Vector2(12, -13), 0.01, ArenaMaterials.authored("concrete", "earth_intake"))
	# Seized bench: belongings sorted into stock totes, each with an issued tag.
	var top: float = 1.0
	var totes: Array = [[Vector3(-9.3, top, -25.3), Color("56636b")], [Vector3(-8.4, top, -24.0), Color("8a6a3a")], [Vector3(-9.4, top, -23.6), Color("4f6650")]]
	var tag: StandardMaterial3D = _mat("stock_tag", Color("e6dfcf"), 0.0, 0.95)
	for entry: Array in totes:
		var at: Vector3 = entry[0]
		var shell: StandardMaterial3D = _mat("tote_%s" % (entry[1] as Color).to_html(false), entry[1], 0.0, 0.7)
		_shape.block(props, "ToteBase", Vector3(0.62, 0.04, 0.44), shell, at + Vector3(0, 0.02, 0))
		for side: float in [-1.0, 1.0]:
			_shape.block(props, "ToteWall", Vector3(0.62, 0.3, 0.03), shell, at + Vector3(0, 0.15, side * 0.205))
			_shape.block(props, "ToteWall", Vector3(0.03, 0.3, 0.44), shell, at + Vector3(side * 0.295, 0.15, 0))
		_shape.block(props, "StockTag", Vector3(0.16, 0.1, 0.006), tag, at + Vector3(0.12, 0.2, -0.225))
		_sign(room, "WORLD_M01_STOCK", Vector2(0.14, 0.07), at + Vector3(0.12, 0.2, -0.23), "north", Color("1e1e22"))
	var cloth: StandardMaterial3D = _mat("jacket_cloth", Color("6b4a35"), 0.0, 0.95)
	var denim: StandardMaterial3D = _mat("denim_cloth", Color("3e4c63"), 0.0, 0.95)
	_shape.block(props, "FoldedJacket", Vector3(0.5, 0.12, 0.36), cloth, Vector3(-9.3, top + 0.2, -25.3))
	_shape.block(props, "FoldedTrousers", Vector3(0.48, 0.1, 0.34), denim, Vector3(-9.4, top + 0.17, -23.6))
	var kettle: StandardMaterial3D = _mat("kettle_enamel", Color("b9b09a"), 0.3, 0.5)
	_shape.lathe(props, "Kettle", PackedVector2Array([Vector2(0, 0), Vector2(0, 0.11), Vector2(0.08, 0.12), Vector2(0.18, 0.1), Vector2(0.22, 0.04), Vector2(0.22, 0)]), kettle, Vector3(-8.4, top + 0.05, -24.0), 12).rotation.x = -PI * 0.5
	# The confiscated radio: the only place the Host is faintly heard.
	var radio: StandardMaterial3D = _mat("radio_case", Color("6e4a30"), 0.1, 0.7)
	var dial: StandardMaterial3D = _mat("radio_dial", Color("d8c9a4"), 0.0, 0.6)
	_shape.block(props, "ConfiscatedRadio", Vector3(0.46, 0.28, 0.2), radio, Vector3(-7.2, top + 0.14, -23.5))
	_shape.cylinder(props, "RadioDial", 0.08, 0.02, dial, Vector3(-7.1, top + 0.15, -23.61), 14)
	_shape.rod(props, "RadioAerial", Vector3(-7.35, top + 0.28, -23.5), Vector3(-7.5, top + 0.75, -23.45), 0.008, _mat("lamp_cage", Color("2f3030"), 0.4, 0.6), 4)
	_shape.block(props, "RadioTag", Vector3(0.14, 0.09, 0.006), tag, Vector3(-7.05, top + 0.08, -23.61))
	# Latch's basket: personal effects, surplus to requirement, and the ledger.
	var wire: StandardMaterial3D = _mat("basket_wire", Color("7c7f7a"), 0.6, 0.45)
	var basket: Vector3 = Vector3(-6.75, top, -25.35)
	_shape.block(props, "BasketBase", Vector3(0.56, 0.02, 0.4), wire, basket + Vector3(0, 0.01, 0))
	for side: float in [-1.0, 1.0]:
		_shape.block(props, "BasketRim", Vector3(0.56, 0.02, 0.02), wire, basket + Vector3(0, 0.22, side * 0.19))
		_shape.block(props, "BasketRim", Vector3(0.02, 0.02, 0.4), wire, basket + Vector3(side * 0.27, 0.22, 0))
		for index: int in range(6):
			_shape.block(props, "BasketBar", Vector3(0.012, 0.22, 0.012), wire, basket + Vector3(-0.25 + float(index) * 0.1, 0.11, side * 0.19))
	var cover: StandardMaterial3D = _mat("ledger_cover", Color("3f5a4e"), 0.0, 0.85)
	var page: StandardMaterial3D = _mat("ledger_page", Color("ece4cf"), 0.0, 0.95)
	_shape.block(props, "LedgerCover", Vector3(0.42, 0.012, 0.3), cover, basket + Vector3(0, 0.235, 0.0))
	_shape.block(props, "LedgerPages", Vector3(0.4, 0.01, 0.28), page, basket + Vector3(0, 0.247, 0.0))
	_sign(room, "WORLD_M01_LEDGER_LINE", Vector2(0.34, 0.12), basket + Vector3(0, 0.254, 0.02), "up", Color("2b2a33"))
	var cyan_patch: StandardMaterial3D = _mat("spare_cyan_patch", Color("4a8a92"), 0.2, 0.7)
	_shape.block(props, "SpareRepairPlate", Vector3(0.2, 0.015, 0.14), cyan_patch, basket + Vector3(0.13, 0.04, -0.08))
	var mug: StandardMaterial3D = _mat("chipped_mug", Color("c4a46a"), 0.0, 0.6)
	_shape.cylinder(props, "BasketMug", 0.045, 0.1, mug, basket + Vector3(-0.17, 0.07, 0.08), 10).rotation.x = PI * 0.5
	_shape.block(props, "BasketTag", Vector3(0.36, 0.17, 0.006), tag, basket + Vector3(0, 0.3, -0.205))
	_sign(room, "WORLD_M01_LATCH_EFFECTS", Vector2(0.33, 0.15), basket + Vector3(0, 0.3, -0.21), "north", Color("1e1e22"))
	_papers(props, Vector3(-7.9, top, -25.6), 2, 3)
	_stamp(props, Vector3(-7.3, top, -25.55))
	# Confiscation bins over the registered bin block: personal things heaped
	# above the rim, a stencilled class on the side facing the bay.
	var bin: StandardMaterial3D = _mat("bin_steel", Color("4e5844"), 0.3, 0.7)
	var rim: StandardMaterial3D = _mat("bin_rim", Color("2c2d32"), 0.5, 0.5)
	for z: float in [-25.9, -24.1]:
		_shape.block(props, "ConfiscationBin", Vector3(1.54, 0.97, 1.74), bin, Vector3(-11.15, 0.485, z))
		_shape.block(props, "BinRim", Vector3(1.6, 0.06, 1.8), rim, Vector3(-11.15, 0.97, z))
	var heap: Array[Color] = [Color("7d3c2c"), Color("3e4c63"), Color("d0c3a0"), Color("5d6b3c"), Color("8a3a58"), Color("2d2b29"), Color("b07a3a")]
	for index: int in range(16):
		var colour: Color = heap[index % heap.size()]
		var thing: StandardMaterial3D = _mat("heap_%s" % colour.to_html(false), colour, 0.0, 0.9)
		var x: float = -11.75 + float((index * 5) % 7) * 0.2
		var z: float = -26.55 + float((index * 3) % 11) * 0.3
		var piece: MeshInstance3D = _shape.block(props, "SeizedBelonging", Vector3(0.3 + float(index % 3) * 0.08, 0.12 + float(index % 4) * 0.04, 0.24 + float(index % 2) * 0.1), thing, Vector3(x, 1.03 + float(index % 3) * 0.05, z))
		piece.rotation = Vector3(float(index % 3) * 0.12, float(index) * 0.7, 0)
	_sign(room, "WORLD_M01_BIN_CLASS", Vector2(1.3, 0.4), Vector3(-10.36, 0.6, -25.0), "east", M01IntakeArt.BONE)
	# A property rack over the bins: tagged bags, a guitar, a bicycle wheel.
	var rack: StandardMaterial3D = _mat("rack_steel", Color("2c2d32"), 0.5, 0.5)
	for y: float in [1.75, 2.5]:
		_shape.block(props, "PropertyShelf", Vector3(0.34, 0.04, 3.6), rack, Vector3(-11.83, y, -25.0))
		for z: float in [-26.7, -25.0, -23.3]:
			_shape.block(props, "ShelfBracket", Vector3(0.3, 0.12, 0.04), rack, Vector3(-11.84, y - 0.07, z))
	for index: int in range(9):
		var colour: Color = heap[(index * 3 + 1) % heap.size()]
		var thing: StandardMaterial3D = _mat("heap_%s" % colour.to_html(false), colour, 0.0, 0.9)
		var y: float = 1.77 if index < 5 else 2.52
		var z: float = -26.5 + float(index % 5) * 0.72 + (0.3 if index >= 5 else 0.0)
		var size: Vector3 = Vector3(0.26, 0.2 + float(index % 3) * 0.07, 0.34 + float(index % 2) * 0.12)
		_shape.block(props, "ShelvedBelonging", size, thing, Vector3(-11.83, y + size.y * 0.5, z))
		_shape.block(props, "ShelfTag", Vector3(0.006, 0.07, 0.12), tag, Vector3(-11.655, y + 0.08, z + 0.05))
	var wood: StandardMaterial3D = _mat("guitar_wood", Color("8d6c43"), 0.0, 0.7)
	_shape.block(props, "GuitarBody", Vector3(0.1, 0.42, 0.34), wood, Vector3(-11.8, 2.83, -24.3))
	_shape.block(props, "GuitarNeck", Vector3(0.05, 0.62, 0.06), _mat("ledger_cover_black", Color("1e1e22"), 0.0, 0.8), Vector3(-11.8, 3.32, -24.3))
	var tyre: StandardMaterial3D = _mat("bicycle_tyre", Color("1b1b1d"), 0.0, 0.8)
	var wheel: MeshInstance3D = _shape.lathe(props, "BicycleWheel", PackedVector2Array([Vector2(-0.02, 0.27), Vector2(-0.02, 0.32), Vector2(0.02, 0.32), Vector2(0.02, 0.27)]), tyre, Vector3(-11.85, 2.86, -25.7), 16)
	wheel.rotation.y = PI * 0.5
	# Numbered property drawers and a stapled board on the bay's north wall.
	var drawer: StandardMaterial3D = _mat("property_drawer", Color("6b6e6b"), 0.4, 0.55)
	var pull: StandardMaterial3D = _mat("drawer_pull", Color("c9c1ad"), 0.3, 0.5)
	for row: int in range(5):
		for column: int in range(12):
			var at: Vector3 = Vector3(4.6 + float(column) * 0.54, 0.55 + float(row) * 0.48, -13.03)
			_shape.block(props, "PropertyDrawer", Vector3(0.5, 0.44, 0.05), drawer, at)
			_shape.block(props, "DrawerPull", Vector3(0.14, 0.03, 0.03), pull, at + Vector3(0, -0.1, -0.035))
			_shape.block(props, "DrawerLabel", Vector3(0.09, 0.045, 0.01), _mat("drawer_label", Color("b8b09a"), 0.0, 0.95), at + Vector3(0, 0.12, -0.03))
	var cork: StandardMaterial3D = _mat("notice_board", Color("4e5844"), 0.0, 0.9)
	_shape.block(props, "NoticeBoard", Vector3(4.2, 1.6, 0.04), cork, Vector3(-8.2, 1.85, -13.02))
	var paper: StandardMaterial3D = _mat("paper", Color("e3dccb"), 0.0, 0.95)
	for index: int in range(14):
		var at: Vector3 = Vector3(-10.0 + float(index % 7) * 0.58, 2.25 - floorf(float(index) / 7.0) * 0.72, -13.05)
		var sheet: MeshInstance3D = _shape.block(props, "PinnedForm", Vector3(0.36, 0.5, 0.006), paper, at)
		sheet.rotation.z = float((index * 5) % 7 - 3) * 0.03
	# Union posters on the partition and inside the bay front.
	_poster(room, Vector3(-4.98, 1.75, -21.5), "east", "WORLD_M01_POSTER_ARTICLE")
	_poster(room, Vector3(7.5, 2.0, -26.98), "south", "WORLD_M01_POSTER_PROMISE")
	# Warm light over the bench, and a plain pool over the Tack by the door.
	_lamp(room, Vector3(-8.0, 3.4, -24.6), 2.0, 6.0, 6.0)
	_lamp(room, Vector3(0.0, 3.3, -25.6), 1.7, 5.5, 6.0)
	_finish(room)

func _poster(room: Node3D, at: Vector3, face: String, key: String) -> void:
	var out: Vector3 = MapDecoration.face_basis(face).z
	_picture(room, "UnionPoster", M01IntakeArt.texture("poster_article"), Vector2(1.2, 1.7), at, face, 0.0)
	_sign(room, key, Vector2(1.04, 0.62), at + out * 0.004 + Vector3(0, -0.47, 0), face, Color("1e1e22"))

# --- intake hall --------------------------------------------------------------

func _build_hall() -> void:
	var room: Node3D = _room("Hall")
	var props: Node3D = _props(room)
	_floor(room, "HallFloor", Vector2(-12, -12), Vector2(12, 12), 0.01, ArenaMaterials.authored("concrete", "earth_intake"))
	# Painted queue lanes from the door to each counter window.
	var paint: StandardMaterial3D = _mat("lane_paint", Color("cfc7ac"), 0.0, 0.9)
	for lane: Array in [[-4.6, -1.4, -5.3], [1.4, 3.6, -1.3]]:
		for x: float in [lane[0], lane[1]]:
			var start: float = -11.2
			var finish: float = lane[2]
			_shape.block(props, "QueueLaneLine", Vector3(0.08, 0.006, finish - start), paint, Vector3(x, 0.016, (start + finish) * 0.5))
		_shape.block(props, "WaitBoxFront", Vector3(lane[1] - lane[0], 0.006, 0.08), paint, Vector3((lane[0] + lane[1]) * 0.5, 0.016, lane[2] - 1.2))
	_sign(room, "WORLD_M01_WINDOW_1", Vector2(2.4, 0.5), Vector3(-3.0, 0.02, -10.4), "up", Color("cfc7ac"))
	_sign(room, "WORLD_M01_WINDOW_2", Vector2(1.8, 0.5), Vector3(2.5, 0.02, -10.4), "up", Color("cfc7ac"))
	# Counter work: forms, stamps, numbered windows and a warm desk lamp.
	var plate: StandardMaterial3D = _mat("sign_plate_black", Color("1e1e22"), 0.2, 0.7)
	for counter: Array in [[Vector3(-3.0, 1.15, -4.0), -5.0, "WORLD_M01_WINDOW_1"], [Vector3(2.5, 1.15, 0.0), -1.0, "WORLD_M01_WINDOW_2"]]:
		var at: Vector3 = counter[0]
		var front: float = counter[1]
		_papers(props, at + Vector3(-1.2, 0, -0.55), 3, int(at.x))
		_stamp(props, at + Vector3(0.95, 0, -0.6))
		_desk_lamp(room, at + Vector3(1.6 if at.x < 0 else 1.25, 0, 0.55), at + Vector3(0.6, 0, -0.4))
		_shape.block(props, "WindowPlate", Vector3(1.2, 0.34, 0.03), plate, Vector3(at.x, 0.78, front - 0.02))
		_sign(room, counter[2], Vector2(1.1, 0.26), Vector3(at.x, 0.78, front - 0.04), "north", M01IntakeArt.BONE)
	# Warm pendants hang over each window: people work here under the strips.
	_lamp(room, Vector3(-3.0, 3.4, -4.2), 2.4, 7.0, 8.0)
	_lamp(room, Vector3(2.5, 3.4, -0.2), 2.4, 7.0, 8.0)
	var toy: StandardMaterial3D = _mat("toy_robot", Color("c9b27a"), 0.2, 0.6)
	_shape.block(props, "ToyRobot", Vector3(0.1, 0.14, 0.08), toy, Vector3(1.5, 1.22, -0.55))
	_shape.block(props, "ToyRobotHead", Vector3(0.08, 0.07, 0.07), toy, Vector3(1.5, 1.33, -0.55))
	_shape.block(props, "ToyTag", Vector3(0.1, 0.06, 0.005), _mat("stock_tag", Color("e6dfcf"), 0.0, 0.95), Vector3(1.6, 1.19, -0.6))
	# Ticket post and the number board: amber digits, never Union red light.
	var post: StandardMaterial3D = _mat("barrier_post", Color("2b2c2e"), 0.5, 0.5)
	var dispenser: StandardMaterial3D = _mat("ticket_dispenser", Color("4e5844"), 0.3, 0.6)
	_shape.cylinder(props, "TicketPost", 0.045, 1.2, post, Vector3(-3.7, 0.6, -11.75), 8).rotation.x = PI * 0.5
	_shape.block(props, "TicketDispenser", Vector3(0.3, 0.26, 0.2), dispenser, Vector3(-3.7, 1.3, -11.75))
	_sign(room, "WORLD_M01_TAKE_NUMBER", Vector2(0.5, 0.2), Vector3(-3.7, 1.55, -11.64), "south", M01IntakeArt.BONE)
	var board: StandardMaterial3D = _mat("number_board", Color("141416"), 0.2, 0.6)
	_shape.block(props, "NowServingBoard", Vector3(0.12, 1.0, 2.6), board, Vector3(-11.9, 3.5, -4.0))
	_sign(room, "WORLD_M01_NOW_SERVING", Vector2(2.3, 0.85), Vector3(-11.83, 3.5, -4.0), "east", Color("f0b860"))
	_wall_clock(props, Vector3(-11.97, 4.62, -4.0), "east")
	# Dropped number tickets along the lanes: the queue was here this morning.
	var ticket: StandardMaterial3D = _mat("number_ticket", Color("d8cfae"), 0.0, 0.95)
	for index: int in range(14):
		var x: float = -4.4 + float((index * 7) % 11) * 0.75
		var z: float = -11.3 + float((index * 5) % 9) * 0.62
		var slip: MeshInstance3D = _shape.block(props, "NumberTicket", Vector3(0.07, 0.004, 0.12), ticket, Vector3(x, 0.014, z))
		slip.rotation.y = float(index) * 1.3
	# Issued banners on the tall hall walls.
	var rod: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	for entry: Array in [[Vector3(-11.97, 5.1, -9.0), "east"], [Vector3(-11.97, 5.1, 2.0), "east"], [Vector3(11.97, 5.1, -9.0), "west"], [Vector3(11.97, 5.1, 4.6), "west"]]:
		var at: Vector3 = entry[0]
		_picture(room, "HallBanner", M01IntakeArt.texture("banner"), Vector2(1.5, 5.0), at, entry[1], 0.0)
		var out: Vector3 = MapDecoration.face_basis(entry[1]).z
		_shape.rod(props, "BannerRod", at + out * 0.06 + Vector3(0, 2.55, -0.85), at + out * 0.06 + Vector3(0, 2.55, 0.85), 0.035, rod, 6)
	_build_address_screen(room, props)
	_finish(room)

## The records screen loops Voss's address with the official caption track.
func _build_address_screen(room: Node3D, props: Node3D) -> void:
	var frame: StandardMaterial3D = _mat("monitor_frame", Color("2c2d32"), 0.4, 0.55)
	var bezel: StandardMaterial3D = _mat("monitor_bezel", Color("141416"), 0.2, 0.6)
	_shape.block(props, "ScreenBank", Vector3(7.7, 2.25, 0.1), frame, Vector3(0, 1.2, 5.95))
	var screens: Array = [[Vector3(0, 1.38, 5.88), Vector2(2.4, 1.8)], [Vector3(-2.65, 1.5, 5.88), Vector2(1.9, 1.42)], [Vector3(2.65, 1.5, 5.88), Vector2(1.9, 1.42)]]
	for entry: Array in screens:
		var at: Vector3 = entry[0]
		var size: Vector2 = entry[1]
		_shape.block(props, "MonitorBezel", Vector3(size.x + 0.16, size.y + 0.16, 0.06), bezel, at + Vector3(0, 0, 0.025))
		var screen: MeshInstance3D = _picture(room, "AddressScreen", _address[0], size, at + Vector3(0, 0, -0.012), "north", 1.25)
		var material: StandardMaterial3D = screen.material_override as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_screen_materials.append(material)
	# The caption runs over the main picture's lower third, so a shot screen
	# leaves it scrolling over the noise (docs/campaign/m01-recall-notice.md).
	# The slate under the bank labels it unmistakably as the official track
	# (docs/lore/the-chancellery.md, in-world propaganda captions).
	_shape.block(props, "CaptionBand", Vector3(2.32, 0.46, 0.006), bezel, Vector3(0, 0.76, 5.864))
	_caption = _sign(room, CAPTIONS[0], Vector2(2.2, 0.4), Vector3(0, 0.76, 5.858), "north", M01IntakeArt.BONE)
	_shape.block(props, "CaptionSlate", Vector3(3.2, 0.34, 0.04), bezel, Vector3(0, 0.25, 5.88))
	_sign(room, "WORLD_M01_OFFICIAL_CAPTION", Vector2(3.0, 0.26), Vector3(0, 0.25, 5.855), "north", Color("c9c1ad"))
	var glow: OmniLight3D = OmniLight3D.new()
	glow.name = "ScreenSpill"
	glow.position = Vector3(0, 1.4, 5.2)
	glow.light_color = Color(0.72, 0.78, 0.86)
	glow.light_energy = 0.9
	glow.omni_range = 5.5
	glow.omni_attenuation = 1.8
	glow.shadow_enabled = false
	room.add_child(glow)

# --- maintenance flank ---------------------------------------------------------

func _build_service() -> void:
	var room: Node3D = _room("Service")
	var props: Node3D = _props(room)
	_floor(room, "ServiceFloor", Vector2(-22, -22), Vector2(-13, 2), 0.01, ArenaMaterials.authored("service_steel", "earth_intake"))
	var pipe: StandardMaterial3D = _mat("service_pipe", Color("5b6458"), 0.4, 0.6)
	var rust: StandardMaterial3D = _mat("service_pipe_rust", Color("6f3f28"), 0.3, 0.75)
	var bracket: StandardMaterial3D = _mat("lamp_bracket", Color("2f3030"), 0.4, 0.6)
	for run: Array in [[4.9, 0.1, pipe], [5.3, 0.065, rust]]:
		_shape.rod(props, "ServicePipe", Vector3(-21.8, run[0], -21.6), Vector3(-21.8, run[0], 1.6), run[1], run[2], 10)
	for z: float in [-21.0, -15.0, -9.0, -3.0, 1.0]:
		_shape.block(props, "PipeBracket", Vector3(0.36, 0.06, 0.06), bracket, Vector3(-21.82, 5.1, z))
	for x: float in [-21.6, -20.6]:
		_shape.rod(props, "MachineRiser", Vector3(x, 2.8, -12.0), Vector3(x, 6.0, -12.0), 0.07, pipe, 8)
	_shape.rod(props, "MachineRiser", Vector3(-21.1, 2.8, -16.0), Vector3(-21.1, 6.0, -16.0), 0.1, rust, 8)
	var panel: StandardMaterial3D = _mat("breaker_panel", Color("4e5844"), 0.3, 0.6)
	var lever: StandardMaterial3D = _mat("breaker_lever", Color("d8c9a4"), 0.0, 0.6)
	_shape.block(props, "BreakerPanel", Vector3(0.12, 0.9, 0.7), panel, Vector3(-13.06, 1.55, -21.2))
	for index: int in range(4):
		_shape.block(props, "BreakerLever", Vector3(0.06, 0.12, 0.05), lever, Vector3(-13.14, 1.75 - float(index % 2) * 0.3, -21.4 + float(index / 2.0) * 0.4))
	_lamp(room, Vector3(-21.6, 3.1, -20.4), 1.9, 6.5)
	_lamp(room, Vector3(-21.6, 3.3, -3.6), 1.9, 6.5)
	_lamp(room, Vector3(-13.25, 3.0, -14.2), 1.5, 5.0)
	_lamp(room, Vector3(-21.6, 5.4, 8.5), 1.8, 6.5)
	_lamp(room, Vector3(-15.0, 5.6, 10.0), 1.8, 6.5, 8.0)
	_finish(room)

# --- records wing ------------------------------------------------------------

## The records wing in three merged rooms (reception, the stacks to dispatch,
## transfer control), so no single merged mesh spans more lamps than the
## Compatibility renderer lights per object.
func _build_records() -> void:
	_build_reception()
	var room: Node3D = _room("Records")
	var props: Node3D = _props(room)
	# File stacks: rows of archive boxes on the faces without locker fronts.
	var kraft: StandardMaterial3D = _mat("archive_box", Color("b49a6e"), 0.0, 0.9)
	var grey: StandardMaterial3D = _mat("archive_box_grey", Color("9a978c"), 0.0, 0.9)
	var label: StandardMaterial3D = _mat("archive_label", Color("e6dfcf"), 0.0, 0.95)
	var shelf: StandardMaterial3D = _mat("shelf_edge", Color("2c2d32"), 0.5, 0.5)
	for face: Array in [[Vector3(-30.0, 3.0, 14.0), 7.0, "west"], [Vector3(-34.0, 3.0, 19.0), 7.0, "east"], [Vector3(-40.0, 3.0, 14.0), 7.0, "west"]]:
		var corner: Vector3 = face[0]
		var length: float = face[1]
		var side: String = face[2]
		var out: Vector3 = MapDecoration.face_basis(side).z
		for row: int in range(4):
			var y: float = corner.y + 0.32 + float(row) * 0.76
			_shape.block(props, "ShelfEdge", Vector3(0.05, 0.035, length - 0.1), shelf, Vector3(corner.x + out.x * 0.025, y - 0.17, corner.z + length * 0.5))
			var count: int = int(length / 0.42)
			for index: int in range(count):
				if (index * 7 + row * 3) % 11 == 0:
					continue
				var z: float = corner.z + 0.25 + float(index) * 0.42
				var box_height: float = 0.3 + float((index + row) % 3) * 0.03
				_shape.block(props, "ArchiveBox", Vector3(0.05, box_height, 0.38), kraft if (index + row) % 4 != 0 else grey, Vector3(corner.x + out.x * 0.025, y - 0.15 + box_height * 0.5, z))
				_shape.block(props, "ArchiveLabel", Vector3(0.012, 0.07, 0.16), label, Vector3(corner.x + out.x * 0.055, y - 0.15 + box_height * 0.55, z))
	_lamp(room, Vector3(-41.5, 5.9, 15.6), 1.6, 5.5, 8.0)
	# Sorting: personal effects bagged by class on the worktable.
	var bag: StandardMaterial3D = _mat("evidence_bag", Color("c8c3b0"), 0.0, 0.6)
	var tray: StandardMaterial3D = _mat("sorting_tray", Color("4e5844"), 0.3, 0.6)
	for index: int in range(3):
		var at: Vector3 = Vector3(-30.0 + float(index) * 2.0, 4.15, 36.0)
		_shape.block(props, "SortingTray", Vector3(1.4, 0.05, 0.8), tray, at + Vector3(0, 0.025, 0))
		for bag_index: int in range(4):
			var piece: MeshInstance3D = _shape.block(props, "EffectsBag", Vector3(0.26, 0.07, 0.34), bag, at + Vector3(-0.45 + float(bag_index) * 0.3, 0.09, float(bag_index % 2) * 0.15 - 0.07))
			piece.rotation.y = float(bag_index - index) * 0.15
	_sign(room, "WORLD_M01_SORT_CLASSES", Vector2(3.6, 0.9), Vector3(-37.0, 4.6, 32.955), "north", M01IntakeArt.BONE)
	_shape.block(props, "SortBoard", Vector3(3.8, 1.1, 0.04), _mat("sort_board_green", Color("4e5844"), 0.1, 0.8), Vector3(-37.0, 4.6, 32.99))
	_lamp(room, Vector3(-28.0, 6.4, 36.0), 2.0, 6.5, 8.0)
	# Work light over the sort board and the bypass end of the floor.
	_lamp(room, Vector3(-37.0, 6.6, 31.6), 1.7, 5.5, 8.0)
	_lamp(room, Vector3(-18.0, 6.4, 37.5), 1.7, 6.0, 8.0)
	_picture(room, "SortingSeal", M01IntakeArt.texture("emblem"), Vector2(1.6, 1.6), Vector3(-20.0, 5.6, 42.98), "north", 0.0)
	for x: float in [-22.4, -17.6]:
		_picture(room, "SortingBanner", M01IntakeArt.texture("banner"), Vector2(1.2, 4.0), Vector3(x, 5.6, 42.97), "north", 0.0)
	# Dispatch: the day's transfers on a board, a logbook under a lamp.
	var board: StandardMaterial3D = _mat("number_board", Color("141416"), 0.2, 0.6)
	_shape.block(props, "DispatchBoard", Vector3(3.4, 1.7, 0.05), board, Vector3(-8.0, 4.7, 31.03))
	_sign(room, "WORLD_M01_DISPATCH_BOARD", Vector2(3.1, 1.45), Vector3(-8.0, 4.7, 31.06), "south", Color("f0b860"))
	_papers(props, Vector3(-7.4, 4.15, 36.0), 2, 9)
	var log_cover: StandardMaterial3D = _mat("ledger_cover_black", Color("1e1e22"), 0.0, 0.8)
	_shape.block(props, "DispatchLog", Vector3(0.5, 0.03, 0.36), log_cover, Vector3(-7.0, 4.165, 37.4))
	_desk_lamp(room, Vector3(-6.4, 4.15, 38.6), Vector3(-7.0, 4.15, 37.4))
	_finish(room)
	_build_transfer()

func _build_reception() -> void:
	var room: Node3D = _room("Reception")
	var props: Node3D = _props(room)
	# Counter work under a desk lamp.
	_papers(props, Vector3(-17.6, 4.2, 19.2), 3, 5)
	_stamp(props, Vector3(-15.6, 4.2, 19.3))
	_desk_lamp(room, Vector3(-14.5, 4.2, 19.6), Vector3(-15.6, 4.2, 19.3))
	_poster(room, Vector3(-19.5, 4.75, 15.48), "north", "WORLD_M01_POSTER_ARTICLE")
	_picture(room, "ReceptionSeal", M01IntakeArt.texture("emblem"), Vector2(1.0, 1.0), Vector3(-13.02, 5.6, 25.0), "west", 0.0)
	# The back screen: pigeonholes of waiting forms behind the counter.
	var cubby: StandardMaterial3D = _mat("pigeonhole", Color("3b3d38"), 0.2, 0.7)
	var form: StandardMaterial3D = _mat("form_green", Color("b8c4a6"), 0.0, 0.95)
	var paper: StandardMaterial3D = _mat("paper", Color("e3dccb"), 0.0, 0.95)
	_shape.block(props, "PigeonholeBack", Vector3(3.4, 1.1, 0.05), cubby, Vector3(-16.0, 5.3, 19.97))
	for row: int in range(3):
		for column: int in range(8):
			var at: Vector3 = Vector3(-17.5 + float(column) * 0.43, 4.86 + float(row) * 0.36, 19.9)
			_shape.block(props, "PigeonholeShelf", Vector3(0.4, 0.025, 0.14), cubby, at + Vector3(0, -0.14, 0))
			if (row * 8 + column) % 5 != 2:
				_shape.block(props, "WaitingForms", Vector3(0.3, 0.05 + float((row + column) % 3) * 0.025, 0.12), form if (row + column) % 4 == 0 else paper, at + Vector3(0, -0.1, 0))
	_finish(room)

func _build_transfer() -> void:
	var room: Node3D = _room("Transfer")
	var props: Node3D = _props(room)
	# Latch's file photo and record on the console monitor.
	var housing: StandardMaterial3D = _mat("terminal_housing", Color("bdb6a0"), 0.1, 0.7)
	var screen_back: StandardMaterial3D = _mat("terminal_screen_back", Color("141210"), 0.0, 0.6)
	_shape.block(props, "FileMonitor", Vector3(1.55, 0.86, 0.5), housing, Vector3(-7.5, 4.65, 23.55))
	_shape.block(props, "FileMonitorScreen", Vector3(1.38, 0.7, 0.02), screen_back, Vector3(-7.5, 4.66, 23.29))
	_picture(room, "LatchFilePhoto", M01IntakeArt.texture("latch_file"), Vector2(0.5, 0.6), Vector3(-7.92, 4.66, 23.275), "north", 1.1)
	_sign(room, "WORLD_M01_LATCH_FILE", Vector2(0.74, 0.56), Vector3(-7.2, 4.66, 23.275), "north", M01IntakeArt.PHOSPHOR)
	var console_glow: OmniLight3D = OmniLight3D.new()
	console_glow.name = "FileGlow"
	console_glow.position = Vector3(-7.5, 4.7, 22.6)
	console_glow.light_color = M01IntakeArt.PHOSPHOR
	console_glow.light_energy = 0.9
	console_glow.omni_range = 3.5
	console_glow.omni_attenuation = 1.8
	room.add_child(console_glow)
	var binder: Array[Color] = [Color("2c2d32"), Color("4e5844"), Color("8c1a1e"), Color("2c2d32")]
	for index: int in range(10):
		var colour: Color = binder[index % binder.size()]
		_shape.block(props, "TransferBinder", Vector3(0.04, 0.34, 0.07), _mat("binder_%s" % colour.to_html(false), colour, 0.0, 0.8), Vector3(-7.98, 4.4, 15.4 + float(index) * 0.11))
	# The lift light: two amber beacons either side of the custody lift sign,
	# the exit landmark from transfer control.
	_lamp(room, Vector3(1.8, 7.25, 19.6), 1.4, 6.0, -1.0, Color(1.0, 0.62, 0.3))
	_lamp(room, Vector3(1.8, 7.25, 24.4), 1.4, 6.0, -1.0, Color(1.0, 0.62, 0.3))
	_build_custody_feed(room, props)
	# Transfer control's own wall: the Union seal and the office clock, so the
	# room where people are scheduled reads as an office, not a void.
	_picture(room, "TransferSeal", M01IntakeArt.texture("emblem"), Vector2(1.3, 1.3), Vector3(-11.98, 5.7, 19.0), "east", 0.0)
	_wall_clock(props, Vector3(-11.97, 5.7, 21.6), "east")
	_finish(room)

## The custody lift camera above the record console. It shows the car waiting
## with Latch behind its bars until the record is read, then the car sinking
## toward the correction ward (docs/campaign/m01-recall-notice.md, the Turn).
func _build_custody_feed(room: Node3D, props: Node3D) -> void:
	var housing: StandardMaterial3D = _mat("feed_housing", Color("2c2d32"), 0.4, 0.55)
	var bracket: StandardMaterial3D = _mat("lamp_bracket", Color("2f3030"), 0.4, 0.6)
	_shape.block(props, "FeedHousing", Vector3(1.86, 1.42, 0.22), housing, FEED_POINT + Vector3(0, 0, 0.14))
	_feed_frames = M01IntakeArt.custody_frames()
	var screen: MeshInstance3D = _picture(room, "CustodyFeed", _feed_frames[0], Vector2(1.6, 1.2), FEED_POINT, "north", 0.95)
	_feed_material = screen.material_override as StandardMaterial3D
	_feed_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var plate: StandardMaterial3D = _mat("sign_plate_black", Color("1e1e22"), 0.2, 0.7)
	_shape.block(props, "FeedPlate", Vector3(1.86, 0.3, 0.04), plate, FEED_POINT + Vector3(0, 0.88, 0.2))
	_sign(room, "WORLD_M01_CUSTODY_FEED", Vector2(1.74, 0.26), FEED_POINT + Vector3(0, 0.88, 0.17), "north", Color("f0b860"))
	var glow: OmniLight3D = OmniLight3D.new()
	glow.name = "FeedGlow"
	glow.position = FEED_POINT + Vector3(0, -0.2, -0.8)
	glow.light_color = M01IntakeArt.PHOSPHOR
	glow.light_energy = 0.5
	glow.omni_range = 3.0
	glow.omni_attenuation = 1.8
	glow.shadow_enabled = false
	room.add_child(glow)
	_motor_player = AudioStreamPlayer3D.new()
	_motor_player.name = "CustodyHoist"
	_motor_player.stream = motor_stream()
	_motor_player.position = FEED_POINT
	_motor_player.bus = &"Effects"
	_motor_player.volume_db = -10.0
	_motor_player.unit_size = 3.0
	_motor_player.max_distance = 18.0
	room.add_child(_motor_player)

## A plain issued wall clock: bone face, dark rim and hands at ten to seven.
func _wall_clock(props: Node3D, at: Vector3, face: String) -> void:
	var basis: Basis = MapDecoration.face_basis(face)
	var out: Vector3 = basis.z
	var rim: StandardMaterial3D = _mat("clock_rim", Color("1e1e22"), 0.4, 0.5)
	var dial: StandardMaterial3D = _mat("clock_face", Color("e3dccb"), 0.0, 0.8)
	var body: MeshInstance3D = _shape.cylinder(props, "ClockRim", 0.3, 0.06, rim, at + out * 0.03, 16)
	body.basis = Basis(Quaternion(Vector3.BACK, out))
	var plate: MeshInstance3D = _shape.cylinder(props, "ClockFace", 0.26, 0.01, dial, at + out * 0.065, 16)
	plate.basis = Basis(Quaternion(Vector3.BACK, out))
	var hand: Vector3 = at + out * 0.075
	var up: Vector3 = Vector3.UP
	var side: Vector3 = basis.x
	_shape.rod(props, "ClockHand", hand, hand + (up * 0.5 - side * 0.866) * 0.13, 0.012, rim, 4)
	_shape.rod(props, "ClockHand", hand, hand + (up * 0.67 + side * 0.74) * 0.21, 0.008, rim, 4)
