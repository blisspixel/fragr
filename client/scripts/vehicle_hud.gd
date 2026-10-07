class_name VehicleHud
extends Control

## A quiet corner panel, using only server vehicle facts and bound controls.
var state: Dictionary = {}
var seat: String = ""
var nearby_seat: String = ""
var summary: String = ""
var prompt_text: String = ""
var _panel: PanelContainer
var _title: Label
var _status: Label
var _controls: RichTextLabel
var _device_revision: int = -1
var _snapshot_tick: int = -2
var _viewer_id: String = ""
var _enabled: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", MenuTheme.panel(Color("171a16"), Color("82765b")))
	add_child(_panel)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	_panel.add_child(stack)
	_title = _label(20)
	stack.add_child(_title)
	_status = _label(17)
	stack.add_child(_status)
	_controls = RichTextLabel.new()
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.fit_content = true
	_controls.scroll_active = false
	_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls.add_theme_font_override("normal_font", MenuTheme.FONT)
	_controls.add_theme_font_size_override("normal_font_size", 15)
	_controls.add_theme_color_override("default_color", MenuTheme.BONE)
	stack.add_child(_controls)
	visible = false

static func _label(font_size: int) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", MenuTheme.BONE)
	return label

func apply(snapshot: Dictionary, player_id: String, enabled: bool) -> void:
	var tick: int = int(snapshot.get("tick", -1))
	if tick == _snapshot_tick and player_id == _viewer_id and enabled == _enabled:
		return
	_snapshot_tick = tick
	_viewer_id = player_id
	_enabled = enabled
	state = {}
	seat = ""
	nearby_seat = ""
	if enabled:
		var occupied: Dictionary = VehicleState.occupied(snapshot, player_id)
		if not occupied.is_empty():
			state = occupied["vehicle"]
			seat = occupied["seat"]
		else:
			for actor: Dictionary in snapshot.get("players", []):
				if actor.get("id") != player_id or float(actor.get("hp", 0)) <= 0.0:
					continue
				var point: Vector3 = Vector3(float(actor["x"]), float(actor["y"]) - 1.5, float(actor["z"]))
				var near: Dictionary = VehicleState.nearby(snapshot, point)
				if not near.is_empty():
					state = near["vehicle"]
					nearby_seat = near["seat"]
				break
	_refresh()

func _refresh() -> void:
	_device_revision = InputDevice.revision
	visible = not state.is_empty()
	if not visible or _title == null:
		summary = ""
		prompt_text = ""
		return
	var aircraft: bool = state["kind"] == "light_aircraft"
	_title.text = tr("VEHICLE_" + str(state["kind"]).to_upper()) + (" / " + tr("VEHICLE_SEAT_" + seat.to_upper()) if not seat.is_empty() else "")
	if seat.is_empty():
		summary = tr("VEHICLE_HULL").format({"hp": int(state["hp"])})
		prompt_text = InputGlyphs.render(_controls, tr("VEHICLE_ENTER").format({"seat": tr("VEHICLE_SEAT_" + nearby_seat.to_upper())}), 18)
	else:
		var heat: int = roundi(float(state["gun_heat"]) * 100.0)
		summary = tr("VEHICLE_HULL_HEAT").format({"hp": int(state["hp"]), "heat": heat})
		if aircraft:
			summary = tr("VEHICLE_FLIGHT_FACTS").format({"hp": int(state["hp"]), "speed": roundi(absf(float(state["speed"])) * 3.6), "altitude": roundi(float(state["position"][1]))})
		var exit_hint: String = tr("VEHICLE_EXIT") if absf(float(state["speed"])) <= 2.0 else tr("VEHICLE_STOP_EXIT")
		if aircraft:
			exit_hint = tr("VEHICLE_LAND_EXIT")
		var controls: String = tr("VEHICLE_MOUNT_FIRE") if seat == "gunner" else tr("VEHICLE_DRIVE").format({
			"forward": InputGlyphs.action_name("move_forward"), "back": InputGlyphs.action_name("move_back"),
			"left": InputGlyphs.action_name("move_left"), "right": InputGlyphs.action_name("move_right")})
		if aircraft:
			controls = tr("VEHICLE_FLY").format({"forward": InputGlyphs.action_name("move_forward"),
				"back": InputGlyphs.action_name("move_back"), "left": InputGlyphs.action_name("move_left"),
				"right": InputGlyphs.action_name("move_right"), "descend": InputGlyphs.action_name("duck")})
			controls += "\n" + exit_hint
		else:
			controls += "\n{weapon} " + tr("VEHICLE_SEAT_GUNNER" if seat == "driver" else "VEHICLE_SEAT_DRIVER") + "   " + exit_hint
		if int(state["burning_ticks"]) > 0:
			controls = tr("VEHICLE_BURNING") + "\n" + exit_hint
		elif seat == "gunner" and heat >= 95:
			controls = tr("VEHICLE_HOT") + "\n" + controls
		if int(state["control_ready_tick"]) > _snapshot_tick:
			controls = tr("VEHICLE_SWITCHING").format({"seconds": "%.1f" % (float(int(state["control_ready_tick"]) - _snapshot_tick) / 20.0)}) + "\n" + controls
		prompt_text = InputGlyphs.render(_controls, controls, 18)
	_status.text = summary
	_status.add_theme_color_override("font_color", MenuTheme.EMBER if int(state["hp"]) < 100 else MenuTheme.BONE)
	_layout()

func _layout() -> void:
	if _panel == null:
		return
	var viewport: Vector2 = get_viewport_rect().size
	_panel.size = Vector2(320, 0)
	_panel.position = Vector2(maxf(12.0, viewport.x - 338.0), maxf(12.0, viewport.y - _panel.size.y - (22.0 if not seat.is_empty() else 135.0)))

func _process(_delta: float) -> void:
	if visible:
		# Device changes update the actual key or pad glyph without a new packet.
		if _device_revision != InputDevice.revision:
			_refresh()
		_layout()
