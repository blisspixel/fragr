extends SceneTree

## The ward is presentation of two server facts, never an alternate objective.
class PauseProbe extends Node:
	var menu: PauseMenu
	var toggles: int = 0
	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("pause") or (menu.is_open() and event.is_action_pressed("ui_cancel")):
			menu.toggle()
			toggles += 1
			get_viewport().set_input_as_handled()

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_m02_ward: " + message)

func _map() -> Dictionary:
	return {"map_id": M02Ward.MAP_ID, "map_name": M02Ward.MAP_NAME, "m02_objectives": 3}

func _state(attempt: int, secured: bool, released: bool, side_secured: bool = false) -> Dictionary:
	return {"id": MissionState.M02_ID, "attempt": attempt, "m02": {
		"ward_secured": secured, "side_ward_secured": side_secured,
		"evacuation": {"phase": "ready" if side_secured else "held", "captives":
			[[22.6, 0.0, 7.5], [24.5, 0.0, 7.5]] if side_secured else [[22.6, 0.0, 9.0], [24.5, 0.0, 9.0]], "evacuated": false},
		"completed": ["ward_reached", "companion_released"] if released else ["ward_reached"]}}

func _run() -> void:
	var ward: M02Ward = M02Ward.new()
	root.add_child(ward)
	ward.configure_map({"map_id": 1, "map_name": M02Ward.MAP_NAME, "m02_objectives": 3})
	_check(not ward._built, "the setpiece stays off unrelated maps")
	ward.configure_map(_map())
	_check(ward._built and ward._latch != null and ward._other_captive != null, "the bundled ward has two visible figures")
	_check(ward._side_captives.size() == 2 and not ward._side_captives[0].visible and not ward._side_captives[1].visible,
		"side-ward figures wait for the optional server state")
	for part: Node in ward._latch.find_children("*", "VisualInstance3D", true, false):
		_check((part as VisualInstance3D).layers == ArenaSky.ACTOR_LAYERS,
			"the fixed and moving Latch share the facility actor lighting layer")
	_check(ward._transfer_list != null and not ward._transfer_list.visible, "the transfer list is hidden until release")
	ward.apply_state(_state(1, false, false))
	_check(ward._side_captives[0].visible and ward._side_captives[1].visible,
		"two figures appear only after the server supplies evacuation state")
	_check(not ward._secured and not ward._released and ward._release_elapsed < 0.0, "initial projection keeps Latch restrained")
	_check(ward._side_release_elapsed < 0.0 and ward._side_left_bars[0].position.x > -0.5,
		"the optional captives remain behind their restraints before a server win")
	ward.apply_state(_state(1, true, false))
	_check(ward._secured and not ward._released and not (ward._machine_lamp.material_override as StandardMaterial3D).emission_enabled,
		"the correction machine stops on ward victory before restraint use")
	ward.apply_state(_state(1, true, false, true))
	ward._process(1.0)
	_check(ward._side_left_bars[0].position.x < -0.9 and ward._side_captives[0].position.z < M02Ward.SIDE_CAPTIVE_FEET[0].z,
		"the side captives visibly open their own restraints and step away on a server win")
	ward._process(M02Ward.SIDE_RELEASE_SECONDS)
	_check(ward._side_release_elapsed == M02Ward.SIDE_RELEASE_SECONDS and ward._side_captives[1].position.z < 8.0,
		"the optional release settles into a free pose")
	ward.apply_state(_state(1, true, false, true))
	_check(ward._side_release_elapsed == M02Ward.SIDE_RELEASE_SECONDS,
		"duplicate side ward state does not replay the release")
	ward.apply_state(_state(1, true, true, true))
	_check(ward._release_elapsed == 0.0 and ward._second_left.position.x > -0.5,
		"the server release begins with the second bay shut")
	_check(ward._latch.visible,
		"an observed local release keeps Latch visible before its first releasing snapshot")
	ward.set_companion_phase("releasing")
	_check(ward._latch.visible and ward._latch is LatchView,
		"the tableau keeps the shared Latch chassis while the server pawn releases")
	ward._process(M02Ward.CROSS_END)
	_check(ward._second_left.position.x > -0.5 and ward._caption_key != "M02_LATCH_SPEECH",
		"Latch crosses the ward before the second door moves or speech begins")
	ward._process(0.6)
	_check(ward._second_left.position.x < -0.6 and ward._caption_key != "M02_LATCH_SPEECH",
		"the second occupied restraint visibly starts opening before speech")
	ward._process(0.51)
	_check(ward._second_left.position.x < -0.9 and ward._second_right.position.x > 0.9
		and ward._caption_key == "M02_LATCH_SPEECH" and not ward._transfer_list.visible,
		"both door leaves open before Latch speaks")
	ward._process(1.4)
	_check(ward._transfer_list.visible and ward._caption_key == "M02_LOW_WATER"
		and ward._copy.text.contains("LOW WATER"), "the transfer list and legible Low Water beat follow speech")
	var elapsed: float = ward._release_elapsed
	ward.apply_state(_state(1, true, true, true))
	_check(ward._release_elapsed == elapsed, "duplicate mission projection does not replay the release")
	var menu: PauseMenu = PauseMenu.new()
	menu.development_mission = true
	root.add_child(menu)
	ward.pause_menu = menu
	var pause_probe: PauseProbe = PauseProbe.new()
	pause_probe.menu = menu
	root.add_child(pause_probe)
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	_check(escape.is_action_pressed("pause") and escape.is_action_pressed("ui_cancel"), "Escape names both pause and skip in the current input map")
	var back: InputEventJoypadButton = InputEventJoypadButton.new()
	back.device = -1
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	_check(back.is_action_pressed("ui_cancel") and not back.is_action_pressed("pause"), "gamepad Back closes the menu without acting as Start")
	menu.open()
	await process_frame
	root.push_input(back)
	await process_frame
	_check(not menu.is_open() and pause_probe.toggles == 1 and ward._release_elapsed < M02Ward.END_SECONDS,
		"gamepad Back closes an open menu without skipping the release")
	menu.open()
	await process_frame
	root.push_input(escape)
	await process_frame
	_check(not menu.is_open() and pause_probe.toggles == 2 and ward._release_elapsed < M02Ward.END_SECONDS,
		"Escape closes an already open match menu without skipping the release (open %s, toggles %d, elapsed %.2f)" % [str(menu.is_open()), pause_probe.toggles, ward._release_elapsed])
	var release: InputEventKey = escape.duplicate()
	release.pressed = false
	root.push_input(release)
	root.push_input(escape)
	await process_frame
	_check(ward._release_elapsed == M02Ward.END_SECONDS and pause_probe.toggles == 2,
		"ward skip consumes Escape before a closed match menu sees it (elapsed %.2f, toggles %d)" % [ward._release_elapsed, pause_probe.toggles])
	pause_probe.queue_free()
	menu.queue_free()
	ward.skip_presentation()
	_check(ward._transfer_list.visible and ward._second_left.position.x < -0.9 and not ward._card.visible,
		"skipping hides text while preserving the server-derived opened bay")
	_check(absf(wrapf(ward._latch.rotation.y + PI / 2.0, -PI, PI)) < 0.01,
		"the tableau faces the server pawn's initial direction before handoff")
	ward.set_companion_phase("following")
	_check(not ward._latch.visible and ward._transfer_list.visible,
		"the first following snapshot hands visible Latch to the moving server pawn")
	var route: Dictionary = _state(1, true, true, true)
	route["m02"]["evacuation"] = {"phase": "moving", "captives": [[18.0, 0.0, 9.0], [19.0, 0.0, 9.0]], "evacuated": false}
	var before_route: Vector3 = ward._side_captives[0].position
	ward.apply_state(route)
	ward._process(0.05)
	_check(ward._side_captives[0].position.x < before_route.x and ward._side_captives[0].position.x > 18.0,
		"moving captives interpolate toward server feet without a snap")
	_check((ward._side_captives[0].get_node("LeftLeg") as Node3D).rotation.x != 0.0,
		"server-driven travel has a visible walking pose")
	ward._process(1.0)
	_check(ward._side_captives[0].position.distance_to(Vector3(18.0, 0.0, 9.0)) < 0.01,
		"the first captive reaches the server sample")
	route["m02"]["evacuation"] = {"phase": "waiting", "captives": [[10.0, 0.0, 11.0], [11.0, 0.0, 11.0]], "evacuated": false}
	ward.apply_state(route)
	ward._process(0.25)
	_check(ward._side_captives[0].position.distance_to(Vector3(10.0, 0.0, 11.0)) < 0.01,
		"both figures can wait at the authoritative floor positions")
	route["m02"]["evacuation"] = {"phase": "evacuated", "captives": [[1.0, 0.0, 20.0], [2.0, 0.0, 20.0]], "evacuated": true}
	ward.apply_state(route)
	ward._process(0.25)
	_check(ward._side_captives[0].position.distance_to(Vector3(1.0, 0.0, 20.0)) < 0.01,
		"both figures appear at the authoritative dock arrival, without inventing success")
	ward.apply_state(_state(2, false, false))
	_check(not ward._secured and not ward._released and ward._latch.visible
		and not ward._transfer_list.visible and ward._second_left.position.x > -0.5,
		"retry reconstructs the restrained ward")
	_check(ward._side_release_elapsed < 0.0 and ward._side_captives[0].position == M02Ward.SIDE_CAPTIVE_FEET[0]
		and ward._side_left_bars[0].position.x > -0.5,
		"retry reconstructs both side captives behind their restraints")
	ward.clear_map()
	ward.configure_map(_map())
	var no_side_ward: Dictionary = _state(2, false, false)
	no_side_ward["m02"].erase("evacuation")
	ward.apply_state(no_side_ward)
	_check(not ward._side_captives[0].visible and not ward._side_captives[1].visible,
		"a legal M02 map without side-ward state draws no captive figures")
	ward.clear_map()
	ward.configure_map(_map())
	var joined_route: Dictionary = _state(2, true, true, true)
	joined_route["m02"]["evacuation"] = {"phase": "waiting", "captives": [[-5.2, 0.0, 11.0], [-3.5, 0.0, 11.0]], "evacuated": false}
	ward.apply_state(joined_route)
	_check(ward._side_captives[0].position == Vector3(-5.2, 0.0, 11.0)
		and ward._side_captives[1].position == Vector3(-3.5, 0.0, 11.0),
		"a late observer starts both figures at the server's current feet without replaying travel")
	ward.clear_map()
	ward.configure_map(_map())
	ward.apply_state(_state(2, true, true, true))
	_check(ward._transfer_list.visible and ward._second_left.position.x < -0.9 and ward._caption_key == "M02_RELEASE_RECAP"
		and ward._copy.text.contains("LOW WATER"), "late observers receive the final open bay and recap")
	_check(ward._side_release_elapsed == M02Ward.SIDE_RELEASE_SECONDS and ward._side_captives[1].position.z < 8.0,
		"late observers see the optional captives already free")
	_check(not ward._latch.visible,
		"state-first late join waits for a companion snapshot before showing fixed Latch")
	ward.set_companion_phase("")
	_check(not ward._latch.visible,
		"a first snapshot without the companion does not briefly resurrect fixed Latch")
	ward.set_companion_phase("releasing")
	_check(ward._latch.visible,
		"a releasing snapshot resolves a state-first late join to the ward tableau")
	ward.set_companion_phase("firing")
	_check(not ward._latch.visible and ward._transfer_list.visible,
		"a late observer sees the moving ally without a duplicate ward figure")
	ward.set_companion_phase("departed")
	_check(not ward._latch.visible and ward._transfer_list.visible,
		"a departed mission does not resurrect the ward figure if the actor is omitted")
	ward.clear_map()
	ward.configure_map(_map())
	ward.apply_state(_state(2, true, true))
	ward.set_companion_phase("following")
	_check(not ward._latch.visible and ward._transfer_list.visible,
		"state-first late join resolves directly to a moving companion without a fixed flash")
	ward.clear_map()
	ward.configure_map(_map())
	ward.set_companion_phase("following")
	ward.apply_state(_state(2, true, true))
	_check(not ward._latch.visible and ward._transfer_list.visible,
		"a snapshot arriving before first MissionState keeps the fixed figure hidden")
	var voice_bus: int = AudioServer.get_bus_index(&"Voice")
	if voice_bus >= 0:
		var muted: bool = AudioServer.is_bus_mute(voice_bus)
		AudioServer.set_bus_mute(voice_bus, true)
		ward._show_caption("M02_LATCH_SPEECH", 1.0)
		_check(not ward._copy.text.is_empty(), "muted Voice still has keyed text")
		AudioServer.set_bus_mute(voice_bus, muted)
	_check(ward.find_children("*", "AudioStreamPlayer", true, false).is_empty(), "missing voice asset cannot stall the text sequence")
	for key: String in ["M02_WARD_STOPPED", "M02_LATCH_RELEASE", "M02_LATCH_HEADING", "M02_LATCH_SPEECH", "M02_LOW_WATER",
		"M02_RELEASE_RECAP", "M02_TRANSFER_LIST", "M02_SKIP_HINT"]:
		_check(not WorldSign.localized(key).is_empty(), "keyed release copy exists: " + key)
	ward.queue_free()
	await process_frame
	if failures == 0:
		print("test_m02_ward: PASS ordered bay and side releases, server facts, late join, retry, skip, muted fallback")
	quit(0 if failures == 0 else 1)
