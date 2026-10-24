class_name M19Works
extends Node3D

## Planned Works presenter: Low Water at night, changed. Static white work
## marks across the streets the party grew up on, the concourse full of
## people leaving, the meal table still set, Edda's clinic dark, the river and
## the lit pier beyond the north railing. Live Paver strips and the coalition
## jetpacks come from snapshot facts; Latch's departure comes from mission
## facts. Nothing here is collision, cover or an interaction target.
signal notice_requested(text: String)

const CAMERA = preload("res://scripts/spectator_cam.gd")
const TownDressing = preload("res://scripts/m19_town_dressing.gd")
const LatchSeat = preload("res://scripts/m19_latch_seat.gd")
const Crowd = preload("res://scripts/m19_crowd.gd")

const MARK_COLOR: Color = Color(0.9, 0.91, 0.87, 0.5)
const MARK_BORDER: float = 0.16
const RIVER_DEPTH: float = 120.0
const LATCH_RUN_SPEED: float = 6.2
const LATCH_FALL_SPEED: float = 9.0
const LINE_SECONDS: float = 3.6
## Latch's three lines on the tank, then the drop.
const TANK_LINES: Array[String] = ["M19_LATCH_TANK_REACH", "M19_TERN_TANK_AGENTS", "M19_LATCH_TANK_GOING"]
## The tank rim Latch sits on, legs over the river side.
const TANK_SEAT: Vector3 = Vector3(-46.2, 9.6, 24.0)
const ARRIVAL_LINES: Array[String] = ["M19_CLERK_FORM", "M19_LATCH_FILING"]
## Latch's warm screen: amber optics over a faint phosphor face.
const LATCH_PHOSPHOR: Color = Color("ffb860")
const LATCH_SCREEN: Color = Color("6a3a16")
## The hand lamp Latch set on the tank rim, beside the seat. It warms the
## rust and ember repairs under the moon, and it is still burning after Latch
## has gone.
const TANK_LAMP: Vector3 = Vector3(-46.0, 9.6, 23.1)

var players: Dictionary = {}
var local_id: String = ""
var state_applied: int = 0
var strips: PaverStrips
var _geometry: Dictionary = {}
var _root: Node3D
var _latch: LatchView
var _latch_mode: String = "hidden"
var _latch_route: Array[Vector3] = []
var _latch_leg: int = 0
var _latch_drop: float = 0.0
var _latch_wait: float = 0.0
var _evacuees: Array[Dictionary] = []
var _packs: Dictionary[String, JetpackRig] = {}
var _fired: Dictionary[String, bool] = {}
var _lines: Array[String] = []
var _line_left: float = 0.0
var _line_key: String = ""
## Latch sits on the tank rim until the last line.
var _latch_seated: bool = false
var _after_lines: Callable = Callable()
var _caption_layer: CanvasLayer
var _caption: Label
var _gauge: JetGauge
var _river_material: ShaderMaterial
var _pier_lamps: Array[OmniLight3D] = []
var _clock: float = 0.0
var _flicker: Array[Dictionary] = []
var _phase: String = ""
var _attempt: int = -1
var _completed: int = 0

func _ready() -> void:
	_caption_layer = CanvasLayer.new()
	_caption_layer.name = "WorksCaptions"
	_caption_layer.layer = 4
	add_child(_caption_layer)
	_caption = Label.new()
	_caption.name = "SpeakerLine"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_left = 160.0
	_caption.offset_right = -160.0
	_caption.offset_top = -252.0
	_caption.offset_bottom = -188.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_override("font", MenuTheme.FONT)
	_caption.add_theme_font_size_override("font_size", MenuTheme.BODY)
	_caption.add_theme_color_override("font_color", MenuTheme.BONE)
	_caption.add_theme_color_override("font_outline_color", MenuTheme.INK)
	_caption.add_theme_constant_override("outline_size", 5)
	_caption.visible = false
	_caption_layer.add_child(_caption)
	_gauge = JetGauge.new()
	_gauge.name = "JetGauge"
	_caption_layer.add_child(_gauge)

func clear_map() -> void:
	_geometry.clear()
	state_applied = 0
	_latch = null
	_latch_mode = "hidden"
	_latch_route.clear()
	_evacuees.clear()
	_packs.clear()
	_fired.clear()
	_lines.clear()
	_line_left = 0.0
	_after_lines = Callable()
	_pier_lamps.clear()
	_flicker.clear()
	_river_material = null
	_phase = ""
	if _caption != null:
		_caption.visible = false
	if _gauge != null:
		_gauge.present({}, false)
	for pack: Variant in get_tree().get_nodes_in_group(&"fragr_m19_pack") if is_inside_tree() else []:
		(pack as Node).queue_free()
	if _root != null:
		_root.queue_free()
		_root = null
	strips = null

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m19") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	_root = Node3D.new()
	_root.name = "PlannedWorks"
	add_child(_root)
	strips = PaverStrips.new()
	strips.name = "PaverStrips"
	strips.strip_marked.connect(_on_strip_marked)
	strips.strip_put_out.connect(_on_strip_put_out)
	_root.add_child(strips)
	var m19: Dictionary = _geometry["m19"]
	_build_marks(m19["work_marks"])
	var town: TownDressing = TownDressing.new()
	town.build(_root, info)
	_flicker.append_array(town.flicker)
	_build_night_town(float(_geometry["half_extent"]))
	_build_river(float(_geometry["half_extent"]))
	_build_concourse()
	_build_meal_table()
	_build_market_lights()
	for point: Variant in m19["latch_route"]:
		_latch_route.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
	_latch = LatchView.new()
	_latch.name = "Latch"
	_latch.visible = false
	# Under the cool night key a free agent must never read as a pale
	# machine: Latch's screen burns warm phosphor all night.
	_latch.set_face_phosphor(LATCH_PHOSPHOR, LATCH_SCREEN, 0.7)
	_root.add_child(_latch)
	_build_tank_lamp()
	ArenaSky.mark_world(_root)
	# Fighters and Latch stay on the actor layer so the view fill reads them.
	_latch.set_render_layers(ArenaSky.ACTOR_LAYERS)

func active() -> bool:
	return _root != null

## Mission facts: lines, Latch, gate and challenge notices.
func apply_state(state: Dictionary) -> void:
	if not active() or state.get("id") != MissionState.M19_ID or not state.get("m19") is Dictionary:
		return
	state_applied += 1
	var progress: Dictionary = state["m19"]
	var phase: String = str(state.get("phase", ""))
	var completed: Array = progress.get("completed", [])
	var current: String = str(progress["current"]["id"]) if progress.get("current") is Dictionary else ""
	var first_state: bool = state_applied == 1
	# A retry (a new attempt, or progress rewound) starts the level's story over.
	var attempt: int = int(state.get("attempt", 0))
	if not first_state and (attempt != _attempt or completed.size() < _completed):
		_restart_story()
	_attempt = attempt
	_completed = completed.size()
	if phase == "in_progress" and _phase != "in_progress" and completed.is_empty():
		_say(ARRIVAL_LINES)
	_phase = phase
	# Latch walks the concourse with the party, then goes ahead to the tanks.
	if completed.size() < 2 and not progress["latch_departed"]:
		_place_latch_concourse()
	elif current == "water_tanks" and not progress["latch_departed"]:
		_place_latch_tank()
	elif progress["latch_departed"] and _latch_mode in ["concourse", "tank"] and not first_state:
		if _latch_mode == "concourse":
			_place_latch_tank()
		_once("latch_lines", func() -> void:
			_say(TANK_LINES, _latch_leave))
	elif progress["latch_departed"] and _latch_mode != "running":
		_hide_latch()
	elif completed.size() >= 2 and _latch_mode == "concourse":
		_hide_latch()
	if progress["jetpack_taken"]:
		_once("jetpack", func() -> void:
			notice_requested.emit(InputGlyphs.plain(tr("M19_JETPACK_ON"))))
	var challenges: Dictionary = progress["challenges"]
	if challenges["crossing_cleared"]:
		_once("crossing", func() -> void: notice_requested.emit(tr("M19_CROSSING_CLEARED")))
	if challenges["paver_interrupted"]:
		_once("interrupted", func() -> void: notice_requested.emit(tr("M19_PAVER_INTERRUPTED")))
	if progress["gate_open"]:
		_once("gate", func() -> void: notice_requested.emit(tr("M19_WATERWORKS_OPEN")))

## Snapshot facts: strips and jetpacks.
func apply_snapshot(snapshot: Dictionary) -> void:
	if not active():
		return
	strips.apply_snapshot(snapshot)
	if not WorksFacts.validation_error(snapshot).is_empty():
		return
	var seen: Dictionary[String, bool] = {}
	var own: Dictionary = {}
	for fact: Dictionary in snapshot.get("jetpacks", []):
		var id: String = str(fact["player_id"])
		seen[id] = true
		if id == local_id:
			own = fact
		var pawn: Node3D = players.get(id) as Node3D
		if pawn == null or not is_instance_valid(pawn):
			continue
		var pack: JetpackRig = _packs.get(id)
		if pack == null or not is_instance_valid(pack):
			pack = JetpackRig.new()
			pack.position.y = -CAMERA.FP_SERVER_REFERENCE_Y
			pack.add_to_group(&"fragr_m19_pack")
			pawn.add_child(pack)
			_packs[id] = pack
		pack.apply(fact, float(JetMovement.FUEL_MAX))
		var hp: int = 1
		for actor: Variant in snapshot.get("players", []):
			if actor is Dictionary and str(actor.get("id", "")) == id:
				hp = int(actor.get("hp", 1))
		pack.visible = hp > 0 and not bool(pawn.get("is_local_fp"))
	for id: String in _packs.keys():
		if not seen.has(id):
			if is_instance_valid(_packs[id]):
				_packs[id].queue_free()
			_packs.erase(id)
	_gauge.present(own, not local_id.is_empty())

func _process(delta: float) -> void:
	if not active():
		return
	var step: float = clampf(delta, 0.0, 0.1)
	_clock += step
	if _river_material != null:
		_river_material.set_shader_parameter("ripple_time", fmod(_clock, 32.0))
	for index: int in range(_pier_lamps.size()):
		_pier_lamps[index].light_energy = 2.2 + 0.25 * sin(_clock * 1.7 + float(index) * 2.1)
	for lamp: Dictionary in _flicker:
		# Interrupted light: a bulb that catches, drops and catches again.
		var on: bool = fmod(_clock * float(lamp["rate"]) + float(lamp["phase"]), 1.0) > float(lamp["duty"])
		(lamp["mesh"] as MeshInstance3D).material_override = lamp["lit"] if on else lamp["dark"]
		if lamp.get("light") is OmniLight3D:
			(lamp["light"] as OmniLight3D).light_energy = float(lamp["energy"]) if on else 0.0
	_advance_evacuees(step)
	_advance_lines(step)
	_advance_latch(step)

func _restart_story() -> void:
	_lines.clear()
	_after_lines = Callable()
	_line_left = 0.0
	_caption.visible = false
	_fired.clear()
	_hide_latch()
	_phase = ""
	if strips != null:
		strips.clear()

func _once(key: String, action: Callable) -> void:
	if _fired.has(key):
		return
	_fired[key] = true
	action.call()

# --- Speaker lines --------------------------------------------------------

func _say(keys: Array[String], then: Callable = Callable()) -> void:
	_lines = keys.duplicate()
	_after_lines = then
	_line_left = 0.0
	_advance_lines(0.0)

func _advance_lines(delta: float) -> void:
	if _caption == null:
		return
	_line_left -= delta
	if _line_left > 0.0:
		return
	if _lines.is_empty():
		_line_key = ""
		if _caption.visible:
			_caption.visible = false
			if _after_lines.is_valid():
				var then: Callable = _after_lines
				_after_lines = Callable()
				then.call()
		return
	_line_key = _lines.pop_front()
	_caption.text = tr(_line_key)
	_caption.visible = true
	_line_left = LINE_SECONDS

# --- Latch ----------------------------------------------------------------

func _place_latch_concourse() -> void:
	if _latch == null or _latch_mode == "concourse":
		return
	_latch_mode = "concourse"
	_latch.visible = true
	_latch_seated = false
	_latch.position = Vector3(-52.6, 0.0, -26.4)
	_latch.rotation.y = PI * 0.75
	_latch.set_weapon_visible(false)

func _place_latch_tank() -> void:
	if _latch == null or _latch_mode == "tank":
		return
	_latch_mode = "tank"
	_latch.visible = true
	# Sitting on the rim of the near tank, legs over the side, looking out
	# at the river and the pier lights.
	_latch_seated = true
	_latch.position = TANK_SEAT
	_latch.rotation.y = PI * 0.5
	LatchSeat.apply(_latch)
	_latch.set_weapon_visible(false)

## On the tank Latch turns to whoever came up beside them.
func _face_party(delta: float) -> void:
	var nearest: Node3D = null
	for pawn: Variant in players.values():
		if pawn is Node3D and is_instance_valid(pawn) and (nearest == null \
				or (pawn as Node3D).global_position.distance_to(_latch.position) < nearest.global_position.distance_to(_latch.position)):
			nearest = pawn
	if nearest == null:
		return
	var toward: Vector3 = nearest.global_position - _latch.position
	var wanted: float = atan2(toward.x, toward.z)
	_latch.rotation.y = lerp_angle(_latch.rotation.y, wanted, clampf(delta * 3.0, 0.0, 1.0))

func _hide_latch() -> void:
	if _latch != null:
		_latch.visible = false
		_latch_seated = false
	_latch_mode = "hidden"

func _latch_leave() -> void:
	if _latch == null or _latch_route.is_empty():
		return
	_latch_mode = "running"
	_latch_seated = false
	_latch_leg = 0
	_latch_drop = 0.0
	_latch_wait = 0.4

func _advance_latch(delta: float) -> void:
	if _latch == null or not _latch.visible:
		return
	if _latch_mode != "running":
		if _latch_mode == "tank" and _line_key == TANK_LINES[TANK_LINES.size() - 1]:
			# "I'm going." Latch stands up on the tank and turns to the party.
			if _latch_seated:
				_latch_seated = false
				_latch.position = TANK_SEAT - Vector3(0.45, 0.0, 0.0)
			_face_party(delta)
		_latch.advance(delta, 0.0, "idle")
		if _latch_seated:
			LatchSeat.apply(_latch)
		return
	if _latch_wait > 0.0:
		_latch_wait -= delta
		_latch.advance(delta, 0.0, "idle")
		return
	if _latch_leg >= _latch_route.size():
		_hide_latch()
		return
	var target: Vector3 = _latch_route[_latch_leg]
	var flat: Vector3 = Vector3(target.x - _latch.position.x, 0.0, target.z - _latch.position.z)
	var travel: float = minf(flat.length(), LATCH_RUN_SPEED * delta)
	if flat.length() > 0.01:
		_latch.rotation.y = atan2(flat.x, flat.z)
		_latch.position += flat.normalized() * travel
	# A drop falls at once rather than sliding down an invisible ramp.
	var remaining: float = flat.length() - travel
	_latch.position.y = move_toward(_latch.position.y, target.y, delta * LATCH_FALL_SPEED)
	_latch.advance(delta, travel, "moving")
	if remaining <= 0.05 and absf(_latch.position.y - target.y) <= 0.05:
		_latch_leg += 1

# --- Strip notices ----------------------------------------------------------

func _on_strip_marked(_owner_id: String, _origin: Vector3) -> void:
	_once("first_strip", func() -> void: notice_requested.emit(tr("M19_STRIP_FIRST")))

func _on_strip_put_out(_owner_id: String, _origin: Vector3) -> void:
	notice_requested.emit(tr("M19_STRIP_PUT_OUT"))

# --- Static dressing --------------------------------------------------------

static func _unshaded(colour: Color, add: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	if colour.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material

## A lamp that blooms: emission drives the environment glow at night.
static func _glow(colour: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = energy
	return material

static func _lit(colour: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material

func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node

static func _hatch_texture() -> ImageTexture:
	var image: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y: int in range(32):
		for x: int in range(32):
			var on: bool = (x + y) % 16 < 5
			image.set_pixel(x, y, Color(1, 1, 1, 0.36 if on else 0.05))
	return ImageTexture.create_from_image(image)

## The authored white work marks: hatched beds with hard borders, laid on the
## street, the market, the roofs and the trench. The machines planned these.
func _build_marks(marks: Array) -> void:
	var group: Node3D = Node3D.new()
	group.name = "WorkMarks"
	_root.add_child(group)
	# Painted marks take the night's light like any paint, so a live strip's
	# projected light is always the brightest thing on the ground.
	var bed_material: StandardMaterial3D = _lit(Color(MARK_COLOR, 1.0), 1.0)
	bed_material.albedo_texture = _hatch_texture()
	bed_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bed_material.uv1_triplanar = true
	bed_material.uv1_world_triplanar = true
	bed_material.uv1_scale = Vector3(0.42, 0.42, 0.42)
	var border: StandardMaterial3D = _lit(Color(MARK_COLOR, 0.82), 1.0)
	border.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for index: int in range(marks.size()):
		var mark: Dictionary = marks[index]
		var low: Vector2 = Vector2(float(mark["min"][0]), float(mark["min"][1]))
		var high: Vector2 = Vector2(float(mark["max"][0]), float(mark["max"][1]))
		var y: float = float(mark["y"]) + 0.018
		var centre: Vector3 = Vector3((low.x + high.x) * 0.5, y, (low.y + high.y) * 0.5)
		var size: Vector2 = high - low
		var bed: MeshInstance3D = MeshInstance3D.new()
		bed.name = "WorkMark%d" % index
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = size
		bed.mesh = plane
		bed.position = centre
		bed.material_override = bed_material
		bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(bed)
		for edge: int in range(4):
			var along_x: bool = edge < 2
			var strip: MeshInstance3D = MeshInstance3D.new()
			strip.name = "MarkEdge"
			var line: PlaneMesh = PlaneMesh.new()
			line.size = Vector2(size.x, MARK_BORDER) if along_x else Vector2(MARK_BORDER, size.y)
			strip.mesh = line
			var sign: float = -1.0 if edge % 2 == 0 else 1.0
			strip.position = centre + (Vector3(0.0, 0.002, sign * (size.y - MARK_BORDER) * 0.5) if along_x \
				else Vector3(sign * (size.x - MARK_BORDER) * 0.5, 0.002, 0.0))
			strip.material_override = border
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			group.add_child(strip)

## Homes outside the south, east and west boundaries. Most windows are dark;
## a few still burn, interrupted. Nothing here is inside the playable square.
func _build_night_town(half: float) -> void:
	var town: Node3D = Node3D.new()
	town.name = "NightTown"
	_root.add_child(town)
	var plaster: Array[StandardMaterial3D] = [_lit(Color("6f6152")), _lit(Color("56605a")), _lit(Color("6b5547")), _lit(Color("77705c"))]
	var roof: StandardMaterial3D = _lit(Color("2c3331"))
	var dark: StandardMaterial3D = _lit(Color("15191b"))
	var lit: StandardMaterial3D = _unshaded(Color("d9b27a"))
	var dim: StandardMaterial3D = _unshaded(Color("6e5a3e"))
	var faces: Array[Array] = [[0.0, -half - 7.0], [PI * 0.5, half + 7.0], [-PI * 0.5, -half - 7.0]]
	for side: int in range(faces.size()):
		var yaw: float = faces[side][0]
		for index: int in range(6):
			var home: Node3D = Node3D.new()
			home.name = "Home%d_%d" % [side, index]
			var along: float = (float(index) - 2.5) * half * 0.36
			var height: float = 11.0 + float((index * 7 + side * 3) % 4) * 1.6
			if side == 0:
				home.position = Vector3(along, 0.0, -half - 7.0)
			elif side == 1:
				home.position = Vector3(half + 7.0, 0.0, along)
				home.rotation.y = -PI * 0.5
			else:
				home.position = Vector3(-half - 7.0, 0.0, along)
				home.rotation.y = PI * 0.5
			town.add_child(home)
			_box(home, "Wall", Vector3(0.0, height * 0.5, 0.0), Vector3(10.0, height, 9.0), plaster[(index + side) % plaster.size()])
			_box(home, "Roof", Vector3(0.0, height + 0.2, 0.0), Vector3(10.6, 0.4, 9.6), roof)
			for level: int in range(3):
				for window: int in range(3):
					var seed: int = (index * 13 + side * 5 + level * 7 + window * 3) % 17
					var pane: StandardMaterial3D = lit if seed == 0 else (dim if seed == 5 else dark)
					_box(home, "Window", Vector3((float(window) - 1.0) * 2.8, height - 2.0 - float(level) * 2.6, 4.53), Vector3(1.3, 1.4, 0.08), pane)
			if index % 3 == 1:
				_box(home, "Tank", Vector3(-2.6, height + 1.3, -0.5), Vector3(2.2, 2.2, 2.2), plaster[(index + 2) % plaster.size()])
	# A tram mast leaning over the south roofs, its wires slack.
	_box(town, "TramMast", Vector3(-8.0, 9.0, -half - 2.5), Vector3(0.35, 18.0, 0.35), dark)

## The river beyond the north railing, the quay, the pier with its freight
## platform, and the waterworks: the refuge crossing, lit.
func _build_river(half: float) -> void:
	var river: Node3D = Node3D.new()
	river.name = "RiverAndPier"
	_root.add_child(river)
	var water: MeshInstance3D = MeshInstance3D.new()
	water.name = "River"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(half * 2.0 + 240.0, RIVER_DEPTH)
	water.mesh = plane
	water.position = Vector3(0.0, -1.1, half + 2.0 + RIVER_DEPTH * 0.5)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_river_material = ShaderMaterial.new()
	_river_material.shader = ArenaWater.SHADER
	_river_material.set_shader_parameter("river_mode", true)
	_river_material.set_shader_parameter("patch_size", plane.size)
	_river_material.set_shader_parameter("deep_color", Color("0b1a22"))
	_river_material.set_shader_parameter("water_color", Color("17303a"))
	_river_material.set_shader_parameter("crest_color", Color("4d6f78"))
	_river_material.set_shader_parameter("shore_color", Color("1a2226"))
	var ripples: Texture2D = EnvironmentTextures.texture_at("res://assets/environment/production/water_ripples.png")
	if ripples != null:
		_river_material.set_shader_parameter("ripple_detail", ripples)
		_river_material.set_shader_parameter("detail_enabled", true)
	water.material_override = _river_material
	river.add_child(water)
	var stone: StandardMaterial3D = _lit(Color("4a4a42"))
	var timber: StandardMaterial3D = _lit(Color("4b3b2c"))
	var iron: StandardMaterial3D = _lit(Color("2a3130"))
	var lamp: StandardMaterial3D = _glow(Color("ffd89a"), 6.0)
	var bulb: StandardMaterial3D = _glow(Color("ffc978"), 4.0)
	var white: StandardMaterial3D = _glow(Color("f2efe4"), 5.0)
	# Quay wall dropping from the railing to the water.
	_box(river, "QuayWall", Vector3(0.0, -0.6, half + 1.0), Vector3(half * 2.0, 1.2, 2.0), stone)
	# The pier runs north from the waterworks, then the freight platform from
	# level 5 sits at its end, now the refuge crossing.
	var pier_x: float = 52.0
	_box(river, "PierDeck", Vector3(pier_x, -0.2, half + 26.0), Vector3(5.0, 0.4, 48.0), timber)
	for index: int in range(9):
		var z: float = half + 4.0 + float(index) * 5.5
		for side: float in [-1.0, 1.0]:
			_box(river, "PierPile", Vector3(pier_x + side * 2.3, -1.0, z), Vector3(0.4, 1.8, 0.4), iron)
	_box(river, "FreightPlatform", Vector3(pier_x, 0.4, half + 58.0), Vector3(22.0, 1.2, 16.0), stone)
	_box(river, "PlatformShed", Vector3(pier_x + 4.0, 3.4, half + 61.0), Vector3(10.0, 4.8, 7.0), _lit(Color("5b6058")))
	_box(river, "ShedRoof", Vector3(pier_x + 4.0, 6.0, half + 61.0), Vector3(11.0, 0.4, 8.0), iron)
	# People waiting on the platform, in households and knots rather than
	# rows: standing, sitting on what they carried, under their own lamps.
	var platform_top: float = 1.0
	var knots: Array[Vector3] = [Vector3(-7.5, 0.0, 52.0), Vector3(-3.2, 0.0, 54.6), Vector3(1.6, 0.0, 52.4),
		Vector3(5.8, 0.0, 55.2), Vector3(-0.8, 0.0, 57.6), Vector3(-6.0, 0.0, 58.4)]
	for knot: int in range(knots.size()):
		var root: Node3D = Node3D.new()
		root.name = "PierKnot%d" % knot
		root.position = Vector3(pier_x, platform_top, half) + knots[knot]
		root.rotation.y = float((knot * 5) % 7) * 0.9
		river.add_child(root)
		var members: int = 2 + (knot * 3) % 3
		for member: int in range(members):
			var seed: int = 300 + knot * 11 + member
			var spot: Vector3 = Vector3(float(member) * 0.7 - 0.5, 0.0, float((member * 2 + knot) % 3) * 0.45 - 0.4)
			if member == 0 and knot % 2 == 0:
				_box(root, "Case", spot + Vector3(0.0, 0.2, 0.0), Vector3(0.7, 0.4, 0.45), _lit(Crowd.LOADS[knot % Crowd.LOADS.size()]))
				var sitter: Node3D = Crowd.seated(seed)
				sitter.position = spot + Vector3(0.0, 0.42, 0.0)
				root.add_child(sitter)
				continue
			var stander: Node3D = Crowd.person(seed, member == members - 1 and knot % 3 == 1)
			stander.position = spot
			stander.rotation.y = float(member) * 1.3
			root.add_child(stander)
		if knot % 2 == 1:
			Crowd.hand_lamp(root, Vector3(0.4, 0.11, 0.6), 0.7)
	# A string of bulbs along both pier rails: the line you follow to the refuge.
	for index: int in range(24):
		for side: float in [-1.0, 1.0]:
			_box(river, "PierBulb", Vector3(pier_x + side * 2.4, 1.3, half + 3.0 + float(index) * 2.0), Vector3(0.16, 0.16, 0.16), bulb)
	for side: float in [-1.0, 1.0]:
		_box(river, "BulbWire", Vector3(pier_x + side * 2.4, 1.38, half + 26.0), Vector3(0.03, 0.03, 46.0), iron)
	for index: int in range(6):
		var at: Vector3 = Vector3(pier_x - 2.6 + float(index % 2) * 5.2, 4.2, half + 6.0 + float(index / 2) * 16.0)
		_box(river, "LampPost", at - Vector3(0.0, 2.1, 0.0), Vector3(0.16, 4.2, 0.16), iron)
		_box(river, "LampHead", at + Vector3(0.0, 0.1, 0.0), Vector3(0.6, 0.3, 0.6), lamp)
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "PierLamp"
		light.light_color = Color("ffcf8a")
		light.light_energy = 2.2
		light.omni_range = 10.0
		light.shadow_enabled = false
		light.position = at
		river.add_child(light)
		_pier_lamps.append(light)
	# Two tall floodlight masts on the freight platform, seen from the roofs.
	for side: float in [-1.0, 1.0]:
		var mast: Vector3 = Vector3(pier_x + side * 9.0, 0.0, half + 52.0)
		_box(river, "FloodMast", mast + Vector3(0.0, 6.0, 0.0), Vector3(0.35, 12.0, 0.35), iron)
		_box(river, "FloodHead", mast + Vector3(0.0, 12.1, -0.4), Vector3(2.0, 0.9, 0.5), white)
		var flood: SpotLight3D = SpotLight3D.new()
		flood.name = "Floodlight"
		flood.light_color = Color("f4f1e6")
		flood.light_energy = 4.0
		flood.spot_range = 30.0
		flood.spot_angle = 50.0
		flood.position = mast + Vector3(0.0, 11.8, -0.8)
		flood.rotation = Vector3(-PI * 0.42, 0.0, 0.0)
		river.add_child(flood)
	for index: int in range(4):
		var at: Vector3 = Vector3(pier_x - 9.0 + float(index) * 6.0, 4.4, half + 51.0)
		_box(river, "PlatformLamp", at, Vector3(0.7, 0.3, 0.7), lamp)
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "PlatformLamp"
		light.light_color = Color("ffd59a")
		light.light_energy = 2.6
		light.omni_range = 14.0
		light.shadow_enabled = false
		light.position = at
		river.add_child(light)
		_pier_lamps.append(light)
	# The waterworks: a pump house over the river east of the trench mouth,
	# its windows lit, a white works light on its gable.
	var works: Node3D = Node3D.new()
	works.name = "Waterworks"
	works.position = Vector3(half + 14.0, 0.0, half + 8.0)
	river.add_child(works)
	_box(works, "PumpHouse", Vector3(0.0, 5.0, 0.0), Vector3(18.0, 10.0, 14.0), _lit(Color("55524a")))
	_box(works, "PumpRoof", Vector3(0.0, 10.4, 0.0), Vector3(19.0, 0.8, 15.0), iron)
	for window: int in range(5):
		_box(works, "WorksWindow", Vector3(-9.05, 6.0, -5.0 + float(window) * 2.5), Vector3(0.1, 1.6, 1.2), lamp)
	_box(works, "GableLight", Vector3(-9.1, 9.0, 0.0), Vector3(0.1, 0.5, 2.4), white)
	# The waterworks chimney beacon, slow and white: the far mark from every roof.
	_box(works, "Chimney", Vector3(4.0, 14.0, 3.0), Vector3(1.6, 8.0, 1.6), _lit(Color("4a4740")))
	_box(works, "Beacon", Vector3(4.0, 18.3, 3.0), Vector3(0.8, 0.6, 0.8), white)
	var gable: OmniLight3D = OmniLight3D.new()
	gable.light_color = Color("e8eef2")
	gable.light_energy = 1.6
	gable.omni_range = 16.0
	gable.position = Vector3(-11.0, 8.0, 0.0)
	works.add_child(gable)

## People leaving through the concourse, a Clerk in a black coat at one end of
## a stretcher, and the coalition stores lamp. The crowd keeps to the quiet
## west half and the gallery, away from the crossing's lines of fire. Nobody
## walks in rank: households, a pair with a crate, someone alone with a case.
func _build_concourse() -> void:
	var hall: Node3D = Node3D.new()
	hall.name = "ConcourseCrowd"
	_root.add_child(hall)
	var lanes: Array[Array] = [
		[Vector3(-56.5, 0.0, -12.0), Vector3(-56.5, 0.0, -32.0)],
		[Vector3(-41.5, 0.0, -10.0), Vector3(-41.5, 0.0, -33.0)],
		[Vector3(-57.0, 4.5, -1.0), Vector3(-45.0, 4.5, -1.0)],
	]
	# Lane, kind (0 alone, 1 household, 2 crate pair), where along the lane,
	# pace and a sideways offset so no two walk on one line.
	var walkers: Array[Array] = [
		[0, 1, 0.05, 0.016, -0.3], [0, 0, 0.27, 0.022, 0.45], [0, 2, 0.46, 0.014, 0.0], [0, 0, 0.71, 0.019, -0.5], [0, 1, 0.88, 0.017, 0.35],
		[1, 0, 0.12, 0.02, 0.4], [1, 1, 0.38, 0.015, -0.2], [1, 0, 0.6, 0.023, -0.55], [1, 0, 0.83, 0.018, 0.3],
		[2, 0, 0.1, 0.021, 0.3], [2, 1, 0.42, 0.016, -0.2], [2, 0, 0.66, 0.019, 0.45], [2, 0, 0.9, 0.024, -0.35],
	]
	for index: int in range(walkers.size()):
		var spec: Array = walkers[index]
		var lane: Array = lanes[int(spec[0])]
		var group: Node3D
		match int(spec[1]):
			1: group = Crowd.family(index + 1)
			2: group = Crowd.crate_pair(index + 1)
			_: group = Crowd.person(index * 7 + 2)
		hall.add_child(group)
		var from: Vector3 = lane[0]
		var to: Vector3 = lane[1]
		var across: Vector3 = (to - from).normalized().cross(Vector3.UP) * float(spec[4])
		_evacuees.append({"node": group, "from": from + across, "to": to + across, "t": float(spec[2]), "speed": float(spec[3])})
	# The stretcher: a Clerk at the head, still in his issued coat with its
	# red armband and seal, and a coalition porter at the foot.
	var stretcher: Node3D = Node3D.new()
	stretcher.name = "Stretcher"
	stretcher.position = Vector3(-55.0, 0.0, -24.5)
	stretcher.rotation.y = PI * 0.5
	hall.add_child(stretcher)
	var clerk: Node3D = _clerk()
	clerk.position = Vector3(0.0, 0.0, -1.1)
	stretcher.add_child(clerk)
	var porter: Node3D = Crowd.person(42)
	porter.position = Vector3(0.0, 0.0, 1.1)
	porter.rotation.y = PI
	stretcher.add_child(porter)
	_box(stretcher, "StretcherBed", Vector3(0.0, 0.82, 0.0), Vector3(0.62, 0.06, 1.9), _lit(Color("8a8576")))
	_box(stretcher, "Patient", Vector3(0.0, 0.95, 0.1), Vector3(0.42, 0.22, 1.5), _lit(Color("6c7a7c")))
	_box(stretcher, "Blanket", Vector3(0.0, 1.02, 0.25), Vector3(0.5, 0.06, 1.1), _lit(Color("9c7b55")))
	# Spare packs hang on the stores racks either side of the sign, harness to
	# the rack: the counter reads as jetpack stores before anyone draws one.
	var racks: Array[float] = [-55.3, -54.5, -47.5, -46.7]
	for index: int in range(racks.size()):
		var spare: Node3D = JetpackRig.spare()
		spare.name = "SparePack%d" % index
		spare.position = Vector3(racks[index], 1.72, -32.76)
		spare.rotation.y = PI * 0.5
		hall.add_child(spare)
	# People who have stopped: on the benches, a child beside a parent.
	var seats: Array[Vector3] = [Vector3(-39.4, 0.9, -27.5), Vector3(-38.1, 0.9, -27.5), Vector3(-36.6, 0.9, -27.5),
		Vector3(-39.0, 0.9, -15.5), Vector3(-37.2, 0.9, -15.5)]
	for index: int in range(seats.size()):
		var sitter: Node3D = Crowd.seated(60 + index * 3, index == 1)
		sitter.position = seats[index]
		sitter.rotation.y = 0.0 if index < 3 else PI
		hall.add_child(sitter)
	# Everything a household could carry, stacked on the luggage cart, and the
	# household itself resting on its cases beside it under a hand lamp.
	var cases: Array[Color] = [Color("8a5a3a"), Color("4d5a52"), Color("6e5a3c"), Color("7a5068")]
	for index: int in range(5):
		var size: Vector3 = Vector3(0.9 - float(index % 2) * 0.25, 0.32, 0.55)
		_box(hall, "Case", Vector3(-40.0 + float(index % 2) * 0.35 - 0.2, 1.6 + 0.16 + float(index) * 0.32, -32.0 + float(index % 3 - 1) * 0.12),
			size, _lit(cases[index % cases.size()]))
	for index: int in range(3):
		var at: Vector3 = Vector3(-38.2 + float(index) * 0.8, 0.0, -31.4 + float(index % 2) * 0.5)
		_box(hall, "RestCase", at + Vector3(0.0, 0.2, 0.0), Vector3(0.6, 0.4, 0.42), _lit(cases[(index + 1) % cases.size()]))
		var resting: Node3D = Crowd.seated(80 + index * 5, index == 2)
		resting.position = at + Vector3(0.0, 0.42, 0.0)
		resting.rotation.y = PI * (0.85 + 0.15 * float(index))
		hall.add_child(resting)
	Crowd.hand_lamp(hall, Vector3(-37.4, 0.11, -30.6), 0.8)
	# Bedding laid along the quiet wall under the gallery, out of every lane.
	var bedding: Array[Color] = [Color("8a5a48"), Color("5d6a52"), Color("9a7650"), Color("6a5a7a")]
	for index: int in range(6):
		var z: float = -5.6 + float(index) * 1.15
		_box(hall, "Bedroll", Vector3(-57.0, 0.04, z), Vector3(1.9, 0.08, 0.85), _lit(bedding[index % bedding.size()]))
		_box(hall, "Pillow", Vector3(-57.75, 0.1, z), Vector3(0.4, 0.1, 0.6), _lit(Color("a49c88")))
		if index % 2 == 0:
			var look: Dictionary = Crowd.look(100 + index)
			var sleeper: Node3D = Node3D.new()
			sleeper.name = "Sleeper"
			sleeper.position = Vector3(-57.0, 0.08, z)
			_box(sleeper, "Body", Vector3(0.1, 0.12, 0.0), Vector3(1.4, 0.24, 0.42), _lit(look["coat"]))
			_box(sleeper, "Head", Vector3(-0.72, 0.14, 0.0), Vector3(0.24, 0.22, 0.24), _lit(look["skin"]))
			hall.add_child(sleeper)
	Crowd.hand_lamp(hall, Vector3(-56.2, 0.11, -0.6), 0.7)

## The Clerk at the stretcher stays recognisably Union while he carries:
## issued black coat, a dark steel collar, a red armband and a red seal. The
## beat is that he helps, not that he changed sides.
func _clerk() -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = "ClerkInBlack"
	var coat: StandardMaterial3D = _lit(Color("17191b"))
	var steel: StandardMaterial3D = _lit(Color("3a4044"), 0.5)
	var red: StandardMaterial3D = _lit(Color("8e1c18"))
	_box(node, "Coat", Vector3(0.0, 1.12, 0.0), Vector3(0.5, 0.74, 0.3), coat)
	_box(node, "Head", Vector3(0.0, 1.66, 0.0), Vector3(0.26, 0.28, 0.26), _lit(Color("a87a5a")))
	_box(node, "Cap", Vector3(0.0, 1.82, 0.02), Vector3(0.3, 0.07, 0.32), coat)
	_box(node, "ClerkCollar", Vector3(0.0, 1.47, 0.0), Vector3(0.44, 0.06, 0.3), steel)
	_box(node, "Seal", Vector3(-0.12, 1.3, 0.152), Vector3(0.1, 0.1, 0.01), red)
	for side: float in [-1.0, 1.0]:
		_box(node, "Leg", Vector3(side * 0.12, 0.4, 0.0), Vector3(0.17, 0.8, 0.18), _lit(Color("1e2224")))
		_box(node, "Arm", Vector3(side * 0.29, 1.12, 0.0), Vector3(0.1, 0.62, 0.14), coat)
	_box(node, "Armband", Vector3(0.29, 1.24, 0.0), Vector3(0.12, 0.1, 0.16), red)
	return node

func _advance_evacuees(delta: float) -> void:
	for walker: Dictionary in _evacuees:
		var node: Node3D = walker["node"]
		var t: float = fmod(float(walker["t"]) + float(walker["speed"]) * delta, 1.0)
		walker["t"] = t
		var from: Vector3 = walker["from"]
		var to: Vector3 = walker["to"]
		# Walk the lane out and back, turning at each end.
		var leg: float = t * 2.0
		var forward: bool = leg < 1.0
		var along: float = leg if forward else 2.0 - leg
		node.position = from.lerp(to, along)
		var heading: Vector3 = (to - from) if forward else (from - to)
		node.rotation.y = atan2(heading.x, heading.z)
		Crowd.stride(node, t * 260.0)

## Festoon bulbs strung between the market awnings from level 4. Most are
## dead; a few burn, one catches and drops. Presentation only.
func _build_market_lights() -> void:
	var market: Node3D = Node3D.new()
	market.name = "MarketFestoons"
	_root.add_child(market)
	var wire: StandardMaterial3D = _lit(Color("1e2222"))
	var lit: StandardMaterial3D = _glow(Color("ffcf86"), 3.5)
	var dark: StandardMaterial3D = _lit(Color("3a362e"))
	var runs: Array[Array] = [[Vector3(0.0, 3.3, 19.5), Vector3(22.0, 3.3, 19.5)], [Vector3(12.0, 3.3, 29.5), Vector3(32.0, 3.3, 29.5)], [Vector3(-2.0, 3.3, 21.0), Vector3(12.0, 3.3, 29.0)]]
	var count: int = 0
	for run: Array in runs:
		var from: Vector3 = run[0]
		var to: Vector3 = run[1]
		var span: float = from.distance_to(to)
		var line: MeshInstance3D = _box(market, "Festoon", (from + to) * 0.5, Vector3(0.03, 0.03, span), wire)
		line.look_at_from_position((from + to) * 0.5, to, Vector3.UP)
		var bulbs: int = int(span / 1.6)
		for index: int in range(bulbs + 1):
			var t: float = float(index) / float(maxi(1, bulbs))
			var at: Vector3 = from.lerp(to, t) - Vector3(0.0, sin(t * PI) * 0.45 + 0.1, 0.0)
			count += 1
			var burning: bool = count % 5 == 1 or count % 7 == 3
			var bulb: MeshInstance3D = _box(market, "Bulb", at, Vector3(0.14, 0.18, 0.14), lit if burning else dark)
			if count == 8:
				var light: OmniLight3D = OmniLight3D.new()
				light.light_color = Color("ffc781")
				light.omni_range = 7.0
				light.shadow_enabled = false
				light.position = at - Vector3(0.0, 0.3, 0.0)
				market.add_child(light)
				_flicker.append({"mesh": bulb, "lit": lit, "dark": dark, "rate": 0.37, "phase": 0.0, "duty": 0.18, "light": light, "energy": 1.6})
			elif burning and count % 3 == 0:
				_flicker.append({"mesh": bulb, "lit": lit, "dark": dark, "rate": 0.9, "phase": float(count) * 0.21, "duty": 0.08})

func _build_tank_lamp() -> void:
	var lamp: Node3D = Node3D.new()
	lamp.name = "TankLamp"
	lamp.position = TANK_LAMP
	_root.add_child(lamp)
	Crowd.hand_lamp(lamp, Vector3(0.0, 0.11, 0.0), 1.3)

## The court's shared meal table from level 4, still set, under a white mark.
func _build_meal_table() -> void:
	var table: Node3D = Node3D.new()
	table.name = "MealTableSetting"
	table.position = Vector3(-19.0, 0.9, 25.0)
	_root.add_child(table)
	_box(table, "Cloth", Vector3(0.0, 0.01, 0.0), Vector3(5.8, 0.02, 1.6), _lit(Color("8f8068")))
	var bowl: StandardMaterial3D = _lit(Color("c9c1ad"))
	var cup: StandardMaterial3D = _lit(Color("6f8a86"))
	for index: int in range(6):
		var x: float = -2.4 + float(index) * 0.96
		for side: float in [-1.0, 1.0]:
			_box(table, "Bowl", Vector3(x, 0.06, side * 0.48), Vector3(0.26, 0.1, 0.26), bowl)
			if (index + int(side)) % 2 == 0:
				_box(table, "Cup", Vector3(x + 0.24, 0.09, side * 0.42), Vector3(0.09, 0.16, 0.09), cup)
	_box(table, "Pot", Vector3(0.0, 0.16, 0.0), Vector3(0.5, 0.32, 0.5), _lit(Color("3a3f3c"), 0.5))
	_box(table, "Bread", Vector3(1.2, 0.07, 0.05), Vector3(0.5, 0.12, 0.22), _lit(Color("a07a4a")))
	# One lantern still lit at the end of the table.
	_box(table, "Lantern", Vector3(-2.7, 0.16, 0.0), Vector3(0.18, 0.3, 0.18), _glow(Color("ffc06e"), 4.0))
	var lantern: OmniLight3D = OmniLight3D.new()
	lantern.light_color = Color("ffb862")
	lantern.light_energy = 1.4
	lantern.omni_range = 5.5
	lantern.shadow_enabled = false
	lantern.position = Vector3(-2.7, 0.5, 0.0)
	table.add_child(lantern)

## The jetpack fuel gauge: three cells for three seconds of thrust, the flame
## glyph while thrusting, and a one-time hint until the first burn.
class JetGauge extends Control:
	var _cells: Array[ColorRect] = []
	var _label: Label
	var _hint: Label
	var _frame: ColorRect
	var _fuel: float = 0.0
	var _thrusting: bool = false
	var _burned: bool = false
	var _clock: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		anchor_left = 0.5
		anchor_right = 0.5
		anchor_top = 1.0
		anchor_bottom = 1.0
		offset_left = -110.0
		offset_right = 110.0
		offset_top = -150.0
		offset_bottom = -104.0
		_frame = ColorRect.new()
		_frame.color = Color(MenuTheme.INK, 0.72)
		_frame.position = Vector2(0.0, 18.0)
		_frame.size = Vector2(220.0, 16.0)
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_frame)
		for index: int in range(3):
			var cell: ColorRect = ColorRect.new()
			cell.position = Vector2(4.0 + float(index) * 71.0, 21.0)
			cell.size = Vector2(70.0, 10.0)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(cell)
			_cells.append(cell)
		_label = Label.new()
		_label.position = Vector2(0.0, -4.0)
		_label.size = Vector2(220.0, 20.0)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_font_override("font", MenuTheme.FONT)
		_label.add_theme_font_size_override("font_size", 16)
		_label.add_theme_color_override("font_color", MenuTheme.BONE)
		_label.add_theme_color_override("font_outline_color", MenuTheme.INK)
		_label.add_theme_constant_override("outline_size", 4)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		_hint = Label.new()
		_hint.position = Vector2(-90.0, 36.0)
		_hint.size = Vector2(400.0, 20.0)
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint.add_theme_font_override("font", MenuTheme.FONT)
		_hint.add_theme_font_size_override("font_size", 16)
		_hint.add_theme_color_override("font_color", MenuTheme.BONE)
		_hint.add_theme_color_override("font_outline_color", MenuTheme.INK)
		_hint.add_theme_constant_override("outline_size", 4)
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_hint)
		visible = false

	func present(fact: Dictionary, human: bool) -> void:
		visible = human and not fact.is_empty()
		if not visible:
			return
		_fuel = clampf(float(fact.get("fuel", 0)) / float(JetMovement.FUEL_MAX), 0.0, 1.0)
		_thrusting = bool(fact.get("thrusting", false))
		if _thrusting:
			_burned = true
		_render()

	func _process(delta: float) -> void:
		if visible:
			_clock += delta
			_render()

	func _render() -> void:
		var warm: Color = Color("f0a24a")
		for index: int in range(_cells.size()):
			var fill: float = clampf(_fuel * 3.0 - float(index), 0.0, 1.0)
			var cell: ColorRect = _cells[index]
			cell.size.x = 70.0 * fill
			cell.color = warm if _thrusting else MenuTheme.BONE
		var empty: bool = _fuel <= 0.001
		_label.text = tr("M19_JET_EMPTY") if empty else (tr("M19_JET_THRUST") if _thrusting else tr("M19_JET_GAUGE"))
		_label.modulate.a = 0.5 + 0.5 * absf(sin(_clock * 6.0)) if empty else 1.0
		_hint.visible = not _burned
		_hint.text = InputGlyphs.plain(tr("M19_JET_HINT"))
