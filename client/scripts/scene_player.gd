class_name ScenePlayer
extends CanvasLayer

## Plays one story scene manifest (see StoryScene): a pixel still per shot with a
## subtle pan or zoom, a keyed caption, optional narration on the Voice bus and
## optional music and ambience beds. A shot without a loadable picture becomes
## the reader-paced text page; a shot without loadable narration waits for the
## reader. Completion is a request, never mission authority.
signal completed

## Seconds a reader-paced still drifts for; a narrated still drifts for its clip.
const DRIFT_SECONDS: float = 14.0
const DEFAULT_MOTION: float = 0.06
const DEFAULT_HOLD: float = 0.8
const VOICE_BUS: StringName = &"Voice"
const MUSIC_BUS: StringName = &"Radio"
const AMBIENCE_BUS: StringName = &"Effects"

var scene: Dictionary = {}
var page: int = 0
var finished: bool = false
## Captions hide only while narration is actually speaking; text-only shots always show.
var captions_enabled: bool = true
var _title: Label
var _speaker: Label
var _body: Label
var _page_number: Label
var _mission_title: Label
var _back: Button
var _next: Button
var _skip: Button
var _captions: Button
var _scroll: ScrollContainer
var _scroll_hint: Label
var _panel: PanelContainer
var _progress: HBoxContainer
var _still_frame: Control
var _still: TextureRect
var _narration: AudioStreamPlayer
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _motion: Tween
## Seconds left before a narrated shot advances itself; negative when idle.
var _auto_advance: float = -1.0
var _voiced: bool = false
var _still_path: String = ""

func _init(manifest: Dictionary = {}) -> void:
	scene = manifest

func shots() -> Array:
	return scene.get("shots", [])

func shot() -> Dictionary:
	return shots()[page]

func _ready() -> void:
	layer = 110
	MouseCapture.release()
	var reason: String = StoryScene.validation_error(scene)
	if not reason.is_empty():
		# A broken scene must never hold the player: report it and hand back.
		push_warning("scene_player: " + reason)
		finish.call_deferred()
		return
	var preferences: FragrSettings = FragrSettings.for_tree(get_tree())
	preferences.load_from_disk()
	captions_enabled = bool(preferences.get_value("gameplay", "story_captions"))
	var backdrop: MenuBackdrop = MenuBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_still_frame = Control.new()
	_still_frame.clip_contents = true
	_still_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_still_frame.gui_input.connect(_on_still_input)
	add_child(_still_frame)
	_still = TextureRect.new()
	_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_still.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_still_frame.add_child(_still)
	var frame: MarginContainer = MarginContainer.new()
	frame.theme = MenuTheme.build()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		frame.add_theme_constant_override("margin_" + side, 100)
	for side: String in ["top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, 64)
	add_child(frame)
	_panel = PanelContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_child(_panel)
	var inset: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 30)
	_panel.add_child(inset)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	inset.add_child(column)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 18)
	column.add_child(heading)
	_mission_title = _label(22)
	_mission_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(_mission_title)
	_progress = HBoxContainer.new()
	_progress.add_theme_constant_override("separation", 6)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for _index: int in shots().size():
		var segment: ColorRect = ColorRect.new()
		segment.custom_minimum_size = Vector2(22, 8)
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_progress.add_child(segment)
	heading.add_child(_progress)
	_page_number = _label(22)
	heading.add_child(_page_number)
	_title = _label(52)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_color_override("font_color", MenuTheme.EMBER)
	column.add_child(_title)
	var rule: ColorRect = ColorRect.new()
	rule.color = Color("875739")
	rule.custom_minimum_size.y = 4
	column.add_child(rule)
	_speaker = _label(22)
	_speaker.add_theme_color_override("font_color", MenuTheme.EMBER)
	column.add_child(_speaker)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_body = _label(32)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("line_spacing", 10)
	_scroll.add_child(_body)
	_scroll_hint = _label(16)
	column.add_child(_scroll_hint)
	_body.resized.connect(_update_scroll_hint)
	_scroll.resized.connect(_update_scroll_hint)
	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 18)
	column.add_child(controls)
	_back = _button(controls, previous)
	_skip = _button(controls, finish)
	_captions = _button(controls, toggle_captions)
	# Text-only scenes keep the plain page; the switch appears once a clip exists.
	_captions.visible = _scene_has_voice()
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	_next = _button(controls, advance)
	_narration = _player(VOICE_BUS)
	_narration.finished.connect(_on_narration_finished)
	_music = _bed("music", MUSIC_BUS)
	_ambience = _bed("ambience", AMBIENCE_BUS)
	_enter_shot()
	_next.grab_focus.call_deferred()

func _label(font_size: int) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(parent: Control, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(180, 62)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _player(bus: StringName) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.bus = bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"
	add_child(player)
	return player

## A bed plays under the whole scene. A missing file is silence, not an error.
func _bed(key: String, bus: StringName) -> AudioStreamPlayer:
	if not scene.get(key) is Dictionary:
		return null
	var bed: Dictionary = scene[key]
	var stream: AudioStream = _stream(str(bed["path"]))
	if stream == null:
		return null
	var player: AudioStreamPlayer = _player(bus)
	player.stream = stream
	player.volume_db = float(bed.get("volume_db", -8.0))
	player.play()
	return player

static func _stream(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream

static func _texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _scene_has_voice() -> bool:
	for candidate: Dictionary in shots():
		if not StoryScene.narration_path(candidate).is_empty():
			return true
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()

## Picture, motion and sound for the current shot. Text lives in _refresh so a
## locale change never restarts a clip.
func _enter_shot() -> void:
	_auto_advance = -1.0
	var current: Dictionary = shot()
	var path: String = str(current.get("image", ""))
	var texture: Texture2D = _texture(path)
	# Several beats over one key image keep drifting instead of snapping back.
	var same_still: bool = texture != null and path == _still_path
	_still_path = path if texture != null else ""
	_still.texture = texture
	_still_frame.visible = texture != null
	_layout(texture != null)
	_narration.stop()
	_narration.stream = _stream(StoryScene.narration_path(current))
	_voiced = _narration.stream != null
	if _voiced:
		_narration.play()
	if not same_still:
		_start_motion(current, texture != null)
	_refresh()

## Text pages keep the original centered panel; a still gets a caption band.
func _layout(has_still: bool) -> void:
	if has_still:
		_panel.custom_minimum_size = Vector2(1180, 0)
		_panel.size_flags_vertical = Control.SIZE_SHRINK_END
		_panel.add_theme_stylebox_override("panel", MenuTheme.panel(Color(0.09, 0.114, 0.102, 0.9), Color("8c714e")))
		_title.add_theme_font_size_override("font_size", 36)
		_scroll.custom_minimum_size.y = 128
	else:
		_panel.custom_minimum_size = Vector2(1180, 760)
		_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_panel.add_theme_stylebox_override("panel", MenuTheme.panel(Color("171d1a"), Color("8c714e")))
		_title.add_theme_font_size_override("font_size", 52)
		_scroll.custom_minimum_size.y = 0

## Ken Burns, kept subtle: at most a few percent of drift, eased, never a cut.
func _start_motion(current: Dictionary, has_still: bool) -> void:
	if _motion != null:
		_motion.kill()
		_motion = null
	_still.scale = Vector2.ONE
	_still.position = Vector2.ZERO
	var motion: Dictionary = current.get("motion", {})
	var kind: String = str(motion.get("kind", "none"))
	if not has_still or kind == "none":
		return
	var amount: float = float(motion.get("amount", DEFAULT_MOTION))
	var size: Vector2 = _still_frame.size if _still_frame.size != Vector2.ZERO else get_viewport().get_visible_rect().size
	_still.pivot_offset = size / 2.0
	var start_scale: float = 1.0 + amount
	var end_scale: float = 1.0 + amount
	var drift: Vector2 = Vector2.ZERO
	match kind:
		"zoom_in":
			start_scale = 1.0
		"zoom_out":
			end_scale = 1.0
		"pan_left":
			drift = Vector2(-1, 0)
		"pan_right":
			drift = Vector2(1, 0)
		"pan_up":
			drift = Vector2(0, -1)
		"pan_down":
			drift = Vector2(0, 1)
	var travel: Vector2 = drift * size * amount * 0.5
	_still.scale = Vector2.ONE * start_scale
	_still.position = -travel
	var seconds: float = DRIFT_SECONDS
	if _voiced:
		seconds = maxf(_narration.stream.get_length() + float(current.get("hold", DEFAULT_HOLD)), 2.0)
	_motion = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(_still, "scale", Vector2.ONE * end_scale, seconds)
	_motion.tween_property(_still, "position", travel, seconds)

func _refresh() -> void:
	if _title == null or finished:
		return
	var current: Dictionary = shot()
	var total: int = shots().size()
	_mission_title.text = tr(scene["title_key"]) if scene.has("title_key") else ""
	_title.text = tr(current["title_key"]) if current.has("title_key") else ""
	_title.visible = not _title.text.is_empty()
	_speaker.text = tr(current["speaker_key"]) if current.has("speaker_key") else ""
	_body.text = tr(current["caption_key"])
	var show_caption: bool = captions_enabled or not _voiced
	_speaker.visible = show_caption and not _speaker.text.is_empty()
	_scroll.visible = show_caption
	_page_number.text = tr("STORY_PAGE").format({"current": page + 1, "total": total})
	for index: int in _progress.get_child_count():
		var segment: ColorRect = _progress.get_child(index) as ColorRect
		segment.color = MenuTheme.EMBER if index == page else (Color("8c714e") if index < page else Color("2e332f"))
	_back.text = tr("STORY_BACK")
	_back.disabled = page == 0
	_next.text = tr("STORY_FINISH" if page == total - 1 else "STORY_NEXT")
	_skip.text = tr(scene.get("skip_key", "STORY_SKIP"))
	_captions.text = tr("STORY_CAPTIONS_ON" if captions_enabled else "STORY_CAPTIONS_OFF")
	_scroll_hint.text = tr("STORY_SCROLL_HINT")
	_scroll.scroll_vertical = 0
	_update_scroll_hint()

func _update_scroll_hint() -> void:
	_scroll_hint.visible = _scroll.visible and _body.size.y > _scroll.size.y

func previous() -> void:
	if finished or page == 0:
		return
	page -= 1
	_enter_shot()
	if page == 0:
		_next.grab_focus()

func advance() -> void:
	if finished:
		return
	if page == shots().size() - 1:
		finish()
	else:
		page += 1
		_enter_shot()

func finish() -> void:
	if finished:
		return
	finished = true
	_auto_advance = -1.0
	for player: AudioStreamPlayer in [_narration, _music, _ambience]:
		if player != null:
			player.stop()
	if _motion != null:
		_motion.kill()
	completed.emit()

func toggle_captions() -> void:
	captions_enabled = not captions_enabled
	_refresh()

## Narration timing advances once the clip ends, after a short hold. The last
## shot never finishes on its own: leaving the scene is always the reader's call.
func _on_narration_finished() -> void:
	if finished or shot().get("timing", "reader") != "narration" or page == shots().size() - 1:
		return
	_auto_advance = float(shot().get("hold", DEFAULT_HOLD))

func _process(delta: float) -> void:
	if _auto_advance < 0.0 or finished:
		return
	_auto_advance -= delta
	if _auto_advance < 0.0:
		advance()

func _on_still_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_still_frame.accept_event()
		advance()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		finish()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and _scroll != null:
		var down: bool = event.is_action("ui_page_down") or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_RIGHT_SHOULDER)
		var up: bool = event.is_action("ui_page_up") or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_LEFT_SHOULDER)
		if down or up:
			_scroll.scroll_vertical += int(_scroll.size.y * 0.8) * (1 if down else -1)
		var caption_key: bool = (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_C) \
			or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_Y)
		if caption_key and _captions.visible and not event.is_echo():
			toggle_captions()
	# Menu/console shortcuts beneath the story must not react to its input.
	get_viewport().set_input_as_handled()
