class_name RewardsPanel
extends VBoxContainer

signal completed
var records: PlayerRecords
var profile_name: String = ""
var draft: Dictionary
var _notice: Label
var _preview: TextureRect
var _identity: Label
var _stamp: Label
var _save: Button
var _selectors: Dictionary[String, OptionButton] = {}

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	draft = records.customization.duplicate()
	_label(tr("REWARD_TITLE"), 26)
	_label(tr("REWARD_LOCAL"), 16)
	var awards: HBoxContainer = HBoxContainer.new()
	awards.add_theme_constant_override("separation", 18)
	add_child(awards)
	for award: String in PlayerRewards.IDS:
		var text: Label = Label.new()
		text.custom_minimum_size.x = 300.0
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size", 16)
		var earned: bool = PlayerRewards.owns(records.unlocks, award)
		text.text = tr("REWARD_" + award.to_upper()) + "\n" \
			+ tr("REWARD_EARNED" if earned else "REWARD_LOCKED") + "\n" \
			+ tr("REWARD_CRITERIA_" + award.to_upper())
		text.add_theme_color_override("font_color", MenuTheme.EMBER if earned else MenuTheme.BONE)
		awards.add_child(text)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	for kind: String in PlayerRewards.DEFAULTS:
		var caption: Label = Label.new()
		caption.text = tr("REWARD_SELECT_" + kind.to_upper())
		caption.add_theme_font_size_override("font_size", 20)
		grid.add_child(caption)
		var selector: OptionButton = OptionButton.new()
		selector.name = "Reward" + kind.capitalize()
		selector.custom_minimum_size = Vector2(410.0, 42.0)
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		selector.add_theme_font_size_override("font_size", 20)
		_selectors[kind] = selector
		for choice: String in PlayerRewards.CHOICES[kind]:
			var available: bool = PlayerRewards.available(kind, choice, records.unlocks)
			selector.add_item(PlayerRewards.label(choice) + ("" if available else " (" + tr("REWARD_LOCKED") + ")"))
		selector.select(PlayerRewards.CHOICES[kind].find(draft[kind]))
		selector.item_selected.connect(func(index: int) -> void:
			draft[kind] = PlayerRewards.CHOICES[kind][index]
			_refresh()
		)
		grid.add_child(selector)
	var display: HBoxContainer = HBoxContainer.new()
	display.add_theme_constant_override("separation", 18)
	add_child(display)
	_preview = TextureRect.new()
	_preview.name = "FinishPreview"
	_preview.texture = WeaponArt.IDLE["Tack"]
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.custom_minimum_size = Vector2(260.0, 126.0)
	display.add_child(_preview)
	var identity: VBoxContainer = VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display.add_child(identity)
	_identity = Label.new()
	_identity.add_theme_font_size_override("font_size", 20)
	_identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_child(_identity)
	_stamp = Label.new()
	_stamp.add_theme_font_size_override("font_size", 18)
	_stamp.add_theme_stylebox_override("normal", MenuTheme.panel(Color("181c18"), MenuTheme.BONE))
	identity.add_child(_stamp)
	_notice = _label("", 16)
	var buttons: HBoxContainer = HBoxContainer.new()
	add_child(buttons)
	_save = Button.new()
	_save.text = tr("REWARD_SAVE")
	_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save.pressed.connect(_commit)
	buttons.add_child(_save)
	var cancel: Button = Button.new()
	cancel.text = tr("REWARD_CANCEL")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void: completed.emit())
	buttons.add_child(cancel)
	_refresh()

func _label(text: String, size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label

func focus_first() -> void:
	_selectors["title"].grab_focus()

func _refresh() -> void:
	_preview.material = PlayerRewards.material(draft["finish"])
	_identity.text = profile_name
	if draft["title"] != "none":
		_identity.text += "\n" + PlayerRewards.label(draft["title"])
	_stamp.text = tr("REWARD_STAMP") if draft["emblem"] == "transfer_stamp" else ""
	_stamp.visible = draft["emblem"] != "none"
	_save.disabled = not PlayerRewards.valid_selection(draft, records.unlocks) or records.writing_blocked()
	_notice.text = tr("REWARD_PREVIEW_LOCKED" if _save.disabled else "REWARD_FINISH_SCOPE")
	if records.error != OK:
		_notice.text = tr("RECORD_SAVE_ERROR")

func _commit() -> void:
	if _save.disabled:
		return
	if records.select_customization(draft) != OK:
		_notice.text = tr("RECORD_SAVE_ERROR")
		return
	completed.emit()
