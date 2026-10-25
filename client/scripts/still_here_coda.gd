class_name StillHereCoda
extends CanvasLayer

## The close of both campaign endings, after the local story has resolved.
##
## Survival, after Latch stops counting: you sit down on the bench beside
## Latch, and the view settles on Latch, the water and the salvaged board. A
## long breath. Then the board shows one fragment, two lines in the voice it
## used on the pier, and times the ferry again.
##
## Exhaustion, after its pages: the same two lines on black, in that same
## voice, with no board and no place to stand.
##
## Either way, then a breath of deep space: a ring of light around nothing,
## far past anything anyone in this story met, twice, and gone, with no
## words. Then the credits: on the walk, the people this run saw again among
## them. Presentation only: the server has already ended the epilogue or the
## run, and any press moves the coda on.
signal finished

const SURVIVAL: String = "survival"
const EXHAUSTION: String = "exhaustion"
## Seconds to sit down beside Latch.
const SETTLE: float = 3.2
const FRAGMENT_AT: float = 5.4
const FRAGMENT_END: float = 11.4
const DARK_AT: float = 12.8
const SPACE_AT: float = 13.8
const SPACE_END: float = 20.8
## Exhaustion starts dark: the fragment, then the same anomaly.
const EXHAUSTION_FRAGMENT_AT: float = 1.0
const EXHAUSTION_FRAGMENT_END: float = 7.0
const EXHAUSTION_SPACE_AT: float = 8.0
const EXHAUSTION_SPACE_END: float = 15.0
const CARD_SECONDS: float = 3.4
const NAMED: Array[String] = ["edda", "splice", "orrin", "sorrel"]
## How far the settled view turns from the board toward Latch: Latch at one
## side of the frame, the board over the water at the other.
const TOWARD_LATCH: float = 0.42

## Which ending this closes: SURVIVAL (the walk) or EXHAUSTION.
var ending: String = SURVIVAL
## The refuge presenter that owns the board (the walk only).
var refuge: StillHereRefuge
## The first-person camera whose view settles on the quay (the walk only).
var camera: Node3D
var _age: float = 0.0
var _veil: ColorRect
var _space: Control
var _card: Label
var _fragment: Label
var _cards: Array[String] = []
var _card_index: int = -1
var _card_age: float = 0.0
var _start_yaw: float = NAN
var _start_pitch: float = NAN
var _start_position: Vector3 = Vector3.INF
var _seat: Vector3 = Vector3.INF
var _target_yaw: float = NAN
var _target_pitch: float = 0.0
var _done: bool = false

func _ready() -> void:
	layer = 61
	if ending not in [SURVIVAL, EXHAUSTION]:
		ending = SURVIVAL
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.color = Color(0, 0, 0, 1.0 if ending == EXHAUSTION else 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_veil)
	_space = DeepSpace.new()
	_space.name = "DeepSpace"
	_space.set_anchors_preset(Control.PRESET_FULL_RECT)
	_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_space.visible = false
	add_child(_space)
	_fragment = _centred_label("Fragment", MenuTheme.BODY, StillHereRefuge.DISPLAY_TEXT)
	_fragment.text = "%s\n%s" % [tr("STILL_HERE_BOARD_FRAGMENT_A"), tr("STILL_HERE_BOARD_FRAGMENT_B")]
	_card = _centred_label("Credit", MenuTheme.BODY, MenuTheme.BONE)
	_cards = credits_for(ending, refuge.refuge if refuge != null else {})
	if camera != null and ending == SURVIVAL:
		_start_yaw = float(camera.get("fp_yaw"))
		_start_pitch = float(camera.get("fp_pitch"))
		_start_position = camera.global_position
		_settle()

func _centred_label(label: String, font_size: int, ink: Color) -> Label:
	var copy: Label = Label.new()
	copy.name = label
	copy.set_anchors_preset(Control.PRESET_FULL_RECT)
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_theme_font_override("font", MenuTheme.FONT)
	copy.add_theme_font_size_override("font_size", font_size)
	copy.add_theme_color_override("font_color", ink)
	copy.add_theme_constant_override("line_spacing", 10)
	copy.visible = false
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(copy)
	return copy

## The survival walk's credit cards, in order: the title, the people this run
## saw again, the game.
static func credits(refuge: Dictionary) -> Array[String]:
	return credits_for(SURVIVAL, refuge)

## Credit cards for either ending. The walk names who this run saw again;
## exhaustion never reached the refuge, so it names only those every ending
## keeps and everyone who crossed, under no epilogue title.
static func credits_for(which: String, refuge: Dictionary) -> Array[String]:
	var people: Array[String] = [TranslationServer.translate("STILL_HERE_CREDITS_WITH"),
		TranslationServer.translate("STILL_HERE_NAME_LATCH"), TranslationServer.translate("STILL_HERE_NAME_MARA"),
		TranslationServer.translate("STILL_HERE_NAME_TERN")]
	if which == SURVIVAL:
		for who: String in NAMED:
			if refuge.get(who) == true:
				people.append(TranslationServer.translate("STILL_HERE_NAME_" + who.to_upper()))
	people.append(TranslationServer.translate("STILL_HERE_CREDITS_EVERYONE"))
	var cards: Array[String] = []
	if which == SURVIVAL:
		cards.append(TranslationServer.translate("STILL_HERE_CREDITS_TITLE"))
	cards.append("\n".join(people))
	cards.append(TranslationServer.translate("STILL_HERE_CREDITS_GAME"))
	cards.append(TranslationServer.translate("STILL_HERE_CREDITS_THANKS"))
	return cards

## Sit down beside Latch: the seat at seated eye height, and a view that
## holds Latch and the board over the water in one frame.
func _settle() -> void:
	if refuge == null or camera == null:
		return
	var focus: Dictionary = refuge.coda_focus()
	if focus.is_empty():
		return
	_seat = focus["seat"]
	var board: Vector3 = focus["board"]
	var latch: Vector3 = focus["latch"]
	var to_board: float = atan2(board.z - _seat.z, board.x - _seat.x)
	var to_latch: float = atan2(latch.z - _seat.z, latch.x - _seat.x)
	_target_yaw = to_board + angle_difference(to_board, to_latch) * TOWARD_LATCH
	var reach: float = Vector2(board.x - _seat.x, board.z - _seat.z).length()
	_target_pitch = atan2(board.y - _seat.y, maxf(reach, 0.5)) * 0.55

func _fragment_end() -> float:
	return EXHAUSTION_FRAGMENT_END if ending == EXHAUSTION else FRAGMENT_END

func _space_at() -> float:
	return EXHAUSTION_SPACE_AT if ending == EXHAUSTION else SPACE_AT

func _space_end() -> float:
	return EXHAUSTION_SPACE_END if ending == EXHAUSTION else SPACE_END

func _input(event: InputEvent) -> void:
	if _done or not (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")) or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		_finish()
		return
	# Each press moves on one beat; nothing in the coda waits on a press.
	if _age < _fragment_end():
		_age = _fragment_end()
	elif _age < _space_at():
		_age = _space_at()
	elif _age < _space_end():
		_age = _space_end()
	else:
		_card_age = CARD_SECONDS

## The fragment is showing: on the board for the walk, on black otherwise.
func fragment_showing() -> bool:
	if ending == EXHAUSTION:
		return _fragment.visible
	return refuge != null and is_instance_valid(refuge) and refuge.fragment

func _process(delta: float) -> void:
	if _done or not is_finite(delta):
		return
	_age += maxf(delta, 0.0)
	if ending == EXHAUSTION:
		_veil.color.a = 1.0
		var showing: bool = _age >= EXHAUSTION_FRAGMENT_AT and _age < EXHAUSTION_FRAGMENT_END
		_fragment.visible = showing
		if showing:
			var into: float = _age - EXHAUSTION_FRAGMENT_AT
			_fragment.modulate.a = clampf(minf(into / 0.8, (EXHAUSTION_FRAGMENT_END - _age) / 0.8), 0.0, 1.0)
		if _age < EXHAUSTION_SPACE_AT:
			return
	else:
		_settle_view()
		if refuge != null and is_instance_valid(refuge):
			var showing: bool = _age >= FRAGMENT_AT and _age < FRAGMENT_END
			if showing != refuge.fragment:
				refuge.show_fragment(showing)
		if _age < DARK_AT:
			_veil.color.a = 0.0
			return
		if _age < SPACE_AT:
			_veil.color.a = clampf((_age - DARK_AT) / (SPACE_AT - DARK_AT), 0.0, 1.0)
			return
	_veil.color.a = 1.0
	if _age < _space_end():
		_space.visible = true
		(_space as DeepSpace).progress = (_age - _space_at()) / (_space_end() - _space_at())
		_space.queue_redraw()
		return
	_space.visible = false
	_card_age += maxf(delta, 0.0)
	if _card_index < 0 or _card_age >= CARD_SECONDS:
		_card_index += 1
		_card_age = 0.0
		if _card_index >= _cards.size():
			_finish()
			return
		_card.text = _cards[_card_index]
		var headline: bool = _cards[_card_index] in [TranslationServer.translate("STILL_HERE_CREDITS_TITLE"), TranslationServer.translate("STILL_HERE_CREDITS_GAME")]
		_card.add_theme_font_size_override("font_size", MenuTheme.LARGE if headline else MenuTheme.BODY)
	_card.visible = true
	var fade: float = minf(_card_age / 0.5, (CARD_SECONDS - _card_age) / 0.5)
	_card.modulate.a = clampf(fade, 0.0, 1.0)

## Sit and turn the walk's first-person view over SETTLE seconds.
func _settle_view() -> void:
	if camera == null or not is_finite(_target_yaw) or _age > SETTLE + 0.1:
		return
	var t: float = smoothstep(0.0, 1.0, clampf(_age / SETTLE, 0.0, 1.0))
	var yaw: float = _start_yaw + angle_difference(_start_yaw, _target_yaw) * t
	var pitch: float = lerpf(_start_pitch, _target_pitch, t)
	camera.set("fp_yaw", yaw)
	camera.set("fp_pitch", pitch)
	# Controls are blocked, so the camera neither follows the body nor
	# applies its own aim: sit and turn the view here, presentation only.
	if _seat.is_finite() and _start_position.is_finite():
		# Over the bench back first, then down onto the seat.
		var across: float = smoothstep(0.0, 0.75, t)
		var down: float = smoothstep(0.35, 1.0, t)
		camera.global_position = Vector3(lerpf(_start_position.x, _seat.x, across),
			lerpf(_start_position.y, _seat.y, down), lerpf(_start_position.z, _seat.z, across))
	camera.rotation.y = ServerYaw.camera_rotation_y(yaw)
	camera.rotation.x = pitch

func _finish() -> void:
	if _done:
		return
	_done = true
	if refuge != null and is_instance_valid(refuge):
		refuge.show_fragment(false)
	finished.emit()

## A far field of stars and, once, something in it: a ring of light around
## a dark that is too large and too round, brightening twice and gone. It
## explains nothing; it is not the Inheritance's rhythm and not a ship.
class DeepSpace:
	extends Control
	var progress: float = 0.0

	func _draw() -> void:
		var area: Vector2 = size
		draw_rect(Rect2(Vector2.ZERO, area), Color(0.01, 0.012, 0.02))
		var pixel: float = maxf(2.0, floorf(area.y / 360.0) * 2.0)
		var centre: Vector2 = Vector2(area.x * 0.62, area.y * 0.44)
		var radius: float = area.y * 0.16
		var ring: float = clampf((progress - 0.18) / 0.2, 0.0, 1.0) * clampf((0.92 - progress) / 0.12, 0.0, 1.0)
		var pulse: float = 0.0
		for at: float in [0.5, 0.64]:
			pulse = maxf(pulse, clampf(1.0 - absf(progress - at) / 0.04, 0.0, 1.0))
		var drift: Vector2 = Vector2(-progress * 18.0, progress * 4.0)
		for index: int in range(420):
			var x: float = fmod(float((index * 7919) % 10007) / 10007.0 * area.x + drift.x * float(index % 3 + 1), area.x)
			var y: float = fmod(float((index * 104729) % 10009) / 10009.0 * area.y + drift.y, area.y)
			var at: Vector2 = Vector2(x, y).snapped(Vector2(pixel, pixel))
			if ring > 0.0 and at.distance_to(centre) < radius * 0.94:
				continue
			var bright: float = 0.35 + float(index % 5) * 0.13
			draw_rect(Rect2(at, Vector2(pixel, pixel)), Color(bright, bright, bright * 1.05, 1.0))
		if ring <= 0.0:
			return
		var steps: int = 260
		var glow: float = (0.45 + 0.55 * pulse) * ring
		# A soft halo first, then the ring itself, two pixels thick.
		for halo: int in range(4):
			var spread: float = pixel * (2.0 + float(halo) * 2.0)
			for step: int in range(0, steps, 2):
				var angle: float = TAU * float(step) / float(steps)
				var at: Vector2 = (centre + Vector2(cos(angle), sin(angle)) * (radius + spread)).snapped(Vector2(pixel, pixel))
				draw_rect(Rect2(at, Vector2(pixel, pixel)), Color(0.80, 0.82, 0.86, glow * 0.12 / float(halo + 1)))
		for step: int in range(steps):
			var angle: float = TAU * float(step) / float(steps)
			var wobble: float = 1.0 + 0.012 * sin(angle * 5.0 + progress * 9.0)
			for thick: float in [0.0, pixel]:
				var at: Vector2 = (centre + Vector2(cos(angle), sin(angle)) * (radius * wobble + thick)).snapped(Vector2(pixel, pixel))
				draw_rect(Rect2(at, Vector2(pixel, pixel)), Color(0.90, 0.88, 0.82, glow))
