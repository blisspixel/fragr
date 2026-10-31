extends Node3D
class_name ShotEffects

## Short, depth-tested geometry from server shot evidence. No local hit tests:
## what a shot struck comes from the resolved trace, and its surface class
## from the struck fighter's body or the registered material of the solid the
## server's endpoint lies on.
const MAX_EFFECTS: int = 128
const MAX_RESULTS: int = 512
const MAX_COORDINATE: float = 8192.0
const MAX_TRACE_LENGTH: float = 1024.0
## An impact sprite's six frames, and every non-Railgun effect's lifetime.
const LIFETIME: float = 0.3
## The Railgun's beam lingers: a thick near-white core that thins, a pale
## edge that burns off first, and a dithered spiral that widens and fades.
const RAIL_SECONDS: float = 0.6
const RAIL_EDGE_SECONDS: float = 0.24
const RAIL_CORE_WIDTH: float = 0.04
const RAIL_CORE_THIN: float = 0.018
const RAIL_SPIRAL_RADIUS: float = 0.09
const RAIL_SPIRAL_GROWTH: float = 0.12
const RAIL_SPIRAL_PITCH: float = 0.75
const RAIL_SPIRAL_STEP: float = 0.1
const RAIL_SPIRAL_METRES: float = 24.0
const RAIL_SPIRAL_WIDTH: float = 0.007
## The spiral starts this far down the line and opens over RAIL_FLARE_METRES,
## over which the core also widens from RAIL_MUZZLE_TAPER of its width.
const RAIL_SPIRAL_FROM: float = 0.8
const RAIL_FLARE_METRES: float = 2.5
const RAIL_MUZZLE_TAPER: float = 0.2
## Where a beam leaves the eye's own gun in first person, in camera space
## (right, down, forward metres): the held gun's muzzle, not the eye, so
## the shooter sees the line and the spiral leave the barrel.
const FIRST_PERSON_MUZZLE: Vector3 = Vector3(0.0, -0.26, 0.72)
## An origin this close to the camera is the viewer's own shot.
const FIRST_PERSON_REACH: float = 0.45
## Cosmetic geometry close to the eye must not become screen-filling polygons.
const CAMERA_CLEARANCE: float = 0.6
const CLEARANCE_SHADER: Shader = preload("res://assets/shaders/shot_clearance.gdshader")
## Impact sprites from `ShotVfx`, on their own surface with the same clearance.
const SPRITE_SHADER: Shader = preload("res://assets/shaders/shot_sprite.gdshader")
## Impact sprites stand off the struck surface and lean toward the eye, so a
## wall does not swallow half of the puff.
const IMPACT_STANDOFF: float = 0.06
const IMPACT_TOWARD_EYE: float = 0.08
## A scatter blast draws at most this many pellets per result, matching the server.
const MAX_PELLETS: int = 7
## Server melee reach in world units. A melee trace can never end farther away.
const MELEE_REACH: Dictionary = {"fists": 1.8, "shiv": 2.2}
## The Sniper's faint tracer: short, thin and orange to match its orange-white
## muzzle flash, gone in a tenth of a second.
const SNIPER_TRACER_SECONDS: float = 0.1
const SNIPER_TRACER_METRES: float = 6.0
const SNIPER_TRACER_WIDTH: float = 0.02
const SNIPER_TRACER_TINT: Color = Color("ffa45c")
## No streak is drawn within this distance of the viewing camera.
const SNIPER_TRACER_VIEWER_CLEARANCE: float = 3.0
const ARC_REACH: float = 24.0
## A bullet tracer: pale amber, warm without reading as a beam.
const TRACER_TINT: Color = Color("ffd49a")
const ARC_DISCHARGE_SECONDS: float = 0.09

class Effect:
	var shooter: String
	var target: String = ""
	var weapon: String
	var origin: Vector3
	var end: Vector3
	var normal: Vector3
	var kind: String
	## Struck surface class (`ShotVfx` CONCRETE, METAL, FLESH, FABRIC or SYNTHETIC).
	var surface: String = ""
	var age: float = 0.0
	## Where the drawn beam starts, fixed on its first draw.
	var start: Vector3 = Vector3.INF

## The surface class of a struck fighter by participant ID; set by the match.
## Unset or unknown fighters read as flesh.
var fighter_surface: Callable = Callable()
## The player's Blood setting; off, a human body hit shows a dust puff.
var blood: bool = true
## The screen point of the first-person gun's drawn muzzle, or Vector2.INF;
## set by the match. Unset, a fixed point low and centre stands in.
var first_person_muzzle: Callable = Callable()
## Shared surface marks; a solid hit leaves its pock here and solids report
## their registered material through it.
var decals: VfxDecals = null
var _marks_left: int = 0
var _effects: Array[Effect] = []
var _last_tick: int = -1
var _mesh: ImmediateMesh = ImmediateMesh.new()
var _material: ShaderMaterial = ShaderMaterial.new()
var _clip_to_camera: bool = false
var _camera_origin: Vector3 = Vector3.ZERO
var _camera_forward: Vector3 = Vector3.FORWARD
var _camera_right: Vector3 = Vector3.RIGHT
var _camera_up: Vector3 = Vector3.UP
var _local_eye: Vector3 = Vector3.ZERO
var _local_forward: Vector3 = Vector3.FORWARD
var _impact_mesh: ImmediateMesh = ImmediateMesh.new()
var _impact_material: ShaderMaterial = ShaderMaterial.new()
var _building_impacts: bool = false
var _impact_quads: int = 0
var _camera_clearance: float = CAMERA_CLEARANCE
var _building_surface: bool = false

func _ready() -> void:
	_material.shader = CLEARANCE_SHADER
	_material.set_shader_parameter("camera_clearance", CAMERA_CLEARANCE)
	var surface: MeshInstance3D = MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = _mesh
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	_impact_material.shader = SPRITE_SHADER
	_impact_material.set_shader_parameter("sprite_texture", ShotVfx.IMPACTS)
	_impact_material.set_shader_parameter("camera_clearance", CAMERA_CLEARANCE)
	var impacts: MeshInstance3D = MeshInstance3D.new()
	impacts.name = "Impacts"
	impacts.mesh = _impact_mesh
	impacts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(impacts)
	visible = false
	set_process(false)

func ingest(tick: int, results: Array) -> void:
	if tick <= _last_tick or results.size() > MAX_RESULTS:
		return
	_last_tick = tick
	for result in results:
		for effect: Effect in _parse_all(result):
			_classify(effect)
			if _effects.size() == MAX_EFFECTS:
				_effects.pop_front()
			_effects.append(effect)
	_rebuild()

## Names what the shot struck and leaves its mark on a solid. A fighter's
## class comes from its body, a solid's from its registered material.
func _classify(effect: Effect) -> void:
	if effect.kind == "fighter":
		var surface: Variant = fighter_surface.call(effect.target) if fighter_surface.is_valid() else ShotVfx.FLESH
		effect.surface = ShotVfx.fighter_class(surface, blood)
	elif effect.kind == "solid":
		effect.surface = decals.surface_at(effect.end, effect.normal) if decals != null else ShotVfx.CONCRETE
		if decals != null:
			_marks_left += 1
			decals.add_mark(effect.end, effect.normal, ShotVfx.mark_cell(effect.weapon, effect.kind, effect.surface, _marks_left))

static func _vector(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3:
		return Vector3.INF
	for component in value:
		if not (component is float or component is int):
			return Vector3.INF
		if not is_finite(float(component)) or absf(float(component)) > MAX_COORDINATE:
			return Vector3.INF
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

## Every pellet of a scatter result is its own trace and impact. Single-ray
## weapons, and servers that omit pellets, yield the one trace in `end`.
static func _parse_all(value: Variant) -> Array[Effect]:
	var effects: Array[Effect] = []
	var first: Effect = _parse(value)
	if first == null:
		return effects
	var pellets: Variant = value["trace"].get("pellets")
	if pellets == null:
		effects.append(first)
		return effects
	if not pellets is Array or pellets.is_empty() or pellets.size() > MAX_PELLETS or first.weapon != "scatter":
		return effects
	for pellet: Variant in pellets:
		if not pellet is Dictionary or pellet.size() != 2:
			return [] as Array[Effect]
		var trace: Dictionary = value["trace"].duplicate()
		trace.erase("pellets")
		trace["end"] = pellet.get("end")
		trace["impact"] = pellet.get("impact")
		var effect: Effect = _parse({"shooter_id": value["shooter_id"], "target_id": value.get("target_id"), "trace": trace})
		if effect == null:
			return [] as Array[Effect]
		effects.append(effect)
	return effects

static func _parse(value: Variant) -> Effect:
	if not value is Dictionary or not value.get("trace") is Dictionary:
		return null
	var trace: Dictionary = value["trace"]
	if not trace.get("weapon") is String or not trace.get("impact") is Dictionary:
		return null
	var weapon: String = trace["weapon"]
	var impact: Dictionary = trace["impact"]
	if weapon not in EquipmentState.WEAPONS or not impact.get("kind") is String:
		return null
	var kind: String = impact["kind"]
	if kind not in ["fighter", "solid", "range"]:
		return null
	var origin: Vector3 = _vector(trace.get("origin"))
	var end: Vector3 = _vector(trace.get("end"))
	if not origin.is_finite() or not end.is_finite() or origin.distance_to(end) > MAX_TRACE_LENGTH:
		return null
	if weapon == "arc" and origin.distance_to(end) > ARC_REACH + 0.01:
		return null
	if weapon in EquipmentState.MELEE and (kind == "range" or origin.distance_to(end) > MELEE_REACH[weapon] + 0.01):
		return null
	if kind == "range" and origin.distance_to(end) <= 0.05:
		return null
	var normal: Vector3 = Vector3.ZERO if kind == "range" else _vector(impact.get("normal"))
	if kind != "range" and (not normal.is_finite() or absf(normal.length_squared() - 1.0) > 0.01):
		return null
	if not value.get("shooter_id") is String:
		return null
	var effect: Effect = Effect.new()
	effect.shooter = value["shooter_id"]
	if value.get("target_id") is String:
		effect.target = value["target_id"]
	effect.weapon = weapon
	effect.origin = origin
	effect.end = end
	effect.normal = normal
	effect.kind = kind
	return effect

func clear() -> void:
	_effects.clear()
	_last_tick = -1
	_mesh.clear_surfaces()
	_impact_mesh.clear_surfaces()
	_impact_quads = 0
	visible = false
	set_process(false)
	if decals != null:
		decals.clear()

## Adopt a new map's faces for surface classes and marks.
func configure_map(info: Dictionary) -> void:
	if decals != null:
		decals.set_map(info)

func active_count() -> int:
	return _effects.size()

func has_shot_from(shooter: String, kind: String = "") -> bool:
	for effect in _effects:
		if effect.shooter == shooter and (kind.is_empty() or effect.kind == kind):
			return true
	return false

func _process(delta: float) -> void:
	for i in range(_effects.size() - 1, -1, -1):
		_effects[i].age += delta
		if _effects[i].age >= lifetime(_effects[i]):
			_effects.remove_at(i)
	_rebuild()

## How long an effect stays: the Railgun's beam lingers on every outcome, a
## miss of any other gun is a brief tracer, and a hit plays its impact.
static func lifetime(effect: Effect) -> float:
	if effect.weapon == "rail":
		return RAIL_SECONDS
	if effect.kind != "range":
		return LIFETIME
	if effect.weapon == "sniper":
		return SNIPER_TRACER_SECONDS
	if effect.weapon == "arc":
		return ARC_DISCHARGE_SECONDS
	return 0.065

func _rebuild() -> void:
	_mesh.clear_surfaces()
	_impact_mesh.clear_surfaces()
	_impact_quads = 0
	visible = not _effects.is_empty()
	set_process(visible)
	if not visible:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	_clip_to_camera = is_instance_valid(camera)
	if _clip_to_camera:
		var camera_transform: Transform3D = camera.get_camera_transform()
		_camera_origin = camera_transform.origin
		_camera_forward = -camera_transform.basis.z.normalized()
		_camera_right = camera_transform.basis.x.normalized()
		_camera_up = camera_transform.basis.y.normalized()
		_local_eye = to_local(_camera_origin)
		_local_forward = (global_transform.basis.inverse() * _camera_forward).normalized()
		_camera_clearance = maxf(CAMERA_CLEARANCE, camera.near)
	_material.set_shader_parameter("camera_clearance", _camera_clearance)
	_impact_material.set_shader_parameter("camera_clearance", _camera_clearance)
	_building_surface = false
	for effect in _effects:
		_draw_effect(effect)
	if _building_surface:
		_mesh.surface_end()
	_building_impacts = false
	for effect in _effects:
		_draw_impact_sprite(effect)
	if _building_impacts:
		_impact_mesh.surface_end()
	visible = _building_surface or _building_impacts

func _draw_effect(effect: Effect) -> void:
	if effect.weapon in EquipmentState.MELEE:
		_draw_melee_impact(effect)
		return
	if effect.weapon == "arc":
		_draw_arc(effect)
		return
	if effect.weapon == "sniper":
		_draw_sniper_tracer(effect)
		return
	if effect.weapon == "rail":
		_draw_rail(effect)
		return
	var tint: Color = TRACER_TINT
	var beam_time: float = 0.065
	var direction: Vector3 = (effect.end - effect.origin).normalized()
	var distance: float = effect.origin.distance_to(effect.end)
	if effect.age < beam_time and distance > 0.05:
		var width: float = 0.018 * (1.0 - 0.6 * effect.age / beam_time)
		var start: Vector3 = effect.origin + direction * minf(0.35, distance * 0.1)
		_segment(start, effect.end, width, tint)
	if effect.kind == "range" or effect.age >= LIFETIME:
		return
	_draw_debris(effect)

## The flash and puff are the impact sprite; these thrown bits add motion in
## the struck surface's own material: hot sparks off metal and machines, grit
## off concrete, dark droplets off a body (pale lint with Blood off).
func _draw_debris(effect: Effect) -> void:
	var normal: Vector3 = effect.normal
	var tangent: Vector3 = normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var bitangent: Vector3 = normal.cross(tangent)
	var row: String = ShotVfx.impact_row(effect.weapon, effect.kind, effect.surface)
	var tint: Color = TRACER_TINT
	var count: int = 4
	var speed: float = 1.8
	var size: float = 0.07
	match row:
		"metal", "synthetic":
			tint = Color("ffd08a")
			count = 6
			speed = 2.6
		"concrete":
			tint = Color("8c847a")
			speed = 1.4
		"flesh":
			tint = Color("6e1218")
			size = 0.1
			speed = 1.2
		"fabric":
			tint = Color("b0a696")
			size = 0.08
			speed = 1.3
	size *= 1.0 - effect.age / LIFETIME
	var centre: Vector3 = effect.end + normal * 0.025
	for i in range(count):
		var angle: float = float(i) * TAU / count + 0.35
		var velocity: Vector3 = (tangent * cos(angle) + bitangent * sin(angle)) * speed + normal * 1.3
		var position: Vector3 = centre + velocity * effect.age + Vector3.DOWN * 3.0 * effect.age * effect.age
		_segment(position, position + velocity.normalized() * size * 1.8, maxf(size * 0.22, 0.002), tint)

## The Railgun's discharge: from the gun's muzzle (the eye's own held gun in
## first person) to the resolved endpoint, a camera-facing ribbon with a
## near-white core between pale cyan edges, and a spiral round it. The core
## starts thick and thins; the edges burn off first; everything dithers out
## by RAIL_SECONDS.
func _draw_rail(effect: Effect) -> void:
	var distance: float = effect.origin.distance_to(effect.end)
	if effect.age >= RAIL_SECONDS or distance <= 0.05:
		return
	if not effect.start.is_finite():
		effect.start = _beam_start(effect)
	var start: Vector3 = effect.start
	var span: Vector3 = effect.end - start
	if span.length() <= 0.05:
		return
	var direction: Vector3 = span.normalized()
	var progress: float = effect.age / RAIL_SECONDS
	var settle: float = smoothstep(0.0, 0.3, progress)
	var core: float = lerpf(RAIL_CORE_WIDTH, RAIL_CORE_THIN, settle)
	var fade: float = clampf((1.0 - progress) * 2.2, 0.0, 1.0)
	var edge_fade: float = clampf(1.0 - effect.age / RAIL_EDGE_SECONDS, 0.0, 1.0)
	var core_colour: Color = Color(ShotVfx.RAIL_CORE, fade)
	var edge_colour: Color = Color(ShotVfx.RAIL_EDGE, edge_fade)
	# The first metres leave the barrel narrow and widen to full, so a beam
	# from the eye's own gun is a line, not a wedge across the view.
	var flare: float = minf(RAIL_FLARE_METRES, span.length() * 0.5)
	var joint: Vector3 = start + direction * flare
	for piece: Array in [[start, joint, RAIL_MUZZLE_TAPER], [joint, effect.end, 1.0]]:
		if edge_fade > 0.0:
			_ribbon(piece[0], piece[1], core, core * 2.0, edge_colour, piece[2])
			_ribbon(piece[0], piece[1], -core * 2.0, -core, edge_colour, piece[2])
		_ribbon(piece[0], piece[1], -core, core, core_colour, piece[2])
	# The spiral: a helix round the line from a little past the muzzle, its
	# radius opening over the first metres and widening as it fades.
	var side: Vector3 = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT).normalized()
	var up: Vector3 = direction.cross(side)
	var radius: float = RAIL_SPIRAL_RADIUS + RAIL_SPIRAL_GROWTH * progress
	var length: float = minf(span.length(), RAIL_SPIRAL_METRES)
	var spiral_colour: Color = Color(ShotVfx.RAIL_SPIRAL, clampf((1.0 - progress) * 1.6, 0.0, 1.0))
	var previous: Vector3 = Vector3.INF
	var along: float = RAIL_SPIRAL_FROM
	while along <= length:
		var angle: float = along / RAIL_SPIRAL_PITCH * TAU
		var opened: float = radius * clampf((along - RAIL_SPIRAL_FROM) / RAIL_FLARE_METRES, 0.25, 1.0)
		var point: Vector3 = start + direction * along + (side * cos(angle) + up * sin(angle)) * opened
		if previous.is_finite():
			_ribbon(previous, point, -RAIL_SPIRAL_WIDTH, RAIL_SPIRAL_WIDTH, spiral_colour)
		previous = point
		along += RAIL_SPIRAL_STEP

## Where a beam is drawn from: the viewer's own held gun when the shot came
## from this eye, else just ahead of the shooter's eye.
func _beam_start(effect: Effect) -> Vector3:
	var direction: Vector3 = (effect.end - effect.origin).normalized()
	var fallback: Vector3 = effect.origin + direction * minf(0.35, effect.origin.distance_to(effect.end) * 0.1)
	if not _clip_to_camera or _camera_origin.distance_to(to_global(effect.origin)) > FIRST_PERSON_REACH:
		return fallback
	var muzzle: Vector3 = _camera_origin + _camera_right * FIRST_PERSON_MUZZLE.x \
		+ _camera_up * FIRST_PERSON_MUZZLE.y + _camera_forward * FIRST_PERSON_MUZZLE.z
	# The held gun's own drawn muzzle, when the view reports one, so the beam
	# leaves the barrel of whatever gun art is on screen.
	var screen: Variant = first_person_muzzle.call() if first_person_muzzle.is_valid() else null
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if screen is Vector2 and (screen as Vector2).is_finite() and is_instance_valid(camera):
		muzzle = camera.project_position(screen, FIRST_PERSON_MUZZLE.z)
	return to_local(muzzle)

## A flat strip facing the eye between `from` and `to`, spanning `inner` to
## `outer` metres to the side of the line. Without a camera it falls back to
## the crossed quads of `_segment`.
func _ribbon(from: Vector3, to: Vector3, inner: float, outer: float, colour: Color, taper: float = 1.0) -> void:
	if not _clip_to_camera:
		if inner < 0.0 and outer > 0.0:
			_segment(from, to, outer, colour)
		return
	var eye: Vector3 = _local_eye
	var along: Vector3 = to - from
	var side: Vector3 = along.cross(eye - from)
	if side.length_squared() < 0.000001:
		return
	side = side.normalized()
	_quad(from + side * inner * taper, from + side * outer * taper, to + side * outer, to + side * inner, colour)

## No beam back to the muzzle: a faint thin streak over the last few metres
## that fades as it closes on the impact, so the shot reads without pointing at
## the shooter the way the Railgun's line does.
func _draw_sniper_tracer(effect: Effect) -> void:
	var distance: float = effect.origin.distance_to(effect.end)
	if distance <= 0.05 or effect.age >= SNIPER_TRACER_SECONDS:
		return
	var direction: Vector3 = (effect.end - effect.origin).normalized()
	var progress: float = clampf(effect.age / SNIPER_TRACER_SECONDS, 0.0, 1.0)
	var length: float = minf(SNIPER_TRACER_METRES, distance * 0.5)
	var tail: Vector3 = effect.end - direction * length * (1.0 - progress * 0.7)
	# A shot that lands on the viewer would end its streak in the lens and fill a
	# scoped view. The hit already reads through damage, so no streak is drawn.
	if not _clip_to_camera or minf(_camera_origin.distance_to(to_global(effect.end)),
			_camera_origin.distance_to(to_global(tail))) > SNIPER_TRACER_VIEWER_CLEARANCE:
		# The unshaded shot material is opaque, so the streak thins rather than fades.
		_segment(tail, effect.end, SNIPER_TRACER_WIDTH * (1.0 - 0.6 * progress), SNIPER_TRACER_TINT)
	if effect.kind == "range":
		return
	var normal: Vector3 = effect.normal
	var tangent: Vector3 = normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var bitangent: Vector3 = normal.cross(tangent)
	var size: float = (0.09 if effect.kind == "fighter" else 0.05) * (1.0 - effect.age / LIFETIME)
	var centre: Vector3 = effect.end + normal * 0.025
	_quad(centre - tangent * size - bitangent * size, centre + tangent * size - bitangent * size,
		centre + tangent * size + bitangent * size, centre - tangent * size + bitangent * size, Color("f2efe4"))

func _draw_arc(effect: Effect) -> void:
	if effect.age >= ARC_DISCHARGE_SECONDS:
		return
	var distance: float = effect.origin.distance_to(effect.end)
	if distance < 0.05:
		return
	var direction: Vector3 = (effect.end - effect.origin).normalized()
	var side: Vector3 = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT).normalized()
	var up: Vector3 = direction.cross(side)
	var start: Vector3 = effect.origin + direction * minf(0.35, distance * 0.1)
	var previous: Vector3 = start
	var fade: float = 1.0 - effect.age / ARC_DISCHARGE_SECONDS
	# Six bounded cosmetic links share the exact resolved origin and endpoint.
	# No world query, target search or secondary damage is performed here.
	for link: int in range(1, 7):
		var fraction: float = float(link) / 6.0
		var point: Vector3 = start.lerp(effect.end, fraction)
		if link < 6:
			point += (side * (1.0 if link % 2 == 0 else -1.0) + up * sin(link * 2.3)) * minf(0.11, distance * 0.02) * fade
		_segment(previous, point, 0.025 * fade + 0.004, Color("fff2c4") if link % 2 == 0 else Color("d6bb76"))
		previous = point

func _draw_melee_impact(effect: Effect) -> void:
	var tangent: Vector3 = effect.normal.cross(Vector3.UP if absf(effect.normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var up: Vector3 = effect.normal.cross(tangent)
	var size: float = 0.035 * (1.0 - effect.age / LIFETIME)
	for index in range(3):
		var centre: Vector3 = effect.end + effect.normal * (0.03 + effect.age * 0.25) \
			+ tangent * (index - 1) * effect.age * 0.5 + up * effect.age * 0.2
		_quad(centre - tangent * size - up * size, centre + tangent * size - up * size,
			centre + tangent * size + up * size, centre - tangent * size + up * size, Color("807361"))

func _segment(start: Vector3, end: Vector3, width: float, colour: Color) -> void:
	var direction: Vector3 = (end - start).normalized()
	var side: Vector3 = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT).normalized() * width
	var up: Vector3 = direction.cross(side)
	_quad(start - side, start + side, end + side, end - side, colour)
	_quad(start - up, start + up, end + up, end - up, colour)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	# Fast path: a quad wholly past the clip plane needs no polygon clipping.
	# The Railgun spiral alone is hundreds of quads a frame.
	if not _clip_to_camera or (_local_depth(a) >= 0.0 and _local_depth(b) >= 0.0
			and _local_depth(c) >= 0.0 and _local_depth(d) >= 0.0):
		if not _building_surface:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
			_building_surface = true
		_mesh.surface_set_color(colour)
		_mesh.surface_add_vertex(a)
		_mesh.surface_add_vertex(b)
		_mesh.surface_add_vertex(c)
		_mesh.surface_add_vertex(a)
		_mesh.surface_add_vertex(c)
		_mesh.surface_add_vertex(d)
		return
	var polygon: Array[Vector3] = [a, b, c, d]
	if _clip_to_camera:
		var clipped: Array[Vector3] = []
		var previous: Vector3 = polygon.back()
		var previous_depth: float = _camera_depth(previous)
		for vertex: Vector3 in polygon:
			var depth: float = _camera_depth(vertex)
			if (depth >= 0.0) != (previous_depth >= 0.0):
				clipped.append(previous.lerp(vertex, previous_depth / (previous_depth - depth)))
			if depth >= 0.0:
				clipped.append(vertex)
			previous = vertex
			previous_depth = depth
		polygon = clipped
	if polygon.size() < 3:
		return
	# A live effect may be entirely behind the cosmetic clip plane. Begin only
	# when there is geometry, but keep processing its authoritative expiry.
	if not _building_surface:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
		_building_surface = true
	_mesh.surface_set_color(colour)
	for index: int in range(1, polygon.size() - 1):
		_mesh.surface_add_vertex(polygon[0])
		_mesh.surface_add_vertex(polygon[index])
		_mesh.surface_add_vertex(polygon[index + 1])

func _camera_depth(vertex: Vector3) -> float:
	return _camera_forward.dot(to_global(vertex) - _camera_origin) - _camera_clearance

## The same depth from this node's own space, for the fast path: the eye and
## view direction are carried into local space once per rebuild. The effects
## node is never scaled, so local and world distances agree.
func _local_depth(vertex: Vector3) -> float:
	return _local_forward.dot(vertex - _local_eye) - _camera_clearance

## One camera-facing quad from the impact atlas, its frame chosen by age.
## The whole quad is skipped when any corner would enter the camera
## clearance, and the shader discards anything the moving eye later reaches.
func _draw_impact_sprite(effect: Effect) -> void:
	if effect.kind == "range" or effect.age >= LIFETIME:
		return
	var row: String = ShotVfx.impact_row(effect.weapon, effect.kind, effect.surface)
	var half: float = ShotVfx.IMPACT_METRES[row] * 0.5
	var centre: Vector3 = effect.end + effect.normal * IMPACT_STANDOFF
	var right: Vector3
	var up: Vector3
	if _clip_to_camera:
		var eye: Vector3 = to_local(_camera_origin) - centre
		if eye.length() > 0.001:
			centre += eye.normalized() * minf(IMPACT_TOWARD_EYE, eye.length() * 0.5)
		right = (global_transform.basis.inverse() * _camera_right).normalized()
		up = (global_transform.basis.inverse() * _camera_up).normalized()
	else:
		right = effect.normal.cross(Vector3.UP if absf(effect.normal.y) < 0.9 else Vector3.RIGHT).normalized()
		up = effect.normal.cross(right)
	var corners: Array[Vector3] = [centre - right * half - up * half, centre + right * half - up * half,
		centre + right * half + up * half, centre - right * half + up * half]
	if _clip_to_camera:
		for corner: Vector3 in corners:
			if _camera_depth(corner) < 0.0:
				return
	var uv: Rect2 = ShotVfx.impact_uv(row, effect.age, LIFETIME)
	var uvs: Array[Vector2] = [Vector2(uv.position.x, uv.end.y), uv.end,
		Vector2(uv.end.x, uv.position.y), uv.position]
	if not _building_impacts:
		_impact_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _impact_material)
		_building_impacts = true
	_impact_quads += 1
	_impact_mesh.surface_set_color(Color.WHITE)
	for index: int in [0, 1, 2, 0, 2, 3]:
		_impact_mesh.surface_set_uv(uvs[index])
		_impact_mesh.surface_add_vertex(corners[index])

## Impact sprites drawn by the last rebuild.
func impact_count() -> int:
	return _impact_quads
