class_name CombatFeed
extends VBoxContainer

const LIMIT: int = 3
const LIFETIME: float = 3.0
signal host_presented(seconds: float)

class Entry:
	var label: Label
	var remaining: float = LIFETIME
	var presented: bool = false
	var host_seconds: float = 0.0
	func _init(value: Label) -> void:
		label = value

var _entries: Array[Entry] = []
var _campaign: bool = false
var coverage_query: Callable
var _covered: bool = false
var _was_hidden: bool = false
var _limit: int = LIMIT

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)

func set_campaign(active: bool) -> void:
	_campaign = active
	alignment = BoxContainer.ALIGNMENT_END if active else BoxContainer.ALIGNMENT_BEGIN
	for entry: Entry in _entries:
		entry.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

func clear() -> void:
	while not _entries.is_empty():
		_remove(0)

func set_limit(value: int) -> void:
	_limit = clampi(value, 0, LIMIT)
	while _entries.size() > _limit:
		_remove(0)

func covered() -> bool:
	return _covered or (coverage_query.is_valid() and bool(coverage_query.call()))

func set_covered(value: bool) -> void:
	_covered = value
	_refresh_coverage()

func _refresh_coverage() -> bool:
	var hidden: bool = covered()
	visible = not hidden
	if not hidden and _was_hidden:
		for entry: Entry in _entries:
			if not entry.presented:
				entry.label.queue_redraw()
	_was_hidden = hidden
	return hidden

func set_region(rect: Rect2) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = rect.position
	size = rect.size

func push(text: String, colour: Color = MenuTheme.BONE, host_seconds: float = 0.0) -> void:
	var line: String = text.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	if line.is_empty() or _limit == 0:
		return
	if _entries.size() >= _limit:
		_remove(0)
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = line.left(200)
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", MenuTheme.BODY)
	label.add_theme_color_override("font_color", MenuTheme.readable_text(colour))
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(label)
	var entry := Entry.new(label)
	entry.host_seconds = host_seconds
	_entries.append(entry)
	label.draw.connect(_first_draw.bind(entry))

func _first_draw(entry: Entry) -> void:
	if entry.presented or not _entries.has(entry) or not entry.label.is_visible_in_tree():
		return
	if covered():
		_was_hidden = true
		return
	entry.presented = true
	if entry.host_seconds > 0.0:
		host_presented.emit(entry.host_seconds)

func _process(delta: float) -> void:
	if _refresh_coverage():
		return
	for index: int in range(_entries.size() - 1, -1, -1):
		var entry: Entry = _entries[index]
		entry.remaining -= delta
		if entry.remaining <= 0.0:
			_remove(index)
		else:
			entry.label.modulate.a = minf(entry.remaining / 0.4, 1.0)

func _remove(index: int) -> void:
	var label: Label = _entries[index].label
	_entries.remove_at(index)
	remove_child(label)
	label.queue_free()
