class_name StillHereTurn
extends CanvasLayer

## The cover between the first light and years later. It fades the court to
## black and says `covered`, so the story page that establishes the elapsed
## time can open over it; it holds through that page and lifts on the same
## court once the server has turned the world and the reader is done. The
## server alone decides when the world turns, and the cover waits for that
## world before it lifts. Without a page it shows its own two words on a
## level baseline. Controls stay blocked while it is up.
signal covered
signal finished

const FADE_IN: float = 0.9
## A cover without a page holds its own words this long.
const HOLD: float = 3.2
const FADE_OUT: float = 1.4

var _veil: ColorRect
var _copy: Label
var _age: float = 0.0
var _world_ready: bool = false
var _covered: bool = false
## A story page is open over the cover; it decides when the reader is done.
var _page_open: bool = false
var _page_seen: bool = false
var _lifting: float = -1.0

func _ready() -> void:
	layer = 60
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.color = Color(0.0, 0.0, 0.0, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_veil)
	_copy = Label.new()
	_copy.name = "YearsLater"
	_copy.text = tr("STILL_HERE_YEARS_LATER")
	_copy.set_anchors_preset(Control.PRESET_FULL_RECT)
	_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_copy.add_theme_font_override("font", MenuTheme.FONT)
	_copy.add_theme_font_size_override("font_size", MenuTheme.LARGE)
	_copy.add_theme_color_override("font_color", MenuTheme.BONE)
	_copy.modulate.a = 0.0
	_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_copy)

## The later world's MapInfo has been applied behind the veil.
func world_turned() -> void:
	_world_ready = true

## The elapsed-time page opened over the cover; the cover holds until
## `page_closed`.
func page_opened() -> void:
	_page_open = true
	_page_seen = true

func page_closed() -> void:
	_page_open = false

func covering() -> bool:
	return _veil != null and _veil.color.a > 0.98

func _process(delta: float) -> void:
	if not is_finite(delta):
		return
	_age += maxf(delta, 0.0)
	if _lifting < 0.0:
		_veil.color.a = clampf(_age / FADE_IN, 0.0, 1.0)
		if _age >= FADE_IN and not _covered:
			_covered = true
			covered.emit()
		# Its own words only when no page carries them.
		var words: float = 0.0 if _page_seen else clampf((_age - FADE_IN * 0.6) / 0.6, 0.0, 1.0)
		_copy.modulate.a = words
		var read: bool = not _page_open and (_page_seen or _age >= FADE_IN + HOLD)
		if _world_ready and _covered and read:
			_lifting = 0.0
		return
	_lifting += maxf(delta, 0.0)
	_copy.modulate.a = minf(_copy.modulate.a, clampf(1.0 - _lifting / (FADE_OUT * 0.5), 0.0, 1.0))
	_veil.color.a = clampf(1.0 - (_lifting - FADE_OUT * 0.3) / FADE_OUT, 0.0, 1.0)
	if _lifting >= FADE_OUT * 1.3:
		finished.emit()
		queue_free()
