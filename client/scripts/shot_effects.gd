extends Node3D
class_name ShotEffects

## Short, depth-tested geometry from server shot evidence. No local hit tests.
const MAX_EFFECTS: int = 128
const MAX_RESULTS: int = 512
const MAX_COORDINATE: float = 8192.0
const MAX_TRACE_LENGTH: float = 1024.0
const LIFETIME: float = 0.24
## Cosmetic geometry close to the eye must not become screen-filling polygons.
const CAMERA_CLEARANCE: float = 0.6
const CLEARANCE_SHADER: Shader = preload("res://assets/shaders/shot_clearance.gdshader")
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

class Effect:
	var shooter: String
	var weapon: String
	var origin: Vector3
	var end: Vector3
	var normal: Vector3
	var kind: String
	var age: float = 0.0

var _effects: Array[Effect] = []
var _last_tick: int = -1
var _mesh: ImmediateMesh = ImmediateMesh.new()
var _material: ShaderMaterial = ShaderMaterial.new()
var _clip_to_camera: bool = false
var _camera_origin: Vector3 = Vector3.ZERO
var _camera_forward: Vector3 = Vector3.FORWARD
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
	visible = false
	set_process(false)

func ingest(tick: int, results: Array) -> void:
	if tick <= _last_tick or results.size() > MAX_RESULTS:
		return
	_last_tick = tick
	for result in results:
		for effect: Effect in _parse_all(result):
			if _effects.size() == MAX_EFFECTS:
				_effects.pop_front()
			_effects.append(effect)
	_rebuild()

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
		var effect: Effect = _parse({"shooter_id": value["shooter_id"], "trace": trace})
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
	visible = false
	set_process(false)

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
		var lifetime: float = LIFETIME
		if _effects[i].kind == "range":
			lifetime = 0.14 if _effects[i].weapon == "rail" else (SNIPER_TRACER_SECONDS if _effects[i].weapon == "sniper" else 0.065)
		if _effects[i].age >= lifetime:
			_effects.remove_at(i)
	_rebuild()

func _rebuild() -> void:
	_mesh.clear_surfaces()
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
		_camera_clearance = maxf(CAMERA_CLEARANCE, camera.near)
	_material.set_shader_parameter("camera_clearance", _camera_clearance)
	_building_surface = false
	for effect in _effects:
		_draw_effect(effect)
	if _building_surface:
		_mesh.surface_end()
	visible = _building_surface

func _draw_effect(effect: Effect) -> void:
	if effect.weapon in EquipmentState.MELEE:
		_draw_melee_impact(effect)
		return
	if effect.weapon == "sniper":
		_draw_sniper_tracer(effect)
		return
	var rail: bool = effect.weapon == "rail"
	var tint: Color = Color("b4e0e8") if rail else Color("f5b568")
	var beam_time: float = 0.14 if rail else 0.065
	var direction: Vector3 = (effect.end - effect.origin).normalized()
	var distance: float = effect.origin.distance_to(effect.end)
	if effect.age < beam_time and distance > 0.05:
		var width: float = (0.045 if rail else 0.018) * (1.0 - 0.6 * effect.age / beam_time)
		var start: Vector3 = effect.origin + direction * minf(0.35, distance * 0.1)
		_segment(start, effect.end, width, tint)
	if effect.kind == "range":
		return
	var normal: Vector3 = effect.normal
	var tangent: Vector3 = normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var bitangent: Vector3 = normal.cross(tangent)
	var size: float = (0.12 if effect.kind == "fighter" else 0.07) * (1.0 - effect.age / LIFETIME)
	var centre: Vector3 = effect.end + normal * 0.025
	_quad(centre - tangent * size - bitangent * size, centre + tangent * size - bitangent * size,
		centre + tangent * size + bitangent * size, centre - tangent * size + bitangent * size, Color("fff0bd"))
	for i in range(4):
		var angle: float = float(i) * PI * 0.5 + 0.35
		var velocity: Vector3 = (tangent * cos(angle) + bitangent * sin(angle)) * 1.8 + normal * 1.3
		var position: Vector3 = centre + velocity * effect.age + Vector3.DOWN * 3.0 * effect.age * effect.age
		_segment(position, position + velocity.normalized() * size * 1.8, maxf(size * 0.22, 0.002), tint)

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
