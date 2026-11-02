extends SceneTree
## #528 fighter rim. A live pawn's dressed body draws the rim pass over every
## material of its own art: warm on a free body, a cool plate value on the
## Union's issued black, never red or cyan, and it follows a change of side.
## The contrast it buys is measured live by client/qa/contrast_scan.gd.

var _failures: int = 0


func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("localexception_settings_path", "")
	set_meta("localexception_records_path", "")
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_fighter_rim: " + message)


func _pawn(team: String) -> Node3D:
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate() as Node3D
	root.add_child(pawn)
	pawn.set_process(false)
	pawn.set_player_data("rim-" + team, "Rim " + team)
	pawn.update_state({"id": "rim-" + team, "name": "Rim " + team, "x": 0.0, "y": 1.5, "z": 0.0, "yaw": 0.0,
		"hp": 100, "weapon": "Tack", "ducking": false, "body": "human", "team": team}, 1)
	return pawn


func _run() -> void:
	_check(not FactionPalette.is_red(FighterRim.FREE) and not FactionPalette.is_cyan(FighterRim.FREE) and FighterRim.FREE.r > FighterRim.FREE.b,
		"the free rim is warm, neither red nor cyan")
	_check(not FactionPalette.is_red(FighterRim.UNION) and not FactionPalette.is_cyan(FighterRim.UNION) and FighterRim.UNION.b >= FighterRim.UNION.r,
		"the Union rim is a cool plate value, neither red nor cyan")
	for team: String in ["coalition", "union"]:
		var pawn: Node3D = _pawn(team)
		var body: Node = pawn.get("character_view")
		var rim: ShaderMaterial = FighterRim.of(body)
		_check(rim != null and rim.shader == FighterRim.SHADER, "%s body carries the rim pass" % team)
		var drawn: int = 0
		var bare: int = 0
		for node: Node in (body as Node).find_children("*", "MeshInstance3D", true, false) if body != null else []:
			var part: MeshInstance3D = node as MeshInstance3D
			for surface: int in range(part.mesh.get_surface_count() if part.mesh != null else 0):
				var material: StandardMaterial3D = part.get_surface_override_material(surface) as StandardMaterial3D
				if material == null:
					continue
				if material.next_pass == rim:
					drawn += 1
				else:
					bare += 1
		_check(drawn > 0 and bare == 0, "%s: every body material draws the rim (%d drawn, %d bare)" % [team, drawn, bare])
		var colour: Color = rim.get_shader_parameter("rim_color") if rim != null else Color.BLACK
		_check(colour == (FighterRim.UNION if team == "union" else FighterRim.FREE), "%s rim colour follows the side" % team)
		pawn.free()
	# A bright venue turns every live rim down, and the next one restores it.
	var lit: Node3D = _pawn("coalition")
	var lit_rim: ShaderMaterial = FighterRim.of(lit.get("character_view"))
	FighterRim.set_venue(ArenaSky.holdfast().fighter_rim)
	_check(lit_rim != null and is_zero_approx(float(lit_rim.get_shader_parameter("rim_strength"))), "Holdfast Atoll turns the rim off")
	FighterRim.set_venue(ArenaSky.larak_lot().fighter_rim)
	_check(lit_rim != null and is_equal_approx(float(lit_rim.get_shader_parameter("rim_strength")), FighterRim.STRENGTH), "Larak Lot restores it")
	FighterRim.set_venue(NAN)
	_check(FighterRim.venue == 1.0, "a malformed share falls back to full")
	lit.free()
	if _failures == 0:
		print("test_fighter_rim: PASS free and Union bodies carry their rim on every material")
	quit(0 if _failures == 0 else 1)
