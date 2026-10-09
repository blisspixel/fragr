class_name GrenadeEffects
extends Node3D

const MAX_BURSTS: int = 16
const VOICES: int = 8
const LIFETIME: float = 0.32
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

## A grenade newly in flight on a live snapshot, by the participant who threw
## it. Bodies already present when a snapshot stream starts are not throws.
signal thrown(owner_id: String)
## A mine newly in flight on a live snapshot, by the participant who placed it.
signal placed(owner_id: String)

func reset() -> void:
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
	for burst: Dictionary in bursts:
		(burst["node"] as Node3D).queue_free()
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
		or int(snapshot["tick"]) <= last_tick:
		return
	var initial: bool = last_tick < 0
	last_tick = int(snapshot["tick"])
	if remote_effects == null:
		remote_effects = RemoteMineEffects.new()
		remote_effects.name = "RemoteCharges"
		add_child(remote_effects)
	remote_effects.apply(snapshot)
	_apply_mines(snapshot, listener, initial)
	_apply_canisters(snapshot)
	var current: Dictionary[int, bool] = {}
	for fact: Dictionary in snapshot.get("grenades", []):
		var id: int = int(fact["id"])
		current[id] = true
		if not bodies.has(id):
			bodies[id] = _mesh(Vector3(0.18, 0.24, 0.18), Color("567c68"))
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
			(bursts.pop_front()["node"] as Node3D).queue_free()
		var burst: Node3D = Node3D.new()
		burst.position = position
		for index: int in range(17):
			var size: float = 0.30 if index == 0 else 0.18 + float(index % 3) * 0.03
			var pixel: MeshInstance3D = _mesh(Vector3.ONE * size, Color("e8e2d6") if index < 5 else (Color("dc8c3c") if index % 2 == 0 else Color("c45a20")))
			pixel.position = Vector3.ZERO if index == 0 else Vector3(sin(index * 2.4) * 0.54, sin(index * 1.7) * 0.40, cos(index * 2.4) * 0.40)
			burst.add_child(pixel)
		add_child(burst)
		bursts.append({"node": burst, "remaining": LIFETIME})
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
			canister.add_child(_mesh(Vector3(0.22, 0.22, 0.24), Color("a49366")))
			var seam: MeshInstance3D = _mesh(Vector3(0.23, 0.06, 0.23), Color("d74932"))
			canister.add_child(seam)
			canisters[id] = canister
			add_child(canister)
		var node: Node3D = canisters[id]
		node.position = GrenadeFacts.vector(fact["position"])
		node.rotation.z = float(fact["age_ticks"]) * 0.35
	for id: int in canisters.keys():
		if not current.has(id):
			canisters[id].queue_free()
			canisters.erase(id)

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
	var puck: MeshInstance3D = _mesh(Vector3(0.22, 0.05, 0.22), MINE_BODY)
	puck.name = "Puck"
	# Round like the drawn face, so no box corner shows past its rim.
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 0.15
	disc.bottom_radius = 0.16
	disc.height = 0.05
	disc.radial_segments = 12
	disc.rings = 1
	puck.mesh = disc
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

func _mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = CLEARANCE
	material.set_shader_parameter("effect_color", color)
	node.material_override = material
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
	for index: int in range(bursts.size() - 1, -1, -1):
		var burst: Dictionary = bursts[index]
		burst["remaining"] = float(burst["remaining"]) - maxf(delta, 0.0)
		var node: Node3D = burst["node"]
		if float(burst["remaining"]) <= 0.0:
			node.queue_free()
			bursts.remove_at(index)
		else:
			var progress: float = 1.0 - float(burst["remaining"]) / LIFETIME
			node.scale = Vector3.ONE * (1.0 + minf(progress, 0.5) * 0.6)
			for child: Node in node.get_children():
				(child as Node3D).scale = Vector3.ONE * maxf(0.15, 1.0 - maxf(progress - 0.2, 0.0) * 1.1)
