class_name M02Ward
extends Node3D

## A noncombat, render-only reading of the M02 mission facts. The server owns
## the ward win and release. Reconnect, retry and skip rebuild from those facts.
const MAP_ID: int = 1002
const MAP_NAME: String = "Persons Unknown: ward graybox"
const FIRST_FEET: Vector3 = Vector3(7.55, 0.0, -10.0)
const SECOND_FEET: Vector3 = Vector3(7.55, 0.0, -14.8)
const BAY_FEET: Vector3 = Vector3(8.35, 0.0, -16.0)
const UNFASTEN_END: float = 0.8
const CROSS_END: float = 3.5
const SECOND_OPEN_END: float = 4.6
const LIST_REVEAL: float = 6.0
const END_SECONDS: float = 12.0

var _built: bool = false
var _seen_state: bool = false
var _attempt: int = 0
var _secured: bool = false
var _released: bool = false
var _release_elapsed: float = -1.0
var _caption_left: float = 0.0
var _caption_key: String = ""
var _root: Node3D
var _latch: Node3D
var _latch_arm: Node3D
var _first_left: Node3D
var _first_right: Node3D
var _second_left: Node3D
var _second_right: Node3D
var _other_captive: Node3D
var _machine_lamp: MeshInstance3D
var _machine_running: StandardMaterial3D
var _machine_stopped: StandardMaterial3D
var _transfer_list: Node3D
var _overlay: CanvasLayer
var _card: PanelContainer
var _heading: Label
var _copy: Label
var _hint: Label
var pause_menu: PauseMenu

func configure_map(info: Dictionary) -> void:
	var matches: bool = info.get("map_id") == MAP_ID and info.get("map_name") == MAP_NAME \
		and info.get("m02_objectives") != null
	if not matches:
		clear_map()
		return
	if _built:
		return
	_build()
	_set_visual(0.0, false)

func clear_map() -> void:
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	if is_instance_valid(_overlay):
		remove_child(_overlay)
		_overlay.queue_free()
	_root = null
	_overlay = null
	_built = false
	_seen_state = false
	_attempt = 0
	_secured = false
	_released = false
	_release_elapsed = -1.0
	_caption_left = 0.0
	_caption_key = ""

## Only validated MissionState data reaches this method from GameManager.
func apply_state(state: Dictionary) -> void:
	if not _built or state.get("id") != MissionState.M02_ID or not state.get("m02") is Dictionary:
		return
	var progress: Dictionary = state["m02"]
	var attempt: int = int(state["attempt"])
	var secured: bool = bool(progress["ward_secured"])
	var released: bool = "companion_released" in progress["completed"]
	if not _seen_state or attempt != _attempt:
		_seen_state = true
		_attempt = attempt
		_secured = secured
		_released = released
		_release_elapsed = -1.0
		_set_visual(END_SECONDS if released else 0.0, released)
		if released:
			_show_caption("M02_RELEASE_RECAP", 8.0)
		else:
			_hide_caption()
		return
	if secured and not _secured:
		_secured = true
		_set_machine_stopped(true)
		_show_caption("M02_WARD_STOPPED", 4.0)
	if released and not _released:
		_released = true
		_release_elapsed = 0.0
		_set_visual(0.0, true)
		_show_caption("M02_LATCH_RELEASE", SECOND_OPEN_END)

func _process(delta: float) -> void:
	if not _built:
		return
	if _release_elapsed >= 0.0 and _release_elapsed < END_SECONDS:
		var before: float = _release_elapsed
		_release_elapsed = minf(_release_elapsed + delta, END_SECONDS)
		_set_visual(_release_elapsed, true)
		if before < SECOND_OPEN_END and _release_elapsed >= SECOND_OPEN_END:
			_show_caption("M02_LATCH_SPEECH", LIST_REVEAL - SECOND_OPEN_END)
		if before < LIST_REVEAL and _release_elapsed >= LIST_REVEAL:
			_show_caption("M02_LOW_WATER", END_SECONDS - LIST_REVEAL)
	if _caption_left > 0.0:
		_caption_left = maxf(0.0, _caption_left - delta)
		_card.visible = _caption_left > 0.0
	_layout_caption()

func _input(event: InputEvent) -> void:
	if _built and _released and _release_elapsed >= 0.0 and _release_elapsed < END_SECONDS \
		and (not is_instance_valid(pause_menu) or not pause_menu.is_open()) \
		and event.is_action_pressed("ui_cancel") and not event.is_echo():
		skip_presentation()
		get_viewport().set_input_as_handled()

## Skip affects no game state. The second bay and list remain open.
func skip_presentation() -> void:
	if not _built or not _released:
		return
	_release_elapsed = END_SECONDS
	_set_visual(END_SECONDS, true)
	_hide_caption()

func _set_visual(seconds: float, released: bool) -> void:
	_set_machine_stopped(_secured)
	var unfasten: float = clampf(seconds / UNFASTEN_END, 0.0, 1.0) if released else 0.0
	_first_left.position.x = -0.43 - unfasten * 0.53
	_first_right.position.x = 0.43 + unfasten * 0.53
	var travel: float = clampf((seconds - UNFASTEN_END) / (CROSS_END - UNFASTEN_END), 0.0, 1.0) if released else 0.0
	_latch.position = FIRST_FEET.lerp(SECOND_FEET, travel)
	_latch.rotation.y = lerp_angle(-PI / 2.0, 2.55, clampf((seconds - 2.8) / 0.7, 0.0, 1.0)) if released else -PI / 2.0
	_latch_arm.rotation.x = -clampf((seconds - CROSS_END) / 0.5, 0.0, 1.0) * PI / 2.0 if released else 0.0
	var open: float = clampf((seconds - CROSS_END) / (SECOND_OPEN_END - CROSS_END), 0.0, 1.0) if released else 0.0
	_second_left.position.x = -0.3 - open * 0.68
	_second_right.position.x = 0.3 + open * 0.68
	_other_captive.position.x = -0.12 + open * 0.12
	_transfer_list.visible = released and seconds >= LIST_REVEAL

func _set_machine_stopped(stopped: bool) -> void:
	_machine_lamp.material_override = _machine_stopped if stopped else _machine_running

func _show_caption(key: String, seconds: float) -> void:
	_caption_key = key
	_caption_left = seconds
	_copy.text = WorldSign.localized(key)
	_heading.text = WorldSign.localized("M02_LATCH_HEADING") if key in ["M02_LATCH_SPEECH", "M02_LOW_WATER", "M02_RELEASE_RECAP"] else ""
	_hint.text = InputGlyphs.plain(WorldSign.localized("M02_SKIP_HINT")) if _release_elapsed >= 0.0 and _release_elapsed < END_SECONDS else ""
	_card.visible = seconds > 0.0

func _hide_caption() -> void:
	_caption_key = ""
	_caption_left = 0.0
	if is_instance_valid(_card):
		_card.visible = false

func _layout_caption() -> void:
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	var width: float = minf(740.0, viewport.x - 48.0)
	_copy.custom_minimum_size.x = width - 40.0
	var height: float = maxf(_card.get_combined_minimum_size().y, 82.0)
	_card.size = Vector2(width, height)
	_card.position = Vector2(24.0, maxf(12.0, viewport.y - height - 26.0))

func _build() -> void:
	_root = Node3D.new()
	_root.name = "WardPresentation"
	add_child(_root)
	var steel: StandardMaterial3D = _material(Color("343d3d"))
	var bone: StandardMaterial3D = _material(Color("c2b9a4"))
	var cyan: StandardMaterial3D = _material(Color("71b8ad"), true)
	var muted: StandardMaterial3D = _material(Color("808a84"))
	var door: StandardMaterial3D = _material(Color("46504e"))
	_latch = _figure("Latch", bone, steel, cyan)
	_latch.position = FIRST_FEET
	_latch.rotation.y = -PI / 2.0
	_root.add_child(_latch)
	_latch_arm = _latch.get_node("RightArm") as Node3D
	var first: Node3D = Node3D.new()
	first.name = "LatchRestraint"
	first.position = Vector3(7.21, 0.0, -10.0)
	first.rotation.y = -PI / 2.0
	_root.add_child(first)
	_first_left = _bar(first, "LeftLatch", -0.43, door)
	_first_right = _bar(first, "RightLatch", 0.43, door)
	var second: Node3D = Node3D.new()
	second.name = "SecondRestraint"
	second.position = BAY_FEET
	second.rotation.y = -PI / 2.0
	_root.add_child(second)
	_box(second, "Back", Vector3(0.0, 1.25, -0.39), Vector3(1.75, 2.5, 0.1), steel)
	for side: float in [-0.92, 0.92]:
		_box(second, "Rail", Vector3(side, 1.25, -0.15), Vector3(0.12, 2.5, 0.32), bone)
	_other_captive = _figure("SecondCaptive", muted, steel, _material(Color("778e88")))
	_other_captive.position = Vector3(-0.12, 0.0, -0.21)
	_second_left = _door(second, "LeftDoor", -0.3, door)
	_second_right = _door(second, "RightDoor", 0.3, door)
	second.add_child(_other_captive)
	_machine_running = _material(Color("bc4737"), true)
	_machine_stopped = _material(Color("626c69"))
	_box(_root, "MachineStatusFrame", Vector3(-2.0, 2.75, -15.16), Vector3(1.44, 0.44, 0.14), steel)
	_machine_lamp = _box(_root, "MachineLamp", Vector3(-2.0, 2.75, -15.26), Vector3(1.16, 0.22, 0.09), _machine_running)
	var list: Node3D = Node3D.new()
	list.name = "TransferList"
	list.position = Vector3(8.27, 1.72, -18.35)
	list.rotation.y = -PI / 2.0
	_root.add_child(list)
	_box(list, "Panel", Vector3.ZERO, Vector3(2.05, 1.25, 0.08), steel)
	var world_copy: WorldSign = WorldSign.new()
	world_copy.name = "Copy"
	world_copy.configure("M02_TRANSFER_LIST", Vector2(1.83, 1.05), MenuTheme.BONE)
	world_copy.position.z = 0.055
	list.add_child(world_copy)
	_transfer_list = list
	ArenaSky.mark_world(_root)
	_build_caption()
	_built = true

func _figure(label: String, shell: StandardMaterial3D, joints: StandardMaterial3D, patch: StandardMaterial3D) -> Node3D:
	var figure: Node3D = Node3D.new()
	figure.name = label
	_box(figure, "Torso", Vector3(0.0, 1.2, 0.0), Vector3(0.62, 0.78, 0.29), shell)
	_box(figure, "ChestPatch", Vector3(0.11, 1.38, 0.164), Vector3(0.22, 0.16, 0.035), patch)
	_box(figure, "Neck", Vector3(0.0, 1.69, 0.0), Vector3(0.2, 0.16, 0.19), joints)
	_box(figure, "Head", Vector3(0.0, 1.9, 0.0), Vector3(0.36, 0.32, 0.32), shell)
	for side: float in [-1.0, 1.0]:
		var leg: Node3D = Node3D.new()
		leg.position = Vector3(side * 0.18, 0.62, 0.0)
		figure.add_child(leg)
		_box(leg, "Leg", Vector3(0.0, -0.24, 0.0), Vector3(0.21, 0.68, 0.22), joints)
		_box(leg, "Foot", Vector3(0.0, -0.53, 0.1), Vector3(0.23, 0.13, 0.38), shell)
		var arm: Node3D = Node3D.new()
		arm.name = "RightArm" if side > 0.0 else "LeftArm"
		arm.position = Vector3(side * 0.42, 1.42, 0.0)
		figure.add_child(arm)
		_box(arm, "Forearm", Vector3(0.0, -0.3, 0.0), Vector3(0.19, 0.66, 0.22), shell if side > 0.0 else joints)
		_box(arm, "Hand", Vector3(0.0, -0.65, 0.01), Vector3(0.13, 0.13, 0.15), joints)
	return figure

func _bar(parent: Node3D, label: String, x: float, material: StandardMaterial3D) -> Node3D:
	var bar: Node3D = Node3D.new()
	bar.name = label
	bar.position.x = x
	parent.add_child(bar)
	_box(bar, "Vertical", Vector3(0.0, 1.17, 0.0), Vector3(0.13, 1.32, 0.1), material)
	_box(bar, "Cuff", Vector3(0.0, 1.28, 0.1), Vector3(0.25, 0.13, 0.25), material)
	return bar

func _door(parent: Node3D, label: String, x: float, material: StandardMaterial3D) -> Node3D:
	var leaf: Node3D = Node3D.new()
	leaf.name = label
	leaf.position.x = x
	parent.add_child(leaf)
	_box(leaf, "Leaf", Vector3(0.0, 1.19, 0.29), Vector3(0.58, 1.93, 0.1), material)
	_box(leaf, "Window", Vector3(0.0, 1.65, 0.36), Vector3(0.31, 0.35, 0.025), _material(Color("768783")))
	return leaf

func _box(parent: Node3D, label: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	node.material_override = material
	parent.add_child(node)
	return node

func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.3
	material.roughness = 0.85
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.3
	return material

func _build_caption() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "WardCaption"
	_overlay.layer = 90
	add_child(_overlay)
	var screen: Control = Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(screen)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", MenuTheme.panel(Color("171d1a"), Color("716344")))
	screen.add_child(_card)
	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_card.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	_heading = _label(20, MenuTheme.EMBER)
	column.add_child(_heading)
	_copy = _label(23, MenuTheme.BONE)
	_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_copy)
	_hint = _label(14, MenuTheme.BONE)
	column.add_child(_hint)
	_card.visible = false

func _label(size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 4)
	return label

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _caption_key != "" and is_instance_valid(_copy):
		_show_caption(_caption_key, _caption_left)
