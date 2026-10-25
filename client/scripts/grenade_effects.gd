class_name GrenadeEffects
extends Node3D

const MAX_BURSTS: int = 16
const VOICES: int = 8
## A blast's fire, the part a burst record tracks; smoke outlives it.
const LIFETIME: float = BlastVfx.FIRE_SECONDS
## Rockets in flight that also carry a small exhaust light; the rest fly
## with their flame sprite alone, so a volley never floods the light budget.
const ROCKET_LIGHTS: int = 2
## Metres between trail puffs; a jump longer than the reset distance (a
## corrected position) starts the trail afresh instead of filling the gap.
const TRAIL_SPACING: float = 0.35
const TRAIL_RESET_METRES: float = 3.0
## The longest a rocket is carried forward along its server velocity
## between snapshots.
const ROCKET_LEAD_SECONDS: float = 0.1
## A round this close to the eye is not drawn.
const ROCKET_EYE_CLEARANCE: float = 1.6
const CLEARANCE: Shader = preload("res://assets/shaders/grenade_surface.gdshader")
const BOUNCE: AudioStream = preload("res://assets/story/effects/grenade_bounce.wav")
const BLAST: AudioStream = preload("res://assets/story/effects/grenade_blast.wav")
## Per-device cues, keyed by the device a resolved blast radius names. The
## proximity mine entries are placeholders from existing audio; each final
## asset is a one-line swap here.
const BLASTS: Dictionary = {4.0: BLAST, 4.5: BLAST}
const MINE_STICK: AudioStream = preload("res://assets/audio/notary/shutter.wav")
const THROW: AudioStream = preload("res://assets/audio/grenade/throw.wav")
## The dark body under the device's face-on picture gives it thickness from
## low angles; the picture itself, lamp included, comes from `WeaponArt`.
const MINE_BODY: Color = Color("2c2d32")
var bodies: Dictionary[int, MeshInstance3D] = {}
var bursts: Array[Dictionary] = []
var voices: Array[AudioStreamPlayer3D] = []
var last_tick: int = -1
var bounce_counts: Dictionary[int, int] = {}
var bounce_cues: int = 0
var blast_cues: int = 0
var throw_cues: int = 0
var _voice_index: int = 0
var _resolved: Dictionary[int, bool] = {}
var mines: Dictionary[int, Node3D] = {}
var mine_phases: Dictionary[int, String] = {}
var stick_cues: int = 0
var lamps_lit: int = 0
var remote_effects: RemoteMineEffects
var canisters: Dictionary[int, Node3D] = {}
var rockets: Dictionary[int, Node3D] = {}
var _rocket_launches: Array[Dictionary] = []
## Per rocket: the last server position, its velocity and the seconds since.
var _rocket_flight: Dictionary[int, Dictionary] = {}
var blast: BlastVfx = BlastVfx.new()

## A grenade newly in flight on a live snapshot, by the participant who threw
## it. Bodies already present when a snapshot stream starts are not throws.
signal thrown(owner_id: String)
## A mine newly in flight on a live snapshot, by the participant who placed it.
signal placed(owner_id: String)
## A resolved blast shown at `position`, for the camera's kick.
signal exploded(position: Vector3, radius: float)

func _init() -> void:
	add_child(blast)

## Shared surface marks: blasts leave their scorch here.
func set_decals(decals: VfxDecals) -> void:
	blast.decals = decals

func reset() -> void:
	for rocket: Node3D in rockets.values():
		rocket.queue_free()
	rockets.clear()
	_rocket_flight.clear()
	_rocket_launches.clear()
	blast.clear()
	for canister: Node3D in canisters.values():
		canister.queue_free()
	canisters.clear()
	if remote_effects != null:
		remote_effects.reset()
	for body: MeshInstance3D in bodies.values():
		body.queue_free()
	bodies.clear()
	for mine: Node3D in mines.values():
		mine.queue_free()
	mines.clear()
	mine_phases.clear()
	stick_cues = 0
	lamps_lit = 0
	bursts.clear()
	bounce_counts.clear()
	_resolved.clear()
	for voice: AudioStreamPlayer3D in voices:
		voice.stop()
	last_tick = -1
	bounce_cues = 0
	blast_cues = 0
	throw_cues = 0

func apply(snapshot: Dictionary, listener: Vector3) -> void:
	if not GrenadeFacts.validation_error(snapshot).is_empty() or not CustodyFacts.validation_error(snapshot).is_empty() \
		or not AssessorFacts.validation_error(snapshot).is_empty() \
		or not RocketFacts.validation_error(snapshot).is_empty() \
		or int(snapshot["tick"]) <= last_tick:
		return
	var initial: bool = last_tick < 0
	var previous_tick: int = last_tick
	last_tick = int(snapshot["tick"])
	if remote_effects == null:
		remote_effects = RemoteMineEffects.new()
		remote_effects.name = "RemoteCharges"
		add_child(remote_effects)
	remote_effects.apply(snapshot)
	_apply_mines(snapshot, listener, initial)
	_apply_canisters(snapshot)
	_apply_rockets(snapshot, previous_tick)
	var current: Dictionary[int, bool] = {}
	for fact: Dictionary in snapshot.get("grenades", []):
		var id: int = int(fact["id"])
		current[id] = true
		if not bodies.has(id):
			bodies[id] = _round(0.08, 0.2, ShotVfx.GRENADE_SKIN)
			bodies[id].name = "Grenade_%d" % id
			add_child(bodies[id])
			if not initial:
				thrown.emit(str(fact["owner_id"]))
				# A body first seen after synchronization has just left a hand.
				if listener.is_finite():
					_sound(THROW, GrenadeFacts.vector(fact["position"]), listener)
					throw_cues += 1
		bodies[id].position = GrenadeFacts.vector(fact["position"])
		if bounce_counts.has(id) and int(fact["bounce_count"]) > bounce_counts[id] and listener.is_finite():
			_sound(BOUNCE, bodies[id].position, listener)
			bounce_cues += 1
		bounce_counts[id] = int(fact["bounce_count"])
	for id: int in bodies.keys():
		if not current.has(id):
			bodies[id].queue_free()
			bodies.erase(id)
			bounce_counts.erase(id)
	# Initial snapshots synchronize old facts. A resolved explosion on a newer
	# tick can be shown even after its owner has died or left the roster.
	if initial:
		for fact: Dictionary in snapshot.get("explosions", []):
			_resolved[int(fact["id"])] = true
		return
	for fact: Dictionary in snapshot.get("explosions", []):
		var id: int = int(fact["id"])
		if _resolved.has(id):
			continue
		_resolved[id] = true
		if _resolved.size() > 256:
			_resolved.erase(_resolved.keys()[0])
		var position: Vector3 = GrenadeFacts.vector(fact["position"])
		if bursts.size() >= MAX_BURSTS:
			bursts.pop_front()
		var radius: float = float(fact["radius"])
		blast.blast(position, radius, id)
		bursts.append({"position": position, "remaining": LIFETIME})
		exploded.emit(position, radius)
		if listener.is_finite():
			_sound(BLASTS.get(float(fact["radius"]), BLAST), position, listener)
			blast_cues += 1

func _apply_canisters(snapshot: Dictionary) -> void:
	var current: Dictionary[int, bool] = {}
	for fact: Dictionary in snapshot.get("assessor_canisters", []):
		var id: int = int(fact["id"])
		current[id] = true
		if not canisters.has(id):
			var canister: Node3D = Node3D.new()
			canister.name = "AssessorCanister_%d" % id
			var shell: MeshInstance3D = _round(0.12, 0.24, ShotVfx.CANISTER_SKIN)
			shell.rotation.x = PI * 0.5
			canister.add_child(shell)
			canisters[id] = canister
			add_child(canister)
		var node: Node3D = canisters[id]
		node.position = GrenadeFacts.vector(fact["position"])
		node.rotation.z = float(fact["age_ticks"]) * 0.35
	for id: int in canisters.keys():
		if not current.has(id):
			canisters[id].queue_free()
			canisters.erase(id)

## A traveling rocket is a modelled round aligned with the server velocity,
## its flame lit at the tail and smoke left behind it. Between snapshots it
## is carried forward along that velocity for at most a tick or two, so it
## flies smoothly; the next snapshot's position always wins. The blast plays
## when it resolves.
func _apply_rockets(snapshot: Dictionary, previous_tick: int) -> void:
	_rocket_launches.clear()
	var current: Dictionary[int, bool] = {}
	for fact: Dictionary in snapshot.get("rockets", []):
		var id: int = int(fact["id"])
		current[id] = true
		if not rockets.has(id):
			# Do not announce synchronized or old reappearing bodies as launches.
			if previous_tick >= 0 and int(snapshot["tick"]) - int(fact["age_ticks"]) > previous_tick:
				_rocket_launches.append({"owner_id": str(fact["owner_id"]), "tick": int(snapshot["tick"])})
			var body: Node3D = _rocket_body(rockets.size() < ROCKET_LIGHTS)
			body.name = "Rocket_%d" % id
			rockets[id] = body
			add_child(body)
		var node: Node3D = rockets[id]
		var velocity: Vector3 = GrenadeFacts.vector(fact["velocity"])
		_rocket_flight[id] = {"position": GrenadeFacts.vector(fact["position"]), "velocity": velocity,
			"since": 0.0, "laid": _rocket_flight.get(id, {}).get("laid", Vector3.INF),
			"puffs": int(_rocket_flight.get(id, {}).get("puffs", 0))}
		node.position = GrenadeFacts.vector(fact["position"])
		if velocity.length_squared() > 0.01:
			var forward: Vector3 = velocity.normalized()
			var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
			node.basis = Basis.looking_at(forward, up)
	for id: int in rockets.keys():
		if not current.has(id):
			rockets[id].queue_free()
			rockets.erase(id)
			_rocket_flight.erase(id)

## The round: an olive body with a stencil band, a dark nose cone, four tail
## fins, and a flickering ember flame at the tail. The model's nose is -Z,
## the way `Basis.looking_at` points it along the velocity.
func _rocket_body(lit: bool) -> Node3D:
	var rocket: Node3D = Node3D.new()
	var skin: StandardMaterial3D = _skin(ShotVfx.ROCKET_SKIN)
	var body: MeshInstance3D = _round(0.065, 0.36, ShotVfx.ROCKET_SKIN)
	body.name = "Body"
	body.rotation.x = -PI * 0.5
	rocket.add_child(body)
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.065
	cone.height = 0.16
	cone.radial_segments = 8
	cone.rings = 1
	var nose: MeshInstance3D = MeshInstance3D.new()
	nose.name = "Nose"
	nose.mesh = cone
	# The skin's dark tail rows, stretched over the cone: a gunmetal warhead.
	var warhead: StandardMaterial3D = _skin(ShotVfx.ROCKET_SKIN)
	warhead.uv1_scale = Vector3(1.0, 0.1, 1.0)
	warhead.uv1_offset = Vector3(0.0, 0.83, 0.0)
	nose.material_override = warhead
	nose.rotation.x = -PI * 0.5
	nose.position = Vector3(0, 0, -0.26)
	nose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rocket.add_child(nose)
	for quarter: int in range(4):
		var fin_mesh: BoxMesh = BoxMesh.new()
		fin_mesh.size = Vector3(0.012, 0.09, 0.1)
		var fin: MeshInstance3D = MeshInstance3D.new()
		fin.name = "Fin%d" % quarter
		fin.mesh = fin_mesh
		fin.material_override = skin
		fin.rotation.z = quarter * PI * 0.5
		fin.position = Vector3(0, 0, 0.14) + Vector3(0, 0.09, 0).rotated(Vector3.BACK, quarter * PI * 0.5)
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rocket.add_child(fin)
	var flame: Sprite3D = Sprite3D.new()
	flame.name = "Flame"
	flame.texture = ShotVfx.ROCKET_FLAME
	flame.hframes = 2
	flame.pixel_size = 0.022
	flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame.shaded = false
	flame.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	flame.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.position = Vector3(0, 0, 0.26)
	rocket.add_child(flame)
	if lit:
		var glow: OmniLight3D = OmniLight3D.new()
		glow.name = "Exhaust"
		glow.light_color = ShotVfx.BLAST_LIGHT
		glow.light_energy = 0.8
		glow.omni_range = 3.2
		glow.shadow_enabled = false
		glow.position = Vector3(0, 0, 0.4)
		rocket.add_child(glow)
	return rocket

## Carries rockets along their velocity between snapshots, flickers their
## flames and lays their smoke.
func _fly_rockets(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye: Vector3 = to_local(camera.get_camera_transform().origin) if is_instance_valid(camera) else Vector3.INF
	for id: int in rockets.keys():
		var flight: Dictionary = _rocket_flight.get(id, {})
		if flight.is_empty():
			continue
		var node: Node3D = rockets[id]
		flight["since"] = float(flight["since"]) + delta
		var velocity: Vector3 = flight["velocity"]
		node.position = (flight["position"] as Vector3) + velocity * minf(float(flight["since"]), ROCKET_LEAD_SECONDS)
		# A round just leaving the viewer's own launcher would fill the lens
		# with its flame; the held tube's flash covers that moment.
		node.visible = eye == Vector3.INF or node.position.distance_to(eye) > ROCKET_EYE_CLEARANCE
		var flame: Sprite3D = node.get_node_or_null("Flame") as Sprite3D
		if flame != null:
			flame.frame = int(Time.get_ticks_msec() / 45) % 2
		# Puffs at a fixed spacing along the path flown, so the trail is one
		# even column at any frame rate or speed.
		var forward: Vector3 = -node.basis.z
		var tail: Vector3 = node.position - forward * 0.34
		var laid: Vector3 = flight.get("laid", tail)
		var gap: float = laid.distance_to(tail)
		if gap > TRAIL_RESET_METRES:
			laid = tail
			gap = 0.0
			if node.visible:
				blast.trail(laid, forward, id * 131)
		while gap >= TRAIL_SPACING:
			laid = laid.move_toward(tail, TRAIL_SPACING)
			gap -= TRAIL_SPACING
			flight["puffs"] = int(flight["puffs"]) + 1
			if node.visible:
				blast.trail(laid, forward, id * 131 + int(flight["puffs"]))
		flight["laid"] = laid

## The manager drains after syncing pawns, before it reconciles local fire.
func take_rocket_launches() -> Array[Dictionary]:
	var launches: Array[Dictionary] = _rocket_launches
	_rocket_launches = []
	return launches

## Placed mines: the face-on device laid on its surface over a dark body, its
## lamp steady amber while arming, blinking red once live and flickering fast
## once tripped. The lamp follows server ticks, so every viewer sees the same
## blink.
func _apply_mines(snapshot: Dictionary, listener: Vector3, initial: bool) -> void:
	var tick: int = int(snapshot["tick"])
	var current: Dictionary[int, bool] = {}
	lamps_lit = 0
	for fact: Dictionary in snapshot.get("mines", []):
		var id: int = int(fact["id"])
		current[id] = true
		if not mines.has(id):
			mines[id] = _mine_body()
			mines[id].name = "Mine_%d" % id
			add_child(mines[id])
			if not initial:
				placed.emit(str(fact["owner_id"]))
		var body: Node3D = mines[id]
		body.position = GrenadeFacts.vector(fact["position"])
		var normal: Vector3 = GrenadeFacts.vector(fact["normal"])
		if normal.length_squared() > 0.5:
			var side: Vector3 = Vector3.RIGHT if absf(normal.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			var forward: Vector3 = side.cross(normal).normalized()
			body.basis = Basis(normal.cross(forward).normalized(), normal, forward)
		var phase: String = str(fact["phase"])
		var lit: bool = CustodyFacts.lamp_lit(fact, tick)
		(body.get_node("Face") as Sprite3D).texture = WeaponArt.mine_device(phase, lit)
		lamps_lit += int(lit)
		if not initial and mine_phases.get(id, "") == "flying" and phase == "arming" and listener.is_finite():
			_sound(MINE_STICK, body.position, listener)
			stick_cues += 1
		mine_phases[id] = phase
	for id: int in mines.keys():
		if not current.has(id):
			mines[id].queue_free()
			mines.erase(id)
			mine_phases.erase(id)

func _mine_body() -> Node3D:
	var body: Node3D = Node3D.new()
	# Round like the drawn face, so no box corner shows past its rim.
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 0.15
	disc.bottom_radius = 0.16
	disc.height = 0.05
	disc.radial_segments = 12
	disc.rings = 1
	var puck: MeshInstance3D = MeshInstance3D.new()
	puck.name = "Puck"
	puck.mesh = disc
	var dark: ShaderMaterial = ShaderMaterial.new()
	dark.shader = CLEARANCE
	dark.set_shader_parameter("effect_color", MINE_BODY)
	puck.material_override = dark
	puck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puck.position = Vector3(0, 0.025, 0)
	body.add_child(puck)
	var face: Sprite3D = Sprite3D.new()
	face.name = "Face"
	face.texture = WeaponArt.mine_device("flying", false)
	face.axis = Vector3.AXIS_Y
	face.pixel_size = WeaponArt.MINE_DEVICE_METRES / float(face.texture.get_width())
	face.shaded = false
	face.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.position = Vector3(0, 0.052, 0)
	body.add_child(face)
	return body

func _exit_tree() -> void:
	for voice: AudioStreamPlayer3D in voices:
		voice.stop()
		voice.stream = null

## A lit, nearest-sampled skin from the baked effect set.
func _skin(texture: Texture2D) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.85
	return material

## A small skinned cylinder along local Y: a grenade, canister or rocket body.
func _round(radius: float, height: float, texture: Texture2D) -> MeshInstance3D:
	var shape: CylinderMesh = CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 8
	shape.rings = 1
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = shape
	node.material_override = _skin(texture)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _sound(stream: AudioStream, position: Vector3, listener: Vector3) -> void:
	if not is_inside_tree() or position.distance_to(listener) > 32.0:
		return
	if voices.size() < VOICES:
		var added: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		added.bus = "Effects"
		added.max_distance = 32.0
		added.unit_size = 3.0
		added.volume_db = -8.0
		add_child(added)
		voices.append(added)
	var voice: AudioStreamPlayer3D = voices[_voice_index % voices.size()]
	_voice_index += 1
	voice.stop()
	voice.position = position
	voice.stream = stream
	voice.play()

func _process(delta: float) -> void:
	var step: float = maxf(delta, 0.0)
	for index: int in range(bursts.size() - 1, -1, -1):
		var burst: Dictionary = bursts[index]
		burst["remaining"] = float(burst["remaining"]) - step
		if float(burst["remaining"]) <= 0.0:
			bursts.remove_at(index)
	_fly_rockets(step)
