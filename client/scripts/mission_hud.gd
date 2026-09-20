class_name MissionHud
extends Control

## A shared objective and physical-use prompt, never a local completion timer.
var state: Dictionary = {}
var player_id: String = ""
var _card: PanelContainer
var _copy: Label
var _prompt: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", MenuTheme.panel(Color("1c2420"), Color("716344")))
	add_child(_card)
	_copy = _label(18)
	_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(_copy)
	_prompt = _label(22)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_prompt)
	_refresh()

func _label(font_size: int) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", MenuTheme.BONE)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 4)
	return label

func apply(value: Dictionary, owner_id: String) -> void:
	state = value
	player_id = owner_id
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()

func _process(_delta: float) -> void:
	if not visible:
		return
	var viewport: Vector2 = get_viewport_rect().size
	var width: float = minf(408.0, viewport.x - 48.0)
	_card.position = Vector2(viewport.x - width - 24.0, 70.0)
	_card.size = Vector2(width, 0.0)
	_copy.custom_minimum_size.x = width - 32.0
	_prompt.position = Vector2(viewport.x * 0.2, viewport.y * 0.64)
	_prompt.size = Vector2(viewport.x * 0.6, 0.0)

func _refresh() -> void:
	if _copy == null:
		return
	visible = not state.is_empty()
	if not visible:
		_copy.text = ""
		_prompt.text = ""
		return
	var lines: Array[String] = [tr("MISSION_M01_TITLE"), ""]
	match state["phase"]:
		"find_transfer": lines.append(tr("MISSION_FIND_RECORD"))
		"reach_lift":
			lines.append(tr("MISSION_REACH_LIFT"))
			lines.append(tr("MISSION_TRANSFER_RECORD"))
			var waiting: Array[String] = []
			for member: Dictionary in state["party"]:
				if not member["aboard"]:
					waiting.append(member["name"])
			if not waiting.is_empty():
				lines.append(tr("MISSION_WAITING_FOR").format({"names": ", ".join(waiting)}))
		"departed":
			lines.append(tr("MISSION_DEPARTED"))
	_copy.text = "\n".join(lines)
	_prompt.text = ""
	for prompt: Dictionary in state["prompts"]:
		if prompt["player_id"] == player_id:
			_prompt.text = tr("MISSION_USE_RECORD" if prompt["kind"] == "transfer_record" else "MISSION_USE_LIFT")
	_prompt.visible = not _prompt.text.is_empty()
