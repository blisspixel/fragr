class_name ConquestHud
extends Control

var state: Dictionary = {}
var _covered: bool = false
## The ticket line in three parts, so only a bleeding side pulses: the
## Union's count right of centre-left, a level divider, the coalition's.
var _tickets: Label
var _tickets_free: Label
var _divider: Label
## The warning plate behind a bleeding side's count. Union red and the free
## side's amber are both faction colours (art bible, faction readability
## contract), so the warning is neither: the count flashes to ink on a
## warm-white plate and back, an inverse-video pulse that reads in grayscale
## and on either side.
var _flash_union: ColorRect
var _flash_free: ColorRect
var _hint: Label
var _sites: Array[Label] = []
var _bars: Array[ColorRect] = []
var header_rect: Rect2 = Rect2(510, 52, 900, 280)

## The bleed (Pillar 6). Below this many tickets a side is bleeding out: the
## count flashes inverse (see the plates) and a low siren sounds every few
## seconds; on its last tickets a heartbeat joins it. The number mirrors the
## server's `rules::CONQUEST_BLEED_TICKETS`, where the Host's one call about
## it is made; this only presents the ticket counts the server sent.
const BLEED_TICKETS: int = 25
const LAST_TICKETS: int = 10
const SIREN_SECONDS: float = 4.0
## The heartbeat is a seamless 3.986 s loop (asset round E-7), restarted on
## its own length so the beat never doubles or gaps.
const HEARTBEAT_SECONDS: float = 3.986
const PULSE_SECONDS: float = 1.0
const SIREN_PATH: String = "res://assets/audio/conquest/siren.wav"
const HEARTBEAT_PATH: String = "res://assets/audio/conquest/heartbeat_loop.wav"
var bleeding: bool = false
var last_tickets: bool = false
var siren_count: int = 0
var heartbeat_count: int = 0
var _siren_in: float = 0.0
var _heartbeat_in: float = 0.0
var _pulse: float = 0.0
var _siren: AudioStreamPlayer
var _heartbeat: AudioStreamPlayer

func set_covered(value: bool) -> void:
	_covered = value
	visible = not _covered and not state.is_empty()

func set_header_rect(rect: Rect2) -> void:
	if rect == header_rect:
		return
	header_rect = rect
	_layout()

func _ready() -> void:
	theme = MenuTheme.build(MenuTheme.Context.GAMEPLAY)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_union = _plate()
	_flash_free = _plate()
	_tickets = _label(MenuTheme.BODY)
	_tickets.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_divider = _label(MenuTheme.BODY)
	_divider.text = ":"
	_tickets_free = _label(MenuTheme.BODY)
	_tickets_free.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint = _label(MenuTheme.BODY)
	_hint.text = tr("CONQUEST_HOLD_MAJORITY")
	_hint.add_theme_color_override("font_color", MenuTheme.BONE)
	for index: int in range(5):
		_sites.append(_label(MenuTheme.BODY))
		var bar: ColorRect = ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		_bars.append(bar)
	# Both cues were gated and loudness-set in asset round E-7 (siren K50
	# -12 beside the other mode cues, heartbeat -24 LUFS under combat).
	_siren = _player("BleedSiren", SIREN_PATH, 0.0)
	_heartbeat = _player("BleedHeartbeat", HEARTBEAT_PATH, 0.0)
	resized.connect(_layout)
	apply({})

func _plate() -> ColorRect:
	var plate: ColorRect = ColorRect.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.color = Color(MenuTheme.BONE, 0.0)
	add_child(plate)
	return plate

## Leaving the match (or the tree) silences the warning at once.
func _exit_tree() -> void:
	for player: AudioStreamPlayer in [_siren, _heartbeat]:
		if player != null:
			player.stop()
			player.stream = null

func _player(node_name: String, path: String, volume_db: float) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = node_name
	player.bus = &"Effects"
	player.volume_db = volume_db
	if ResourceLoader.exists(path):
		player.stream = load(path)
	add_child(player)
	return player

func _label(font_size: int) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", MenuTheme.INK)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func apply(snapshot: Dictionary) -> void:
	var raw: Variant = snapshot.get("conquest")
	state = raw.duplicate(true) if raw is Dictionary and ConquestState.validation_error(snapshot).is_empty() else {}
	visible = not _covered and not state.is_empty()
	_update_bleed()
	if state.is_empty() or _tickets == null:
		return
	_tickets.text = tr("CONQUEST_TICKETS_UNION").format({"union": int(state.tickets.union)})
	_tickets_free.text = tr("CONQUEST_TICKETS_COALITION").format({"coalition": int(state.tickets.coalition)})
	for index: int in range(5):
		var point: Dictionary = state.points[index]
		_sites[index].text = ConquestState.label(str(point.id)) + "\n" + ConquestState.status(point)
		_sites[index].add_theme_color_override("font_color", MenuTheme.EMBER if point.contested else MenuTheme.BONE)
		_bars[index].color = MenuTheme.team_color(str(point.capturing)) if point.capturing != null else MenuTheme.team_color(str(point.owner))
	_layout()

## Which warning the ticket counts call for. Crossing into the bleed sounds
## the siren at once; the heartbeat starts on the last tickets.
func _update_bleed() -> void:
	var lowest: int = 1 << 30
	if not state.is_empty():
		lowest = mini(int(state.tickets.union), int(state.tickets.coalition))
	var was_bleeding: bool = bleeding
	var was_last: bool = last_tickets
	bleeding = lowest < BLEED_TICKETS and lowest > 0
	last_tickets = bleeding and lowest <= LAST_TICKETS
	if bleeding and not was_bleeding:
		_siren_in = 0.0
		_pulse = 0.0
	if last_tickets and not was_last:
		_heartbeat_in = 0.0
	if not last_tickets and _heartbeat != null:
		_heartbeat.stop()
	if not bleeding and _siren != null:
		_siren.stop()
		_heartbeat.stop()
	if _tickets != null:
		_tickets.add_theme_color_override("font_color", MenuTheme.BONE)
		_tickets_free.add_theme_color_override("font_color", MenuTheme.BONE)
		_tickets.add_theme_color_override("font_outline_color", MenuTheme.INK)
		_tickets_free.add_theme_color_override("font_outline_color", MenuTheme.INK)
		_flash_union.color = Color(MenuTheme.BONE, 0.0)
		_flash_free.color = Color(MenuTheme.BONE, 0.0)

func _process(delta: float) -> void:
	if not bleeding or state.is_empty():
		return
	# A level inverse-video pulse: the plate fills in warm white and the
	# count turns ink, then back. Value and brightness only, never a tilt or
	# a jump of the baseline, and never a faction colour.
	_pulse = fmod(_pulse + delta, PULSE_SECONDS)
	var heat: float = 0.5 - 0.5 * cos(_pulse / PULSE_SECONDS * TAU)
	for side: Array in [[_tickets, _flash_union, "union"], [_tickets_free, _flash_free, "coalition"]]:
		var label: Label = side[0]
		var plate: ColorRect = side[1]
		if label == null:
			continue
		var left: int = int(state.tickets[side[2]])
		var lit: float = heat if left > 0 and left < BLEED_TICKETS else 0.0
		label.add_theme_color_override("font_color", MenuTheme.BONE.lerp(MenuTheme.INK, lit))
		label.add_theme_color_override("font_outline_color", MenuTheme.INK.lerp(MenuTheme.BONE, lit))
		plate.color = Color(MenuTheme.BONE, lit)
	_siren_in -= delta
	if _siren_in <= 0.0:
		_siren_in = SIREN_SECONDS
		siren_count += 1
		if _siren.stream != null:
			_siren.play()
	if last_tickets:
		_heartbeat_in -= delta
		if _heartbeat_in <= 0.0:
			_heartbeat_in = HEARTBEAT_SECONDS
			heartbeat_count += 1
			if _heartbeat.stream != null:
				_heartbeat.play()

func _layout() -> void:
	if _tickets == null or state.is_empty():
		return
	var width: float = header_rect.size.x
	var left: float = header_rect.position.x
	var top: float = header_rect.position.y
	var half: float = width * 0.5
	_tickets.position = Vector2(left, top)
	_tickets.size = Vector2(half - 18.0, 32)
	_divider.position = Vector2(left + half - 18.0, top)
	_divider.size = Vector2(36.0, 32)
	_tickets_free.position = Vector2(left + half + 18.0, top)
	_tickets_free.size = Vector2(half - 18.0, 32)
	# Each plate hugs its count's text with a little room either side.
	var font: Font = MenuTheme.FONT
	var union_width: float = font.get_string_size(_tickets.text, HORIZONTAL_ALIGNMENT_LEFT, -1, MenuTheme.BODY).x + 20.0
	var free_width: float = font.get_string_size(_tickets_free.text, HORIZONTAL_ALIGNMENT_LEFT, -1, MenuTheme.BODY).x + 20.0
	_flash_union.position = Vector2(left + half - 18.0 - union_width + 10.0, top - 2.0)
	_flash_union.size = Vector2(union_width, 34)
	_flash_free.position = Vector2(left + half + 18.0 - 10.0, top - 2.0)
	_flash_free.size = Vector2(free_width, 34)
	_hint.position = Vector2(left, top + 220)
	_hint.size = Vector2(width, 34)
	for index: int in range(5):
		var cell: float = width / 3.0
		var row: int = index / 3
		var column: int = index % 3
		var x: float = left + cell * (float(column) + (0.5 if row == 1 else 0.0))
		var y: float = top + 40.0 + float(row) * 88.0
		_sites[index].position = Vector2(x, y)
		_sites[index].size = Vector2(cell, 70)
		_bars[index].position = Vector2(x + 5, y + 72)
		_bars[index].size = Vector2((cell - 10) * float(state.points[index].progress) / float(state.capture_ticks), 3)
