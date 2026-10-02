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
const MINE_BODY: Color = Color("2f3438")
const MINE_RIM: Color = Color("6b6f72")
const LAMP_ARMING: Color = Color("efb56e")
const LAMP_LIVE: Color = Color("ff3020")
const LAMP_DARK: Color = Color("3a1612")
var bodies: Dictionary[int, MeshInstance3D] = {}
var bursts: Array[Dictionary] = []
var voices: Array[AudioStreamPlayer3D] = []
var last_tick: int = -1
var bounce_counts: Dictionary[int, int] = {}
var bounce_cues: int = 0
var blast_cues: int = 0
var _voice_index: int = 0
var _resolved: Dictionary[int, bool] = {}
var mines: Dictionary[int, Node3D] = {}
var mine_phases: Dictionary[int, String] = {}
var stick_cues: int = 0
var lamps_lit: int = 0

## A grenade newly in flight on a live snapshot, by the participant who threw
## it. Bodies already present when a snapshot stream starts are not throws.
signal thrown(owner_id: String)

func reset() -> void:
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

func apply(snapshot: Dictionary, listener: Vector3) -> void:
	if not GrenadeFacts.validation_error(snapshot).is_empty() or not CustodyFacts.validation_error(snapshot).is_empty() \
		or int(snapshot["tick"]) <= last_tick:
		return
	var initial: bool = last_tick < 0
	last_tick = int(snapshot["tick"])
	_apply_mines(snapshot, listener, initial)
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

## Placed mines: a dark puck on its surface and a lamp that is steady while
## arming, blinks once live and flickers fast once tripped. The lamp follows
## server ticks, so every viewer sees the same blink.
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
		var body: Node3D = mines[id]
		body.position = GrenadeFacts.vector(fact["position"])
		var normal: Vector3 = GrenadeFacts.vector(fact["normal"])
		if normal.length_squared() > 0.5:
			var side: Vector3 = Vector3.RIGHT if absf(normal.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			var forward: Vector3 = side.cross(normal).normalized()
			body.basis = Basis(normal.cross(forward).normalized(), normal, forward)
		var phase: String = str(fact["phase"])
		var lamp: MeshInstance3D = body.get_node("Lamp")
		var lit: bool = CustodyFacts.lamp_lit(fact, tick)
		var colour: Color = LAMP_ARMING if phase == "arming" else (LAMP_LIVE if lit else LAMP_DARK)
		(lamp.material_override as ShaderMaterial).set_shader_parameter("effect_color", colour)
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
	var puck: MeshInstance3D = _mesh(Vector3(0.30, 0.08, 0.30), MINE_BODY)
	puck.name = "Puck"
	body.add_child(puck)
	var rim: MeshInstance3D = _mesh(Vector3(0.36, 0.04, 0.12), MINE_RIM)
	rim.name = "Rim"
	rim.position = Vector3(0, -0.02, 0)
	body.add_child(rim)
	var lamp: MeshInstance3D = _mesh(Vector3(0.09, 0.07, 0.09), LAMP_DARK)
	lamp.name = "Lamp"
	lamp.position = Vector3(0, 0.07, 0)
	body.add_child(lamp)
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
