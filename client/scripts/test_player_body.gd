extends SceneTree

## The chosen body: allowlist, Hello, Welcome and snapshot validation, the
## pawn that wears it, its gait, and the baked strips' freshness and palette.

class CaptureNetwork extends "res://scripts/net_client.gd":
	var sent: Array[Dictionary] = []
	func send_json(data: Dictionary) -> void:
		sent.append(data.duplicate(true))

const UNION_RED: Array[Color] = [Color8(140, 26, 30), Color8(226, 52, 48)]

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_player_body: " + message)

func _run() -> void:
	_check_allowlist()
	_check_hello_and_welcome()
	await _check_pawn()
	_check_bake()
	if _failures == 0:
		print("test_player_body: PASS allowlist, hello, welcome, snapshot, pawn body and gait, fresh free-palette bake")
	quit(0 if _failures == 0 else 1)

func _check_allowlist() -> void:
	for kind: String in PlayerBody.KINDS:
		_check(PlayerBody.valid(kind) and PlayerBody.preference(kind) == kind, "known body " + kind)
		_check(ResourceLoader.exists(PlayerBody.strip_path(kind)), "every body has baked art: " + kind)
	for bad: Variant in ["robot", "Human", "res://assets/characters/union/sweeper.png", 7, null, ["human"]]:
		_check(not PlayerBody.valid(bad) and PlayerBody.preference(bad) == PlayerBody.HUMAN,
			"unknown bodies narrow to human: " + str(bad))
	_check(PlayerBody.strip_path("res://x") == PlayerBody.strip_path(PlayerBody.HUMAN),
		"a path never reaches resource loading")
	_check(PlayerBody.label(PlayerBody.SYNTHETIC) == "EMBODIED AGENT", "canon name in the menu")
	# Idle breathes at rest; the gait follows distance walked, not the clock.
	_check(PlayerBody.frame(5.0, 0.0, 0.0) == 1 and PlayerBody.frame(7.9, 99.0, 0.1) == 3, "idle cells at rest")
	var stride: float = EnemyAnimation.STRIDE_METRES / PlayerBody.WALK_FRAMES
	for step: int in range(8):
		var walking: int = PlayerBody.frame(0.0, stride * step + 0.01, 3.0)
		_check(walking == PlayerBody.IDLE_FRAMES + step % PlayerBody.WALK_FRAMES, "walk cell %d" % step)

func _check_hello_and_welcome() -> void:
	for role: String in ["human", "agent", "spectator"]:
		for body: String in PlayerBody.KINDS:
			var network: CaptureNetwork = CaptureNetwork.new()
			network.role = role
			network.player_name = "Same name for every body"
			network.requested_body = body
			network.send_hello()
			var hello: Dictionary = network.sent[0]
			_check(hello["gameplay_version"] == PlayerBody.VERSION, "hello advertises the body capability")
			if role == "spectator":
				_check(not hello.has("body"), "a spectator asks for no body")
			else:
				_check(hello["body"] == body and hello["role"] == role, "the body never implies the control role")
			# A resumed pawn keeps its own body, whatever this profile asked.
			var other: String = PlayerBody.SYNTHETIC if body == PlayerBody.HUMAN else PlayerBody.HUMAN
			var welcome: Dictionary = {"type":"welcome", "role":role,
				"player_id":null if role == "spectator" else "self"}
			if role != "spectator":
				welcome["body"] = other
			network._handle_message(JSON.stringify(welcome))
			_check(network.accepted_body == ("" if role == "spectator" else other), "the server's body wins")
			network.free()
	var legacy: CaptureNetwork = CaptureNetwork.new()
	legacy.role = "human"
	legacy.requested_body = PlayerBody.SYNTHETIC
	legacy._handle_message('{"type":"welcome","role":"human","player_id":"self"}')
	_check(legacy.accepted_body == PlayerBody.HUMAN, "an older server's pawn is human, never inferred from the request")
	legacy.free()
	for case: Array in [["spectator", "human"], ["human", "robot"], ["agent", 4], ["human", "res://x.png"]]:
		var data: Dictionary = {"type":"welcome", "role":case[0], "player_id":"self", "body":case[1]}
		_check(not PlayerBody.welcome_error(data, case[0]).is_empty(), "inconsistent welcome rejected: " + str(case))
		var network: CaptureNetwork = CaptureNetwork.new()
		network.role = case[0]
		var errors: Array[String] = []
		network.server_error.connect(func(message: String) -> void: errors.append(message))
		network._handle_message(JSON.stringify(data))
		_check(errors.size() == 1 and network.accepted_body.is_empty(), "a bad welcome closes: " + str(case))
		network.free()
	for players: Array in [[{"id":"a", "body":12}], [{"id":"a", "body":"robot"}], [{"id":"a", "body":{}}]]:
		_check(not PlayerBody.snapshot_error({"players":players}).is_empty(), "bad snapshot body: " + str(players))
	_check(PlayerBody.snapshot_error({"players":[{"id":"a"}, {"id":"b", "body":"synthetic"}]}).is_empty(),
		"absent bodies (Union actors, the boss, older servers) are fine")

func _check_pawn() -> void:
	var strip: Dictionary[String, String] = {}
	for kind: String in PlayerBody.KINDS:
		strip[kind] = PlayerBody.strip_path(kind)
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate()
	root.add_child(pawn)
	await process_frame
	pawn.call("set_player_data", "a1", "Dead Air Dan")
	var body: Sprite3D = pawn.get_node("Body")
	var legacy: Texture2D = body.texture
	var state: Dictionary = {"id":"a1", "name":"Dead Air Dan", "x":0.0, "y":1.5, "z":0.0, "yaw":0.0,
		"hp":100, "armor":0, "score":0, "weapon":"Rail"}
	pawn.call("update_state", state, 1)
	_check(body.texture == legacy and str(pawn.get("body_kind")).is_empty(), "no body keeps the legacy look")
	state["body"] = PlayerBody.SYNTHETIC
	pawn.call("update_state", state, 2)
	_check(body.texture.resource_path == strip[PlayerBody.SYNTHETIC], "the accepted body is worn")
	_check(body.hframes == 8 and body.vframes == 1, "idle and walk cells")
	_check(is_equal_approx(body.pixel_size, EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE),
		"the same field as the Union bake, never enlarged")
	_check(is_equal_approx(body.position.y + 1.5, EnemyAnimation.CENTRE_HEIGHT), "feet on the floor")
	_check((pawn.get_node("Label3D") as Label3D).position.y + 1.5 < 2.3, "the plate sits just over the head")
	_check(body.modulate == Color.WHITE, "a free body keeps its own palette")
	state["team"] = "coalition"
	pawn.call("update_state", state, 3)
	_check(body.modulate == Color.WHITE, "the free coalition side keeps the free palette")
	_check(pawn.get("player_color") == MatchRules.COALITION_LABEL, "the side still reads on the plate")
	state["team"] = "union"
	pawn.call("update_state", state, 4)
	_check(body.modulate.get_luminance() < 0.8, "the Union side still reads dark in a team match")
	state.erase("team")
	state["body"] = PlayerBody.HUMAN
	state["name"] = "COMPLIANCE-DRONE"
	pawn.call("update_state", state, 5)
	_check(body.texture.resource_path == strip[PlayerBody.HUMAN], "the body follows the server, never the callsign")
	state["body"] = "robot"
	pawn.call("update_state", state, 6)
	_check(pawn.get("body_kind") == PlayerBody.HUMAN, "an unknown body changes nothing")
	pawn.queue_free()
	var enemy: Node3D = load("res://scenes/player.tscn").instantiate()
	root.add_child(enemy)
	await process_frame
	enemy.call("set_player_data", "u1", "clerk-1")
	enemy.call("update_state", {"id":"u1", "name":"clerk-1", "x":0.0, "y":1.5, "z":0.0, "yaw":0.0, "hp":60,
		"weapon":"Tack", "body":PlayerBody.SYNTHETIC, "campaign":{"side":"union", "kind":"clerk", "phase":"idle",
		"phase_started":1, "phase_ends":1}}, 1)
	_check(str(enemy.get("body_kind")).is_empty(), "a Union actor never wears a participant body")
	enemy.queue_free()
	await process_frame

func _check_bake() -> void:
	var folder: String = "res://assets/characters/free/"
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder + "manifest.json"))
	if not manifest is Dictionary or not manifest.get("sources") is Dictionary or not manifest.get("entries") is Array:
		_check(false, "the bake manifest describes its sources and outputs")
		return
	for source: String in manifest["sources"]:
		_check(FileAccess.get_sha256(source) == manifest["sources"][source], "rebake after changing " + source)
	_check((manifest["entries"] as Array).size() == PlayerBody.KINDS.size(), "one strip per body")
	for entry: Dictionary in manifest["entries"]:
		var file: String = folder + str(entry["file"])
		_check(PlayerBody.KINDS.has(entry.get("body")) and FileAccess.get_sha256(file) == entry["sha256"],
			"strip matches its receipt: " + file)
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(file))
		if image == null:
			_check(false, "strip loads: " + file)
			continue
		image.convert(Image.FORMAT_RGBA8)
		_check(image.get_size() == Vector2i(EnemyAnimation.TILE * 8, EnemyAnimation.TILE), "strip layout: " + file)
		# The free palette never borrows the Union's red, and reads light where
		# issue reads black.
		var union_pixels: int = 0
		var opaque: int = 0
		var light: float = 0.0
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				var colour: Color = image.get_pixel(x, y)
				if colour.a < 0.5:
					continue
				opaque += 1
				light += colour.get_luminance()
				for red: Color in UNION_RED:
					if _near(colour, red):
						union_pixels += 1
		_check(opaque > 4000 and union_pixels == 0, "%s has %d Union red pixels of %d" % [file, union_pixels, opaque])
		_check(light / maxf(opaque, 1.0) > 0.3, "%s reads light: mean luminance %.2f" % [file, light / maxf(opaque, 1.0)])

static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.09
