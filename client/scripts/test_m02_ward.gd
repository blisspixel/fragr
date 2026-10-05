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
	return {"map_id": M02Ward.MAP_ID, "map_name": M02Ward.MAP_NAME, "m02_objectives": 3,
		"geometry_version": 2, "half_extent": 40.0,
		"solids": [{"min_x": 8.0, "max_x": 9.0, "bottom": 0.0, "top": 2.6, "min_z": -13.0, "max_z": -9.0}]}

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
	_check(ward._notary != null and ward._notary.get_node_or_null("NotaryBody/LeftDuct") != null
		and ward._notary.get_node_or_null("NotaryBody/RightDuct") != null
		and ward._notary.get_node_or_null("NotaryBody/DimOptic") != null,
		"the M02 bay shows one canonical ducted-fan Notary silhouette")
	_check(ward._notary.find_children("*", "VisualInstance3D", true, false).size() <= 22,
		"the observation model stays bounded for a later source bake")
	var latch: LatchView = ward._latch
	var source_mesh: MeshInstance3D = latch._source_body.get_node("Armature/Skeleton3D/char1") as MeshInstance3D
	var skeleton: Skeleton3D = latch._source_body.get_node("Armature/Skeleton3D") as Skeleton3D
	_check(latch.find_children("*", "VisualInstance3D", true, false).size() <= 40,
		"the shared local chassis stays within a bounded mesh count")
	_check(source_mesh != null and source_mesh.skin != null and skeleton.get_bone_count() == 24
		and is_equal_approx(source_mesh.mesh.get_aabb().size.y, 1.8)
		and is_zero_approx(source_mesh.mesh.get_aabb().position.y),
		"the reviewed civilian source retains weighted skin and registered 1.8 metre feet")
	var finish: StandardMaterial3D = source_mesh.material_override as StandardMaterial3D
	_check(finish != null and finish.albedo_texture != null and finish.normal_texture != null
		and finish.albedo_texture.get_width() <= 1024 and finish.normal_texture.get_width() <= 1024,
		"the real workshop finish and normal map survive bounded preparation")
	_check(latch.get_node("PixelEyes") is MeshInstance3D
		and (latch._eyes.material_override as StandardMaterial3D).emission_enabled,
		"friendly optics remain independently emissive")
	var resting_hand: Transform3D = latch._source.bone_transform(latch._source_body, "RightHand")
	_check(ward._side_captives.size() == 2 and not ward._side_captives[0].visible and not ward._side_captives[1].visible,
		"side-ward figures wait for the optional server state")
	for part: Node in ward._latch.find_children("*", "VisualInstance3D", true, false):
		_check((part as VisualInstance3D).layers == ArenaSky.ACTOR_LAYERS,
			"the fixed and moving Latch share the facility actor lighting layer")
	_check(ward._transfer_list != null and not ward._transfer_list.visible, "the transfer list is hidden until release")
	ward.apply_state(_state(1, false, false))
	_check(ward._notary.visible and (ward._notary.get_node("NotaryBody/DimOptic") as MeshInstance3D).visible,
		"held captives retain the dim observation pose")
	_check(ward._ward_machine_sound.playing and ward._floor_machine_sound.playing,
		"initial mission state starts the spatial ward and floor beds")
	_check(not ward._ward_stop_sound.playing and not ward._release_sound.playing
		and not ward._second_release_sound.playing and not ward._side_release_sound.playing,
		"initial state does not invent a stop or restraint release")
	_check(ward._ward_machine_sound.bus == &"Effects" and ward._floor_machine_sound.bus == &"Effects"
		and ward._ward_machine_sound.max_distance < 30.0 and ward._floor_machine_sound.max_distance < 30.0,
		"the machinery beds use the bounded spatial Effects mix")
	_check((ward._ward_machine_sound.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD
		and (ward._floor_machine_sound.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"both baked machinery beds repeat without restarting in script")
	var missing: AudioStreamPlayer3D = ward._audio_player("MissingProbe", "missing_effect.wav", Vector3.ZERO, 0.0, 4.0, 12.0)
	ward._play_audio(missing)
	_check(missing.stream == null and not missing.playing, "a missing sound file leaves the server presentation usable")
	_check(ward._side_captives[0].visible and ward._side_captives[1].visible,
		"two figures appear only after the server supplies evacuation state")
	_check(not ward._secured and not ward._released and ward._release_elapsed < 0.0, "initial projection keeps Latch restrained")
	_check(ward._side_release_elapsed < 0.0 and ward._side_left_bars[0].position.x > -0.5,
		"the optional captives remain behind their restraints before a server win")
	ward.apply_state(_state(1, true, false))
	_check(ward._ward_stop_sound.playing and ward._machine_fade_elapsed == 0.0,
		"a live ward victory plays the machine decay and fades the bed")
	ward._process(M02Ward.MACHINE_FADE_SECONDS)
	_check(not ward._ward_machine_sound.playing and ward._machine_fade_elapsed < 0.0,
		"the ward bed reaches silence after its short fade")
	ward._ward_stop_sound.stop()
	ward.apply_state(_state(1, true, false))
	_check(not ward._ward_stop_sound.playing, "duplicate ward state cannot replay its stop")
	_check(ward._secured and not ward._released and not (ward._machine_lamp.material_override as StandardMaterial3D).emission_enabled,
		"the correction machine stops on ward victory before restraint use")
	ward.apply_state(_state(1, true, false, true))
	_check(ward._side_release_sound.playing, "the optional ward uses its own local restraint sound")
	ward._process(1.0)
	_check(ward._side_left_bars[0].position.x < -0.9 and ward._side_captives[0].position.z < M02Ward.SIDE_CAPTIVE_FEET[0].z,
		"the side captives visibly open their own restraints and step away on a server win")
	ward._process(M02Ward.SIDE_RELEASE_SECONDS)
	_check(ward._side_release_elapsed == M02Ward.SIDE_RELEASE_SECONDS and ward._side_captives[1].position.z < 8.0,
		"the optional release settles into a free pose")
	ward.apply_state(_state(1, true, false, true))
	_check(ward._side_release_elapsed == M02Ward.SIDE_RELEASE_SECONDS,
		"duplicate side ward state does not replay the release")
	ward._side_release_sound.stop()
	ward.apply_state(_state(1, true, false, true))
	_check(not ward._side_release_sound.playing, "duplicate side state cannot restart its release sound")
	ward.apply_state(_state(1, true, true, true))
	_check(ward._notary.visible and (ward._notary.get_node("NotaryBody/DimOptic") as MeshInstance3D).visible,
		"the Notary remains separate from Latch's release and the side captives")
	_check(ward._release_sound.playing, "Latch's live release plays at the primary restraint")
	_check(not ward._second_release_sound.playing and ward._second_release_sound.position.distance_to(M02Ward.SECOND_FEET) < 1.5,
		"the second restraint cue waits at the correct bay")
	_check(ward._release_elapsed == 0.0 and ward._second_left.position.x > -0.5,
		"the server release begins with the second bay shut")
	_check(ward._latch.visible,
		"an observed local release keeps Latch visible before its first releasing snapshot")
	ward.set_companion_phase("releasing")
	_check(not ward._latch.visible and ward._latch is LatchView,
		"the actual releasing snapshot hands the visible body to the authoritative pawn")
	ward._process(M02Ward.CROSS_END)
	_check(ward._second_left.position.x > -0.5 and ward._caption_key != "M02_LATCH_SPEECH",
		"Latch crosses the ward before the second door moves or speech begins")
	_check(ward._second_release_sound.playing,
		"crossing the second bay threshold starts its local mechanism cue before the door moves")
	ward._second_release_sound.stop()
	ward._process(0.6)
	_check(ward._second_left.position.x < -0.6 and ward._caption_key != "M02_LATCH_SPEECH",
		"the second occupied restraint visibly starts opening before speech")
	_check(not ward._second_release_sound.playing, "later release frames do not restart the second restraint cue")
	ward._process(0.51)
	_check(ward._second_left.position.x < -0.9 and ward._second_right.position.x > 0.9
		and ward._caption_key == "M02_LATCH_SPEECH" and not ward._transfer_list.visible,
		"both door leaves open before Latch speaks")
	var release_hand: Transform3D = latch._source.bone_transform(latch._source_body, "RightHand")
	var release_left: Transform3D = latch._source.bone_transform(latch._source_body, "LeftHand")
	_check(release_hand.origin.y > resting_hand.origin.y + 0.25
		and release_hand.origin.z > resting_hand.origin.z + 0.2
		and not release_hand.basis.is_equal_approx(resting_hand.basis)
		and release_left.origin.y > 1.05,
		"actual skinned arm reaches, rotates the palm and braces with the other arm at the second restraint")
	ward._process(1.4)
	_check(ward._transfer_list.visible and ward._caption_key == "M02_LOW_WATER"
		and ward._copy.text.contains("LOW WATER"), "the transfer list and legible Low Water beat follow speech")
	var elapsed: float = ward._release_elapsed
	ward.apply_state(_state(1, true, true, true))
	_check(ward._release_elapsed == elapsed and not ward._second_release_sound.playing,
		"duplicate mission projection does not replay either restraint release")
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
	_check(not ward._release_sound.playing and not ward._second_release_sound.playing
		and not ward._side_release_sound.playing and not ward._ward_stop_sound.playing,
		"skipping the scene silences unfinished one-shots")
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
	_check(ward._notary.visible and (ward._notary.get_node("NotaryBody/DimOptic") as MeshInstance3D).visible,
		"retry keeps one passive observation without a second actor")
	_check(ward._ward_machine_sound.playing and ward._floor_machine_sound.playing
		and not ward._ward_stop_sound.playing and not ward._release_sound.playing
		and not ward._second_release_sound.playing,
		"retry restores both beds and suppresses old one-shots")
	_check(latch._source.bone_transform(latch._source_body, "RightHand").is_equal_approx(resting_hand)
		and is_zero_approx(latch._release),
		"retry returns actual skinned palm and arm to the restrained pose")
	_check(not ward._secured and not ward._released and ward._latch.visible
		and not ward._transfer_list.visible and ward._second_left.position.x > -0.5,
		"retry reconstructs the restrained ward")
	_check(ward._side_release_elapsed < 0.0 and ward._side_captives[0].position == M02Ward.SIDE_CAPTIVE_FEET[0]
		and ward._side_left_bars[0].position.x > -0.5,
		"retry reconstructs both side captives behind their restraints")
	ward.apply_state(_state(2, true, true))
	ward.skip_presentation()
	ward._process(M02Ward.CROSS_END)
	_check(not ward._second_release_sound.playing,
		"skipping before the second bay prevents its timed cue on later frames")
	var clearing_bed: AudioStreamPlayer3D = ward._ward_machine_sound
	ward.clear_map()
	_check(not clearing_bed.playing and ward._ward_machine_sound == null,
		"map clear stops the old loop before removing its owner")
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
	_check(ward._notary.visible and (ward._notary.get_node("NotaryBody/DimOptic") as MeshInstance3D).visible,
		"a late observer sees one passive Notary independent of either captive release")
	_check(not ward._ward_machine_sound.playing and ward._floor_machine_sound.playing
		and not ward._ward_stop_sound.playing and not ward._release_sound.playing
		and not ward._second_release_sound.playing
		and not ward._side_release_sound.playing,
		"a late observer hears only the current floor bed, without historical one-shots")
	_check(ward._side_captives[0].position == Vector3(-5.2, 0.0, 11.0)
		and ward._side_captives[1].position == Vector3(-3.5, 0.0, 11.0),
		"a late observer starts both figures at the server's current feet without replaying travel")
	ward.clear_map()
	ward.configure_map(_map())
	ward.apply_state(_state(2, true, true, true))
	_check(not ward._ward_stop_sound.playing and not ward._release_sound.playing
		and not ward._second_release_sound.playing
		and not ward._side_release_sound.playing,
		"state-first late join opens the bay without replaying the past")
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
	_check(not ward._latch.visible,
		"a releasing snapshot resolves a state-first late join to the authoritative pawn")
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
	ward.clear_map()
	await process_frame
	ward.free()
	# The headless mixer releases a stopped looping playback on its next buffer.
	await create_timer(0.25).timeout
	if failures == 0:
		print("test_m02_ward: PASS ordered bay and side releases, server facts, late join, retry, skip, muted fallback")
	quit(0 if failures == 0 else 1)
