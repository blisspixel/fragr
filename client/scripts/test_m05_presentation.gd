extends SceneTree

class LocalPreview extends LocalMatch:
	func executable_path() -> String:
		return ""

var failures: int = 0
var path: String
var output: String

func _initialize() -> void:
	set_meta("fragr_automated", true)
	path = "user://m05-presentation-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", path)
	output = ProjectSettings.globalize_path("res://../.agents/m05-client-buildout-20260930")
	_run.call_deferred()

func _finalize() -> void:
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m05_presentation: " + message)

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "isolated framebuffer capture saved")

func _run() -> void:
	var prefs: FragrSettings = FragrSettings.new(path)
	prefs.set_value("video", "display_mode", 0)
	prefs.set_value("video", "resolution_height", 720)
	_check(prefs.save_to_disk() == OK, "isolated preferences saved")
	var local: LocalPreview = LocalPreview.new()
	local.name = "LocalMatch"
	root.add_child(local)
	var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await menu._show("practice")
	var selector: OptionButton = menu._root.get_node("DevelopmentMission")
	_check(selector.item_count == 10 and selector.selected == 5 and selector.get_item_text(8) == tr("M10_PROTOTYPE_TITLE") and selector.get_item_text(9) == tr("M11_PROTOTYPE_TITLE"), "compact selector adds the tender while retaining the M07 default and old indices")
	selector.select(3)
	_check(selector.get_item_text(selector.selected) == tr("M05_PROTOTYPE_TITLE"), "M05 retains its exact selectable entry index")
	selector.grab_focus()
	_check(selector.has_focus() and selector.focus_mode == Control.FOCUS_ALL, "selector participates in keyboard and gamepad navigation")
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	var back: Button = menu._root.get_child(menu._root.get_child_count() - 1)
	_check(back.text == "BACK" and back.is_visible_in_tree(), "return action stays reachable")
	await _capture("practice-development-1280x720")
	root.size = Vector2i(640, 360)
	await process_frame
	await process_frame
	await _capture("practice-development-resized-640x360")
	root.size = Vector2i(1600, 900)
	menu.queue_free()
	await process_frame
	var scene: ScenePlayer = ScenePlayer.new(StoryScene.load_scene("m05_arrival"))
	root.add_child(scene)
	await process_frame
	await process_frame
	_check(scene._narration.playing and scene._narration.bus == &"Voice" and scene._body.text == tr("STORY_M05_ARRIVAL_ROOFS"), "actual M05 arrival plays exact committed voice/caption")
	await _capture("m05-arrival-voice-caption")
	scene.finish()
	scene.queue_free()
	await process_frame
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0, 1.4, 5)
	camera.current = true
	world.add_child(camera)
	var environment: WorldEnvironment = WorldEnvironment.new()
	var sky: Environment = Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color("292f2b")
	environment.environment = sky
	world.add_child(environment)
	var effects: GrenadeEffects = GrenadeEffects.new()
	world.add_child(effects)
	effects.apply({"tick": 1}, camera.position)
	effects.apply({"tick": 2, "grenades": [{"id": 1, "owner_id": "00000000-0000-0000-0000-000000000002", "position": [0, 1.4, 0], "fuse_ticks": 10, "bounce_count": 0}]}, camera.position)
	await _capture("grenade-authoritative-live-body")
	effects.apply({"tick": 3, "explosions": [{"id": 1, "owner_id": "00000000-0000-0000-0000-000000000002", "position": [0, 1.4, 0], "radius": 4, "hits": []}]}, camera.position)
	var tiles: Array[Image] = []
	for index: int in range(5):
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			tiles.append(root.get_texture().get_image())
		await create_timer(0.05).timeout
	if not tiles.is_empty():
		var strip: Image = Image.create(tiles.size() * 320, 180, false, Image.FORMAT_RGBA8)
		for index: int in range(tiles.size()):
			tiles[index].resize(320, 180, Image.INTERPOLATE_NEAREST)
			strip.blit_rect(tiles[index], Rect2i(0, 0, 320, 180), Vector2i(index * 320, 0))
		_check(strip.save_png(output.path_join("grenade-resolved-burst-strip.png")) == OK, "resolved burst motion strip saved")
	# A stopped voice keeps its playback in the audio server until the mixer
	# retires it. Quitting first leaked the blast playback and its stream on a
	# slow macOS runner, so wait for that actual release, with a bound.
	var playbacks: Array[WeakRef] = []
	for voice: AudioStreamPlayer3D in effects.voices:
		if voice.has_stream_playback():
			playbacks.append(weakref(voice.get_stream_playback()))
	effects.reset()
	world.queue_free()
	local.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	var deadline: int = Time.get_ticks_msec() + 3000
	while playbacks.any(func(ref: WeakRef) -> bool: return ref.get_ref() != null) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(playbacks.all(func(ref: WeakRef) -> bool: return ref.get_ref() == null), "stopped grenade voices release their playbacks before exit")
	if failures == 0:
		print("test_m05_presentation: PASS compact selector/navigation, exact arrival playback and bounded grenade render fixture")
	quit(0 if failures == 0 else 1)
