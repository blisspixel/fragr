class_name LatchFace
extends RefCounted

## Personal pixel expressions. Inputs describe accepted presentation facts only.
const STATES: Array[String] = ["relaxed", "walking", "focused", "concerned", "hopeful", "reassured", "wince"]
const PIXEL: float = 0.006
const BLINK_SECONDS: float = 0.12
const HURT_SECONDS: float = 0.45
static var _meshes: Dictionary[String, ArrayMesh] = {}
var state: String = "relaxed"
var blinking: bool = false
var _phase: String = "following"
var _ward: bool = false
var _ward_state: String = "concerned"
var _health: int = -1
var _hurt_left: float = 0.0
var _shot_left: float = 0.0
var _moving_left: float = 0.0
var _blink_left: float = 0.0
var _blink_wait: float = 3.7
var _blink_count: int = 0

func observe_health(health: int) -> void:
	if health < 1 or health > 100:
		return
	if _health > 0 and health < _health:
		_hurt_left = HURT_SECONDS
	_health = health
	_resolve()

func ward(progress: float, released: bool) -> void:
	_ward = true
	progress = clampf(progress, 0.0, 1.0) if is_finite(progress) else 0.0
	_ward_state = "concerned" if not released else ("hopeful" if progress < 0.5 else "reassured")
	_resolve()

func advance(delta: float, travel: float, phase: String) -> void:
	_ward = false
	_phase = phase if phase in ActorState.COMPANION_PHASES else "following"
	if is_finite(travel) and travel > 0.001 and travel < 2.0:
		_moving_left = 0.16
	tick(delta)

func shot() -> void:
	_shot_left = 0.25
	_resolve()

func tick(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	# A paused or suspended application never catches up cosmetic animation.
	delta = minf(delta, 0.25)
	_hurt_left = maxf(0.0, _hurt_left - delta)
	_shot_left = maxf(0.0, _shot_left - delta)
	_moving_left = maxf(0.0, _moving_left - delta)
	if _blink_left > 0.0:
		_blink_left = maxf(0.0, _blink_left - delta)
	else:
		_blink_wait -= delta
		if _blink_wait <= 0.0:
			_blink_left = BLINK_SECONDS
			_blink_count += 1
			_blink_wait = 3.7 + float(_blink_count % 3) * 0.65
	_resolve()

func _resolve() -> void:
	if _hurt_left > 0.0:
		state = "wince"
	elif _ward:
		state = _ward_state
	elif _phase == "firing" or _shot_left > 0.0:
		state = "focused"
	elif _phase == "releasing":
		state = "hopeful"
	elif _moving_left > 0.0:
		state = "walking"
	else:
		state = "relaxed"
	blinking = _blink_left > 0.0 and state not in ["focused", "wince"]

static func mesh(expression: String, closed: bool = false) -> ArrayMesh:
	if expression not in STATES:
		expression = "relaxed"
	var key: String = expression + ("_closed" if closed else "_open")
	if _meshes.has(key):
		return _meshes[key]
	var rectangles: Array[Rect2] = []
	# Rectangles use a common pixel grid inside the retained display recess.
	if closed:
		rectangles.append_array([Rect2(-7, 4, 4, 1), Rect2(3, 4, 4, 1)])
	else:
		match expression:
			"relaxed":
				rectangles.append_array([Rect2(-7, 3, 3, 4), Rect2(4, 3, 3, 4), Rect2(-8, 7, 4, 1), Rect2(4, 7, 4, 1)])
			"walking":
				rectangles.append_array([Rect2(-7, 3, 3, 5), Rect2(4, 3, 3, 5)])
			"focused":
				rectangles.append_array([Rect2(-7, 3, 4, 2), Rect2(3, 3, 4, 2), Rect2(-8, 7, 3, 1), Rect2(-5, 6, 2, 1), Rect2(3, 6, 2, 1), Rect2(5, 7, 3, 1)])
			"concerned":
				rectangles.append_array([Rect2(-7, 2, 3, 4), Rect2(4, 2, 3, 4), Rect2(-8, 7, 2, 1), Rect2(-6, 8, 3, 1), Rect2(3, 8, 3, 1), Rect2(6, 7, 2, 1)])
			"hopeful":
				rectangles.append_array([Rect2(-7, 2, 3, 6), Rect2(4, 2, 3, 6), Rect2(-8, 9, 4, 1)])
			"reassured":
				rectangles.append_array([Rect2(-7, 4, 1, 2), Rect2(-6, 6, 2, 1), Rect2(-4, 4, 1, 2), Rect2(3, 4, 1, 2), Rect2(4, 6, 2, 1), Rect2(6, 4, 1, 2)])
			"wince":
				rectangles.append_array([Rect2(-7, 6, 2, 1), Rect2(-5, 5, 2, 1), Rect2(-7, 4, 2, 1), Rect2(5, 6, 2, 1), Rect2(3, 5, 2, 1), Rect2(5, 4, 2, 1)])
	match expression:
		"concerned":
			rectangles.append_array([Rect2(-3, -5, 6, 1), Rect2(-4, -6, 1, 1), Rect2(3, -6, 1, 1)])
		"focused":
			rectangles.append(Rect2(-2, -5, 4, 1))
		"wince":
			rectangles.append_array([Rect2(-2, -4, 4, 1), Rect2(-3, -6, 1, 2), Rect2(2, -6, 1, 2), Rect2(-2, -7, 4, 1)])
		"walking":
			rectangles.append_array([Rect2(-3, -6, 6, 1), Rect2(-4, -5, 1, 1), Rect2(3, -5, 2, 1), Rect2(5, -4, 1, 1)])
		"reassured":
			rectangles.append_array([Rect2(-3, -7, 6, 1), Rect2(-5, -6, 2, 1), Rect2(3, -6, 2, 1), Rect2(-6, -4, 1, 2), Rect2(5, -4, 1, 2)])
		_:
			rectangles.append_array([Rect2(-3, -6, 6, 1), Rect2(-4, -5, 1, 1), Rect2(3, -5, 1, 1)])
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var geometry: RefCounted = preload("res://scripts/model_geometry.gd").new()
	for rect: Rect2 in rectangles:
		var a: Vector2 = rect.position * PIXEL
		var b: Vector2 = rect.end * PIXEL
		geometry.quad(surface, Vector3(a.x, a.y, 0), Vector3(b.x, a.y, 0),
			Vector3(b.x, b.y, 0), Vector3(a.x, b.y, 0), Vector3.BACK)
	_meshes[key] = surface.commit()
	return _meshes[key]
