extends SceneTree
## #528 colour-blind team preset. Simulates deuteranopia and protanopia
## (Machado, Oliveira and Fernandes 2009, severity 1.0, in linear RGB) on the
## side colours a fight is read by: the body tape (team accent), the HUD side
## label, the feed and board marks, and the free-versus-free pair. Under the
## red-green safe choice every pair stays at least MIN_DELTA_E apart in
## CIELAB for both conditions, and every colour still keeps the faction
## contract (Union red only on the Union side, no cyan, no off-white free).
## The table prints every choice, so the standard palette's shortfall is on
## record beside the preset that fixes it.

## CIELAB distance that reads as clearly different colours at a glance.
const MIN_DELTA_E: float = 20.0
const DEUTERANOPIA: Basis = Basis(Vector3(0.367322, 0.280085, -0.011820), Vector3(0.860646, 0.672501, 0.042940), Vector3(-0.227968, 0.047413, 0.968881))
const PROTANOPIA: Basis = Basis(Vector3(0.152286, 0.114503, -0.003882), Vector3(1.052583, 0.786281, -0.048116), Vector3(-0.204868, 0.099216, 1.051998))

var _failures: int = 0


func _initialize() -> void:
	set_meta("localexception_automated", true)
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_colour_vision: " + message)


## A colour as a viewer with this condition sees it (sRGB in and out).
static func simulate(colour: Color, condition: Basis) -> Color:
	var linear: Color = colour.srgb_to_linear()
	var seen: Vector3 = condition * Vector3(linear.r, linear.g, linear.b)
	return Color(clampf(seen.x, 0.0, 1.0), clampf(seen.y, 0.0, 1.0), clampf(seen.z, 0.0, 1.0)).linear_to_srgb()


static func _lab(colour: Color) -> Vector3:
	var c: Color = colour.srgb_to_linear()
	var x: float = (0.4124 * c.r + 0.3576 * c.g + 0.1805 * c.b) / 0.95047
	var y: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	var z: float = (0.0193 * c.r + 0.1192 * c.g + 0.9505 * c.b) / 1.08883
	var f: Callable = func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = f.call(x)
	var fy: float = f.call(y)
	var fz: float = f.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func delta_e(a: Color, b: Color) -> float:
	return _lab(a).distance_to(_lab(b))


func _run() -> void:
	var names: Dictionary[int, String] = {LocalExceptionSettings.TEAM_STANDARD: "standard", LocalExceptionSettings.TEAM_HIGH_CONTRAST: "high contrast",
		LocalExceptionSettings.TEAM_COLOUR_BLIND: "red-green safe"}
	print("test_colour_vision: | choice | pair | normal | deuteranopia | protanopia |")
	for choice: int in names:
		var pairs: Dictionary[String, Array] = {
			"body tape": [FactionPalette.team_accent("union", choice), FactionPalette.team_accent("coalition", choice)],
			"side label": [MatchRules.team_label_color("union", choice), MatchRules.team_label_color("coalition", choice)],
			"feed mark": [HudRelation.mark_color("union", "", false, choice), HudRelation.mark_color("coalition", "", false, choice)],
			"free pair": FactionPalette.free_pair(choice),
		}
		for label: String in pairs:
			var a: Color = pairs[label][0]
			var b: Color = pairs[label][1]
			var normal: float = delta_e(a, b)
			var deut: float = delta_e(simulate(a, DEUTERANOPIA), simulate(b, DEUTERANOPIA))
			var prot: float = delta_e(simulate(a, PROTANOPIA), simulate(b, PROTANOPIA))
			print("test_colour_vision: | %s | %s | %.0f | %.0f | %.0f |" % [names[choice], label, normal, deut, prot])
			if choice == LocalExceptionSettings.TEAM_COLOUR_BLIND:
				_check(minf(deut, prot) >= MIN_DELTA_E, "%s stays apart for red-green viewers: %.1f / %.1f" % [label, deut, prot])
	# The preset keeps the contract: Union red stays Union red, and the free
	# side's blue is neither the Inheritance's cyan nor an off-white.
	var blind: int = LocalExceptionSettings.TEAM_COLOUR_BLIND
	_check(FactionPalette.team_accent("union", blind) == FactionPalette.UNION_RED, "Union keeps its red")
	for free: Color in [FactionPalette.team_accent("coalition", blind), MatchRules.team_label_color("coalition", blind)] + FactionPalette.free_pair(blind):
		_check(FactionPalette.free_accent_allowed(free), "free colour %s avoids red, cyan and off-white" % free.to_html(false))
	# The setting reaches the palette through LocalExceptionSettings.apply, and an
	# unknown stored choice falls back to standard.
	var settings: LocalExceptionSettings = LocalExceptionSettings.new("")
	settings.set_value("accessibility", "team_colours", blind)
	settings.apply_accessibility()
	_check(FactionPalette.team_accent("coalition") == FactionPalette.FREE_BLUE and MatchRules.team_label_color("coalition") == FactionPalette.FREE_BLUE_LABEL,
		"the saved choice recolours the free side")
	settings.set_value("accessibility", "team_colours", 7)
	_check(settings.team_colours() == LocalExceptionSettings.TEAM_STANDARD, "an unknown choice is refused")
	settings.apply_accessibility()
	_check(FactionPalette.team_accent("coalition") == FactionPalette.FREE_AMBER, "standard is amber again")
	if _failures == 0:
		print("test_colour_vision: PASS red-green safe sides apart by %.0f+ for deuteranopia and protanopia" % MIN_DELTA_E)
	quit(0 if _failures == 0 else 1)
