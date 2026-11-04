class_name AimReticle
extends Control

## The server's cone projected through the actual camera. No bloom, speed or
## recovery rules live here. The centre pip never follows the outer ring.
const PIP: Rect2 = Rect2(-1.0, -1.0, 2.0, 2.0)
const EDGE: Color = Color("101014")
var radius: float = 0.0
var ink: Color = Color("e4dac4")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func projected_radius(cone_microradians: int, fov_degrees: float, axis_pixels: float) -> float:
	if cone_microradians <= 0 or not is_finite(fov_degrees) or not is_finite(axis_pixels) \
		or fov_degrees <= 0.0 or fov_degrees >= 180.0 or axis_pixels <= 0.0:
		return 0.0
	return tan(float(cone_microradians) / 1000000.0) * axis_pixels / (2.0 * tan(deg_to_rad(fov_degrees) * 0.5))


func present(cone_microradians: int, fov_degrees: float, axis_pixels: float, colour: Color) -> void:
	var next_radius: float = projected_radius(cone_microradians, fov_degrees, axis_pixels)
	if is_equal_approx(radius, next_radius) and ink == colour:
		return
	radius = next_radius
	ink = colour
	queue_redraw()


func _draw() -> void:
	# A sub-pip cone cannot be drawn as a detached ring. Never enlarge it to
	# suggest a spread the server does not use, or move the reference pip.
	if radius > 4.0:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 97, EDGE, 3.0, false)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 97, ink, 1.0, false)
	draw_rect(PIP.grow(1.0), EDGE)
	draw_rect(PIP, ink)
