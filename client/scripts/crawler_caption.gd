class_name CrawlerCaption
extends Control

const MAX_ENTRIES: int = 2
const LIFETIME_MS: int = 2300
const DEDUP_MS: int = 900
const CAPTION_KEY: String = "CAPTION_CRAWLER_SCRABBLE"

var entries: Array[Dictionary] = []
var last_scrabble_ms: int = -DEDUP_MS
var caption_label: Label

func _ready() -> void:
	name = "CrawlerCaption"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 120.0
	offset_right = -120.0
	offset_top = -176.0
	offset_bottom = -104.0
	caption_label = Label.new()
	caption_label.name = "CaptionLabel"
	caption_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_label.add_theme_font_size_override("font_size", 20)
	caption_label.add_theme_color_override("font_color", Color(0.94, 0.92, 0.86))
	caption_label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.05))
	caption_label.add_theme_constant_override("outline_size", 5)
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption_label)
	_render()

func push_scrabble(now_ms: int = -1) -> bool:
	var when: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	if when - last_scrabble_ms < DEDUP_MS:
		return false
	last_scrabble_ms = when
	prune(when)
	entries.append({"key": CAPTION_KEY, "expires": when + LIFETIME_MS})
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()
	_render()
	return true

func prune(now_ms: int = -1) -> void:
	var when: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	while not entries.is_empty() and int(entries[0]["expires"]) <= when:
		entries.pop_front()
	_render()

func clear() -> void:
	entries.clear()
	last_scrabble_ms = -DEDUP_MS
	_render()

func _process(_delta: float) -> void:
	prune()

func _render() -> void:
	if caption_label == null:
		return
	var lines: PackedStringArray = []
	for entry: Dictionary in entries:
		lines.append(tr(str(entry["key"])))
	caption_label.text = "\n".join(lines)
	caption_label.visible = not entries.is_empty()
