extends SceneTree

## The fighter roster: every look baked and distinct, the server's counts
## matched, the faction colour rules on every look and accent, the Hello and
## snapshot `dress` boundary, the saved preference, and the pawn that wears
## a look on the free side and issued Union kit on the Union side.

class CaptureNetwork extends "res://scripts/net_client.gd":
	var sent: Array[Dictionary] = []
	func send_json(data: Dictionary) -> void:
		sent.append(data.duplicate(true))

const SERVER_BODY: String = "res://../server/src/protocol/body.rs"

var _failures: PackedStringArray = []


func _initialize() -> void:
	set_meta("localexception_automated", true)
	set_meta("localexception_settings_path", "")
	_run.call_deferred()


func _run() -> void:
	_roster()
	_faction_rules()
	_wire()
	_settings()
	await _pawns()
	await _preview()
	for failure: String in _failures:
		push_error("test_fighter_looks: " + failure)
	if _failures.is_empty():
		print("test_fighter_looks: PASS roster, server counts, faction rules, wire, settings, pawns and preview")
	quit(0 if _failures.is_empty() else 1)


func _roster() -> void:
	_expect(FighterLooks.count(PlayerBody.HUMAN) >= 6 and FighterLooks.count(PlayerBody.SYNTHETIC) >= 3,
		"at least six human and three synthetic looks")
	var textures: Array[Texture2D] = []
	for body: String in PlayerBody.KINDS:
		_expect(FighterLooks.person(body, 0).is_empty() and FighterLooks.texture(body, 0) == null, "look 0 is the body's own art: " + body)
		for look: int in range(1, FighterLooks.count(body)):
			var person: String = FighterLooks.person(body, look)
			var texture: Texture2D = FighterLooks.texture(body, look)
			_expect(texture != null, "look %s %d is baked" % [body, look])
			_expect(CastPaint.source_for(person) == SkinnedCharacter.SOURCES[body], "look %s %d paints its own body" % [body, look])
			_expect(not textures.has(texture), "look %s %d is its own paint" % [body, look])
			textures.append(texture)
	# The server keeps the same counts; a mismatch would refuse real choices.
	var source: String = FileAccess.get_file_as_string(SERVER_BODY)
	_expect(not source.is_empty(), "server roster counts readable")
	for line: String in ["pub const HUMAN_LOOKS: u8 = %d;" % FighterLooks.count(PlayerBody.HUMAN),
			"pub const SYNTHETIC_LOOKS: u8 = %d;" % FighterLooks.count(PlayerBody.SYNTHETIC),
			"pub const ACCENTS: u8 = %d;" % FighterLooks.ACCENTS.size()]:
		_expect(source.contains(line), "server agrees: " + line)
	_expect(not FighterLooks.valid_look(PlayerBody.SYNTHETIC, FighterLooks.count(PlayerBody.SYNTHETIC))
		and not FighterLooks.valid_look(PlayerBody.HUMAN, -1) and not FighterLooks.valid_look(PlayerBody.HUMAN, 1.0),
		"looks outside a body's roster are invalid")


## Every look and every accent against the faction readability contract:
## no matte off-white base, no cyan field, no black-and-red pairing with any
## accent, and an accent palette clear of the reserved colours.
func _faction_rules() -> void:
	for entry: Dictionary in FighterLooks.ACCENTS:
		var color: Color = entry["color"]
		_expect(FactionPalette.free_accent_allowed(color), "accent %s stays off red, cyan and off-white" % entry["label"])
	for body: String in PlayerBody.KINDS:
		for look: int in range(1, FighterLooks.count(body)):
			var image: Image = FighterLooks.texture(body, look).get_image()
			if image.is_compressed():
				image.decompress()
			var samples: Array[Color] = []
			var cyan: int = 0
			for index: int in range(4096):
				var texel: Color = image.get_pixel((index * 7919) % image.get_width(), (index * 104729 / image.get_width() + index * 31) % image.get_height())
				if texel.a < 0.5:
					continue
				samples.append(texel)
				if texel.s >= 0.35 and texel.v >= 0.3 and FactionPalette.is_cyan(texel):
					cyan += 1
			samples.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
			var base: Color = samples[samples.size() / 2]
			var label: String = "%s %s" % [body, FighterLooks.label(body, look)]
			_expect(not FactionPalette.is_off_white(base), label + " base is not matte off-white")
			_expect(cyan * 100 < samples.size(), label + " carries no cyan field (%d of %d)" % [cyan, samples.size()])
			for entry: Dictionary in FighterLooks.ACCENTS:
				var checked: Dictionary = FactionPalette.check({"base": base, "accent": entry["color"]})
				_expect(not checked["changed"], "%s with %s passes the colour picker rule" % [label, entry["label"]])


func _wire() -> void:
	_expect(FighterLooks.parse(null, PlayerBody.HUMAN) == {"look": FighterLooks.AUTO, "accent": FighterLooks.AUTO}, "no dress is AUTO")
	_expect(FighterLooks.parse({"look": 7.0, "accent": 3.0}, PlayerBody.HUMAN) == {"look": 7, "accent": 3}, "JSON numbers parse to indices")
	_expect(FighterLooks.parse({"look": 2.0}, PlayerBody.SYNTHETIC) == {"look": 2, "accent": FighterLooks.AUTO}, "accent is optional")
	for bad: Variant in [{"look": 7.0}, {"look": 1.5}, {"look": "res://x.png"}, {"accent": 8.0}, {"accent": -1.0},
			{"look": 1.0, "colour": "#ff0000"}, [1, 2], "look"]:
		_expect(FighterLooks.parse(bad, PlayerBody.SYNTHETIC).is_empty(), "malformed dress refused: " + str(bad))
	var player: Dictionary = {"id": "a", "body": "synthetic", "dress": {"look": 4.0, "accent": 1.0}}
	_expect(PlayerBody.snapshot_error({"players": [player]}).is_empty(), "a roster dress passes the snapshot boundary")
	for bad: Dictionary in [{"id": "b", "body": "synthetic", "dress": {"look": 7.0}}, {"id": "c", "dress": {"look": 1.0}}]:
		_expect(not PlayerBody.snapshot_error({"players": [bad]}).is_empty(), "an outside dress closes the connection: " + str(bad))
	for case: Array in [[PlayerBody.HUMAN, 6, 2, {"look": 6, "accent": 2}], [PlayerBody.SYNTHETIC, 6, 2, {"accent": 2}],
			[PlayerBody.HUMAN, FighterLooks.AUTO, FighterLooks.AUTO, {}]]:
		var network: CaptureNetwork = CaptureNetwork.new()
		network.role = "human"
		network.player_name = "Looker"
		network.requested_body = case[0]
		network.requested_dress = {"look": case[1], "accent": case[2]}
		network.send_hello()
		var hello: Dictionary = network.sent[0]
		_expect(hello.get("dress", {}) == case[3], "hello asks for %s" % str(case[3]))
		network.free()
	var watcher: CaptureNetwork = CaptureNetwork.new()
	watcher.role = "spectator"
	watcher.requested_dress = {"look": 1, "accent": 1}
	watcher.send_hello()
	_expect(not watcher.sent[0].has("dress"), "a spectator asks for no look")
	watcher.free()


func _settings() -> void:
	var path: String = "user://test-looks-%d.cfg" % OS.get_process_id()
	var settings: LocalExceptionSettings = LocalExceptionSettings.new(path)
	_expect(settings.player_look() == FighterLooks.AUTO and settings.player_accent() == FighterLooks.AUTO
		and settings.player_dress().is_empty(), "the default lets the server choose")
	settings.set_value("profile", "body", PlayerBody.HUMAN)
	settings.set_value("profile", "look", 7)
	settings.set_value("profile", "accent", 5)
	_expect(settings.save_to_disk() == OK, "settings save")
	var loaded: LocalExceptionSettings = LocalExceptionSettings.new(path)
	loaded.load_from_disk()
	_expect(loaded.player_dress() == {"look": 7, "accent": 5}, "look and accent round trip the one settings file")
	loaded.set_value("profile", "body", PlayerBody.SYNTHETIC)
	_expect(loaded.player_look() == FighterLooks.AUTO and loaded.player_dress() == {"accent": 5}, "a look the body lacks becomes AUTO")
	for bad: Variant in [99, -2, "7", 2.5, null]:
		loaded.set_value("profile", "look", bad)
		loaded.set_value("profile", "accent", bad)
		_expect(int(loaded.get_value("profile", "look")) == FighterLooks.AUTO and int(loaded.get_value("profile", "accent")) == FighterLooks.AUTO,
			"an invalid saved value snaps to AUTO: " + str(bad))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _pawns() -> void:
	var cases: Array[Dictionary] = [
		{"team": "", "body": PlayerBody.HUMAN, "look": 3, "accent": 4},
		{"team": "coalition", "body": PlayerBody.SYNTHETIC, "look": 2, "accent": 1},
		{"team": "union", "body": PlayerBody.HUMAN, "look": 4, "accent": 3},
		{"team": "union", "body": PlayerBody.SYNTHETIC, "look": 2, "accent": 0},
	]
	for case: Dictionary in cases:
		var pawn: Node3D = load("res://scenes/player.tscn").instantiate() as Node3D
		root.add_child(pawn)
		pawn.set_process(false)
		pawn.set_player_data("p", "Looker")
		var state: Dictionary = {"id": "p", "name": "Looker", "x": 0.0, "y": 1.5, "z": 0.0, "yaw": 0.0, "hp": 100,
			"weapon": "Tack", "body": case["body"], "dress": {"look": float(case["look"]), "accent": float(case["accent"])}}
		if not str(case["team"]).is_empty():
			state["team"] = case["team"]
		pawn.update_state(state, 1)
		await process_frame
		var view: SkinnedCharacter = pawn.character_view
		var union: bool = case["team"] == "union"
		var label: String = "%s %s look %d" % [case["team"] if case["team"] != "" else "sideless", case["body"], case["look"]]
		_expect(view != null and pawn.look == case["look"] and pawn.personal_accent == case["accent"], label + " accepted")
		if view == null:
			pawn.free()
			continue
		_expect(FighterLooks.worn(view) == (null if union else FighterLooks.texture(case["body"], case["look"])),
			label + " wears its look, or the own art under Union issue")
		var worn: Texture2D = null
		for material: StandardMaterial3D in view._materials:
			if view._materials[material] != null:
				worn = material.albedo_texture
		_expect((worn == FighterLooks.worn(view)) != union, label + (" wears issued livery, not the look" if union else " shows the look"))
		var band: Array[Node] = view.find_children("PersonalBand", "MeshInstance3D", true, false)
		_expect(band.size() == 1 and (band[0] as MeshInstance3D).visible != union, label + " personal band only off the Union side")
		# Marks are fitted to the person: a wrist band and collar and stripes
		# at body scale between the knees and the crown.
		for part: MeshInstance3D in FighterLooks.marks(view):
			var box: AABB = part.global_transform * part.mesh.get_aabb()
			_expect(box.size.length() > 0.02 and box.size.length() < 0.5 and box.position.y > 0.5 and box.end.y < 1.95,
				"%s %s sits on the body at person scale: %s" % [label, part.name, box])
		if not union:
			var band_color: Color = ((band[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
			_expect(band_color.is_equal_approx(FighterLooks.accent_color(case["accent"])), label + " band in the chosen accent")
		var seals: int = view.find_children("RankSeal", "MeshInstance3D", true, false) \
			.filter(func(seal: Node) -> bool: return (seal as MeshInstance3D).visible).size()
		_expect((seals > 0) == (union and FighterLooks.union_rank(case["look"]) > 0), label + " rank marks only on Union rank")
		if case["team"] == "":
			_expect(view.accent.is_equal_approx(FighterLooks.accent_color(case["accent"])), label + " tape in the chosen accent")
		elif case["team"] == "coalition":
			_expect(view.accent.is_equal_approx(FactionPalette.team_accent("coalition")), label + " keeps the coalition amber tape")
		# A later snapshot with a malformed dress changes nothing.
		state["dress"] = {"look": 99.0}
		pawn.update_state(state, 2)
		_expect(pawn.look == case["look"], label + " ignores a malformed dress")
		pawn.free()


func _preview() -> void:
	var preview: LookPreview = LookPreview.new()
	root.add_child(preview)
	preview.show_look(PlayerBody.HUMAN, 5, 2)
	await process_frame
	_expect(preview.view != null and FighterLooks.worn(preview.view) == FighterLooks.texture(PlayerBody.HUMAN, 5), "preview wears the look")
	preview.show_look(PlayerBody.SYNTHETIC, 7, FighterLooks.AUTO)
	_expect(preview.view.kind == PlayerBody.SYNTHETIC and preview.look == FighterLooks.AUTO and FighterLooks.worn(preview.view) == null,
		"preview narrows a look the body lacks to its own art")
	preview.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
