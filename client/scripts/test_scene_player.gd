extends SceneTree

## The shared scene player: text fallback, stills, narration timing, captions,
## skip and replay, input consumption and the departure hook.

const STILL: String = "res://assets/factions/free_coalition/dont_tread_on_me.png"
const CLIP: String = "res://assets/audio/fire.wav"

## Stands in for menus and match shortcuts beneath a scene.
class Beneath extends Node:
	var heard: int = 0
	func _unhandled_input(event: InputEvent) -> void:
		if event.is_pressed():
			heard += 1

var failures: int = 0
var completions: int = 0
var settings_path: String

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://scene-player-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	call_deferred("_run")

func _finalize() -> void:
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_scene_player: " + message)

func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _pad(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _scene(shots: Array) -> Dictionary:
	return {"format": 1.0, "id": "harness", "title_key": "STORY_L02_TITLE", "skip_key": "STORY_SKIP_SCENE", "shots": shots}

func _start(manifest: Dictionary) -> ScenePlayer:
	completions = 0
	var player: ScenePlayer = ScenePlayer.new(manifest)
	player.completed.connect(func() -> void: completions += 1)
	root.add_child(player)
	await process_frame
	await process_frame
	return player

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _fallback()
	await _still_and_narration()
	await _skip_and_replay()
	await _broken_scene()
	await _departure_hook()
	await process_frame
	await process_frame
	if failures == 0:
		print("test_scene_player: PASS text fallback, stills, narration timing, captions, skip, replay, input and departure")
	quit(0 if failures == 0 else 1)

## Missing pictures and clips leave a complete reader-paced text page.
func _fallback() -> void:
	var player: ScenePlayer = await _start(StoryScene.load_scene("l01_l02"))
	_expect(not player._still_frame.visible and player._still.texture == null, "missing still falls back to the text page")
	_expect(player._panel.custom_minimum_size == Vector2(1180, 760), "text page keeps the opening's panel")
	_expect(not player._voiced and player._narration.stream == null, "missing narration leaves no clip")
	_expect(player._body.text.contains("You 3. Me 3.") and player._scroll.visible, "caption text is complete without audio")
	_expect(not player._captions.visible, "no caption switch without a voice clip")
	_expect(player._skip.text == tr("STORY_SKIP_SCENE") and player._mission_title.text == tr("STORY_L02_TITLE"), "scene keys label the page")
	_expect(player._progress.get_child_count() == 3, "progress shows one segment per shot")
	player._on_narration_finished()
	for frame: int in 4:
		await process_frame
	_expect(player.page == 0, "a text page never advances on its own")
	player.advance()
	_expect(player._speaker.visible and player._speaker.text == tr("STORY_SPEAKER_MARA"), "speaker label is shown with the line")
	_expect((player._progress.get_child(1) as ColorRect).color == MenuTheme.EMBER, "progress marks the current shot")
	player.free()

func _still_and_narration() -> void:
	var manifest: Dictionary = _scene([
		{"id": "ONE", "caption_key": "STORY_L01_L02_LEDGER", "image": STILL, "motion": {"kind": "zoom_in", "amount": 0.05},
			"narration": CLIP, "timing": "narration", "hold": 0.0},
		{"id": "TWO", "caption_key": "STORY_L01_L02_SHIFT", "speaker_key": "STORY_SPEAKER_MARA", "image": STILL,
			"motion": {"kind": "pan_left"}, "narration": CLIP, "timing": "narration"},
	])
	_expect(StoryScene.validation_error(manifest).is_empty(), "harness manifest is valid")
	var player: ScenePlayer = await _start(manifest)
	_expect(player._still_frame.visible and player._still.texture != null, "still is shown")
	_expect(player._still.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "still uses nearest filtering")
	_expect(player._panel.size_flags_vertical == Control.SIZE_SHRINK_END, "a still puts the caption in a band")
	_expect(player._voiced and player._narration.bus == &"Voice", "narration plays on the Voice bus")
	_expect(AudioServer.get_bus_index(&"Voice") >= 0, "the Voice bus exists")
	_expect(player._motion != null and player._motion.is_valid(), "the still drifts")
	var drift: Tween = player._motion
	_expect(player._captions.visible and player._scroll.visible, "captions show by default beside narration")
	await _key(KEY_C, true)
	await _key(KEY_C, false)
	_expect(not player.captions_enabled and not player._scroll.visible, "C hides captions while narration speaks")
	await _pad(JOY_BUTTON_Y)
	_expect(player.captions_enabled and player._scroll.visible, "controller Y restores captions")
	player._on_narration_finished()
	for frame: int in 4:
		await process_frame
	_expect(player.page == 1, "narration timing advances when the clip ends")
	_expect(player._motion == drift, "beats over the same still keep one drift")
	player._on_narration_finished()
	for frame: int in 60:
		await process_frame
	_expect(player.page == 1 and completions == 0, "the last shot waits for the reader")
	player.toggle_captions()
	_expect(player._speaker.visible == false and not player._scroll.visible, "hidden captions hide the speaker too")
	player.toggle_captions()
	player.previous()
	_expect(player.page == 0 and player._auto_advance < 0.0, "back cancels a pending advance")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	player._on_still_input(click)
	_expect(player.page == 1, "clicking the still advances")
	player.advance()
	_expect(completions == 1 and player.finished and not player._narration.playing, "finishing stops narration and emits once")
	player.advance()
	player.finish()
	_expect(completions == 1, "completion never repeats")
	player.free()

	# Captions off in settings starts a voiced scene without captions.
	var preferences: FragrSettings = FragrSettings.for_tree(self)
	preferences.set_value("gameplay", "story_captions", false)
	preferences.save_to_disk()
	player = await _start(manifest)
	_expect(not player.captions_enabled and not player._scroll.visible, "the captions setting is honored")
	player.free()
	player = await _start(StoryScene.load_scene("l01_l02"))
	_expect(player._scroll.visible, "text-only shots show text even with captions off")
	player.free()
	preferences.set_value("gameplay", "story_captions", true)
	preferences.save_to_disk()

## Escape and B skip the whole scene; input never reaches what lies beneath.
func _skip_and_replay() -> void:
	var beneath: Beneath = Beneath.new()
	root.add_child(beneath)
	var player: ScenePlayer = await _start(StoryScene.load_scene("l01_l02"))
	await _key(KEY_PAGEDOWN, true)
	await _key(KEY_PAGEDOWN, false)
	await _key(KEY_SPACE, true)
	await _key(KEY_SPACE, false)
	_expect(beneath.heard == 0, "keys under a scene are consumed")
	await _key(KEY_ESCAPE, true)
	_expect(completions == 1 and player.finished, "Escape skips the whole scene")
	await _key(KEY_ESCAPE, false)
	_expect(beneath.heard == 0, "the skip key is consumed too")
	player.free()
	player = await _start(StoryScene.load_scene("l01_l02"))
	player.advance()
	await _pad(JOY_BUTTON_B)
	_expect(completions == 1 and beneath.heard == 0, "controller B skips and is consumed")
	player.free()
	# Replay is a fresh presenter from the same manifest.
	player = await _start(StoryScene.load_scene("l01_l02"))
	_expect(player.page == 0 and not player.finished and completions == 0, "replay starts at the first shot")
	player.free()
	beneath.free()

## A broken manifest hands back at once rather than holding the player.
func _broken_scene() -> void:
	var player: ScenePlayer = ScenePlayer.new({"format": 1.0, "id": "broken", "shots": []})
	var ended: Array[bool] = [false]
	player.completed.connect(func() -> void: ended[0] = true)
	root.add_child(player)
	await process_frame
	await process_frame
	_expect(ended[0] and player.finished, "an invalid scene completes instead of blocking")
	player.free()

## The campaign plays the between-level scene once, after the server departs.
## The manager stays outside the tree: this checks the hook, not a live match.
func _departure_hook() -> void:
	var manager: Node = load("res://scripts/game_manager.gd").new()
	var owned: LocalMatch = LocalMatch.new()
	manager.set("local_match", owned)
	manager.set("is_human_player", true)
	var departed: Dictionary = {"id": MissionState.ID, "phase": "departed"}
	manager.call("play_departure_scene", {"id": MissionState.ID, "phase": "reach_lift"})
	_expect(manager.get("interlude") == null, "no scene before departure")
	manager.call("play_departure_scene", {"id": MissionState.M02_ID, "phase": "departed"})
	_expect(manager.get("interlude") == null, "a mission without a scene plays nothing")
	manager.set("is_human_player", false)
	manager.call("play_departure_scene", departed)
	_expect(manager.get("interlude") == null, "spectators do not get the scene")
	manager.set("is_human_player", true)
	manager.call("play_departure_scene", departed)
	var interlude: ScenePlayer = manager.get("interlude") as ScenePlayer
	_expect(interlude != null and interlude.scene.get("id") == "l01_l02", "departure plays the next scene")
	_expect(bool(manager.call("_mission_controls_blocked")), "the scene blocks match controls")
	manager.set("pending_jump", true)
	interlude.finish()
	_expect(manager.get("interlude") == null and not bool(manager.get("pending_jump")), "finishing releases the scene and drops queued actions")
	manager.call("play_departure_scene", departed)
	_expect(manager.get("interlude") == null, "a repeated departure state does not replay the scene")
	manager.set("local_match", null)
	manager.free()
	owned.free()
