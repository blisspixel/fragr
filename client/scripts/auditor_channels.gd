class_name AuditorChannels
extends Node3D

## Auditor repair channels as a readable world cue: a pulsing chain of pixels
## from the officer's raised hand to the disabled body it reaches, and a lamp
## per remaining repair on the shield plate. Facts come from the validated
## snapshot; the server owns every channel, snap and repair.
const SERVER_REFERENCE_Y: float = 1.5
const HAND_ABOVE_FEET: float = 1.35
const BODY_ABOVE_FEET: float = 0.3
const LINKS: int = 14
const PULSE_SECONDS: float = 0.6
const BEAM: Color = Color("ffd27a")
const BEAM_HOT: Color = Color("fff3d0")
const LAMP_ON: Color = Color("ff3020")
const LAMP_SPENT: Color = Color("3a1612")
const CLEARANCE: Shader = preload("res://assets/shaders/grenade_surface.gdshader")
## Placeholder cues from existing audio; each final asset is a one-line swap.
const CHANNEL_LOOP: AudioStream = preload("res://assets/audio/m02/ward_machine_loop.wav")
const REPAIR_DONE: AudioStream = preload("res://assets/audio/m02/restraint_release.wav")

## Pawn nodes by player id, shared with the match manager.
var pawns: Dictionary = {}
## auditor id -> {"target": String, "links": Node3D, "voice": AudioStreamPlayer3D}
var channels: Dictionary = {}
## auditor id -> repairs left, from the newest snapshot.
var budgets: Dictionary = {}
var last_tick: int = -1
var repair_cues: int = 0
var _clock: float = 0.0

func reset() -> void:
	for id: String in channels.keys():
		_drop(id)
	channels.clear()
	budgets.clear()
	last_tick = -1
	repair_cues = 0

func apply(snapshot: Dictionary) -> void:
	if not CustodyFacts.validation_error(snapshot).is_empty() or int(snapshot["tick"]) <= last_tick:
		return
	var initial: bool = last_tick < 0
	last_tick = int(snapshot["tick"])
	var live: Dictionary = {}
	for fact: Dictionary in snapshot.get("auditors", []):
		var id: String = fact["id"]
		live[id] = true
		var left: int = int(fact["repairs_left"])
		if not initial and budgets.has(id) and left < int(budgets[id]):
			repair_cues += 1
			_cue(REPAIR_DONE, id)
		budgets[id] = left
		var target: String = str(fact.get("channel_target", ""))
		if target.is_empty():
			_drop(id)
			continue
		if channels.has(id) and channels[id]["target"] == target:
			continue
		_drop(id)
		var links: Node3D = Node3D.new()
		links.name = "Channel_%s" % id.left(8)
		for index: int in range(LINKS):
			var link: MeshInstance3D = MeshInstance3D.new()
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3.ONE * 0.09
			link.mesh = mesh
			var material: ShaderMaterial = ShaderMaterial.new()
			material.shader = CLEARANCE
			material.set_shader_parameter("effect_color", BEAM)
			link.material_override = material
			link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			links.add_child(link)
		add_child(links)
		var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		voice.bus = "Effects"
		voice.max_distance = 24.0
		voice.unit_size = 3.0
		voice.volume_db = -14.0
		voice.stream = CHANNEL_LOOP
		links.add_child(voice)
		if is_inside_tree():
			voice.play()
		channels[id] = {"target": target, "links": links, "voice": voice}
	for id: String in channels.keys():
		if not live.has(id):
			_drop(id)
	for id: String in budgets.keys():
		if not live.has(id):
			budgets.erase(id)
	_lamps()

func _drop(id: String) -> void:
	if not channels.has(id):
		return
	var channel: Dictionary = channels[id]
	(channel["voice"] as AudioStreamPlayer3D).stop()
	(channel["links"] as Node3D).queue_free()
	channels.erase(id)

func _cue(stream: AudioStream, id: String) -> void:
	var pawn: Variant = pawns.get(id)
	if not is_inside_tree() or not is_instance_valid(pawn):
		return
	var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	voice.bus = "Effects"
	voice.max_distance = 24.0
	voice.volume_db = -8.0
	voice.stream = stream
	voice.position = to_local((pawn as Node3D).global_position)
	voice.finished.connect(voice.queue_free)
	add_child(voice)
	voice.play()

## Two lamps on each plate; a completed repair darkens one for good.
func _lamps() -> void:
	for id: String in budgets.keys():
		var pawn: Variant = pawns.get(id)
		if not is_instance_valid(pawn):
			continue
		var plate: Node = (pawn as Node).get_node_or_null("AuditorPlate")
		if plate == null:
			continue
		for index: int in range(CustodyFacts.MAX_REPAIRS):
			var lamp: MeshInstance3D = plate.get_node_or_null("Lamp%d" % index)
			if lamp != null and lamp.material_override is ShaderMaterial:
				(lamp.material_override as ShaderMaterial).set_shader_parameter(
					"effect_color", LAMP_ON if index < int(budgets[id]) else LAMP_SPENT)

func _process(delta: float) -> void:
	_clock = fposmod(_clock + maxf(delta, 0.0), PULSE_SECONDS)
	for id: String in channels.keys():
		var channel: Dictionary = channels[id]
		var auditor: Variant = pawns.get(id)
		var body: Variant = pawns.get(channel["target"])
		var links: Node3D = channel["links"]
		if not is_instance_valid(auditor) or not is_instance_valid(body):
			links.visible = false
			continue
		links.visible = true
		var hand: Vector3 = (auditor as Node3D).global_position + Vector3.UP * (HAND_ABOVE_FEET - SERVER_REFERENCE_Y)
		var corpse: Vector3 = (body as Node3D).global_position + Vector3.UP * (BODY_ABOVE_FEET - SERVER_REFERENCE_Y)
		(channel["voice"] as AudioStreamPlayer3D).global_position = hand
		var phase: float = _clock / PULSE_SECONDS
		for index: int in range(LINKS):
			var along: float = (float(index) + 0.5) / LINKS
			var link: MeshInstance3D = links.get_child(index) as MeshInstance3D
			# A slight sag and a travelling bright pixel read as a pull, not a shot.
			link.global_position = hand.lerp(corpse, along) + Vector3.DOWN * sin(along * PI) * 0.25
			var hot: bool = absf(along - phase) < 0.5 / LINKS
			(link.material_override as ShaderMaterial).set_shader_parameter("effect_color", BEAM_HOT if hot else BEAM)

func _exit_tree() -> void:
	for channel: Dictionary in channels.values():
		(channel["voice"] as AudioStreamPlayer3D).stop()
