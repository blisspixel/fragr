class_name WalkerView
extends Node3D

## The machine, its warnings and projectiles follow accepted authoritative facts.
signal notice_requested(text: String)
const STEEL: Color = Color("343c40")
const EDGE: Color = Color("727b79")
const RED: Color = Color("b94b37")
const WARM: Color = Color("efd296")
const WARNING: AudioStream = preload("res://assets/audio/notary/shutter.wav")
const IMPACT: AudioStream = preload("res://assets/story/effects/grenade_blast.wav")
const Workshop = preload("res://scripts/model_geometry.gd")
var _workshop: RefCounted = Workshop.new()
var optics: Array[MeshInstance3D] = []
var geometry: Dictionary = {}
var last_tick: int = -1
var phase: String = ""
var phase_started: int = -1
var machine: Node3D
var status_label: Label3D
var stomp_ring: MeshInstance3D
var markers: Array[Node3D] = []
var vents: Array[MeshInstance3D] = []
var shutters: Array[MeshInstance3D] = []
var _shutter_raises: Array[float] = []
var pistons: Array[MeshInstance3D] = []
var shells: Dictionary[int, Node3D] = {}
var voices: Array[AudioStreamPlayer3D] = []
var _voice_index: int = 0
var _elapsed: float = 0.0
var _duration: float = 1.0
var _progress: float = 0.0
var _travel: float = 0.0
var _feet: Vector3 = Vector3.ZERO
var cue_count: int = 0

func clear_map() -> void:
	geometry.clear()
	last_tick = -1
	phase = ""
	phase_started = -1
	vents.clear()
	shutters.clear()
	_shutter_raises.clear()
	pistons.clear()
	optics.clear()
	markers.clear()
	shells.clear()
	for voice: AudioStreamPlayer3D in voices:
		voice.stop()
	voices.clear()
	_voice_index = 0
	machine = null
	status_label = null
	stomp_ring = null
	_travel = 0.0
	cue_count = 0
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("walker") is Dictionary or not MapGeometry.validation_error(info).is_empty():
		return
	geometry = info.duplicate(true)
	machine = Node3D.new()
	machine.name = "ContinuanceWalker"
	add_child(machine)
	_feet = GrenadeFacts.vector(info["walker"]["stations"][0])
	machine.position = _feet
	for ordinal: int in range(5):
		var solid: Dictionary = info["solids"][int(info["walker"]["solids"][ordinal])]
		var low := Vector3(float(solid["min_x"]), float(solid.get("bottom",0.0)), float(solid["min_z"]))
		var high := Vector3(float(solid["max_x"]), float(solid.get("top",MoveStep.WALL_TOP)), float(solid["max_z"]))
		var size_at: Vector3 = high - low
		var center: Vector3 = (low + high) * 0.5 - _feet
		if ordinal == 0:
			_build_torso(center, size_at)
		else:
			_build_leg(ordinal, center, size_at)
	var torso: Dictionary = info["solids"][int(info["walker"]["solids"][0])]
	status_label = Label3D.new()
	status_label.name = "WalkerIntegrity"
	status_label.font = WorldSign.FONT
	status_label.font_size = 28
	status_label.outline_size = 5
	status_label.outline_modulate = Color("101518")
	status_label.modulate = WARM
	status_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status_label.no_depth_test = false
	# Clear the near roof edge from ordinary player-height fighting distances.
	status_label.position = Vector3(0,float(torso.get("top",MoveStep.WALL_TOP))-_feet.y+1.65,0)
	status_label.layers = ArenaSky.WORLD_LAYERS
	status_label.visible = false
	machine.add_child(status_label)
	stomp_ring = _ring(WalkerFacts.STOMP_RADIUS, 0.20, RED)
	stomp_ring.name = "StompBoundary"
	stomp_ring.visible = false
	add_child(stomp_ring)
	for index: int in range(3):
		var marker := Node3D.new()
		marker.name = "ArtilleryTarget%d" % index
		marker.add_child(_ring(WalkerFacts.SHELL_RADIUS, 0.15, RED))
		# Crosshairs give the shell's exact locked center without color dependence.
		for axis: int in range(2):
			var bar: MeshInstance3D = _box("Crosshair", Vector3(1.2,0.035,0.10), Vector3(0,0.03,0), WARM, true)
			bar.rotation.y = float(axis) * PI * 0.5
			marker.add_child(bar)
		marker.visible = false
		markers.append(marker)
		add_child(marker)
	for index: int in range(3):
		var voice := AudioStreamPlayer3D.new()
		voice.bus = "Effects"
		voice.max_distance = 65.0
		voice.unit_size = 12.0
		voice.volume_db = -8.0
		voices.append(voice)
		add_child(voice)

func _build_torso(at: Vector3, size_at: Vector3) -> void:
	# Broad chamfered castings, recessed drive cabinets and three deep launch
	# sockets describe a purpose-built machine inside the registered body.
	var outline := PackedVector2Array()
	for point: Vector2 in [Vector2(-0.5,-0.34),Vector2(-0.39,-0.5),Vector2(0.39,-0.5),Vector2(0.5,-0.34),Vector2(0.5,0.08),Vector2(0.34,0.33),Vector2(-0.34,0.33),Vector2(-0.5,0.08)]:
		outline.append(Vector2(point.x*size_at.z*0.94,point.y*size_at.y))
	_workshop.prism(machine,"Torso",outline,size_at.x*0.94,_finish(Color("50565a")),at)
	_block("LowerChassis",Vector3(size_at.x*0.96,0.24,size_at.z*0.74),at+Vector3(0,-size_at.y*0.43,0),Color("85877c"))
	for side: float in [-1.0,1.0]:
		_block("RoofShoulder",Vector3(size_at.x*0.12,0.66,size_at.z*0.66),at+Vector3(side*size_at.x*0.40,size_at.y*0.34,0),Color("656c68"))
		# Side drive housings stay below the sloped upper shoulders.
		_block("DriveHousing",Vector3(0.16,size_at.y*0.51,size_at.z*0.70),at+Vector3(side*(size_at.x*0.5-0.08),-0.15,0),Color("777c78"))
		_block("DriveRecess",Vector3(0.17,0.72,size_at.z*0.44),at+Vector3(side*(size_at.x*0.5-0.09),-0.10,0),Color("22292b"))
		for row: int in range(5):
			_block("CoolingRib",Vector3(0.18,0.065,size_at.z*0.40),at+Vector3(side*(size_at.x*0.5-0.09),-0.36+row*0.13,0),Color("94978a"))
		for z: float in [-0.30,0.30]:
			_block("HousingFastener",Vector3(0.18,0.12,0.12),at+Vector3(side*(size_at.x*0.5-0.09),0.38,z*size_at.z),EDGE)
		var face_z: float = side*(size_at.z*0.5-0.06)
		_block("FrontApron",Vector3(size_at.x*0.78,0.75,0.09),at+Vector3(0,-0.16,face_z),Color("6b716e"))
		_block("IssuedBand",Vector3(size_at.x*0.70,0.16,0.10),at+Vector3(0,0.15,face_z),RED)
		_block("InspectionSeal",Vector3(0.48,0.46,0.11),at+Vector3(0,-0.24,face_z),Color("b2ac93"))
		for x: float in [-0.31,0.31]:
			_block("OpticRecess",Vector3(0.66,0.32,0.11),at+Vector3(x*size_at.x,-0.09,face_z),Color("151c20"))
			var optic: MeshInstance3D = _box("Optic",Vector3(0.36,0.10,0.03),at+Vector3(x*size_at.x,-0.08,side*(size_at.z*0.5-0.018)),RED,true)
			machine.add_child(optic)
			optics.append(optic)
	# Compact hollow sockets have dark inner walls rather than painted dots.
	for x: float in [-0.21,0.0,0.21]:
		var top: Vector3 = at+Vector3(x*size_at.x,size_at.y*0.5-0.28,0)
		var socket: MeshInstance3D = _workshop.lathe(machine,"ArtilleryMouth",PackedVector2Array([Vector2(-0.25,0.30),Vector2(-0.25,0.45),Vector2(-0.18,0.48),Vector2(0.18,0.48),Vector2(0.25,0.43),Vector2(0.25,0.30)]),_finish(Color("828679")),top,12)
		socket.rotation.x = PI*0.5
		_cylinder("BoreShadow",0.30,0.02,top+Vector3(0,-0.23,0),Color("11171b"))

func _build_leg(index: int, at: Vector3, size_at: Vector3) -> void:
	_block("Foot%d" % index,Vector3(size_at.x,0.28,size_at.z),Vector3(at.x,0.14,at.z),Color("8b8d7c"))
	_block("Ankle%d" % index,Vector3(size_at.x*0.65,0.46,size_at.z*0.66),Vector3(at.x,0.48,at.z),Color("343b3e"))
	_block("Shin%d" % index,Vector3(size_at.x*0.84,size_at.y*0.36,size_at.z*0.72),at+Vector3(0,-0.30,0.06),Color("5c6464"))
	_block("UpperStrut%d" % index,Vector3(size_at.x*0.72,size_at.y*0.37,size_at.z*0.80),at+Vector3(0,0.91,-0.04),Color("626965"))
	var knee: MeshInstance3D = _cylinder("Joint%d" % index,size_at.z*0.45,size_at.x*0.98,at+Vector3(0,0.27,0),Color("929385"))
	knee.rotation.z = PI*0.5
	var piston: MeshInstance3D = _cylinder("Piston%d" % index,size_at.x*0.11,size_at.y*0.54,at+Vector3(size_at.x*0.33,0.08,-size_at.z*0.28),Color("bbc0af"))
	pistons.append(piston)
	for side: float in [-1.0,1.0]:
		_block("AnkleToe",Vector3(size_at.x*0.68,0.12,0.12),Vector3(at.x,0.27,at.z+side*size_at.z*0.40),Color("343b3e"))
		var vent: MeshInstance3D = _box("RecoveryVent%d" % index,Vector3(size_at.x*0.65,size_at.y*0.22,0.035),at+Vector3(0,size_at.y*0.17,side*(size_at.z*0.5-0.05)),WARM,true)
		machine.add_child(vent)
		vents.append(vent)
		var shutter: MeshInstance3D = _box("VentShutter%d" % index,Vector3(size_at.x*0.70,size_at.y*0.25,0.03),vent.position+Vector3(0,0,side*0.032),RED)
		machine.add_child(shutter)
		shutters.append(shutter)
		_shutter_raises.append(size_at.y*0.20)
		for row: int in range(3):
			machine.add_child(_box("VentSlat",Vector3(size_at.x*0.65,0.035,0.05),vent.position+Vector3(0,(float(row)-1.0)*size_at.y*0.06,0),STEEL))

func _finish(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = _workshop.material("walker_"+color.to_html(false),color,0.12,0.88)
	material.uv1_scale = Vector3(0.20,0.20,0.20)
	return material

func _block(label: String, size_at: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	return _workshop.block(machine,label,size_at,_finish(color),at)

func _cylinder(label: String, radius: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	return _workshop.instance(machine,label,mesh,_finish(color),at)

static func _box(label: String, size_at: Vector3, at: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	return AssessorRig.part(label,size_at,at,color,glow)

static func _ring(radius: float, width: float, color: Color) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for segment: int in range(48):
		var a: float = float(segment) * TAU / 48.0
		var b: float = float(segment+1) * TAU / 48.0
		var corners: Array[Vector3] = [Vector3(cos(a)*radius,0.035,sin(a)*radius),Vector3(cos(b)*radius,0.035,sin(b)*radius),Vector3(cos(a)*(radius-width),0.035,sin(a)*(radius-width)),Vector3(cos(b)*(radius-width),0.035,sin(b)*(radius-width))]
		for index: int in [0,2,1,1,2,3]:
			vertices.append(corners[index])
			normals.append(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.layers = ArenaSky.WORLD_LAYERS
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	return node

func apply(snapshot: Dictionary) -> void:
	if geometry.is_empty() or not WalkerFacts.validation_error(snapshot,geometry).is_empty() or int(snapshot["tick"]) <= last_tick:
		return
	var value: Dictionary = snapshot["walker"]
	var next_phase: String = value["phase"]
	var initial: bool = last_tick < 0
	var changed: bool = next_phase != phase or int(value["phase_started"]) != phase_started
	var next_feet: Vector3 = GrenadeFacts.vector(value["feet"])
	if not initial:
		_travel += next_feet.distance_to(_feet)
	_feet = next_feet
	machine.position = _feet
	last_tick = int(snapshot["tick"])
	phase = next_phase
	phase_started = int(value["phase_started"])
	_update_status(int(value["hp"]),int(value["stage"]))
	_duration = maxf(1.0,float(int(value["phase_ends"])-phase_started))
	_progress = clampf(float(last_tick-phase_started)/_duration,0.0,1.0)
	_elapsed = 0.0
	stomp_ring.position = _feet
	stomp_ring.visible = phase in ["stomp_warning","stomp"]
	for index: int in range(3):
		markers[index].position = GrenadeFacts.vector(value["artillery_targets"][index])
		markers[index].visible = phase in ["artillery_warning","artillery"] or not value["shells"].is_empty()
	var current: Dictionary[int,bool] = {}
	for shell: Dictionary in value["shells"]:
		var id: int = int(shell["id"])
		current[id] = true
		if not shells.has(id):
			var body: MeshInstance3D = _box("WalkerShell%d" % id,Vector3(0.22,0.36,0.22),Vector3.ZERO,WARM,true)
			add_child(body)
			shells[id] = body
			shells[id].add_child(_box("ShellCore",Vector3(0.12,0.26,0.12),Vector3(0,0.05,0),RED))
		var node: Node3D = shells[id]
		node.position = GrenadeFacts.vector(shell["position"])
	for id: int in shells.keys():
		if not current.has(id):
			shells[id].queue_free()
			shells.erase(id)
	if changed and not initial:
		var key: String = ""
		if phase == "stomp_warning":
			key = "WALKER_STOMP_WARNING"
		elif phase == "artillery_warning":
			key = "WALKER_ARTILLERY_WARNING"
		elif phase == "recovery":
			key = "WALKER_RECOVERY"
		elif phase == "disabled":
			key = "WALKER_DISABLED"
		if not key.is_empty():
			notice_requested.emit(tr(key))
		if phase in ["stomp_warning","artillery_warning","stomp","disabled"] and not voices.is_empty():
			var voice: AudioStreamPlayer3D = voices[_voice_index % voices.size()]
			_voice_index += 1
			voice.position = _feet+Vector3(0,2,0)
			voice.stream = IMPACT if phase in ["stomp","disabled"] else WARNING
			voice.pitch_scale = 0.65 if phase == "stomp_warning" else 0.85
			voice.play()
			cue_count += 1
	_present()

func _update_status(hp: int, stage: int) -> void:
	if status_label == null:
		return
	var caption: String = tr("WALKER_INTEGRITY").format({"hp":hp,"maximum":WalkerFacts.MAX_HP,"stage":stage}) if hp > 0 else tr("WALKER_INTEGRITY_OFFLINE")
	if status_label.visible and status_label.text == caption:
		return
	status_label.text = caption
	var measured: Vector2 = WorldSign.FONT.get_multiline_string_size(status_label.text,HORIZONTAL_ALIGNMENT_CENTER,-1,28)
	status_label.pixel_size = minf(6.5/maxf(measured.x,1.0),1.15/maxf(measured.y,1.0))
	status_label.visible = true

func _process(delta: float) -> void:
	if machine == null:
		return
	_elapsed = minf(_elapsed+maxf(delta,0.0),0.10)
	_present()

func _present() -> void:
	var progress: float = clampf(_progress+_elapsed*20.0/_duration,0.0,1.0)
	for optic: MeshInstance3D in optics:
		optic.visible = phase != "disabled"
	for index: int in range(vents.size()):
		vents[index].visible = phase == "recovery"
		shutters[index].position.y = vents[index].position.y+(_shutter_raises[index] if phase == "recovery" else 0.0)
	for index: int in range(pistons.size()):
		var stroke: float = sin(_travel*4.0+float(index%2)*PI)*0.10 if phase == "relocating" else 0.0
		pistons[index].scale.y = 1.0+stroke
	if stomp_ring.visible:
		(stomp_ring.material_override as StandardMaterial3D).albedo_color = RED.lerp(WARM,progress*0.75) if phase == "stomp_warning" else WARM
	# No speculative machine displacement, target movement or damage is animated.
