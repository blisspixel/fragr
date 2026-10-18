extends RefCounted

## Exercise actual mapped pad events through GameManager and the owned socket.
## Call only after ordinary readiness and a finite human weapon claim.
static func button(index: JoyButton, pressed: bool) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

static func trigger(value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

static func pawn(game: Node) -> Dictionary:
	for player: Dictionary in game.latest_snapshot.get("players", []):
		if player.get("id") == game.net_client.player_id:
			return player
	return {}

static func run(tree: SceneTree, game: Node, until: Callable, check: Callable, label: String) -> bool:
	if not await until.call(func() -> bool: return not game.controls_blocked() and game.net_client.equipment.has("loaded"), label + " finite input is ready"):
		return false
	var weapon: String = game.net_client.equipment["selected"]
	var initial: int = EquipmentState.shots(game.net_client.equipment, weapon)
	check.call(initial > 0, label + " starts with a loaded finite magazine")
	trigger(1.0)
	var emptied: bool = await until.call(func() -> bool: return EquipmentState.shots(game.net_client.equipment, weapon) == 0, label + " pad trigger empties the server magazine")
	trigger(0.0)
	if not emptied:
		return false
	button(JOY_BUTTON_DPAD_DOWN, true)
	var reloading: bool = await until.call(func() -> bool:
		for magazine: Dictionary in game.net_client.equipment.get("loaded", []):
			if magazine.get("weapon") == weapon:
				return magazine.has("ready_at")
		return false, label + " pad reload starts the server timer")
	if not reloading:
		button(JOY_BUTTON_DPAD_DOWN, false)
		return false
	var reloaded: bool = await until.call(func() -> bool: return EquipmentState.shots(game.net_client.equipment, weapon) > 0, label + " server refills the magazine")
	button(JOY_BUTTON_DPAD_DOWN, false)
	if not reloaded:
		return false
	var loaded: int = EquipmentState.shots(game.net_client.equipment, weapon)
	trigger(1.0)
	var refired: bool = await until.call(func() -> bool: return EquipmentState.shots(game.net_client.equipment, weapon) < loaded, label + " pad trigger fires the refilled magazine")
	trigger(0.0)
	if not refired:
		return false
	button(JOY_BUTTON_DPAD_LEFT, true)
	var crouched: bool = await until.call(func() -> bool: return pawn(game).get("ducking", false), label + " pad crouch reaches authoritative stance")
	if crouched:
		await tree.create_timer(0.2).timeout
		check.call(pawn(game).get("ducking", false), label + " held crouch persists")
		var captures: String = OS.get_environment("FRAGR_PAD_QA_DIR")
		if not captures.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			check.call(DirAccess.make_dir_recursive_absolute(captures) == OK, "pad capture directory")
			check.call(tree.root.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "pad capture saved")
	button(JOY_BUTTON_DPAD_LEFT, false)
	if not crouched:
		return false
	return await until.call(func() -> bool: return not pawn(game).get("ducking", false), label + " released crouch stands on the server")
