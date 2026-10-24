extends SceneTree

class Child extends LocalProcess:
	var alive: bool = false
	var output: PackedByteArray = PackedByteArray()
	var args: PackedStringArray = PackedStringArray()
	var stops: int = 0
	func start(_executable: String, arguments: PackedStringArray) -> bool:
		alive = true
		args = arguments
		return true
	func running() -> bool:
		return alive
	func read_output() -> PackedByteArray:
		var bytes: PackedByteArray = output
		output = PackedByteArray()
		return bytes
	func drain_errors() -> void:
		pass
	func request_stop() -> void:
		stops += 1
		alive = false
	func dispose() -> void:
		alive = false

class Owner extends LocalHost:
	func executable_path() -> String:
		return "fixture-native"

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_host_menu: " + message)

func _run() -> void:
	var owner: Owner = Owner.new()
	owner.name = "LocalHost"
	var child: Child = Child.new()
	owner.process = child
	root.add_child(owner)
	var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
	menu.set("_settings", FragrSettings.new("user://test-host-menu-%d.cfg" % OS.get_process_id()))
	root.add_child(menu)
	await process_frame
	await menu._show("host")
	_check(menu._local_host == owner and menu._host_mode.selected == 0, "real menu resolves one existing root owner and defaults TDM")
	_check(menu._host_map.item_count == 6 and menu._host_map.get_selected_id() == 1,
		"TDM offers all six registered maps with Arena Duel default")
	_check(not menu._host_lan.button_pressed and not menu._host_port.editable,
		"hosting defaults to this computer rather than opening LAN")
	_check(menu._host_bot_policy.selected == 0 and menu._host_bots.value == 4,
		"fixed four remains the initial bot profile")
	_check(menu._host_bot_policy.is_visible_in_tree() and not menu._host_more.button_pressed and not menu._host_advanced.visible
		and menu._root.get_node("HostMoreOptions").get_index() < menu._root.get_node("StartServer").get_index(),
		"default hosting shows mode, map and an explicit bot policy; rules and network fold before Start")
	menu._host_more.button_pressed = true
	_check(menu._host_advanced.visible and menu._host_lan.is_visible_in_tree() and menu._host_mutator.is_visible_in_tree(),
		"one switch discloses rules, friendly fire, LAN and port")
	await menu._show("host")
	_check(menu._host_advanced.visible, "the disclosure stays open across a page rebuild")
	menu._host_more.button_pressed = false
	_check(not menu._host_advanced.visible, "the disclosure folds again")
	# A failed start leaves the setup page with its reason, Start again and Back,
	# and Multiplayer does not claim a running match.
	owner.error_key = "LOCAL_SERVER_START_FAILED"
	await menu._show("host")
	var host_error: Label = menu._root.get_node_or_null("HostError") as Label
	var failed_start: Button = menu._root.get_node_or_null("StartServer") as Button
	_check(host_error != null and host_error.text == tr("LOCAL_SERVER_START_FAILED") and failed_start != null and not failed_start.disabled
		and menu._root.get_node_or_null("HostBack") != null and menu.get_viewport().gui_get_focus_owner() != null,
		"a failed start shows its reason beside a usable Start and Back")
	await menu._show("multi")
	_check(menu._root.get_node_or_null("RunningMatch") == null
		and (menu._root.get_node("RunServer") as Button).text == tr("HOST_CREATE").to_upper(),
		"after a failed start Multiplayer offers Run a match, not a running card")
	owner.error_key = ""
	# Leave the way a player does, through Run a match.
	var run_again: Button = menu._root.get_node("RunServer") as Button
	run_again.grab_focus()
	run_again.pressed.emit()
	await process_frame
	await process_frame
	_check(menu._page == "host" and menu._root.get_node_or_null("HostError") == null, "Run a match reopens setup without the old error")
	menu._host_bots.value = 7
	menu._host_bot_policy.select(2)
	menu._host_bot_policy.item_selected.emit(2)
	_check(menu._host_bots_label.text == tr("HOST_TOTAL_FIGHTERS") and menu._host_bots.value == 4
		and menu._host_bots.min_value == 1 and menu._host_bots_row.visible,
		"automatic fill clearly asks for desired total fighters")
	menu._host_bots.value = 10
	menu._host_bot_policy.select(1)
	menu._host_bot_policy.item_selected.emit(1)
	_check(not menu._host_bots_row.visible and menu._host_bots.value == 0,
		"explicit no bots hides the unused count")
	menu._host_bot_policy.select(0)
	menu._host_bot_policy.item_selected.emit(0)
	_check(menu._host_bots.value == 7 and menu._host_bots.min_value == 0
		and menu._host_bots_label.text == tr("HOST_BOT_COUNT"), "fixed count survives policy switching and accepts zero")
	menu._host_bot_policy.select(2)
	menu._host_bot_policy.item_selected.emit(2)
	_check(menu._host_bots.value == 10, "automatic target survives policy switching")
	menu._host_bot_policy.select(1)
	menu._host_bot_policy.item_selected.emit(1)
	menu._host_mode.select(2)
	menu._host_mode.item_selected.emit(2)
	_check(menu._host_map.item_count == 1 and menu._host_map.get_selected_id() == 7,
		"Conquest offers its registered island through the ordinary Host form")
	menu._host_mode.select(1)
	menu._host_mode.item_selected.emit(1)
	_check(menu._host_map.item_count == 2 and menu._host_map.get_item_id(0) == 4
		and menu._host_map.get_item_id(1) == 8 and menu._host_map.get_selected_id() == 4,
		"Sabotage offers exactly Sector 9 and Low Water, defaulting to Sector 9")
	menu._host_bot_policy.select(2)
	menu._host_bot_policy.item_selected.emit(2)
	_check(menu._host_bots.value == 10, "5v5 Sabotage defaults automatic fill to ten fighters")
	menu._host_bots.value = 8
	menu._host_mode.select(0)
	menu._host_mode.item_selected.emit(0)
	menu._host_mode.select(1)
	menu._host_mode.item_selected.emit(1)
	_check(menu._host_bots.value == 8, "deliberate per-mode automatic count survives mode switching")
	menu._host_bot_policy.select(1)
	menu._host_bot_policy.item_selected.emit(1)
	menu._host_map.select(1)
	_check(menu._host_map.get_selected_id() == 8, "Low Water is selectable through the ordinary Sabotage form")
	menu._host_map.select(0)
	menu._host_bots.value = 0
	menu._host_lan.button_pressed = true
	menu._host_lan.toggled.emit(true)
	menu._host_port.value = 16867
	_check(menu._host_port.editable, "LAN opt-in exposes the selected port")
	var start: Button = menu._root.get_node("StartServer")
	start.pressed.emit()
	_check(owner.state == LocalHost.State.STARTING and child.args == PackedStringArray([
		"--desktop-host", "--bind", "0.0.0.0:16867", "--mode", "sabotage", "--map", "4", "--bots", "0",
		"--bot-policy", "none", "--fill-target", "0", "--sabotage-five-v-five"]),
		"ordinary menu activation starts exact first preset through canonical native flags")
	_check(menu._root.get_node_or_null("JoinHosted") == null, "starting child is not presented as joinable")
	var ready: Dictionary = {"version": 1, "kind": "arena", "url": "ws://127.0.0.1:16867", "listen": "0.0.0.0:16867",
		"map_id": 4, "mode": "sabotage", "five_vs_five": true, "bots": 0, "bot_policy": "none", "fill_target": 0, "gameplay_version": LocalHost.GAMEPLAY_VERSION}
	child.output = (JSON.stringify(ready) + "\n").to_ascii_buffer()
	owner._process(0)
	await process_frame
	_check(menu._root.get_node_or_null("JoinHosted") != null and menu._root.get_node_or_null("StopServer") != null,
		"accepted actual-shaped readiness exposes Watch Join and Stop separately")
	await menu._show("main")
	_check(menu._root.get_node_or_null("RejoinHosted") != null, "main menu exposes the still-running match")
	await menu._show("multi")
	var run: Button = menu._root.get_node_or_null("RunServer") as Button
	var running_card: Label = menu._root.get_node_or_null("RunningMatch") as Label
	_check(running_card != null and running_card.text == tr("HOST_RUNNING") % tr("HOST_SABOTAGE"),
		"Multiplayer leads with a card for the match this app is running")
	_check(run != null and run.text == tr("HOST_YOUR_SERVER").to_upper() and run.get_index() < menu._root.get_node("FindMatch").get_index(),
		"the running match is managed from its own control, above Find / join")
	_check(menu.get_viewport().gui_get_focus_owner() == run, "the running match control owns focus on arrival")
	_check(child.alive and owner.state == LocalHost.State.RUNNING, "returning to Multiplayer keeps hosting")
	await menu._show("join")
	_check(menu._match_line.text == "Check this address to join a different server.", "an owned match does not automatically probe an unrelated join address")
	_check(menu._root.find_child("UseRunningServer", true, false) == null, "join page has no control that replaces the typed address")
	_check(menu._host_edit.text != owner.url, "the join address is not the owned server")
	_check(menu._watch_button.disabled and menu._join_button.disabled,
		"an unchecked remote address never inherits the running local match's admission")
	menu._host_edit.text = "remote.example:6767"
	menu._host_edit.text_changed.emit("remote.example:6767")
	await menu._show("multi")
	run = menu._root.get_node("RunServer") as Button
	run.pressed.emit()
	await process_frame
	_check(menu._page == "host" and menu._root.get_node_or_null("JoinHosted") != null and menu._root.find_child("HostAddress", true, false) == null,
		"your server opens its own page and does not use the join field")
	_check(menu._root.get_node("WatchHosted").get_index() < menu._root.get_node("JoinHosted").get_index()
		and menu._root.get_node("JoinHosted").get_index() < menu._root.get_node("StopServer").get_index(),
		"the running card keeps Watch, Join and Stop as separate explicit actions")
	var escape: InputEventKey = InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	menu._unhandled_input(escape)
	await process_frame
	_check(menu._page == "multi" and menu.get_viewport().gui_get_focus_owner() == menu._root.get_node("RunServer"),
		"Escape from the running card returns to Multiplayer with its control focused")
	await menu._show("join")
	_check(menu._host_edit.text == "remote.example:6767", "a typed join address survives the server page")
	_check(menu._root.find_child("UseRunningServer", true, false) == null, "the join page still does not replace that address")
	menu.queue_free()
	await process_frame
	_check(child.alive and owner.state == LocalHost.State.RUNNING, "boot scene retirement does not stop shared arena")
	var pause: PauseMenu = PauseMenu.new()
	pause.hosting_server = true
	var stops: Array[bool] = []
	pause.stop_server_requested.connect(func() -> void: stops.append(true))
	root.add_child(pause)
	await process_frame
	var stop_button: Button
	for node: Node in pause._column.get_children():
		if node is Button and (node as Button).text == tr("HOST_STOP"):
			stop_button = node as Button
	_check(stop_button != null, "owning host match menu has explicit Stop Server action")
	if stop_button != null:
		stop_button.pressed.emit()
	_check(stops == [true] and child.alive, "pause action emits its owning boundary without independently killing a server")
	pause.queue_free()
	owner.stop()
	owner._process(0)
	_check(owner.state == LocalHost.State.IDLE and not child.alive and child.stops == 1, "only explicit owner stop closes the native lease")
	var returned: Control = load("res://scenes/boot_menu.tscn").instantiate()
	returned.set("_settings", FragrSettings.new("user://test-host-return-%d.cfg" % OS.get_process_id()))
	root.add_child(returned)
	await process_frame
	await returned._show("host")
	_check(returned._host_mode.selected == 1 and returned._host_bot_policy.selected == 1
		and returned._host_lan.button_pressed and returned._host_port.value == 16867,
		"returning from a match restores its last host profile after stop")
	_check(returned._host_advanced.visible and returned._host_more.button_pressed,
		"a remembered LAN profile opens its folded options rather than hiding them")
	returned._host_bot_policy.select(2)
	returned._host_bot_policy.item_selected.emit(2)
	returned._host_bots.value = 8
	returned._start_host()
	returned.queue_free()
	await process_frame
	owner.stop()
	owner._process(0)
	var reopened: Control = load("res://scenes/boot_menu.tscn").instantiate()
	reopened.set("_settings", FragrSettings.new("user://test-host-reopen-%d.cfg" % OS.get_process_id()))
	root.add_child(reopened)
	await process_frame
	await reopened._show("host")
	_check(reopened._host_bot_policy.selected == 2 and reopened._host_bots.value == 8,
		"automatic fill and deliberate count survive menu replacement and server stop")
	reopened.queue_free()
	await process_frame
	owner.queue_free()
	await process_frame
	var campaign_owner: LocalMatch = root.get_node_or_null("LocalMatch") as LocalMatch
	if campaign_owner != null:
		campaign_owner.queue_free()
		await process_frame
	if failures == 0:
		print("test_host_menu: PASS")
	quit(0 if failures == 0 else 1)
