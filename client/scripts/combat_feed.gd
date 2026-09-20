class_name CombatFeed
extends VBoxContainer

const LIMIT: int = 3
const LIFETIME: float = 3.0

class Entry:
	var label: Label
	var remaining: float = LIFETIME
	func _init(value: Label) -> void:
		label = value

var _entries: Array[Entry] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)

func push(text: String, colour: Color = MenuTheme.BONE) -> void:
	var line: String = text.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	if line.is_empty():
		return
	if _entries.size() == LIMIT:
		_remove(0)
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = line.left(200)
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(label)
	_entries.append(Entry.new(label))

func _process(delta: float) -> void:
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
