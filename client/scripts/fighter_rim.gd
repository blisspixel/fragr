class_name FighterRim
extends RefCounted
## A live fighter's rim of light (#528): every material on the dressed body
## draws `fighter_rim.gdshader` over itself, so the figure separates from the
## lot behind it at fighting range. Rim highlights, not outlines (TF2's rule,
## docs/plans/fun-craft-targets.md); the colour follows the faction contract:
## a free body's rim is warm, the Union's issued black takes a cool plate
## value, and neither is red or cyan. `client/qa/contrast_scan.gd` measures
## the result against each fighter's local background.

const SHADER: Shader = preload("res://assets/shaders/fighter_rim.gdshader")
const FREE: Color = Color("f4c890")
const UNION: Color = Color("aab0bc")
const STRENGTH: float = 1.3
const META: StringName = &"fighter_rim"

## The venue's share of the rim (ArenaSky preset `fighter_rim`), set when a
## map's look is applied; every live rim follows it.
static var venue: float = 1.0
static var _rims: Array[WeakRef] = []


## A new venue: every rim already drawn takes its strength.
static func set_venue(share: float) -> void:
	venue = clampf(share, 0.0, 1.0) if is_finite(share) else 1.0
	var kept: Array[WeakRef] = []
	for ref: WeakRef in _rims:
		var rim: ShaderMaterial = ref.get_ref() as ShaderMaterial
		if rim != null:
			rim.set_shader_parameter("rim_strength", STRENGTH * venue)
			kept.append(ref)
	_rims = kept


## Give `body` its rim for this livery, creating it on first use.
static func apply(body: Node, union: bool) -> ShaderMaterial:
	if body == null:
		return null
	var rim: ShaderMaterial = of(body)
	if rim == null:
		rim = ShaderMaterial.new()
		rim.shader = SHADER
		body.set_meta(META, rim)
		_rims.append(weakref(rim))
	rim.set_shader_parameter("rim_strength", STRENGTH * venue)
	rim.set_shader_parameter("rim_color", UNION if union else FREE)
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node as MeshInstance3D
		if part.mesh == null:
			continue
		for surface: int in range(part.mesh.get_surface_count()):
			var material: StandardMaterial3D = part.get_surface_override_material(surface) as StandardMaterial3D
			if material != null:
				material.next_pass = rim
	return rim


## The rim `body` carries, or null.
static func of(body: Node) -> ShaderMaterial:
	if body == null or not body.has_meta(META):
		return null
	return body.get_meta(META) as ShaderMaterial
