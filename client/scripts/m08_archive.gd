class_name M08Archive
extends Node3D

## The custody archive's presentation: records machinery, personal remnants,
## practical light and the custody machine's support nodes. Renn, the
## captives and Orrin's cabinet are provisional static art driven by server
## facts, never simulated participants. Every outcome comes from mission state.
const POSSESSIONS: String = "res://assets/environment/moon/possessions/"
const SURFACES: String = "res://assets/environment/moon/surfaces/"
const TEXTILE: String = POSSESSIONS + "lunar_civilian_patched_textile_0.png"
const DRAWING: String = POSSESSIONS + "lunar_child_earth_drawing_0.png"
const MEAL_CLOTH: String = POSSESSIONS + "lunar_personal_meal_cloth_0.png"
const NODE_LIVE: Color = Color("ff5a2a")
const NODE_HURT: Color = Color("b8622c")
const NODE_DEAD: Color = Color("2e2420")
const CABINET_COLD: Color = Color("7fa6c2")
const CABINET_TAKEN: Color = Color("e0b468")
const NOISE_LAMP: Color = Color("d8d0a0")
## Captive and Renn figures reuse the participant body strip until final art.
const CAPTIVE_TINTS: Array[Color] = [Color("d8c6a0"), Color("b8a888"), Color("c9b498"), Color("a9bcac")]
const FALL_SECONDS: float = 1.4
const ROOF_Y: float = 9.0
## The repeating rhythm under "Authorized noise": three short, one long.
const NOISE_PATTERN: Array[float] = [0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.5, 0.6]

var _root: Node3D
var _geometry: Dictionary = {}
var _neutral_layout: Dictionary = {}
var _solids: Array = []
var node_lamps: Array[MeshInstance3D] = []
var node_arms: Array[MeshInstance3D] = []
var renn: Sprite3D
var captives: Array[Sprite3D] = []
var upper_shutters: Array[MeshInstance3D] = []
var cabinet_lamp: MeshInstance3D
var noise_lamp: MeshInstance3D
var falling: MeshInstance3D
var fall_left: float = 0.0
var _machine_fallen: bool = false
var _noise_clock: float = 0.0
var _noise_on: bool = false
var state_applied: int = 0

func clear_map() -> void:
	_geometry.clear()
	_neutral_layout.clear()
	_solids.clear()
	node_lamps.clear()
	node_arms.clear()
	captives.clear()
	upper_shutters.clear()
	renn = null
	cabinet_lamp = null
	noise_lamp = null
	falling = null
	fall_left = 0.0
	_machine_fallen = false
	_noise_on = false
	state_applied = 0
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m08") is Dictionary or not MapGeometry.validation_error(info).is_empty() \
		or not M08MissionState.map_error(info).is_empty():
		return
	_root = Node3D.new()
	_root.name = "CustodyArchiveDetails"
	add_child(_root)
	_solids = info["solids"]
	_neutral_layout = M08NeutralBodies.layout(info)
	var m08: Dictionary = info["m08"]
	_records_machinery()
	_hall_light()
	for detail: Dictionary in info["presentation"]["decorations"]:
		var host: Dictionary = _solids[int(detail["solid"])]
		var transform: Transform3D = MapDecoration.placement(host, detail)
		match detail["kind"]:
			"m08_lost_property_six":
				_jackets(host)
			"m08_registry":
				_registry(transform, host)
			"m08_bay_release":
				_lower_bays(transform)
			"m08_cold_cabinet":
				cabinet_lamp = _box("ColdCabinetLamp", transform.origin + transform.basis.z * 0.05 + Vector3.UP * 0.9,
					Vector3(0.5, 0.12, 0.06), CABINET_COLD, true)
				_cabinet_frost(transform)
			"m08_authorized_noise":
				noise_lamp = _box("NoiseRhythmLamp", transform.origin + transform.basis.z * 0.04 - transform.basis.y * 0.7,
					Vector3(0.18, 0.18, 0.06), NOISE_LAMP, true)
			"m08_freight_departure":
				_lane_lights(transform)
	_machine(m08)
	_upper_bays(m08)
	_geometry = M08MissionState.geometry_for(info)
	_machine_fallen = bool(m08["machine_fallen"])
	_apply_fallen(_machine_fallen)
	ArenaSky.mark_world(self)

## Records cabinets along the hall's outer wall: the institution's machinery.
func _records_machinery() -> void:
	for side: int in range(4):
		for index: int in range(7):
			var along: float = -15.0 + float(index) * 5.0
			var at: Vector3
			var size: Vector3
			match side:
				0: at = Vector3(along, 1.0, -19.55); size = Vector3(3.6, 2.0, 0.7)
				1: at = Vector3(along, 1.0, 19.55); size = Vector3(3.6, 2.0, 0.7)
				2: at = Vector3(-19.55, 1.0, along); size = Vector3(0.7, 2.0, 3.6)
				_: at = Vector3(19.55, 1.0, along); size = Vector3(0.7, 2.0, 3.6)
			# Leave the entry, the stair doors and the lost-property cage clear.
			if (side == 0 and absf(along) < 6.0) or (side == 2 and along > -9.0 and along < -1.0) \
				or (side == 1 and along > 12.0) or (side == 3 and along > 12.0):
				continue
			var cabinet: MeshInstance3D = _box("RecordsCabinet", at, size, Color("4d544f"))
			_apply_surface(cabinet, "moon_union_service")
			for drawer: int in range(3):
				_box("RecordsDrawerLabel", at + Vector3(0, -0.6 + drawer * 0.6, 0) + (Vector3(0, 0, 0.37) if side == 0 else (Vector3(0, 0, -0.37) if side == 1 else (Vector3(0.37, 0, 0) if side == 2 else Vector3(-0.37, 0, 0)))),
					Vector3(0.5, 0.12, 0.02) if side < 2 else Vector3(0.02, 0.12, 0.5), Color("c9c2a2"))

## Practical light: desk lamps in the hall and the shaft's cold glow.
func _hall_light() -> void:
	for at: Vector3 in [Vector3(-12.5, 2.2, -13.5), Vector3(12.5, 2.2, -13.5), Vector3(0, 2.2, 12.5),
			Vector3(-14, 5.2, -11.5), Vector3(13.5, 8.2, 9.5), Vector3(0, 5.0, 30.0)]:
		_box("DeskLamp", at, Vector3(0.6, 0.06, 0.3), Color("e8d6a6"), true)
		_light("PracticalLamp", at + Vector3.DOWN * 0.15, Color("ffe2ad"), 1.4, 9.0)
	_light("ShaftGlow", Vector3(0, 4.5, 0), Color("c9dde8"), 1.2, 14.0)

func _jackets(host: Dictionary) -> void:
	# Confiscated jackets on the cage floor; one carries the six.
	var floor_y: float = MoveStep.solid_bottom(host) + 0.04
	for index: int in range(5):
		var jacket: MeshInstance3D = _box("ConfiscatedJacket", Vector3(15.6 + index * 0.9, floor_y + index * 0.05, 15.4 + (index % 2) * 0.6),
			Vector3(0.8, 0.08, 0.6), CAPTIVE_TINTS[index % CAPTIVE_TINTS.size()])
		jacket.material_override = possession_material(TEXTILE)
	_box("JacketSix", Vector3(17.4, floor_y + 0.26, 15.4), Vector3(0.22, 0.02, 0.22), Color("c9a15a"), true)

func _registry(transform: Transform3D, _host: Dictionary) -> void:
	_box("RegistryCase", transform.origin + transform.basis.y * 0.62 + transform.basis.x * 0.6,
		Vector3(0.55, 0.32, 0.4), Color("5a4a3a"))
	# Renn stands behind the desk, across it from the party.
	var behind: Vector3 = _neutral_layout["renn"] + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT
	renn = _figure("RennProvisional", behind, Color("8f9aa2"))
	renn.visible = false

func _lower_bays(transform: Transform3D) -> void:
	# Personal remnants in the bays: a drawing, a meal cloth and folded clothes.
	var drawing: MeshInstance3D = MeshInstance3D.new()
	drawing.name = "BayDrawing"
	var page: QuadMesh = QuadMesh.new()
	page.size = Vector2(0.8, 0.8)
	drawing.mesh = page
	drawing.transform = Transform3D(transform.basis, transform.origin + transform.basis.x * 3.2 + transform.basis.y * 0.4)
	drawing.material_override = possession_material(DRAWING)
	_root.add_child(drawing)
	var cloth: MeshInstance3D = _box("BayMealCloth", transform.origin + transform.basis.x * -3.0 - transform.basis.y * 1.05 + transform.basis.z * 1.0,
		Vector3(1.0, 0.02, 0.7), Color("b8aa87"))
	cloth.material_override = possession_material(MEAL_CLOTH)
	for index: int in range(4):
		var captive: Sprite3D = _figure("CaptiveProvisional", _neutral_layout["held"][index] + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT,
			CAPTIVE_TINTS[index])
		captives.append(captive)

func _upper_bays(m08: Dictionary) -> void:
	# Upper custody bay shutters on the south wall; they lift with the seal.
	for index: int in range(4):
		var shutter: MeshInstance3D = _box("UpperBayShutter", Vector3(4.0 + index * 4.0, 7.5, -19.6),
			Vector3(3.0, 3.0, 0.12), Color("3c4248"))
		_apply_surface(shutter, "moon_union_service")
		upper_shutters.append(shutter)
	_set_shutters(bool(m08["seal_open"]))

func _cabinet_frost(transform: Transform3D) -> void:
	_box("OrrinBackupCase", transform.origin + transform.basis.z * 0.25, Vector3(0.6, 0.45, 0.35) if absf(transform.basis.z.x) > 0.5 else Vector3(0.35, 0.45, 0.6),
		Color("6f7f88"))

func _lane_lights(transform: Transform3D) -> void:
	# The freight lane's lights below the bridge are the exit landmark.
	for index: int in range(6):
		var at: Vector3 = Vector3(-5.5 if index % 2 == 0 else 5.5, 0.06, 24.0 + float(index / 2) * 4.0)
		_box("LaneLight", at, Vector3(0.5, 0.06, 0.9), Color("f0d890"), true)
	_light("LaneFloodlight", transform.origin + Vector3.UP * 3.0 - transform.basis.z * 3.0, Color("fff0c0"), 2.0, 18.0)

func _machine(m08: Dictionary) -> void:
	var machine: Dictionary = _solids[int(m08["machine"])]
	var centre: Vector3 = _centre(machine)
	for index: int in range(m08["nodes"].size()):
		var node: Dictionary = _solids[int(m08["nodes"][index]["solid"])]
		var at: Vector3 = _centre(node)
		var lamp: MeshInstance3D = _box("SupportNodeGlow", at, _size(node) * 1.08, NODE_LIVE, true)
		node_lamps.append(lamp)
		var arm: MeshInstance3D = _box("SupportArm", (at + centre) * 0.5, Vector3(0.18, 0.18, at.distance_to(centre)), Color("555c5e"))
		arm.look_at_from_position(arm.position, at, Vector3.UP)
		node_arms.append(arm)
	var top: float = MoveStep.solid_top(machine)
	_box("MachineChain", Vector3(centre.x, (top + ROOF_Y) * 0.5, centre.z),
		Vector3(0.2, maxf(ROOF_Y - top, 0.05), 0.2), Color("3a3f40"))
	_light("MachineCore", centre + Vector3.DOWN * 0.3, Color("ff7a4a"), 1.6, 10.0)

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.get("id") != MissionState.M08_ID \
		or not M08MissionState.validation_error({"tick": EquipmentState.MAX_EXACT_INTEGER, "state": state}, _with_stage(state)).is_empty():
		return
	state_applied += 1
	var facts: Dictionary = state["m08"]
	for index: int in range(mini(node_lamps.size(), facts["node_hp"].size())):
		var hp: int = int(facts["node_hp"][index])
		_tint(node_lamps[index], NODE_LIVE if hp == M08MissionState.NODE_HP else (NODE_HURT if hp > 0 else NODE_DEAD))
	if is_instance_valid(renn):
		renn.visible = bool(facts["custodian_joined"])
	var released: bool = bool(facts["custody_released"])
	for index: int in range(captives.size()):
		# Released captives walk to the freight lane and wait there.
		var feet: Vector3 = _neutral_layout["released" if released else "held"][index]
		captives[index].position = feet + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT
	_set_shutters(bool(facts["seal_open"]))
	if is_instance_valid(cabinet_lamp):
		_tint(cabinet_lamp, CABINET_TAKEN if facts["recovered_mind_secured"] else CABINET_COLD)
	_noise_on = bool(facts["transfer_evidence"])
	if bool(facts["machine_fallen"]) and not _machine_fallen:
		_machine_fallen = true
		_start_fall()

func _with_stage(state: Dictionary) -> Dictionary:
	# The presenter follows the facts' own stage; the map contract is static.
	var geometry: Dictionary = _geometry.duplicate(true)
	geometry["m08"]["seal_open"] = state["m08"]["seal_open"]
	geometry["m08"]["machine_fallen"] = state["m08"]["machine_fallen"]
	return geometry

func _set_shutters(open: bool) -> void:
	for shutter: MeshInstance3D in upper_shutters:
		shutter.position.y = 8.85 if open else 7.5
		shutter.scale.y = 0.1 if open else 1.0

func _start_fall() -> void:
	if not is_instance_valid(_root) or _geometry.is_empty():
		return
	var machine: Dictionary = _solids[int(_geometry["m08"]["machine"])]
	falling = _box("FallingCustodyMachine", _centre(machine), _size(machine), Color("4a5052"))
	_apply_surface(falling, "moon_union_service")
	fall_left = FALL_SECONDS
	_apply_fallen(true)

func _apply_fallen(fallen: bool) -> void:
	for arm: MeshInstance3D in node_arms:
		arm.visible = not fallen
	for lamp: MeshInstance3D in node_lamps:
		lamp.visible = not fallen

func _process(delta: float) -> void:
	var step: float = maxf(delta, 0.0)
	if is_instance_valid(falling) and fall_left > 0.0:
		fall_left = maxf(0.0, fall_left - step)
		var progress: float = 1.0 - fall_left / FALL_SECONDS
		# Accelerating drop through every gallery to the shaft floor.
		falling.position.y = lerpf(7.6, 0.75, progress * progress)
		falling.rotation.z = progress * 0.35
		if fall_left == 0.0:
			falling.queue_free()
			falling = null
	if is_instance_valid(noise_lamp):
		var lit: bool = false
		if _noise_on:
			var total: float = 0.0
			for part: float in NOISE_PATTERN:
				total += part
			_noise_clock = fposmod(_noise_clock + step, total)
			var at: float = 0.0
			for index: int in range(NOISE_PATTERN.size()):
				at += NOISE_PATTERN[index]
				if _noise_clock < at:
					lit = index % 2 == 0
					break
		noise_lamp.visible = lit

func _figure(label: String, at: Vector3, tint: Color) -> Sprite3D:
	var figure: Sprite3D = Sprite3D.new()
	figure.name = label
	figure.texture = load(PlayerBody.strip_path(PlayerBody.HUMAN)) as Texture2D
	figure.hframes = PlayerBody.IDLE_FRAMES + PlayerBody.WALK_FRAMES
	figure.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
	figure.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	figure.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	figure.position = at
	figure.modulate = tint
	_root.add_child(figure)
	return figure

func _light(label: String, at: Vector3, colour: Color, energy: float, reach: float) -> void:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = label
	light.position = at
	light.light_color = colour
	light.light_energy = energy
	light.omni_range = reach
	light.light_cull_mask = 2
	light.add_to_group(ArenaSky.PRACTICAL_GROUP)
	_root.add_child(light)

func _box(label: String, at: Vector3, size: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	return MoonBackdrop._piece(_root, label, at, size, MoonBackdrop._material(color, glow))

func _tint(mesh: MeshInstance3D, colour: Color) -> void:
	mesh.material_override = MoonBackdrop._material(colour, true)

static func _centre(solid: Dictionary) -> Vector3:
	return Vector3((float(solid.min_x) + float(solid.max_x)) * 0.5,
		(MoveStep.solid_bottom(solid) + MoveStep.solid_top(solid)) * 0.5,
		(float(solid.min_z) + float(solid.max_z)) * 0.5)

static func _size(solid: Dictionary) -> Vector3:
	return Vector3(float(solid.max_x) - float(solid.min_x), MoveStep.solid_top(solid) - MoveStep.solid_bottom(solid),
		float(solid.max_z) - float(solid.min_z))

static func _apply_surface(mesh: MeshInstance3D, id: String) -> void:
	var path: String = SURFACES + id + ".png"
	if ResourceLoader.exists(path, "Texture2D"):
		mesh.material_override = possession_material(path)

static func possession_material(path: String) -> StandardMaterial3D:
	var material: StandardMaterial3D = MoonBackdrop._material(Color.WHITE)
	if ResourceLoader.exists(path, "Texture2D"):
		material.albedo_texture = load(path) as Texture2D
	return material
