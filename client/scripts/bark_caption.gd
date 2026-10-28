class_name BarkCaption
extends Control

## Captions for campaign chatter: "SPEAKER: line", at most two at once, on a
## level baseline just above the Crawler caption. Captions show whether or
## not a recording exists or audio is muted.

const MAX_ENTRIES: int = 2
const LIFETIME_MS: int = 3400
const UNION_LABEL: Color = MenuTheme.DANGER
const LATCH_LABEL: Color = MenuTheme.EMBER

var entries: Array[Dictionary] = []
var caption_label: RichTextLabel


func _ready() -> void:
	name = "BarkCaption"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 200.0
	offset_right = -200.0
	offset_top = -306.0
	offset_bottom = -182.0
	caption_label = RichTextLabel.new()
	caption_label.name = "CaptionLabel"
	caption_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	caption_label.bbcode_enabled = true
	caption_label.fit_content = false
	caption_label.scroll_active = false
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	caption_label.add_theme_font_size_override("normal_font_size", MenuTheme.BODY)
	caption_label.add_theme_font_override("normal_font", MenuTheme.FONT)
	caption_label.add_theme_color_override("default_color", MenuTheme.BONE)
	caption_label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	caption_label.add_theme_constant_override("outline_size", 5)
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption_label)
	_render()


## Show one line. Empty keys are refused.
func push(speaker_key: String, caption_key: String, union: bool, now_ms: int = -1) -> bool:
	if speaker_key.is_empty() or caption_key.is_empty():
		return false
	var when: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	prune(when)
	entries.append({"speaker": speaker_key, "key": caption_key, "union": union, "expires": when + LIFETIME_MS})
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()
	_render()
	return true


func prune(now_ms: int = -1) -> void:
	var when: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	var changed: bool = false
	while not entries.is_empty() and int(entries[0]["expires"]) <= when:
		entries.pop_front()
		changed = true
	if changed:
		_render()


func clear() -> void:
	entries.clear()
	_render()


## The plain caption text, for checks.
func text() -> String:
	var lines: PackedStringArray = []
	for entry: Dictionary in entries:
		lines.append(tr(str(entry["speaker"])) + ": " + tr(str(entry["key"])))
	return "\n".join(lines)


func _process(_delta: float) -> void:
	prune()


func _render() -> void:
	if caption_label == null:
		return
	var lines: PackedStringArray = []
	for entry: Dictionary in entries:
		var colour: Color = UNION_LABEL if bool(entry["union"]) else LATCH_LABEL
		lines.append("[center][color=#%s]%s:[/color] %s[/center]" % [
			colour.to_html(false),
			_escape(tr(str(entry["speaker"]))),
			_escape(tr(str(entry["key"]))),
		])
	caption_label.text = "\n".join(lines)
	caption_label.visible = not entries.is_empty()


static func _escape(value: String) -> String:
	return value.replace("[", "[lb]")
