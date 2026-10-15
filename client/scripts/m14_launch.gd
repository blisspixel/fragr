class_name M14Launch
extends Node3D

## Launch services and the fallen machine follow accepted mission geometry.
## Live Walker movement remains with WalkerView; this node never predicts a fall.
const Workshop = preload("res://scripts/model_geometry.gd")
const ID: String = "launch_authority"
const HELD: Color = Color("b94b37")
const RELEASED: Color = Color("e8e0c2")
signal notice_requested(text: String)
const REPORT_KEY: String = "WORLD_M14_MARA_SITES"
const FLARE_SECONDS: float = 8.0
const FLARE_GAP: float = 1.5
var _workshop: RefCounted = Workshop.new()
var _geometry: Dictionary = {}
var _lamps: Array[MeshInstance3D] = []
var _pad_material: StandardMaterial3D
var _control_sign: WorldSign
var wreck: Node3D
var state_applied: int = 0
var _map_half: float = 0.0
var _report_attempt: String = ""
var _report_known: bool = false
var _report_progress: int = 0
var _report_fired: bool = false
var _flare_elapsed: float = -1.0
var _flares: Array[Node3D] = []
var _flare_materials: Array[StandardMaterial3D] = []
var _previous_message: Dictionary = {}

func clear_map() -> void:
	_geometry.clear()
	_lamps.clear()
	_pad_material = null
	_control_sign = null
	wreck = null
	state_applied = 0
	_map_half = 0.0
	_report_attempt = ""
	_report_known = false
	_report_progress = 0
	_report_fired = false
	_previous_message.clear()
	_clear_flares()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func configure_map(info: Dictionary) -> void:
	var previous_geometry: Dictionary = _geometry.duplicate(true)
	var previous_message: Dictionary = _previous_message.duplicate(true)
	var report: Array = [_report_attempt,_report_known,_report_progress,_report_fired]
	clear_map()
	if not info.get("m14") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	if _geometry.get("id") != ID:
		_geometry.clear()
		return
	_map_half = float(info["half_extent"])
	if not previous_geometry.is_empty() and M14MissionState.same_contract(previous_geometry,_geometry):
		_previous_message = previous_message
		_report_attempt = report[0]
		_report_known = report[1]
		_report_progress = report[2]
		_report_fired = report[3]
	if info["m14"]["fallen"]:
		wreck = Node3D.new()
		wreck.name = "FallenContinuanceWalker"
		add_child(wreck)
		for ordinal: int in range(5):
			var box: AABB = _solid_bounds(info["solids"][int(info["m14"]["walker_solids"][ordinal])])
			if ordinal == 0:
				_build_fallen_hull(box)
			else:
				_build_folded_leg(box,ordinal)
	_build_launch_services(info)

static func _solid_bounds(solid: Dictionary) -> AABB:
	var low := Vector3(float(solid["min_x"]),float(solid.get("bottom",0.0)),float(solid["min_z"]))
	var high := Vector3(float(solid["max_x"]),float(solid.get("top",MoveStep.WALL_TOP)),float(solid["max_z"]))
	return AABB(low,high-low)

func _finish(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = _workshop.material("m14_"+color.to_html(false),color,0.12,0.88)
	material.uv1_scale = Vector3(0.2,0.2,0.2)
	return material

func _block(parent: Node3D,label: String,size_at: Vector3,at: Vector3,color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = _workshop.block(parent,label,size_at,_finish(color),at)
	node.layers = ArenaSky.WORLD_LAYERS
	return node

func _build_fallen_hull(box: AABB) -> void:
	var size_at: Vector3 = box.size
	var at: Vector3 = box.get_center()
	# A broad buckled lower hull retains the issue band, cooling cabinets and
	# three launch sockets. All pieces fit the accepted low wreck body.
	_block(wreck,"GroundedChassis",size_at*Vector3(0.97,0.28,0.93),Vector3(at.x,box.position.y+size_at.y*0.14,at.z),Color("85877c"))
	var outline := PackedVector2Array()
	for point: Vector2 in [Vector2(-0.48,-0.36),Vector2(-0.48,0.12),Vector2(-0.31,0.44),Vector2(0.30,0.30),Vector2(0.48,0.08),Vector2(0.48,-0.36)]:
		outline.append(Vector2(point.x*size_at.z,point.y*size_at.y))
	var hull: MeshInstance3D = _workshop.prism(wreck,"BuckledHull",outline,size_at.x*0.95,_finish(Color("50565a")),at)
	hull.layers = ArenaSky.WORLD_LAYERS
	for side: float in [-1.0,1.0]:
		_block(wreck,"CollapsedDriveCabinet",Vector3(size_at.x*0.045,size_at.y*0.55,size_at.z*0.67),at+Vector3(side*size_at.x*0.475,-size_at.y*0.03,0),Color("343c40"))
		for row: int in range(4):
			_block(wreck,"CoolingRib",Vector3(size_at.x*0.047,size_at.y*0.035,size_at.z*0.53),at+Vector3(side*size_at.x*0.475,size_at.y*(-0.20+row*0.12),0),Color("727b79"))
		_block(wreck,"IssuedBand",Vector3(size_at.x*0.72,size_at.y*0.09,size_at.z*0.015),at+Vector3(0,-size_at.y*0.11,side*size_at.z*0.49),HELD)
		_block(wreck,"ColdOpticRecess",Vector3(size_at.x*0.15,size_at.y*0.13,size_at.z*0.017),at+Vector3(side*size_at.x*0.27,-size_at.y*0.27,-size_at.z*0.49),Color("11171b"))
	for x: float in [-0.21,0.0,0.21]:
		var radius: float = minf(size_at.y*0.22,size_at.x*0.075)
		var mouth: Vector3 = at+Vector3(x*size_at.x,size_at.y*0.03,-size_at.z*0.465)
		var socket: MeshInstance3D = _workshop.lathe(wreck,"SpentArtilleryMouth",PackedVector2Array([
			Vector2(-size_at.z*0.03,radius*0.65),Vector2(-size_at.z*0.03,radius),
			Vector2(size_at.z*0.03,radius),Vector2(size_at.z*0.03,radius*0.65)]),_finish(Color("828679")),mouth,12)
		socket.layers = ArenaSky.WORLD_LAYERS
		_block(wreck,"ColdBore",Vector3(radius*1.35,radius*1.35,0.02),mouth-Vector3(0,0,size_at.z*0.023),Color("11171b"))
	_block(wreck,"InspectionSeal",Vector3(size_at.x*0.08,size_at.y*0.19,size_at.z*0.017),at+Vector3(0,-size_at.y*0.29,-size_at.z*0.49),Color("b2ac93"))

func _build_folded_leg(box: AABB,ordinal: int) -> void:
	var at: Vector3 = box.get_center()
	var size_at: Vector3 = box.size
	var side: float = -1.0 if ordinal in [1,2] else 1.0
	_block(wreck,"FoldedStrut%d" % ordinal,size_at*Vector3(0.95,0.56,0.65),at+Vector3(0,-size_at.y*0.17,0),Color("626965"))
	_block(wreck,"GroundedFoot%d" % ordinal,size_at*Vector3(0.29,0.22,0.93),at+Vector3(side*size_at.x*0.34,-size_at.y*0.39,0),Color("8b8d7c"))
	var hub := CylinderMesh.new()
	hub.top_radius = minf(size_at.x*0.27,size_at.z*0.40)
	hub.bottom_radius = hub.top_radius
	hub.height = size_at.y*0.72
	hub.radial_segments = 12
	hub.rings = 1
	var joint: MeshInstance3D = _workshop.instance(wreck,"FoldedJoint%d" % ordinal,hub,_finish(Color("929385")),at+Vector3(-side*size_at.x*0.15,size_at.y*0.06,0))
	joint.layers = ArenaSky.WORLD_LAYERS
	_block(wreck,"ClosedJointShutter%d" % ordinal,size_at*Vector3(0.26,0.12,0.65),at+Vector3(side*size_at.x*0.16,size_at.y*0.23,0),HELD)
	_block(wreck,"RetainedActuator%d" % ordinal,size_at*Vector3(0.62,0.13,0.11),at+Vector3(0,size_at.y*0.08,size_at.z*0.37),Color("bbc0af"))

## Cosmetic panels only bind to the retained authored host they were fitted to.
## Unknown revisions omit the detail instead of placing floating hardware.
static func _host(info: Dictionary,low: Vector3,high: Vector3) -> bool:
	for solid: Dictionary in info["solids"]:
		var box: AABB = _solid_bounds(solid)
		if box.position.is_equal_approx(low) and box.end.is_equal_approx(high):
			return true
	return false

func _panel(label: String,at: Vector3,size_at: Vector2,color: Color,yaw: float = PI) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	panel.name = label
	var mesh := QuadMesh.new()
	mesh.size = size_at
	panel.mesh = mesh
	panel.material_override = _finish(color)
	panel.position = at
	panel.rotation.y = yaw
	panel.layers = ArenaSky.WORLD_LAYERS
	add_child(panel)
	return panel

func _sign(label: String,key: String,at: Vector3,size_at: Vector2) -> WorldSign:
	var sign := WorldSign.new()
	sign.name = label
	sign.configure(key,size_at,MenuTheme.BONE)
	sign.position = at
	sign.rotation.y = PI
	sign.layers = ArenaSky.WORLD_LAYERS
	sign.no_depth_test = false
	add_child(sign)
	return sign

func _lamp(label: String,at: Vector3,size_at: Vector2,floor_face: bool = false) -> void:
	var lamp: MeshInstance3D = _panel(label,at,size_at,HELD)
	lamp.material_override = _pad_material
	if floor_face:
		lamp.rotation = Vector3(-PI*0.5,0,0)
	_lamps.append(lamp)

func _build_launch_services(info: Dictionary) -> void:
	_pad_material = StandardMaterial3D.new()
	_pad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pad_material.albedo_color = HELD
	_pad_material.emission_enabled = true
	_pad_material.emission = HELD*0.3
	if _host(info,Vector3(22,0,38),Vector3(37,0.2,49)):
		for x: float in [23,25,27,29,31,33,35,36]:
			_lamp("PadEdgeLamp",Vector3(x,0.212,38.4),Vector2(0.36,0.55),true)
	for x: float in [0,10]:
		if _host(info,Vector3(x,0,41),Vector3(x+1,28,42)):
			for y: float in [8,16,24]:
				_lamp("GantryBeacon",Vector3(x+0.5,y,40.988),Vector2(0.64,0.30))
	if _host(info,Vector3(2,0,46.5),Vector3(8,3.2,47)):
		_panel("PadControlPlate",Vector3(5,2.5,46.488),Vector2(4.8,0.65),Color("202a2c"))
		_control_sign = _sign("PadControlSign","M14_PAD_HELD",Vector3(5,2.5,46.478),Vector2(4.4,0.48))
	if _host(info,Vector3(-40,0,-16.4),Vector3(-31,3.5,-16)):
		_panel("DepotServicePlate",Vector3(-35.5,2.8,-16.412),Vector2(5.8,0.56),Color("343c40"))
		_sign("DepotServiceSign","M14_LAUNCH_SERVICES",Vector3(-35.5,2.8,-16.422),Vector2(5.4,0.43))
	if _host(info,Vector3(26.5,5,39.7),Vector3(32.5,12,45.3)):
		# Retained cargo-spine faces carry individually repaired modules and
		# restraints. These are fitted surfaces, not new invisible obstacles.
		for column: int in range(3):
			for row: int in range(3):
				var center := Vector3(27.5+column*2,6.15+row*1.9,39.688)
				var tint: Color = [Color("a9b0a2"),Color("879b9a"),Color("b4ad96")][(column+row)%3]
				_panel("CargoModule",center,Vector2(1.78,1.64),tint)
				for dx: float in [-0.60,0.60]:
					_panel("CargoRestraint",center+Vector3(dx,0,-0.008),Vector2(0.10,1.64),Color("343c40"))
				_panel("CargoHandle",center+Vector3(0,-0.38,-0.009),Vector2(0.38,0.12),Color("343c40"))
		_panel("CargoManifestPlate",Vector3(29.5,11.6,39.675),Vector2(5.5,0.48),Color("343c40"))
		_sign("CargoManifest","M14_SETTLEMENT_CARGO",Vector3(29.5,11.6,39.665),Vector2(5.1,0.34))

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.get("id") != ID or not state.get("m14") is Dictionary \
		or not MissionState.validation_error({"tick":EquipmentState.MAX_EXACT_INTEGER,"state":state},_geometry,_previous_message).is_empty():
		return
	_previous_message = {"tick":EquipmentState.MAX_EXACT_INTEGER,"state":state.duplicate(true)}
	state_applied += 1
	_update_overlook(state)
	var released: bool = state["m14"]["machine_fallen"]
	var ink: Color = RELEASED if released else HELD
	_pad_material.albedo_color = ink
	_pad_material.emission = ink*0.3
	if _control_sign != null:
		var key: String = "M14_PAD_RELEASED" if released else "M14_PAD_HELD"
		if _control_sign.message_key != key:
			_control_sign.configure(key,_control_sign.bounds,MenuTheme.BONE)

func _update_overlook(state: Dictionary) -> void:
	var run: Dictionary = state.get("run",{})
	var identity: String = "%s:%s" % [str(run.get("id","development")),str(state["attempt"])]
	if identity != _report_attempt:
		_clear_flares()
		_report_attempt = identity
		_report_known = false
		_report_fired = false
	var progress: int = state["m14"]["completed"].size()
	var active: bool = state["phase"] == "in_progress"
	# A newly hydrated late spectator does not hear an old victory as it happens.
	# Only accepted progression introduces this beat; neither a local timer nor
	# the flare can activate the Walker or delay an already active encounter.
	if active and progress == 4 and _report_known and _report_progress < 4 \
		and not _report_fired and not state["m14"]["challenges"]["walker_disabled"] \
		and not state["m14"]["machine_fallen"]:
		_report_fired = true
		notice_requested.emit(tr(REPORT_KEY))
		_start_flares()
	_report_known = true
	_report_progress = progress
	if not active or state["m14"]["machine_fallen"]:
		_clear_flares()

func _clear_flares() -> void:
	_flare_elapsed = -1.0
	for flare: Node3D in _flares:
		remove_child(flare)
		flare.queue_free()
	_flares.clear()
	_flare_materials.clear()

func _start_flares() -> void:
	_clear_flares()
	_flare_elapsed = 0.0
	for index: int in range(2):
		var flare := Node3D.new()
		flare.name = "OtherSiteFlare%d" % (index+1)
		# Horizon presentation only. Entire shapes remain beyond playable bounds.
		flare.position = Vector3((-1.0 if index==0 else 1.0)*(_map_half+24.0),12.0,_map_half+55.0)
		add_child(flare)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.96,0.83,0.57,0.0)
		var core := SphereMesh.new()
		core.radius = 0.85
		core.height = 1.7
		core.radial_segments = 8
		core.rings = 4
		var mesh := MeshInstance3D.new()
		mesh.name = "FlareCore"
		mesh.mesh = core
		mesh.material_override = material
		mesh.layers = ArenaSky.WORLD_LAYERS
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flare.add_child(mesh)
		var trail := CylinderMesh.new()
		trail.top_radius = 0.13
		trail.bottom_radius = 0.03
		trail.height = 5.0
		trail.radial_segments = 6
		var tail := MeshInstance3D.new()
		tail.name = "FlareTrail"
		tail.mesh = trail
		tail.position.y = -3.1
		tail.material_override = material
		tail.layers = ArenaSky.WORLD_LAYERS
		tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flare.add_child(tail)
		_flares.append(flare)
		_flare_materials.append(material)
	_advance_flares(0.0)

func _process(delta: float) -> void:
	_advance_flares(delta)

func _advance_flares(delta: float) -> void:
	if _flare_elapsed < 0.0:
		return
	_flare_elapsed += maxf(0.0,delta)
	for index: int in range(_flares.size()):
		var age: float = _flare_elapsed-float(index)*FLARE_GAP
		var flare: Node3D = _flares[index]
		flare.visible = age >= 0.0 and age < FLARE_SECONDS
		flare.position.y = 12.0+clampf(age,0.0,FLARE_SECONDS)*1.6
		var ink: Color = _flare_materials[index].albedo_color
		ink.a = clampf(minf(age/1.2,(FLARE_SECONDS-age)/2.0),0.0,1.0)
		_flare_materials[index].albedo_color = ink
	if _flare_elapsed >= FLARE_SECONDS+FLARE_GAP:
		_clear_flares()
