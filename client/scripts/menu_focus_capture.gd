extends SceneTree

## Rendered mixed-input menu captures for the shared focus policy (#435) and
## the Multiplayer structure (#436). Desktop only: it needs a real renderer,
## so the headless suite parses it and never runs it. Inspect the images; a
## nonblank capture is not a pass.
##
##   godot --path client --script res://scripts/menu_focus_capture.gd -- \
##     --out=/abs/dir --size=1280x720
##
## Each frame prints one JSON line naming the focus owner (the control Enter or
## A activates) and the control under the pointer, so a capture states which
## target it claims to show.

var _out: String = ""
var _size: Vector2i = Vector2i(1280, 720)
var _failures: int = 0
## Menus render into a SubViewport at exactly --size, stretched from the
## project's 1920x1080 canvas the way the window stretch does, so a tiling
## window manager cannot change the captured resolution.
var _vp: SubViewport

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "user://menu-focus-capture-%d.cfg" % OS.get_process_id())
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--size="):
			var parts: PackedStringArray = arg.trim_prefix("--size=").split("x")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				_size = Vector2i(int(parts[0]), int(parts[1]))
	_run.call_deferred()

## The canvas size `canvas_items` stretch with `expand` aspect gives a window.
static func canvas_for(window: Vector2i) -> Vector2i:
	var base: Vector2 = Vector2(1920.0, 1080.0)
	var aspect: float = float(window.x) / float(maxi(window.y, 1))
	if aspect >= base.x / base.y:
		return Vector2i(roundi(base.y * aspect), int(base.y))
	return Vector2i(int(base.x), roundi(base.x / aspect))

func _settle(frames: int = 4) -> void:
	for _frame: int in range(frames):
		await process_frame

func _point(control: Control) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	var at: Vector2 = control.get_global_rect().get_center()
	motion.position = at
	motion.global_position = at
	motion.relative = Vector2(12.0, 0.0)
	motion.screen_relative = Vector2(12.0, 0.0)
	_vp.push_input(motion, true)
	# Real motion and key events arrive on separate frames; keep that order.
	await _settle()

func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		_vp.push_input(key)

func _capture(label: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var focus: Control = _vp.gui_get_focus_owner()
	var hovered: Control = _vp.gui_get_hovered_control()
	var record: Dictionary = {
		"capture": label, "size": "%dx%d" % [_size.x, _size.y], "canvas": "%dx%d" % [_vp.size_2d_override.x, _vp.size_2d_override.y],
		"focus": str(focus.name) if focus != null else "",
		"focus_visible": focus != null and focus.has_focus(true),
		"hovered": str(hovered.name) if hovered != null else "",
	}
	print("menu_focus_capture: ", JSON.stringify(record))
	var image: Image = _vp.get_texture().get_image()
	if image == null or image.is_empty():
		_failures += 1
		push_error("menu_focus_capture: empty frame for " + label)
		return
	var path: String = _out.path_join("%s_%dx%d.png" % [label, _size.x, _size.y])
	if image.save_png(path) != OK:
		_failures += 1
		push_error("menu_focus_capture: could not write " + path)

func _buttons(parent: Node) -> Array[Button]:
	var found: Array[Button] = []
	for node: Node in parent.find_children("*", "Button", true, false):
		if (node as Button).is_visible_in_tree():
			found.append(node as Button)
	return found

func _run() -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		push_error("menu_focus_capture: needs --out=<dir> and a rendered display")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_vp = SubViewport.new()
	_vp.name = "Capture"
	_vp.size = _size
	_vp.size_2d_override = canvas_for(_size)
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
	_vp.add_child(menu)
	await _settle(8)

	# Main: the pointer rests on one row while the keyboard walks to another.
	await menu._show("main")
	var main: Array[Button] = _buttons(menu._root)
	await _point(main[3])
	await _settle()
	_key(KEY_DOWN)
	await _capture("main_pointer_then_keys")
	_key(KEY_DOWN)
	await _point(main[5])
	await _capture("main_keys_then_pointer")

	var pages: Array[String] = ["multi"]
	if menu.has_method("_page_join"):
		pages.append("join")
	for page: String in pages:
		await menu._show(page)
		await _settle()
		menu._stop_lan_listen()
		await _capture(page + "_first_focus")

	if menu.has_method("_page_join"):
		menu._book.favorites.clear()
		menu._book.recent.clear()
		for index: int in range(20):
			if index < 12:
				menu._book.favorites.append("127.0.0.1:%d" % (18001 + index))
			else:
				menu._book.recent.append("127.0.0.1:%d" % (18001 + index))
		await menu._show("join")
		menu._stop_lan_listen()
		menu._list_queue.clear()
		var last: Button = menu._saved_box.find_child("Use_127_0_0_1_18020", true, false) as Button
		if last != null:
			await _point(menu._scroll_back)
			last.grab_focus()
			await _capture("join_last_saved_focused")
			_key(KEY_ENTER)
			await _capture("join_selected_server")

	await menu._show("host")
	await _capture("host_setup")
	var more: CheckButton = menu._root.find_child("HostMoreOptions", true, false) as CheckButton
	if more != null:
		more.button_pressed = true
		await _point(more)
		_key(KEY_DOWN)
		await _capture("host_more_options")

	await menu._show("settings")
	await _settle()
	var panel: Control = menu._root.get_node("SettingsPanel")
	var tabs: Array[Button] = _buttons(panel)
	await _point(tabs[2])
	_key(KEY_DOWN)
	await _capture("settings_mixed")
	menu.queue_free()
	await _settle()

	var pause: PauseMenu = PauseMenu.new()
	_vp.add_child(pause)
	await _settle()
	pause.open()
	await _settle()
	var items: Array[Button] = _buttons(pause._column)
	await _point(items[2])
	_key(KEY_DOWN)
	await _capture("pause_mixed")
	pause.queue_free()
	await _settle()
	if _failures == 0:
		print("menu_focus_capture: PASS wrote captures to ", _out)
	quit(0 if _failures == 0 else 1)
