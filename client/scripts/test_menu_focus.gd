extends SceneTree

## Mixed-input menu regressions (#435): one activation target after pointer,
## keyboard and gamepad sequences, complete focus geometry, and the failure
## paths a stationary or returning pointer could hit. Events go through the
## real viewport input path, not direct signal emission.

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "user://test-menu-focus-%d.cfg" % OS.get_process_id())
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_menu_focus: " + message)

func _settle(frames: int = 3) -> void:
	for _frame: int in range(frames):
		await process_frame

func _motion_at(at: Vector2, distance: float = 12.0) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = Vector2(distance, 0.0)
	motion.screen_relative = Vector2(distance, 0.0)
	root.push_input(motion, true)
	await _settle()

func _point(control: Control, distance: float = 12.0) -> void:
	await _motion_at(control.get_global_rect().get_center(), distance)

func _click(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.pressed = pressed
		root.push_input(click, true)
	await _settle()

func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		root.push_input(key)
	await _settle()

func _pad(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var pad: InputEventJoypadButton = InputEventJoypadButton.new()
		pad.button_index = button
		pad.pressed = pressed
		root.push_input(pad)
	await _settle()

func _focus() -> Control:
	return root.gui_get_focus_owner()

## The focus plate must frame every edge, carry a heavier rail and never be
## mistaken for hover. Checked for each control type and both contexts.
func _check_geometry(theme: Theme, type: StringName, label: String) -> void:
	var focus: StyleBoxFlat = theme.get_stylebox("focus", type) as StyleBoxFlat
	var hover: StyleBox = theme.get_stylebox("hover", type)
	_check(focus != null, label + " has a drawn focus plate")
	if focus == null:
		return
	_check(focus.border_width_top >= MenuTheme.FOCUS_FRAME and focus.border_width_right == focus.border_width_top
		and focus.border_width_bottom == focus.border_width_top, label + " focus frames top, right and bottom equally")
	_check(focus.border_width_left >= MenuTheme.FOCUS_RAIL and focus.border_width_left > focus.border_width_top,
		label + " focus adds a rail, a shape cue beyond colour")
	_check(focus.expand_margin_left == 0.0 and focus.expand_margin_right == 0.0 and focus.expand_margin_top == 0.0
		and focus.expand_margin_bottom == 0.0 and focus.shadow_size == 0,
		label + " focus is drawn inside its own rect, so clips and neighbours cannot cut an edge")
	_check(focus.border_color == MenuTheme.EMBER, label + " focus keeps the established accent")
	_check(hover != focus and not (hover is StyleBoxFlat and (hover as StyleBoxFlat).border_color == MenuTheme.EMBER),
		label + " hover never uses the selected accent")
	if hover is StyleBoxFlat:
		_check((hover as StyleBoxFlat).border_width_left < MenuTheme.FOCUS_RAIL, label + " hover has no rail")
	_check(theme.get_color("font_hover_color", type if type != MenuTheme.MENU_ITEM else &"Button") != MenuTheme.EMBER,
		label + " hover text stays plain")

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	_check(int(ProjectSettings.get_setting("gui/common/show_focus_state_on_pointer_event")) == 2,
		"focus gained by a click is drawn, so the click target is the visible Enter target")
	for context: MenuTheme.Context in [MenuTheme.Context.FRONT_END, MenuTheme.Context.GAMEPLAY]:
		var theme: Theme = MenuTheme.build(context)
		for type: StringName in [&"Button", &"OptionButton", &"CheckButton", &"CheckBox", MenuTheme.MENU_ITEM]:
			_check_geometry(theme, type, "%s/%s" % [context, type])
		_check(theme.get_type_variation_base(MenuTheme.MENU_ITEM) == &"Button", "menu rows are a Button variation")
		for toggle: StringName in [&"CheckButton", &"CheckBox"]:
			for state: String in ["pressed", "hover_pressed"]:
				var on: StyleBoxFlat = theme.get_stylebox(state, toggle) as StyleBoxFlat
				_check(on != null and on.border_color != MenuTheme.EMBER, "a switched-on %s is not drawn as selected (%s)" % [toggle, state])

	var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
	root.add_child(menu)
	await _settle(4)
	await menu._show("main")
	await _settle()
	var owner: MenuFocus = root.get_meta(MenuFocus.META) as MenuFocus
	_check(owner != null and owner.get_parent() == root and MenuFocus.attach(menu) == owner,
		"one shared focus owner per viewport, reused by every menu")
	var rows: Array[Button] = []
	for child: Node in menu._root.get_children():
		if child is Button:
			rows.append(child as Button)
	for row: Button in rows:
		_check(row.theme_type_variation == MenuTheme.MENU_ITEM and not row.has_theme_stylebox_override("focus")
			and not row.has_theme_stylebox_override("hover") and not row.has_theme_color_override("font_hover_color"),
			"menu row %s takes hover and focus from the shared theme" % row.name)
	var single: Button = menu._root.get_node("SinglePlayer")
	var callsign: Button = menu._root.get_node("CallsignButton")
	var record: Button = menu._root.get_node("ServiceRecordButton")
	var quit_row: Button = menu._root.get_node("Quit")
	_check(_focus() == single and single.has_focus(true), "the first row owns visible focus on arrival")

	# A pointer that has not moved takes nothing: a bump below the threshold.
	await _point(quit_row, 1.0)
	_check(_focus() == single, "a stationary pointer or tiny bump does not steal focus")
	# Deliberate pointer motion makes the row under it the Enter target.
	await _point(callsign)
	_check(_focus() == callsign and callsign.has_focus(true) and root.gui_get_hovered_control() == callsign,
		"deliberate pointer motion moves visible focus to the pointed row")
	# Keyboard then moves focus away from the stationary pointer.
	await _key(KEY_DOWN)
	_check(_focus() == record and root.gui_get_hovered_control() == callsign,
		"arrows move focus while the pointer stays on another row")
	_check(callsign.get_draw_mode() == BaseButton.DRAW_HOVER and not callsign.has_focus()
		and callsign.get_theme_stylebox("hover") != record.get_theme_stylebox("focus"),
		"the hovered row is drawn as hover only, never as the selected plate")
	await _key(KEY_ENTER)
	_check(menu._page == "records", "Enter activates the focused row, not the hovered one")
	await _key(KEY_ESCAPE)
	await _settle()
	_check(menu._page == "main" and _focus() == menu._root.get_node("ServiceRecordButton"),
		"Back returns focus to the row that opened the page")

	# A rebuild under a stationary pointer does not hand focus to the pointer.
	await menu._show("main")
	await _settle()
	_check(_focus() == menu._root.get_node("ServiceRecordButton"), "a page rebuild keeps the remembered focus")

	# A click activates the clicked row even when focus was elsewhere.
	var settings: Button = menu._root.get_node("Settings")
	await _click(settings)
	_check(menu._page == "settings", "a click activates the row under the pointer")
	await _key(KEY_ESCAPE)
	await _settle()
	_check(menu._page == "main", "Escape leaves settings")

	# Gamepad: the d-pad moves focus and A activates the focused row.
	await menu._show("main")
	await _settle()
	menu._root.get_node("SinglePlayer").grab_focus()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	_check(_focus() == menu._root.get_node("Multiplayer"), "the d-pad moves focus")
	await _pad(JOY_BUTTON_A)
	_check(menu._page == "multi", "A activates the focused row")

	# Window focus loss and return: the first motion only re-anchors.
	await menu._show("main")
	await _settle()
	var focused_before: Control = _focus()
	owner._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _point(menu._root.get_node("Quit"))
	_check(_focus() == focused_before, "returning to the window does not move focus on the first pointer report")
	await _point(menu._root.get_node("Quit"))
	_check(_focus() == menu._root.get_node("Quit"), "the next deliberate motion moves focus again")

	# Join view: disabled actions, text entry and partly clipped rows.
	menu._book.favorites.clear()
	menu._book.recent.clear()
	for index: int in range(20):
		if index < 12:
			menu._book.favorites.append("127.0.0.1:%d" % (18001 + index))
		else:
			menu._book.recent.append("127.0.0.1:%d" % (18001 + index))
	await menu._show("join")
	menu._stop_lan_listen()
	menu._probe.cancel_request()
	menu._list_queue.clear()
	await _settle()
	var check: Button = menu._root.find_child("CheckHost", true, false) as Button
	check.grab_focus()
	_check(menu._watch_button.disabled, "fixture: Watch waits for a check")
	await _point(menu._watch_button)
	_check(_focus() == check, "a disabled action cannot take focus from the pointer")
	menu._host_edit.grab_focus()
	await _point(check)
	_check(_focus() == menu._host_edit, "a text field keeps focus while the player types")
	var scroll: ScrollContainer = menu._page_scroll
	scroll.scroll_vertical = 0
	await _settle()
	var clipped: Button = null
	for node: Node in menu._root.find_children("Use_*", "Button", true, false):
		var row: Button = node as Button
		var rect: Rect2 = row.get_global_rect()
		if rect.intersects(scroll.get_global_rect()) and not scroll.get_global_rect().encloses(rect):
			clipped = row
			break
	_check(clipped != null, "fixture: a saved row is partly scrolled out of view")
	if clipped != null:
		check.grab_focus()
		var before: int = scroll.scroll_vertical
		await _motion_at(clipped.get_global_rect().intersection(scroll.get_global_rect()).get_center())
		_check(_focus() == check and scroll.scroll_vertical == before,
			"a partly hidden row does not take focus or scroll the list under the pointer")
	menu.queue_free()
	await _settle()

	# The match menu uses the same policy on panel buttons.
	var pause: PauseMenu = PauseMenu.new()
	root.add_child(pause)
	await _settle()
	pause.open()
	await _settle()
	var items: Array[Button] = []
	for child: Node in pause._column.get_children():
		if child is Button:
			items.append(child as Button)
	_check(_focus() == items[0], "the match menu opens on Resume")
	await _point(items[2])
	_check(_focus() == items[2], "the match menu follows deliberate pointer motion")
	await _key(KEY_UP)
	_check(_focus() == items[1] and root.gui_get_hovered_control() == items[2]
		and items[2].get_draw_mode() == BaseButton.DRAW_HOVER, "keys leave the pointed item as hover only")
	pause.queue_free()
	await _settle()
	if _failures == 0:
		print("test_menu_focus: PASS one activation target across pointer, keys, pad, rebuilds, clips and window return")
	quit(0 if _failures == 0 else 1)
