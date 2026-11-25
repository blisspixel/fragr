extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("localexception_settings_path", "user://test-multiplayer-layout-%d.cfg" % OS.get_process_id())
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_multiplayer_layout: " + message)

func _settle() -> void:
	for _frame: int in range(4):
		await process_frame

## The same press and release the Tab walk uses. A bare push_input pair can be
## dropped on the macOS display server before the focused button sees it.
func _tap(key: Key) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.physical_keycode = key
	down.keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up: InputEventKey = down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
	root.add_child(menu)
	await _settle()
	for count: int in [0, 1, 2, 20]:
		menu._book.favorites.clear()
		menu._book.recent.clear()
		for index: int in range(count):
			var address: String = "127.0.0.1:%d" % (18001 + index)
			if index < 12:
				menu._book.favorites.append(address)
			else:
				menu._book.recent.append(address)
		await menu._show("join")
		menu._stop_lan_listen()
		menu._probe.cancel_request()
		if menu._list_probe != null:
			menu._list_probe.cancel_request()
		menu._list_queue.clear()
		menu._match_line.text = "Arena Duel. Arena. 5 fighters. 0 connections. Free for all 8 ms."
		await _settle()
		var card: Rect2 = Rect2(Vector2(420, 72), Vector2(1080, 936))
		for control: Control in [menu._title, menu._page_scroll, menu._scroll_back, menu._status]:
			_check(card.grow(0.1).encloses(control.get_global_rect()),
				"fixed menu controls remain inside the card with %d saved hosts" % count)
		_check(menu._page_scroll.follow_focus and menu._page_scroll.clip_contents,
			"the bounded host list clips and follows ordinary focus")
		if count > 0:
			var last: Button = menu._saved_box.find_child("Use_127_0_0_1_%d" % (18000 + count), true, false)
			if count == 20:
				for _step: int in range(96):
					if root.gui_get_focus_owner() == last:
						break
					var tab: InputEventKey = InputEventKey.new()
					tab.physical_keycode = KEY_TAB
					tab.keycode = KEY_TAB
					tab.pressed = true
					Input.parse_input_event(tab)
					tab = tab.duplicate()
					tab.pressed = false
					Input.parse_input_event(tab)
					await process_frame
				_check(root.gui_get_focus_owner() == last, "ordinary Tab navigation reaches the twentieth host")
			last.grab_focus()
			await _settle()
			_check(menu._page_scroll.get_global_rect().grow(0.1).encloses(last.get_global_rect()),
				"focusing the final host scrolls its complete row into view")
			_check(menu._scroll_back.is_visible_in_tree() and card.encloses(menu._scroll_back.get_global_rect()),
				"Back stays visible while the last saved host is focused")
			if count == 20:
				await _tap(KEY_ENTER)
				var chosen: bool = false
				var view: Rect2 = menu._page_scroll.get_global_rect().grow(0.1)
				for _wait: int in range(30):
					view = menu._page_scroll.get_global_rect().grow(0.1)
					var card_in: bool = is_instance_valid(menu._selected_card) \
						and menu._selected_card.get_parent() == menu._saved_box \
						and view.encloses(menu._selected_card.get_global_rect())
					if menu._host_edit.text == "127.0.0.1:18020" and card_in \
							and view.encloses(last.get_global_rect()) \
							and root.gui_get_focus_owner() == last:
						chosen = true
						break
					await process_frame
				_check(chosen,
					"choosing the last host keeps it focused and scrolls its whole status card into view (text=%s focus=%s card=%s row=%s view=%s viewport=%s scale=%s)" % [
						menu._host_edit.text,
						str(root.gui_get_focus_owner()),
						menu._selected_card.get_global_rect() if is_instance_valid(menu._selected_card) else Rect2(),
						last.get_global_rect(),
						view,
						root.get_visible_rect().size,
						root.content_scale_factor,
					])
				menu._probe.cancel_request()
			var check: Control = menu._root.find_child("CheckHost", true, false) as Control
			check.grab_focus()
			await _settle()
			_check(menu._page_scroll.get_global_rect().grow(0.1).encloses(check.get_global_rect()),
				"focus returns the first action fully into view")
	await menu._show("main")
	await _settle()
	_check(not menu._page_scroll.visible and not menu._scroll_back.visible
		and menu._root.get_parent() == menu._column, "leaving Multiplayer restores the existing menu layout")
	menu.queue_free()
	await process_frame
	if _failures == 0:
		print("test_multiplayer_layout: PASS bounded empty/full host lists, focus scrolling, fixed Back and page return")
	quit(0 if _failures == 0 else 1)
