class_name DamageBearing
extends Control

## Remember resolved incoming directions, never a live shooter's location.
const LIFETIME: float = 0.85
const MAX_HITS: int = 4
const PIXEL: float = 4.0
var directions: Array[Vector3] = []
var remaining: Array[float] = []
var view_basis: Basis = Basis.IDENTITY


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	reset()


func reset() -> void:
	directions.clear()
	remaining.clear()
	visible = false
	queue_redraw()


func hit(direction: Vector3) -> void:
	if not direction.is_finite() or Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	if directions.size() == MAX_HITS:
		directions.pop_front()
		remaining.pop_front()
	directions.append(direction.normalized())
	remaining.append(LIFETIME)
	visible = true
	queue_redraw()


func advance(delta: float, basis: Basis) -> void:
	if not is_finite(delta) or delta < 0.0 or not basis.is_finite():
		return
	view_basis = basis
	for index: int in range(remaining.size() - 1, -1, -1):
		remaining[index] -= delta
		if remaining[index] <= 0.0:
			remaining.remove_at(index)
			directions.remove_at(index)
	visible = not directions.is_empty()
	queue_redraw()


## Zero is front, positive angles turn right. Pitch cannot skew the bearing.
static func angle(direction: Vector3, basis: Basis) -> float:
	var forward: Vector3 = -basis.z
	forward.y = 0.0
	var incoming: Vector3 = direction
	incoming.y = 0.0
	if not incoming.is_finite() or not basis.is_finite() \
			or incoming.length_squared() < 0.0001 or forward.length_squared() < 0.0001:
		return NAN
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP)
	return atan2(incoming.dot(right), incoming.dot(forward))


func _draw() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var centre: Vector2 = viewport_size * 0.5
	var radius: Vector2 = viewport_size * Vector2(0.39, 0.36)
	for index: int in range(directions.size()):
		var bearing: float = angle(directions[index], view_basis)
		if not is_finite(bearing):
			continue
		var alpha: float = minf(1.0, remaining[index] / 0.25)
		for step: int in range(-5, 6):
			var offset: float = bearing + float(step) * 0.035
			var radial: Vector2 = Vector2(sin(offset), -cos(offset))
			var point: Vector2 = (centre + radial * radius).snapped(Vector2.ONE * PIXEL)
			var strength: float = 1.0 - absf(float(step)) * 0.06
			draw_rect(Rect2(point - Vector2.ONE * PIXEL, Vector2.ONE * PIXEL * 2.0),
				Color(0.75, 0.15, 0.12, alpha * strength))
			if absi(step) <= 2:
				draw_rect(Rect2(point, Vector2.ONE * PIXEL), Color(1.0, 0.79, 0.56, alpha))
