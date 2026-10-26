class_name VfxDecals
extends Node3D

## Marks combat leaves on the map: a pock or dent where a shot struck a solid
## and a scorch where a blast went off. Presentation only, placed from server
## evidence (a resolved endpoint and normal, a resolved blast position) on the
## faces of the current MapInfo solids, so no mark ever floats off a wall or
## wraps round a corner: every mark is an axis-aligned quad clipped to the
## face it lies on. Both renderers draw it; no Decal node is needed.
##
## Bounded: the oldest mark or scorch makes way for a new one, and each fades
## out through an ordered dither after its lifetime.

const SHADER: Shader = preload("res://assets/shaders/vfx_decal.gdshader")
const MAX_MARKS: int = 48
const MAX_SCORCHES: int = 10
const MARK_SECONDS: float = 24.0
const SCORCH_SECONDS: float = 40.0
const FADE_SECONDS: float = 3.0
## A fresh scorch keeps ember cracks glowing this long before they are rust.
const SCORCH_HEAT_SECONDS: float = 2.2
const SCORCH_DELAY_SECONDS: float = 0.15
## World size of a blast scorch, metres across.
const SCORCH_METRES: float = 2.8
## How far a blast may sit off the face it scorches.
const SCORCH_REACH: float = 1.1
## Marks stand off their face so the wall's own depth never wins.
const STANDOFF: float = 0.012
const PROBE: float = 0.05

class Mark:
	var centre: Vector3
	var normal: Vector3
	## Face rectangle in the face's own two axes, and those axes.
	var u_axis: Vector3
	var v_axis: Vector3
	var face_min: Vector2
	var face_max: Vector2
	var half: float
	var uv: Rect2
	var age: float = 0.0
	var lifetime: float
	var hot: bool = false

## Solid boxes as [min_x, max_x, bottom, top, min_z, max_z] and their class.
var _boxes: Array[PackedFloat32Array] = []
var _classes: PackedStringArray = PackedStringArray()
var _ground_class: String = ShotVfx.CONCRETE
var _half_extent: float = 50.0
var _has_map: bool = false
var _marks: Array[Mark] = []
var _scorches: Array[Mark] = []
var _mesh: ImmediateMesh = ImmediateMesh.new()
var _mark_material: ShaderMaterial = ShaderMaterial.new()
var _scorch_material: ShaderMaterial = ShaderMaterial.new()
var _scorch_serial: int = 0

func _init() -> void:
	name = "VfxDecals"
	_mark_material.shader = SHADER
	_mark_material.set_shader_parameter("decal_texture", ShotVfx.MARKS)
	_scorch_material.shader = SHADER
	_scorch_material.set_shader_parameter("decal_texture", ShotVfx.SCORCH)
	var view: MeshInstance3D = MeshInstance3D.new()
	view.name = "Marks"
	view.mesh = _mesh
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# World geometry before it ever enters a tree: the actor-only view light
	# must never pair with it.
	view.layers = ArenaSky.WORLD_LAYERS
	add_child(view)
	set_process(false)

## Adopt a new map's faces and drop every old mark. Invalid map facts leave
## the decals empty and inert; they never decide anything.
func set_map(info: Dictionary) -> void:
	clear()
	_boxes.clear()
	_classes.clear()
	_ground_class = ShotVfx.CONCRETE
	_has_map = false
	if not MapGeometry.validation_error(info).is_empty():
		return
	_half_extent = float(info["half_extent"])
	var presentation: Variant = info.get("presentation")
	var surfaces: Array = []
	if presentation is Dictionary:
		surfaces = presentation["solids"]
		_ground_class = ShotVfx.surface_class(str(presentation["ground"]))
	var solids: Array = info["solids"]
	for index: int in range(solids.size()):
		var solid: Dictionary = solids[index]
		_boxes.append(PackedFloat32Array([float(solid["min_x"]), float(solid["max_x"]),
			float(solid.get("bottom", MoveStep.GROUND_Y)), float(solid.get("top", MoveStep.WALL_TOP)),
			float(solid["min_z"]), float(solid["max_z"])]))
		_classes.append(ShotVfx.surface_class(str(surfaces[index])) if index < surfaces.size() else ShotVfx.CONCRETE)
	_has_map = true

func clear() -> void:
	_marks.clear()
	_scorches.clear()
	_mesh.clear_surfaces()
	set_process(false)

func mark_count() -> int:
	return _marks.size()

func scorch_count() -> int:
	return _scorches.size()

## The impact class of the solid face at `point` with outward `normal`: the
## registered material of the box the point sits on, else the ground's.
func surface_at(point: Vector3, normal: Vector3) -> String:
	var index: int = _box_at(point - normal * PROBE)
	if index >= 0:
		return _classes[index]
	return _ground_class

## Leaves a shot mark of `cell` (a `ShotVfx.MARK_CELLS` name) on the face at
## `point`. A point on no known face, or with no map, leaves nothing.
func add_mark(point: Vector3, normal: Vector3, cell: String) -> bool:
	if not _has_map or cell.is_empty() or not point.is_finite() or not normal.is_finite():
		return false
	var mark: Mark = _face_mark(point, normal, ShotVfx.MARK_METRES * 0.5)
	if mark == null:
		return false
	mark.uv = ShotVfx.mark_uv(cell)
	mark.lifetime = MARK_SECONDS
	if _marks.size() >= MAX_MARKS:
		_marks.pop_front()
	_marks.append(mark)
	_rebuild()
	return true

## Scorches the nearest face within reach of a resolved blast: the floor
## under it, the wall it struck or the ceiling above it.
func add_scorch(position: Vector3) -> bool:
	if not _has_map or not position.is_finite():
		return false
	var best_normal: Vector3 = Vector3.ZERO
	var best_distance: float = SCORCH_REACH
	for direction: Vector3 in [Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3.UP]:
		var distance: float = _distance_to_face(position, direction)
		if distance < best_distance:
			best_distance = distance
			best_normal = -direction
	if best_normal == Vector3.ZERO:
		return false
	var mark: Mark = _face_mark(position - best_normal * best_distance, best_normal, SCORCH_METRES * 0.5)
	if mark == null:
		return false
	mark.uv = ShotVfx.strip_uv(_scorch_serial % ShotVfx.SCORCH_VARIANTS, ShotVfx.SCORCH_VARIANTS)
	_scorch_serial += 1
	mark.lifetime = SCORCH_SECONDS
	mark.hot = true
	# The fire covers the wall first; the burn shows as it clears.
	mark.age = -SCORCH_DELAY_SECONDS
	if _scorches.size() >= MAX_SCORCHES:
		_scorches.pop_front()
	_scorches.append(mark)
	_rebuild()
	return true

## Ages every mark; the mesh is rebuilt only while a scorch cools, a mark
## fades or one expires, not every frame a wall merely carries marks.
func _process(delta: float) -> void:
	var step: float = maxf(delta, 0.0)
	var changed: bool = false
	for list: Array[Mark] in [_marks, _scorches]:
		for index: int in range(list.size() - 1, -1, -1):
			var mark: Mark = list[index]
			mark.age += step
			if mark.age >= mark.lifetime:
				list.remove_at(index)
				changed = true
			elif mark.lifetime - mark.age < FADE_SECONDS or (mark.hot and mark.age - step < SCORCH_HEAT_SECONDS):
				changed = true
	if changed:
		_rebuild()

## Index of the solid box containing `point`, or -1.
func _box_at(point: Vector3) -> int:
	for index: int in range(_boxes.size()):
		var box: PackedFloat32Array = _boxes[index]
		if point.x >= box[0] - 0.001 and point.x <= box[1] + 0.001 and point.y >= box[2] - 0.001 \
				and point.y <= box[3] + 0.001 and point.z >= box[4] - 0.001 and point.z <= box[5] + 0.001:
			return index
	return -1

## Distance from `point` along an axis `direction` to the first face that
## faces back at it within reach: a solid's side, top or underside, or the
## ground. INF when none is in reach.
func _distance_to_face(point: Vector3, direction: Vector3) -> float:
	var best: float = INF
	if direction == Vector3.DOWN and point.y >= MoveStep.GROUND_Y - 0.01:
		best = point.y - MoveStep.GROUND_Y
	var axis: int = direction.abs().max_axis_index()
	var facing: float = signf(direction[axis])
	for box: PackedFloat32Array in _boxes:
		var low: Vector3 = Vector3(box[0], box[2], box[4])
		var high: Vector3 = Vector3(box[1], box[3], box[5])
		var plane: float = low[axis] if facing > 0.0 else high[axis]
		var distance: float = (plane - point[axis]) * facing
		if distance < -0.05 or distance >= best:
			continue
		var inside: bool = true
		for other: int in range(3):
			if other != axis and (point[other] < low[other] or point[other] > high[other]):
				inside = false
		if inside:
			best = maxf(distance, 0.0)
	return best

## A quad of `half` metres half-width centred on `point`, lying on the face
## with outward `normal`, clipped to that face's rectangle. Null when the
## point is on no face.
func _face_mark(point: Vector3, normal: Vector3, half: float) -> Mark:
	var axis: int = normal.abs().max_axis_index()
	var outward: Vector3 = Vector3.ZERO
	outward[axis] = signf(normal[axis]) if normal[axis] != 0.0 else 1.0
	var u_index: int = (axis + 1) % 3
	var v_index: int = (axis + 2) % 3
	var u_axis: Vector3 = Vector3.ZERO
	u_axis[u_index] = 1.0
	var v_axis: Vector3 = Vector3.ZERO
	v_axis[v_index] = 1.0
	var face_min: Vector2
	var face_max: Vector2
	var plane: float
	var index: int = _box_at(point - outward * PROBE)
	if index >= 0:
		var box: PackedFloat32Array = _boxes[index]
		var low: Vector3 = Vector3(box[0], box[2], box[4])
		var high: Vector3 = Vector3(box[1], box[3], box[5])
		plane = high[axis] if outward[axis] > 0.0 else low[axis]
		face_min = Vector2(low[u_index], low[v_index])
		face_max = Vector2(high[u_index], high[v_index])
	elif axis == 1 and outward.y > 0.0 and absf(point.y - MoveStep.GROUND_Y) < 0.2:
		plane = MoveStep.GROUND_Y
		face_min = Vector2(-_half_extent, -_half_extent)
		face_max = Vector2(_half_extent, _half_extent)
	else:
		return null
	var mark: Mark = Mark.new()
	mark.normal = outward
	mark.u_axis = u_axis
	mark.v_axis = v_axis
	mark.face_min = face_min
	mark.face_max = face_max
	mark.half = half
	var centre: Vector3 = point
	centre[axis] = plane
	mark.centre = centre
	return mark

func _rebuild() -> void:
	_mesh.clear_surfaces()
	set_process(not _marks.is_empty() or not _scorches.is_empty())
	_draw(_marks, _mark_material)
	_draw(_scorches, _scorch_material)

func _draw(list: Array[Mark], material: ShaderMaterial) -> void:
	if list.is_empty():
		return
	var begun: bool = false
	for mark: Mark in list:
		if mark.age < 0.0:
			continue
		var fade: float = clampf((mark.lifetime - mark.age) / FADE_SECONDS, 0.0, 1.0)
		var heat: float = clampf(1.0 - mark.age / SCORCH_HEAT_SECONDS, 0.0, 1.0) if mark.hot else 0.0
		var u: float = mark.centre.dot(mark.u_axis)
		var v: float = mark.centre.dot(mark.v_axis)
		var low: Vector2 = Vector2(maxf(u - mark.half, mark.face_min.x), maxf(v - mark.half, mark.face_min.y))
		var high: Vector2 = Vector2(minf(u + mark.half, mark.face_max.x), minf(v + mark.half, mark.face_max.y))
		if low.x >= high.x or low.y >= high.y:
			continue
		if not begun:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
			begun = true
		var base: Vector3 = mark.centre - mark.u_axis * u - mark.v_axis * v + mark.normal * STANDOFF
		var corners: Array[Vector2] = [low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)]
		var colour: Color = Color(heat, 0.0, 0.0, fade)
		for corner_index: int in [0, 1, 2, 0, 2, 3]:
			var corner: Vector2 = corners[corner_index]
			var local: Vector2 = (corner - Vector2(u - mark.half, v - mark.half)) / (mark.half * 2.0)
			_mesh.surface_set_color(colour)
			_mesh.surface_set_normal(mark.normal)
			_mesh.surface_set_uv(mark.uv.position + Vector2(local.x, 1.0 - local.y) * mark.uv.size)
			_mesh.surface_add_vertex(base + mark.u_axis * corner.x + mark.v_axis * corner.y)
	if begun:
		_mesh.surface_end()
