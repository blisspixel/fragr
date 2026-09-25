extends Node3D
class_name ShotEffects

## Short, depth-tested geometry from server shot evidence. No local hit tests.
const MAX_EFFECTS: int = 128
const MAX_RESULTS: int = 512
const MAX_COORDINATE: float = 8192.0
const MAX_TRACE_LENGTH: float = 1024.0
const LIFETIME: float = 0.24
## A scatter blast draws at most this many pellets per result, matching the server.
const MAX_PELLETS: int = 7
## Server melee reach in world units. A melee trace can never end farther away.
const MELEE_REACH: Dictionary = {"fists": 1.8, "shiv": 2.2}

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
var _material: StandardMaterial3D = StandardMaterial3D.new()

func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
			lifetime = 0.14 if _effects[i].weapon == "rail" else 0.065
		if _effects[i].age >= lifetime:
			_effects.remove_at(i)
	_rebuild()

func _rebuild() -> void:
	_mesh.clear_surfaces()
	visible = not _effects.is_empty()
	set_process(visible)
	if not visible:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for effect in _effects:
		_draw_effect(effect)
	_mesh.surface_end()

func _draw_effect(effect: Effect) -> void:
	if effect.weapon in EquipmentState.MELEE:
		_draw_melee_impact(effect)
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
	_mesh.surface_set_color(colour)
	for vertex in [a, b, c, a, c, d]:
		_mesh.surface_add_vertex(vertex)
