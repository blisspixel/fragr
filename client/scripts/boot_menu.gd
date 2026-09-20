extends Control

## The front menu, in the shape every shooter has used since Doom: single
## player, multiplayer, settings, quit. It builds itself in code rather than
## living in a scene file, because a menu with submenus is a state machine and
## a state machine is easier to read as code than as a node tree.
##
## It is fully keyboard navigable. Arrow keys move, Enter chooses, Escape goes
## back. A laptop with no mouse is a first-class way to play this.

const ARENA_SCENE: String = "res://scenes/main.tscn"
const LOOPBACK: String = "127.0.0.1:6767"
const MENU_FONT: Font = preload("res://assets/fonts/BlackOpsOne-Regular.ttf")

var _page: String = "main"
var _root: VBoxContainer = null
var _status: Label = null
var _host_edit: LineEdit = null
var _console: FragrConsole = null
var _settings: FragrSettings
var _name_edit: LineEdit = null

func _ready() -> void:
	MouseCapture.release()
	theme = MenuTheme.build()
	if _settings == null:
		_settings = FragrSettings.for_tree(get_tree())
	_settings.load_from_disk()
	_settings.changed.connect(_settings.apply)
	_settings.apply()
	_build_chrome()
	_show("main")
	_console = FragrConsole.new()
	_console.name = "FragrConsole"
	_console.preferences = _settings
	add_child(_console)

func _build_chrome() -> void:
	var back: MenuBackdrop = MenuBackdrop.new()
	back.anchor_right = 1.0
	back.anchor_bottom = 1.0
	add_child(back)

	var centre: CenterContainer = CenterContainer.new()
	centre.anchor_right = 1.0
	centre.anchor_bottom = 1.0
	add_child(centre)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.custom_minimum_size = Vector2(660.0, 0.0)
	centre.add_child(column)

	var title: Label = Label.new()
	title.text = "FRAGR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 154)
	title.add_theme_color_override("font_color", Color("c7b89a"))
	title.add_theme_color_override("font_shadow_color", Color("5d291d"))
	title.add_theme_constant_override("shadow_offset_x", 6)
	title.add_theme_constant_override("shadow_offset_y", 9)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color("080b0b"))
	column.add_child(title)
	var tagline: Label = Label.new()
	tagline.text = "CONTESTED FREQUENCY  //  PORT 6767"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 18)
	tagline.add_theme_color_override("font_color", Color("a4774c"))
	column.add_child(tagline)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 8)
	column.add_child(_root)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(0.6, 0.62, 0.64))
	_status.text = "ARROWS + ENTER   /   ESC BACK\nFreedom is not a licensed feature."
	column.add_child(_status)

func _clear() -> void:
	for child in _root.get_children():
		_root.remove_child(child)
		child.queue_free()

func _button(text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text.to_upper()
	b.custom_minimum_size = Vector2(0.0, 62.0)
	b.add_theme_font_size_override("font_size", 32)
	b.add_theme_color_override("font_color", Color("bba789"))
	b.add_theme_color_override("font_focus_color", Color("ffcc83"))
	b.add_theme_color_override("font_hover_color", Color("ffcc83"))
	b.add_theme_color_override("font_pressed_color", Color("ffffff"))
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	var selected: StyleBoxFlat = StyleBoxFlat.new()
	selected.bg_color = Color("4a2019")
	selected.border_color = Color("b66637")
	selected.border_width_left = 6
	selected.border_width_bottom = 2
	b.add_theme_stylebox_override("focus", selected)
	b.add_theme_stylebox_override("hover", selected)
	b.add_theme_stylebox_override("pressed", selected)
	b.pressed.connect(handler)
	_root.add_child(b)
	return b

func _label(text: String) -> void:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.55, 0.7, 0.72))
	_root.add_child(l)

func _show(page: String) -> void:
	_page = page
	_clear()
	match page:
		"main":
			_page_main()
		"single":
			_page_single()
		"multi":
			_page_multi()
		"settings":
			_page_settings()
		"profile":
			_page_profile()
	await get_tree().process_frame
	if page == "settings" and _page == page:
		(_root.get_node("SettingsPanel") as SettingsPanel).focus_first()
		return
	for child in _root.get_children():
		if child is Button and not (child as Button).disabled:
			(child as Button).grab_focus()
			break

func _page_main() -> void:
	_button("Single Player", func() -> void: _show("single"))
	_button("Multiplayer", func() -> void: _show("multi"))
	_button("Your callsign", func() -> void: _show("profile"))
	_button("Settings", func() -> void: _show("settings"))
	_button("Quit", func() -> void: get_tree().quit())

func _page_single() -> void:
	_label("Campaign")
	_button("Episode 0: Calibration", func() -> void: _launch("solo", LOOPBACK))
	var later: Button = _button("Episode 1: Larak Lot", func() -> void: pass)
	later.disabled = true
	later.tooltip_text = "Not built yet"
	_label("Practice")
	_button("Arena against bots", func() -> void: _launch("join", LOOPBACK))
	_button("Watch the bots", func() -> void: _launch("spectate", LOOPBACK))
	_label("Connects to a running local server on port 6767.")
	_button("Back", func() -> void: _show("main"))

func _page_multi() -> void:
	_label("A server is a program you run. Anyone can host one.")
	_button("Join local server", func() -> void: _launch("join", LOOPBACK))
	_label("Join by address")
	_host_edit = LineEdit.new()
	_host_edit.text = OS.get_environment("FRAGR_SERVER")
	if _host_edit.text.is_empty():
		_host_edit.text = LOOPBACK
	_host_edit.custom_minimum_size = Vector2(0.0, 36.0)
	_root.add_child(_host_edit)
	_button("Connect", func() -> void: _launch("join", _host_address()))
	_button("Connect as spectator", func() -> void: _launch("spectate", _host_address()))
	var browser: Button = _button("Server list", func() -> void: pass)
	browser.disabled = true
	browser.tooltip_text = "Not built yet. Run your own and share the address."
	_label("The host chooses the arena and rules.")
	_button("Back", func() -> void: _show("main"))

func _page_profile() -> void:
	_label("CALLSIGN")
	_name_edit = LineEdit.new()
	_name_edit.name = "Callsign"
	_name_edit.text = _settings.player_name()
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(0, 58)
	_name_edit.add_theme_font_size_override("font_size", 28)
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_name_edit)
	_label("RETICLE COLOUR")
	var colour: OptionButton = OptionButton.new()
	colour.name = "ReticleColour"
	colour.custom_minimum_size.y = 50
	colour.add_theme_font_size_override("font_size", 24)
	var choices: Array[String] = ["bone", "amber", "cyan"]
	for choice in choices:
		colour.add_item(choice.to_upper())
	colour.select(choices.find(str(_settings.get_value("profile", "reticle_colour"))))
	colour.item_selected.connect(func(index: int) -> void:
		_settings.set_value("profile", "reticle_colour", choices[index])
	)
	_root.add_child(colour)
	var bob: CheckButton = CheckButton.new()
	bob.name = "WeaponBob"
	bob.text = "WEAPON BOB"
	bob.add_theme_font_size_override("font_size", 24)
	bob.button_pressed = bool(_settings.get_value("gameplay", "head_bob"))
	bob.toggled.connect(func(on: bool) -> void: _settings.set_value("gameplay", "head_bob", on))
	_root.add_child(bob)
	_button("Save and back", _save_profile)
	_button("Cancel", func() -> void:
		_settings.load_from_disk()
		_show("main")
	)

func _save_profile() -> void:
	_settings.set_value("profile", "name", _name_edit.text)
	var result: Error = _settings.save_to_disk()
	if result != OK:
		_status.text = "Could not save callsign. Check available disk space."
		return
	_show("main")

func _page_settings() -> void:
	var panel: SettingsPanel = SettingsPanel.new()
	panel.name = "SettingsPanel"
	panel.preferences = _settings
	panel.closed.connect(func() -> void: _show("main"))
	_root.add_child(panel)

func _host_address() -> String:
	if _host_edit != null and not _host_edit.text.strip_edges().is_empty():
		return _host_edit.text.strip_edges()
	return LOOPBACK

func _unhandled_input(event: InputEvent) -> void:
	if _console != null and _console.is_open():
		return
	if event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE and _page != "main":
			_settings.load_from_disk()
			_show("main")
			get_viewport().set_input_as_handled()

func _launch(mode: String, host: String) -> void:
	var boot: Dictionary = {
		"mode": mode,
		"host": host,
	}
	get_tree().set_meta("fragr_boot", boot)
	var err: Error = get_tree().change_scene_to_file(ARENA_SCENE)
	if err != OK:
		push_error("boot_menu: failed to load arena scene: " + str(err))
		if _status != null:
			_status.text = "Failed to load arena (" + str(err) + ")"
