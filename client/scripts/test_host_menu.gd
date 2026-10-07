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
	menu._host_mode.select(1)
	menu._host_mode.item_selected.emit(1)
	_check(menu._host_map.item_count == 1 and menu._host_map.get_selected_id() == 4,
		"Sabotage preset only offers its actual validated objective map")
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
	await menu._show("multi")
	_check(child.alive and owner.state == LocalHost.State.RUNNING, "returning to Multiplayer keeps hosting")
	_check(menu._root.get_node_or_null("UseRunningServer") == null, "join page has no control that replaces the typed address")
	_check(menu._host_edit.text != owner.url, "the join address is not the owned server")
	var run: Button = menu._root.get_node("RunServer") as Button
	_check(run != null and run.text == tr("HOST_YOUR_SERVER").to_upper(), "a running server stays on its own control")
	var headings: PackedStringArray = PackedStringArray()
	var next_name: String = ""
	var passed_check: bool = false
	for node: Node in menu._root.get_children():
		if node is Label:
			headings.append((node as Label).text)
		if passed_check and node is Button and next_name.is_empty():
			next_name = node.name
		if node.name == "CheckHost":
			passed_check = true
	_check(headings.has(tr("HOST_RUN_SECTION")) and headings.has(tr("JOIN_SECTION")) and headings.has(tr("HOST_STILL_RUNNING")),
		"run and join are separate headings")
	_check(next_name == "Watch", "Watch follows Check host, with no second check between them")
	menu._host_edit.text = "remote.example:6767"
	menu._host_edit.text_changed.emit("remote.example:6767")
	run.pressed.emit()
	await process_frame
	_check(menu._page == "host" and menu._root.get_node_or_null("JoinHosted") != null and menu._root.get_node_or_null("HostAddress") == null,
		"your server opens its own page and does not use the join field")
	await menu._show("multi")
	_check(menu._host_edit.text == "remote.example:6767", "a typed join address survives the server page")
	_check(menu._root.get_node_or_null("UseRunningServer") == null, "the join page still does not replace that address")
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
	owner.queue_free()
	await process_frame
	var campaign_owner: LocalMatch = root.get_node_or_null("LocalMatch") as LocalMatch
	if campaign_owner != null:
		campaign_owner.queue_free()
		await process_frame
	if failures == 0:
		print("test_host_menu: PASS")
	quit(0 if failures == 0 else 1)
