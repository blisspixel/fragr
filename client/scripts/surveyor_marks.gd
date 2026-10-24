class_name SurveyorMarks
extends Node3D

## Server Surveyor discs drawn as light on the ground: a pale disc with a
## muted cyan rim, a real spot light from the lens and a faint beam. The
## server owns every disc's centre, lifetime and tracking; this only draws.
const INVALID: String = "Invalid Surveyor mark snapshot."
const MAX_MARKS: int = 8
const RADIUS: float = 3.0
const DISC_SHADER: Shader = preload("res://assets/shaders/surveyor_disc.gdshader")
const LIGHT: Color = Color("e6ecdf")
## Seconds to glide a disc toward a newer server centre.
const GLIDE: float = 0.1

class Mark extends RefCounted:
	var disc: MeshInstance3D
	var material: ShaderMaterial
	var spot: SpotLight3D
	var beam: MeshInstance3D
	var target: Vector3
	var lens: Vector3
	var tracking: bool = true
	var seen: int = 0

var marks: Dictionary[String, Mark] = {}
var _clock: float = 0.0
var _snapshot_tick: int = -1

static func validation_error(snapshot: Dictionary) -> String:
	var facts: Variant = snapshot.get("surveyor_marks", [])
	if not facts is Array or facts.size() > MAX_MARKS:
		return INVALID
	if facts.is_empty():
		return ""
	var actors: Variant = snapshot.get("players")
	if not actors is Array or not EquipmentState.integer(snapshot.get("tick"), EquipmentState.MAX_EXACT_INTEGER):
		return INVALID
	var surveyors: Dictionary[String, bool] = {}
	for actor: Variant in actors:
		if actor is Dictionary and ActorState.is_hostile(actor) and actor["campaign"].get("kind") == "surveyor" \
			and actor["campaign"].get("phase") == "firing":
			surveyors[str(actor.get("id", ""))] = true
	var seen: Dictionary[String, bool] = {}
	for fact: Variant in facts:
		if not M03MissionState._exact(fact, ["id", "center", "radius", "since", "until", "tracking"]) \
			or not MissionState._uuid(fact["id"]) or not surveyors.has(str(fact["id"])) or seen.has(str(fact["id"])) \
			or not GrenadeFacts.point(fact["center"]) or absf(float(fact["center"][0])) > 512.0 \
			or absf(float(fact["center"][2])) > 512.0 or float(fact["center"][1]) < 0.0 or float(fact["center"][1]) > 512.0 \
			or not MapGeometry._number(fact["radius"]) or absf(float(fact["radius"]) - RADIUS) > 0.001 \
			or not EquipmentState.integer(fact["since"], int(snapshot["tick"])) \
			or not EquipmentState.integer(fact["until"], EquipmentState.MAX_EXACT_INTEGER) \
			or int(fact["until"]) <= int(fact["since"]) or not fact["tracking"] is bool:
			return INVALID
		seen[str(fact["id"])] = true
	return ""

func clear() -> void:
	for key: String in marks.keys():
		_retire(key)
	marks.clear()
	_snapshot_tick = -1

func apply_snapshot(snapshot: Dictionary) -> void:
	if not validation_error(snapshot).is_empty():
		return
	var tick: int = int(snapshot.get("tick", 0))
	if tick <= _snapshot_tick:
		return
	_snapshot_tick = tick
	var lenses: Dictionary[String, Vector3] = {}
	for actor: Variant in snapshot.get("players", []):
		if actor is Dictionary and ActorState.is_hostile(actor) and actor["campaign"].get("kind") == "surveyor":
			lenses[str(actor["id"])] = Vector3(float(actor["x"]), float(actor["y"]) - EnemyView.CAMERA.FP_SERVER_REFERENCE_Y + SurveyorRig.LENS_HEIGHT, float(actor["z"]))
	var live: Dictionary[String, bool] = {}
	for fact: Dictionary in snapshot.get("surveyor_marks", []):
		var key: String = str(fact["id"])
		live[key] = true
		var center: Vector3 = Vector3(float(fact["center"][0]), float(fact["center"][1]), float(fact["center"][2]))
		var mark: Mark = marks.get(key) as Mark
		if mark == null:
			mark = _create(key, center)
			marks[key] = mark
		mark.target = center
		mark.tracking = bool(fact["tracking"])
		mark.lens = lenses.get(key, center + Vector3(0, 6, 0))
		mark.seen = tick
	for key: String in marks.keys():
		if not live.has(key):
			_retire(key)
			marks.erase(key)

func _create(key: String, center: Vector3) -> Mark:
	var mark: Mark = Mark.new()
	mark.target = center
	mark.disc = MeshInstance3D.new()
	mark.disc.name = "Disc_" + key
	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	mark.disc.mesh = quad
	mark.material = ShaderMaterial.new()
	mark.material.shader = DISC_SHADER
	mark.disc.material_override = mark.material
	mark.disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.disc.position = center + Vector3(0, 0.03, 0)
	add_child(mark.disc)
	mark.spot = SpotLight3D.new()
	mark.spot.name = "Lens_" + key
	mark.spot.light_color = LIGHT
	mark.spot.light_energy = 6.0
	mark.spot.spot_range = 22.0
	mark.spot.spot_angle = 11.0
	mark.spot.spot_attenuation = 0.6
	mark.spot.shadow_enabled = false
	add_child(mark.spot)
	mark.beam = MeshInstance3D.new()
	mark.beam.name = "Beam_" + key
	var beam: CylinderMesh = CylinderMesh.new()
	beam.top_radius = 0.06
	beam.bottom_radius = RADIUS * 0.55
	beam.height = 1.0
	beam.radial_segments = 10
	beam.rings = 1
	beam.cap_top = false
	beam.cap_bottom = false
	mark.beam.mesh = beam
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.albedo_color = Color(0.29, 0.54, 0.57, 0.07)
	mark.beam.material_override = glow
	mark.beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mark.beam)
	return mark

func _retire(key: String) -> void:
	var mark: Mark = marks.get(key) as Mark
	if mark == null:
		return
	for node: Node in [mark.disc, mark.spot, mark.beam]:
		if is_instance_valid(node):
			node.queue_free()

func _process(delta: float) -> void:
	if not is_finite(delta):
		return
	_clock = fmod(_clock + maxf(delta, 0.0), 64.0)
	for key: String in marks:
		var mark: Mark = marks[key]
		var weight: float = clampf(delta / GLIDE, 0.0, 1.0)
		var at: Vector3 = mark.disc.position.lerp(mark.target + Vector3(0, 0.03, 0), weight)
		mark.disc.position = at
		mark.material.set_shader_parameter("pulse", fmod(_clock * 0.8, 1.0))
		mark.material.set_shader_parameter("tracking", 1.0 if mark.tracking else 0.0)
		mark.spot.position = mark.lens
		var aim: Vector3 = at - mark.lens
		if aim.length() > 0.05:
			mark.spot.look_at_from_position(mark.lens, at, Vector3.UP if absf(aim.normalized().y) < 0.99 else Vector3.FORWARD)
		mark.spot.light_energy = 6.0 if mark.tracking else 2.5
		var length: float = maxf(0.1, aim.length())
		mark.beam.position = mark.lens + aim * 0.5
		mark.beam.visible = aim.length() > 0.05
		if mark.beam.visible:
			# The cylinder's narrow top sits at the lens, its wide foot on the disc.
			var up: Vector3 = -aim.normalized()
			var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
			mark.beam.basis = Basis(side, up * length, side.cross(up))
