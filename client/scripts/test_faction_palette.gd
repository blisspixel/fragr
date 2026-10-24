extends SceneTree

## The faction readability contract's colour picker rule, callsign colours,
## team overlay accents and the measured free bodies.

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_faction_palette: " + message)

func _run() -> void:
	_check_bands()
	_check_picker_rule()
	_check_records()
	_check_labels()
	_check_overlay()
	await _check_bodies()
	if _failures == 0:
		print("test_faction_palette: PASS")
	quit(1 if _failures > 0 else 0)


func _check_bands() -> void:
	_check(FactionPalette.is_red(Color("e23430")) and FactionPalette.is_red(Color.from_hsv(345.0 / 360.0, 0.8, 0.8)),
		"Union red and a crimson are red")
	_check(not FactionPalette.is_red(Color("dc8c3c")) and not FactionPalette.is_red(Color("2a0b0b")),
		"amber is not red, and a red too dim to see reads black")
	_check(not FactionPalette.is_red(Color("8c7f7e")), "a grey with a red cast is not a saturated red")
	_check(FactionPalette.is_cyan(Color("4a8a92")) and FactionPalette.is_cyan(Color("00e5ff")), "Inheritance cyan is cyan")
	_check(not FactionPalette.is_cyan(Color("3d50ff")) and not FactionPalette.is_cyan(Color("40c060")), "blue and green are not cyan")
	_check(FactionPalette.is_off_white(Color("e8e2d6")) and FactionPalette.is_off_white(Color.WHITE), "bone and white are off-white")
	_check(not FactionPalette.is_off_white(Color("e8c08a")) and not FactionPalette.is_off_white(Color("9a9a9a")),
		"a warm tan and a mid grey are not")
	_check(FactionPalette.is_dark(Color("141416")) and not FactionPalette.is_dark(Color("56575e")), "black cloth is dark")
	_check(FactionPalette.is_warm_light(Color("ffb050")) and FactionPalette.is_warm_light(Color("fff8f0")),
		"amber and warm white are warm light")
	_check(not FactionPalette.is_warm_light(Color("e23430")) and not FactionPalette.is_warm_light(Color("4ad0e0")),
		"red and cyan light are not")


func _check_picker_rule() -> void:
	var fine: Dictionary = FactionPalette.check({"base": Color("6e5a44"), "secondary": Color("e23430"),
		"accent": Color("4a8a92"), "emissive": Color("ffb050")})
	_check(not fine["changed"] and fine["reason"] == "", "a mid base may carry red and cyan as painted accents: " + fine["reason"])
	_check(fine["scheme"]["secondary"] == Color("e23430"), "an allowed scheme is returned as chosen")
	var red_alone: Dictionary = FactionPalette.check({"base": Color("a03028")})
	_check(not red_alone["changed"], "red alone is allowed")
	var black_alone: Dictionary = FactionPalette.check({"base": Color("141416"), "accent": Color("dc8c3c")})
	_check(not black_alone["changed"], "black alone with a warm accent is allowed")

	var union: Dictionary = FactionPalette.check({"base": Color("141416"), "trim": Color("e23430"), "accent": Color("dc8c3c")})
	var trim: Color = union["scheme"]["trim"]
	_check(union["changed"] and not FactionPalette.is_red(trim), "black with red trim snaps the trim off red: " + trim.to_html(false))
	_check(union["scheme"]["accent"] == Color("dc8c3c"), "only the offending field moves")
	_check(absf(trim.s - Color("e23430").s) < 0.01 and absf(trim.v - Color("e23430").v) < 0.01, "the snap keeps saturation and value")
	_check(FactionPalette._arc_distance(FactionPalette.hue_degrees(trim), FactionPalette.RED_HUE_TO) <= FactionPalette.SNAP_MARGIN_DEGREES + 0.5,
		"a red near 0 degrees snaps to the nearer warm edge: %.1f" % FactionPalette.hue_degrees(trim))
	_check(str(union["reason"]).contains("Union") and not str(union["reason"]).contains("\n"), "one line names the Union: " + union["reason"])
	var crimson: Dictionary = FactionPalette.check({"base": Color("101010"), "secondary": Color.from_hsv(350.0 / 360.0, 0.9, 0.8)})
	_check(FactionPalette.hue_degrees(crimson["scheme"]["secondary"]) < FactionPalette.RED_HUE_FROM - 1.0,
		"a crimson snaps toward magenta, its nearer edge")
	var again: Dictionary = FactionPalette.check(union["scheme"])
	_check(not again["changed"], "a snapped scheme passes the rule unchanged")

	var shell: Dictionary = FactionPalette.check({"base": Color("e8e2d6"), "accent": Color("c8409e")})
	var base: Color = shell["scheme"]["base"]
	_check(shell["changed"] and not FactionPalette.is_off_white(base), "a matte off-white base snaps: " + base.to_html(false))
	_check(str(shell["reason"]).contains("Inheritance"), "the reason names the Inheritance: " + shell["reason"])
	_check(Vector3(base.r, base.g, base.b).distance_to(Vector3(0.91, 0.886, 0.839)) < 0.25, "the snap is the nearest allowed base")
	var white: Dictionary = FactionPalette.check({"base": Color.WHITE})
	_check(not FactionPalette.is_off_white(white["scheme"]["base"]), "pure white snaps out of off-white")

	for light: Color in [Color("ff2020"), Color("4ad0e0"), Color("3050ff")]:
		var lit: Dictionary = FactionPalette.check({"base": Color("6e5a44"), "emissive": light})
		var snapped: Color = lit["scheme"]["emissive"]
		_check(lit["changed"] and FactionPalette.is_warm_light(snapped) and not FactionPalette.is_red(snapped)
			and not FactionPalette.is_cyan(snapped), "emissive %s snaps to warm light %s" % [light.to_html(false), snapped.to_html(false)])
	var red_light: Dictionary = FactionPalette.check({"base": Color("6e5a44"), "emissive": Color("ff2020")})
	_check(str(red_light["reason"]).contains("Union") and str(red_light["reason"]).contains("Inheritance"),
		"a red light names both reserved lights: " + red_light["reason"])
	var many: Dictionary = FactionPalette.check({"base": Color("101010"), "accent": Color("e23430"), "emissive": Color("4ad0e0")})
	_check(str(many["reason"]).count("; ") == 1 and not str(many["reason"]).contains("\n"), "two snaps share one line: " + many["reason"])

	var missing: Dictionary = FactionPalette.check({"accent": Color("dc8c3c")})
	_check(missing["changed"] and missing["scheme"].is_empty(), "a body needs a base")
	var junk: Dictionary = FactionPalette.check({"base": Color("6e5a44"), "trim": "red", "hat": Color.RED})
	_check(junk["changed"] and not junk["scheme"].has("trim") and not junk["scheme"].has("hat"), "non-colours and unknown fields are dropped")


func _check_records() -> void:
	var loaded: Dictionary = FactionPalette.check_record({"base": "#141416", "accent": "#e23430"})
	_check(loaded["changed"] and not FactionPalette.is_red(loaded["scheme"]["accent"]), "an edited file cannot load the Union livery")
	var parsed: Dictionary = FactionPalette.check_record(JSON.parse_string("{\"base\": \"#6e5a44\", \"emissive\": \"#ffb050\"}"))
	_check(not parsed["changed"] and parsed["scheme"]["base"] == Color("6e5a44"), "a valid record loads as saved")
	for bad: Variant in [null, [], "base", {"base": 7}, {"base": "#zzzzzz"}, {"base": "x".repeat(200)}]:
		_check(FactionPalette.check_record(bad)["changed"], "a malformed record is refused or repaired: " + str(bad).left(40))
	var partial: Dictionary = FactionPalette.check_record({"base": "#6e5a44", "trim": 12})
	_check(partial["changed"] and str(partial["reason"]).begins_with("trim"), "a bad field is named: " + partial["reason"])


func _check_labels() -> void:
	for id: int in range(400):
		var color: Color = FactionPalette.callsign_color("fighter-%d" % id)
		_check(not FactionPalette.is_red(color) and not FactionPalette.is_cyan(color) and not FactionPalette.is_off_white(color),
			"callsign colour %d avoids reserved hues: %s" % [id, color.to_html(false)])
	_check(FactionPalette.callsign_color("Nightfall") == FactionPalette.callsign_color("Nightfall"), "a callsign keeps its colour")
	var hues: Dictionary = {}
	for id: int in range(200):
		hues[int(FactionPalette.hue_degrees(FactionPalette.callsign_color("p%d" % id)) / 30.0)] = true
	_check(hues.size() >= 7, "callsign colours still spread across the allowed hues: %d bands" % hues.size())
	for color: Color in [Color("e23430"), Color("4ad0e0"), Color("f4f0e6")]:
		var label: Color = FactionPalette.label_color(color)
		_check(not FactionPalette.is_red(label) and not FactionPalette.is_cyan(label) and not FactionPalette.is_off_white(label),
			"plate colour %s snaps to %s" % [color.to_html(false), label.to_html(false)])
	_check(FactionPalette.label_color(Color("74884e")) == Color("74884e"), "an allowed plate colour is unchanged")
	var pawn_script: GDScript = load("res://scripts/player_pawn.gd")
	var bots: Dictionary = pawn_script.get_script_constant_map()["BOT_COLORS"]
	for bot: String in bots:
		_check(FactionPalette.label_color(bots[bot]) == bots[bot], "rule bot %s already wears an allowed colour" % bot)


func _check_overlay() -> void:
	_check(FactionPalette.livery("union") == "union" and FactionPalette.livery("coalition") == "free"
		and FactionPalette.livery("") == "free", "only the Union side wears issued livery")
	_check(FactionPalette.team_accent("union") == FactionPalette.UNION_RED, "Union red only on the Union side")
	for high_contrast: bool in [false, true]:
		var amber: Color = FactionPalette.team_accent("coalition", high_contrast)
		_check(FactionPalette.free_accent_allowed(amber) and FactionPalette.is_warm_light(amber),
			"the free accent is warm amber (high contrast %s): %s" % [high_contrast, amber.to_html(false)])
		var pair: Array[Color] = FactionPalette.free_pair(high_contrast)
		_check(pair.size() == 2 and FactionPalette.free_accent_allowed(pair[0]) and FactionPalette.free_accent_allowed(pair[1]),
			"free-versus-free accents avoid every reserved colour (high contrast %s)" % high_contrast)
		var gap: float = absf(pair[0].get_luminance() - pair[1].get_luminance())
		_check(gap > (0.4 if high_contrast else 0.1), "the pair separates in grayscale: %.2f" % gap)
	_check(FactionPalette.free_pair()[0] == FactionPalette.FREE_EMBER and FactionPalette.free_pair()[1] == FactionPalette.FREE_MAGENTA,
		"ember and magenta by default")
	_check(FactionPalette.team_accent("").a == 0.0 and FactionPalette.team_accent("office").a == 0.0, "no side, no team accent")


## The real free bodies: a measured base that is neither Union black nor an
## Inheritance shell, two tapes and a visor fitted to each, and the picker
## rule refusing a red accent on a dark body.
func _check_bodies() -> void:
	for kind: String in PlayerBody.KINDS + ["tern", "edda"]:
		var view: SkinnedCharacter = SkinnedCharacter.new()
		root.add_child(view)
		if not view.configure(kind):
			_check(false, "%s body loads" % kind)
			view.free()
			continue
		var base: Color = view.base_color()
		_check(not FactionPalette.is_off_white(base), "%s base is not matte off-white: %s" % [kind, base.to_html(false)])
		var fitting: Dictionary = BodyLivery.fitting_for(view)
		_check((fitting["bands"] as Array).size() == 2 and fitting.has("visor"), "%s fits two tapes and a visor" % kind)
		view.dress("free", FactionPalette.FREE_AMBER)
		await process_frame
		for part: MeshInstance3D in view.accent_parts():
			var box: AABB = part.global_transform * part.mesh.get_aabb()
			_check(box.size.length() > 0.03 and box.size.length() < 0.5 and box.position.y > 1.0 and box.end.y < 1.95,
				"%s %s sits on the upper body at person scale: %s" % [kind, part.name, box])
		view.dress("union", Color.TRANSPARENT)
		var visor: MeshInstance3D = view.accent_parts()[-1]
		var head: Vector3 = view.skeleton.global_transform * view.skeleton.get_bone_global_pose(view.skeleton.find_bone("Head")).origin
		_check(visor.name == "UnionVisor" and visor.visible and visor.global_position.z > head.z, "%s visor sits on the face side" % kind)
		var dark_body: Dictionary = FactionPalette.check({"base": Color(0.12, 0.12, 0.13), "accent": FactionPalette.UNION_RED})
		_check(dark_body["changed"], "a red accent on a dark body is refused")
		view.free()
