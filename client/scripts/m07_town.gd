class_name M07Town
extends Node3D

## Declared Goods presentation: the curfew town under its pressure dome, dark
## shutters, market awnings, the silent window figure, the curfew chime, the
## lamp line toward the cut and the depot's radial tower. Every piece is
## presentation of server facts or static scenery; none of it is collision,
## cover or a mission control.
signal notice_requested(text: String)

## Seconds between the curfew chimes, from the brief.
const CHIME_SECONDS: float = 30.0
## Seconds between one lamp and the next after the curfew post falls.
const LAMP_INTERVAL: float = 0.5
## The window figure starts her pantomime when a participant is this close.
const FIGURE_RANGE: float = 14.0
const FIGURE_CYCLE: float = 3.2
const LAMP_ON: Color = Color("ffd9a0")
const LAMP_OFF: Color = Color("2a2b2b")
const SHUTTER: Color = Color("2b2f31")
const SHUTTER_RIB: Color = Color("1b1e1f")
const DARK_WINDOW: Color = Color("15191c")
const AWNINGS: Array[Color] = [Color("7c4a3a"), Color("566f63"), Color("8a7a52"), Color("5d566f")]
## The town's dome, centred over the habitation ring; outside play entirely.
const DOME_CENTRE: Vector3 = Vector3(-13.0, 0.0, -36.0)
const DOME_RADII: Vector3 = Vector3(62.0, 26.0, 40.0)
const DEPOT_TOWER: Vector3 = Vector3(130.0, 0.0, 60.0)

var _root: Node3D
var _geometry: Dictionary = {}
var lamps: Array[Dictionary] = []
var lamps_lit_count: int = 0
var _lamp_clock: float = -1.0
var _lamp_known: bool = false
var _lamp_attempt: String = ""
var chime: AudioStreamPlayer
var chime_count: int = 0
var _chime_clock: float = 0.0
var _chiming: bool = false
var figure: Node3D
var figure_hand: MeshInstance3D
var figure_active: bool = false
var _figure_clock: float = 0.0
var _figure_origin: Vector3 = Vector3.ZERO
var _figure_glass: Vector3 = Vector3.ZERO
var _figure_out: Vector3 = Vector3.ZERO
var listener_position: Vector3 = Vector3.INF

func _exit_tree() -> void:
	_stop_chime()

func _stop_chime() -> void:
	if is_instance_valid(chime):
		chime.stop()
		chime.stream = null
	chime = null

func clear_map() -> void:
	_geometry.clear()
	lamps.clear()
	lamps_lit_count = 0
	_lamp_clock = -1.0
	_lamp_known = false
	_lamp_attempt = ""
	chime_count = 0
	_chime_clock = 0.0
	_chiming = false
	figure = null
	figure_hand = null
	figure_active = false
	_stop_chime()
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m07") is Dictionary or not MapGeometry.validation_error(info).is_empty() \
		or not MissionState.map_error(info).is_empty():
		return
	_root = Node3D.new()
	_root.name = "CurfewTown"
	add_child(_root)
	var solids: Array = info["solids"]
	for detail: Dictionary in info["presentation"]["decorations"]:
		var host: Dictionary = solids[int(detail["solid"])]
		var placed: Transform3D = MapDecoration.placement(host, detail)
		var size: Vector2 = Vector2(float(detail["size"][0]), float(detail["size"][1]))
		match detail["kind"]:
			"m07_shutter_row":
				_shutter_row(placed, size)
			"m07_market_stall":
				_awning(placed, size, _root.get_child_count())
			"m07_curfew_lamp":
				_lamp(placed)
			"m07_window_figure":
				_window_figure(placed, host)
	# The line lights from the post toward the cut, which lies north.
	lamps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["node"] as Node3D).position.z < (b["node"] as Node3D).position.z)
	for index: int in range(lamps.size()):
		(lamps[index]["node"] as Node3D).name = "CurfewLamp%d" % index
	_dome()
	_depot_tower()
	_port_behind()
	chime = AudioStreamPlayer.new()
	chime.name = "CurfewChime"
	chime.bus = &"Effects"
	chime.volume_db = -6.0
	if ResourceLoader.exists(L07Assets.CURFEW_CHIME_SOUND):
		chime.stream = load(L07Assets.CURFEW_CHIME_SOUND)
	_root.add_child(chime)
	_geometry = M07MissionState.geometry_for(info)
	ArenaSky.mark_world(_root)

## Server facts drive the curfew: the chime runs while the mission is live,
## and clearing the post starts the lamp line one fixture at a time.
func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.get("id") != MissionState.M07_ID \
		or not MissionState.validation_error({"tick": EquipmentState.MAX_EXACT_INTEGER, "state": state}, _geometry).is_empty():
		return
	_chiming = state["phase"] == "in_progress"
	var run: Variant = state.get("run")
	var identity: String = "%s:%s" % [str(run.get("id", "development")) if run is Dictionary else "development", str(state["attempt"])]
	if identity != _lamp_attempt:
		# A retry restores the dark street.
		_lamp_attempt = identity
		_lamp_known = false
		_set_lamps(0)
		_lamp_clock = -1.0
	var lit: bool = M07MissionState.lamps_lit(state["m07"])
	if not lit:
		_lamp_known = true
		if lamps_lit_count > 0:
			_set_lamps(0)
		_lamp_clock = -1.0
		return
	if _lamp_clock >= 0.0 or lamps_lit_count == lamps.size():
		return
	if not _lamp_known:
		# Joining after the post fell shows the finished line at once.
		_lamp_known = true
		_set_lamps(lamps.size())
		return
	_lamp_clock = 0.0
	_set_lamps(1)
	notice_requested.emit(tr("WORLD_M07_LATCH_LINE"))

func _process(delta: float) -> void:
	if _root == null:
		return
	var step: float = maxf(delta, 0.0)
	if _lamp_clock >= 0.0:
		_lamp_clock += step
		_set_lamps(mini(lamps.size(), 1 + floori(_lamp_clock / LAMP_INTERVAL)))
		if lamps_lit_count == lamps.size():
			_lamp_clock = -1.0
	if _chiming:
		_chime_clock += step
		if chime_count == 0 or _chime_clock >= CHIME_SECONDS:
			ring_chime()
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		listener_position = camera.global_position
	_animate_figure(step)

## One curfew chime. The first one in a visit also reads the PA line.
func ring_chime() -> void:
	chime_count += 1
	_chime_clock = 0.0
	if is_instance_valid(chime) and chime.stream != null and chime.is_inside_tree():
		chime.stop()
		chime.play()
	if chime_count == 1:
		notice_requested.emit(tr("WORLD_M07_CURFEW_PA"))

func _set_lamps(count: int) -> void:
	lamps_lit_count = clampi(count, 0, lamps.size())
	for index: int in range(lamps.size()):
		var on: bool = index < lamps_lit_count
		var lamp: Dictionary = lamps[index]
		(lamp["bulb"] as MeshInstance3D).material_override = _material(LAMP_ON if on else LAMP_OFF, on)
		(lamp["light"] as OmniLight3D).visible = on

func _lamp(placed: Transform3D) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "CurfewLamp%d" % lamps.size()
	holder.transform = placed
	_root.add_child(holder)
	MoonBackdrop._piece(holder, "Bracket", Vector3(0, 0, 0.12), Vector3(0.08, 0.08, 0.24), _material(Color("3c3f40")))
	var shade: MeshInstance3D = MoonBackdrop._piece(holder, "Shade", Vector3(0, 0.08, 0.3), Vector3(0.36, 0.12, 0.3), _material(Color("4a4c48")))
	shade.name = "Shade"
	var bulb: MeshInstance3D = MoonBackdrop._piece(holder, "Bulb", Vector3(0, -0.02, 0.3), Vector3(0.18, 0.12, 0.18), _material(LAMP_OFF))
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "LampLight"
	light.position = Vector3(0, -0.3, 0.5)
	light.light_color = LAMP_ON
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.omni_attenuation = 1.3
	light.light_cull_mask = ArenaSky.WORLD_LAYERS
	light.visible = false
	holder.add_child(light)
	lamps.append({"node": holder, "bulb": bulb, "light": light})

func _shutter_row(placed: Transform3D, size: Vector2) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "ShutterRow"
	holder.transform = placed
	_root.add_child(holder)
	var bays: int = maxi(1, floori(size.x / 2.4))
	var bay: float = size.x / bays
	for index: int in range(bays):
		var x: float = -size.x * 0.5 + bay * (index + 0.5)
		MoonBackdrop._piece(holder, "Shutter", Vector3(x, 0, 0.03), Vector3(bay - 0.3, size.y, 0.06), _material(SHUTTER))
		for rib: int in range(4):
			MoonBackdrop._piece(holder, "ShutterRib", Vector3(x, -size.y * 0.5 + size.y * (rib + 0.5) / 4.0, 0.065),
				Vector3(bay - 0.3, 0.05, 0.02), _material(SHUTTER_RIB))
		# The window above the shutter is dark: curfew.
		MoonBackdrop._piece(holder, "DarkWindow", Vector3(x, size.y * 0.5 + 1.4, 0.02), Vector3(bay * 0.5, 0.9, 0.04), _material(DARK_WINDOW))

func _awning(placed: Transform3D, size: Vector2, variant: int) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "MarketAwning"
	holder.transform = placed
	_root.add_child(holder)
	var cloth: Color = AWNINGS[posmod(variant, AWNINGS.size())]
	# Up-face basis: x along the stall, y across it, z up.
	for side: float in [-1.0, 1.0]:
		MoonBackdrop._piece(holder, "AwningPole", Vector3(side * size.x * 0.48, 0, 0.6), Vector3(0.06, 0.06, 1.2), _material(Color("4e4b45")))
	var canopy: MeshInstance3D = MoonBackdrop._piece(holder, "Canopy", Vector3(0, 0.15, 1.25), Vector3(size.x + 0.4, size.y + 0.6, 0.05), _material(cloth))
	canopy.rotation.x = 0.18
	MoonBackdrop._piece(holder, "Goods", Vector3(0, 0, 0.12), Vector3(size.x * 0.8, size.y * 0.6, 0.2), _material(Color("6f6655")))

func _window_figure(placed: Transform3D, host: Dictionary) -> void:
	_figure_out = placed.basis.z.normalized()
	var thickness: float = absf(_figure_out.dot(MapDecoration._size(host)))
	# The room floor sits under a one metre sill below the pane.
	var floor_y: float = float(host.get("bottom", MoveStep.GROUND_Y)) - 1.0
	_figure_glass = placed.origin - _figure_out * (MapDecoration.OFFSET + thickness)
	_figure_glass.y = floor_y
	_figure_origin = _figure_glass - _figure_out * 0.7
	figure = Node3D.new()
	figure.name = "WindowFigure"
	_root.add_child(figure)
	var body: Sprite3D = Sprite3D.new()
	body.name = "Resident"
	body.texture = load(PlayerBody.strip_path(PlayerBody.HUMAN)) as Texture2D
	body.hframes = PlayerBody.IDLE_FRAMES + PlayerBody.WALK_FRAMES
	body.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
	body.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	body.modulate = Color("c9b79a")
	body.position = _figure_origin + Vector3(0, EnemyAnimation.CENTRE_HEIGHT, 0)
	figure.add_child(body)
	figure_hand = MeshInstance3D.new()
	figure_hand.name = "Hand"
	var hand_mesh: BoxMesh = BoxMesh.new()
	hand_mesh.size = Vector3(0.12, 0.12, 0.12)
	figure_hand.mesh = hand_mesh
	figure_hand.material_override = _material(Color("b88965"))
	figure.add_child(figure_hand)
	# A small warm lamp behind her: the only lit window on the street.
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.name = "RoomLamp"
	lamp.position = _figure_origin - _figure_out * 1.0 + Vector3(0, 2.2, 0)
	lamp.light_color = Color("ffcf94")
	lamp.light_energy = 0.9
	lamp.omni_range = 4.0
	lamp.light_cull_mask = ArenaSky.WORLD_LAYERS
	figure.add_child(lamp)
	_place_hand(0.0)

## Tap the glass twice, then point down the side street toward the square.
## No speech and no caption: the gesture is the whole beat.
func _animate_figure(step: float) -> void:
	if figure == null:
		return
	var near: bool = listener_position.is_finite() and listener_position.distance_to(_figure_origin) <= FIGURE_RANGE
	if near and not figure_active:
		figure_active = true
		_figure_clock = 0.0
	if not figure_active:
		return
	_figure_clock = fposmod(_figure_clock + step, FIGURE_CYCLE)
	_place_hand(_figure_clock)

func _place_hand(clock: float) -> void:
	if figure_hand == null:
		return
	var glass: Vector3 = _figure_glass - _figure_out * 0.08 + Vector3(0, 1.55, 0)
	var rest: Vector3 = _figure_origin + _figure_out * 0.25 + Vector3(0, 1.2, 0)
	var along: Vector3 = Vector3(0, 0, 1)
	if clock < 1.2:
		# Two taps against the pane.
		var tap: float = absf(sin(clock / 1.2 * TAU))
		figure_hand.position = rest.lerp(glass, tap)
	else:
		# Arm out along the glass, pointing up the side street.
		var reach: float = clampf((clock - 1.2) / 0.4, 0.0, 1.0)
		figure_hand.position = glass.lerp(glass + along * 0.9 + Vector3(0, 0.15, 0), reach)

func _dome() -> void:
	var lines: ImmediateMesh = ImmediateMesh.new()
	var ribs: MeshInstance3D = MeshInstance3D.new()
	ribs.name = "PressureDomeRibs"
	ribs.mesh = lines
	# Faint ribs: the dome reads as structure without striping the sky.
	ribs.material_override = _material(Color("4d524f"), true)
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for ring: int in range(1, 6):
		var lift: float = float(ring) / 6.0 * PI * 0.5
		for segment: int in range(48):
			for corner: int in [segment, segment + 1]:
				var angle: float = float(corner) / 48.0 * TAU
				lines.surface_add_vertex(_dome_point(angle, lift))
	for meridian: int in range(16):
		var angle: float = float(meridian) / 16.0 * TAU
		for step: int in range(12):
			lines.surface_add_vertex(_dome_point(angle, float(step) / 12.0 * PI * 0.5))
			lines.surface_add_vertex(_dome_point(angle, float(step + 1) / 12.0 * PI * 0.5))
	lines.surface_end()
	ribs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(ribs)
	var shell: MeshInstance3D = MeshInstance3D.new()
	shell.name = "PressureDomeShell"
	var hemisphere: SphereMesh = SphereMesh.new()
	hemisphere.is_hemisphere = true
	hemisphere.radius = 1.0
	hemisphere.height = 1.0
	hemisphere.radial_segments = 32
	hemisphere.rings = 8
	shell.mesh = hemisphere
	shell.scale = DOME_RADII
	shell.position = DOME_CENTRE
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.62, 0.62, 0.05)
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	shell.material_override = glass
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(shell)

func _dome_point(angle: float, lift: float) -> Vector3:
	return DOME_CENTRE + Vector3(cos(angle) * cos(lift) * DOME_RADII.x,
		sin(lift) * DOME_RADII.y + 10.0, sin(angle) * cos(lift) * DOME_RADII.z)

## The depot's radial tower, across the crater: the level's compass.
func _depot_tower() -> void:
	var depot: Node3D = Node3D.new()
	depot.name = "DepotRadialTower"
	depot.position = DEPOT_TOWER
	_root.add_child(depot)
	var shell: Material = _material(Color("b1b1a4"))
	var basalt: Material = _material(Color("343b3c"))
	var red: Material = _material(Color("8c1a1e"), true)
	# Tall enough to stand over the town blocks from the tunnel mouth.
	MoonBackdrop._piece(depot, "TowerShaft", Vector3(0, 70, 0), Vector3(12, 140, 12), shell)
	MoonBackdrop._piece(depot, "TowerCrown", Vector3(0, 141, 0), Vector3(17, 2, 17), basalt)
	for index: int in range(6):
		var arm: MeshInstance3D = MoonBackdrop._piece(depot, "RadialArm", Vector3(0, 104, 16).rotated(Vector3.UP, index * TAU / 6.0),
			Vector3(3.5, 3.5, 26), basalt)
		arm.rotation.y = index * TAU / 6.0
		var wing: MeshInstance3D = MoonBackdrop._piece(depot, "RadialWing", Vector3(0, 7, 24).rotated(Vector3.UP, index * TAU / 6.0),
			Vector3(8, 14, 34), basalt)
		wing.rotation.y = index * TAU / 6.0
	MoonBackdrop._piece(depot, "BeaconLamp", Vector3(0, 143.5, 0), Vector3(2.5, 2.5, 2.5), red)
	for y: float in [25.0, 45.0, 65.0, 85.0, 105.0, 125.0]:
		MoonBackdrop._piece(depot, "TowerBand", Vector3(0, y, 0), Vector3(12.4, 0.8, 12.4), _material(Color("d8c69d"), true))

## The port behind and below: gantries and cranes beyond the town's south edge.
func _port_behind() -> void:
	var port: Node3D = Node3D.new()
	port.name = "PortBehind"
	_root.add_child(port)
	var steel: Material = _material(Color("515d5d"))
	var shell: Material = _material(Color("8f8f84"))
	for index: int in range(4):
		var x: float = -60.0 + float(index) * 26.0
		MoonBackdrop._piece(port, "CraneTower", Vector3(x, 18, -118), Vector3(3, 36, 3), steel)
		var boom: MeshInstance3D = MoonBackdrop._piece(port, "CraneBoom", Vector3(x + 6, 35, -118), Vector3(16, 1.4, 1.4), shell)
		boom.rotation.z = 0.08 * float(index % 2)
	MoonBackdrop._piece(port, "PortShell", Vector3(-20, 9, -132), Vector3(110, 18, 16), shell)
	var earth: MeshInstance3D = MeshInstance3D.new()
	earth.name = "Earth"
	var disc: QuadMesh = QuadMesh.new()
	disc.size = Vector2(26, 26)
	earth.mesh = disc
	earth.position = Vector3(-30, 70, -300)
	var planet: StandardMaterial3D = _material(Color.WHITE, true)
	planet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	planet.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if ResourceLoader.exists("res://assets/environment/moon/earth.png"):
		planet.albedo_texture = load("res://assets/environment/moon/earth.png") as Texture2D
	earth.material_override = planet
	port.add_child(earth)

static func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	return MoonBackdrop._material(color, unshaded)
