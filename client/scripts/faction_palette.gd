class_name FactionPalette
extends RefCounted

## The faction readability contract in code (docs/ART_STORY_BIBLE.md, "Faction
## readability contract"). From a distance a free human or agent must never
## read as a Union enforcer or an Inheritance machine:
##
## - Union: black cloth, plates one step lighter, red visors, armbands and
##   optics. Red light belongs to Union hardware.
## - Free: individual personal colour, warm personal light, never the Union
##   black-plus-red livery or a matte off-white base.
## - Inheritance: matte off-white continuous bodies, muted cyan working light.
##
## `check` is the colour picker rule. Every colour picker, saved record and
## received cosmetic runs its composed body through it, on load as well as on
## pick. It snaps to the nearest allowed colour and says why in one line.
## Presentation only: nothing here decides a side or an outcome.

## Union issued livery.
const UNION_CLOTH: Color = Color("141416")
const UNION_PLATE: Color = Color("3c3d43")
const UNION_RED: Color = Color("e23430")
## How the issued livery recolours a body's own art: grey, then this bright.
## White panels become plates one step above black cloth.
const UNION_LIVERY_BRIGHTNESS: float = 0.34
## The free side's team accent: the warm amber of the existing Free plate,
## with a lighter warm yellow under the high-contrast team setting.
const FREE_AMBER: Color = Color("dc8c3c")
const FREE_AMBER_HIGH_CONTRAST: Color = Color("ffc93c")
## Free-versus-free sides: ember and magenta by default, and a yellow and
## blue pair that stays apart in grayscale and for red-green colour vision.
const FREE_EMBER: Color = Color("e8782a")
const FREE_MAGENTA: Color = Color("c8409e")
const FREE_PAIR_HIGH_CONTRAST: Array[Color] = [Color("ffd23f"), Color("3d50ff")]
## Inheritance restoration machines: never on a free body.
const INHERITANCE_BONE: Color = Color("d9d4c7")
const INHERITANCE_CYAN: Color = Color("4a8a92")

## Thresholds from the contract, in degrees and 0 to 1 HSV. They are a
## starting point to tune in the actual renderer.
const RED_HUE_FROM: float = 340.0
const RED_HUE_TO: float = 20.0
const CYAN_HUE_FROM: float = 160.0
const CYAN_HUE_TO: float = 220.0
const WARM_LIGHT_FROM: float = 25.0
const WARM_LIGHT_TO: float = 55.0
const DARK_BASE_VALUE: float = 0.30
const OFF_WHITE_VALUE: float = 0.80
const OFF_WHITE_SATURATION: float = 0.15
## Below this saturation a colour reads grey or white, so its hue is not
## perceived and no hue rule applies.
const HUE_SATURATION_FLOOR: float = 0.25
## A dim red under this value reads black, not red.
const RED_VALUE_FLOOR: float = 0.20
## A white light at or below this saturation counts as warm white.
const WARM_WHITE_SATURATION: float = 0.12
## How far a snapped colour sits inside the allowed range.
const SNAP_MARGIN_DEGREES: float = 5.0
const SNAP_MARGIN: float = 0.02
## Painted fields of a composed body. `base` is the dominant body colour.
const PAINT_FIELDS: Array[String] = ["base", "secondary", "trim", "accent"]
const LIGHT_FIELDS: Array[String] = ["emissive"]


static func hue_degrees(color: Color) -> float:
	return fposmod(color.h * 360.0, 360.0)


static func _hue_in(color: Color, from: float, to: float) -> bool:
	var hue: float = hue_degrees(color)
	if from <= to:
		return hue >= from and hue <= to
	return hue >= from or hue <= to


## A saturated red, hue about 340 to 20 degrees.
static func is_red(color: Color) -> bool:
	return color.s >= HUE_SATURATION_FLOOR and color.v >= RED_VALUE_FLOOR \
		and _hue_in(color, RED_HUE_FROM, RED_HUE_TO)


## A saturated cyan, hue about 160 to 220 degrees.
static func is_cyan(color: Color) -> bool:
	return color.s >= HUE_SATURATION_FLOOR and _hue_in(color, CYAN_HUE_FROM, CYAN_HUE_TO)


## Near-black, the Union's cloth.
static func is_dark(color: Color) -> bool:
	return color.v <= DARK_BASE_VALUE


## Matte off-white, the Inheritance's surface.
static func is_off_white(color: Color) -> bool:
	return color.v >= OFF_WHITE_VALUE and color.s <= OFF_WHITE_SATURATION


## Warm amber to warm white: the only personal light a free body carries.
static func is_warm_light(color: Color) -> bool:
	return color.s <= WARM_WHITE_SATURATION or _hue_in(color, WARM_LIGHT_FROM, WARM_LIGHT_TO)


static func _with_hue(color: Color, degrees: float) -> Color:
	return Color.from_hsv(fposmod(degrees, 360.0) / 360.0, color.s, color.v, color.a)


static func _arc_distance(a: float, b: float) -> float:
	var gap: float = absf(fposmod(a - b, 360.0))
	return minf(gap, 360.0 - gap)


## Move a hue to the nearer edge outside [from, to], a margin clear of it.
static func _hue_outside(color: Color, from: float, to: float) -> Color:
	var hue: float = hue_degrees(color)
	var below: float = from - SNAP_MARGIN_DEGREES
	var above: float = to + SNAP_MARGIN_DEGREES
	return _with_hue(color, below if _arc_distance(hue, from) <= _arc_distance(hue, to) else above)


## Move a hue to the nearer edge inside [from, to], a margin within it.
static func _hue_inside(color: Color, from: float, to: float) -> Color:
	var hue: float = hue_degrees(color)
	var low: float = from + SNAP_MARGIN_DEGREES
	var high: float = to - SNAP_MARGIN_DEGREES
	return _with_hue(color, low if _arc_distance(hue, from) <= _arc_distance(hue, to) else high)


## The nearer of a darker value or a warmer saturation, so a pale base stops
## reading as an Inheritance shell while keeping as much of the choice as it can.
static func _off_off_white(color: Color) -> Color:
	var darker: Color = Color.from_hsv(color.h, color.s, OFF_WHITE_VALUE - SNAP_MARGIN, color.a)
	var hue: float = color.h if color.s > 0.02 else WARM_LIGHT_FROM / 360.0
	var warmer: Color = Color.from_hsv(hue, OFF_WHITE_SATURATION + SNAP_MARGIN, color.v, color.a)
	var to_darker: float = Vector3(darker.r - color.r, darker.g - color.g, darker.b - color.b).length()
	var to_warmer: float = Vector3(warmer.r - color.r, warmer.g - color.g, warmer.b - color.b).length()
	return darker if to_darker <= to_warmer else warmer


## The colour picker rule on a composed free body. `scheme` maps `base`
## (required), `secondary`, `trim`, `accent` and `emissive` to colours. The
## result is {"scheme": the allowed scheme, "changed": bool, "reason": one
## line naming every snap, or empty}. Unknown fields and non-colours are
## dropped, because a received record is untrusted.
static func check(scheme: Dictionary) -> Dictionary:
	var allowed: Dictionary = {}
	var reasons: PackedStringArray = []
	for field: String in PAINT_FIELDS + LIGHT_FIELDS:
		if scheme.get(field) is Color:
			allowed[field] = scheme[field]
		elif scheme.has(field):
			reasons.append("%s is not a colour, so it was dropped" % field)
	if not allowed.has("base"):
		return {"scheme": {}, "changed": true, "reason": "a body needs a base colour"}
	var base: Color = allowed["base"]
	if is_off_white(base):
		allowed["base"] = _off_off_white(base)
		reasons.append("a matte off-white body reads as an Inheritance machine, so the base moved off it")
	elif is_dark(base):
		var moved: PackedStringArray = []
		for field: String in ["secondary", "trim", "accent"]:
			if allowed.has(field) and is_red(allowed[field]):
				allowed[field] = _hue_outside(allowed[field], RED_HUE_FROM, RED_HUE_TO)
				moved.append(field)
		if not moved.is_empty():
			reasons.append("black with red is the Union's issued livery, so %s moved off red" % ", ".join(moved))
	if allowed.has("emissive") and not is_warm_light(allowed["emissive"]):
		var light: Color = allowed["emissive"]
		allowed["emissive"] = _hue_inside(light, WARM_LIGHT_FROM, WARM_LIGHT_TO)
		if is_red(light) or is_cyan(light):
			reasons.append("red light is the Union's and cyan light the Inheritance's, so the light moved to warm amber")
		else:
			reasons.append("personal light stays warm amber to warm white, so the light moved to warm amber")
	return {"scheme": allowed, "changed": not reasons.is_empty(), "reason": "; ".join(reasons)}


## A saved or received record of `#rrggbb` strings, checked the same way, so
## an edited file cannot bypass the picker. Invalid strings are dropped.
static func check_record(record: Variant) -> Dictionary:
	if not record is Dictionary:
		return {"scheme": {}, "changed": true, "reason": "a colour record must be an object"}
	var scheme: Dictionary = {}
	var reasons: PackedStringArray = []
	for field: String in PAINT_FIELDS + LIGHT_FIELDS:
		var value: Variant = record.get(field)
		if value == null:
			continue
		if value is String and (value as String).length() <= 9 and Color.html_is_valid(value):
			scheme[field] = Color.html(value)
		else:
			reasons.append("%s is not a colour, so it was dropped" % field)
	var result: Dictionary = check(scheme)
	if not reasons.is_empty():
		var line: String = "; ".join(reasons)
		result["reason"] = line if str(result["reason"]).is_empty() else line + "; " + str(result["reason"])
		result["changed"] = true
	return result


## A nameplate colour: never Union red, Inheritance cyan or matte off-white,
## because a plate is drawn unshaded and reads as light at a distance.
static func label_color(color: Color) -> Color:
	var snapped: Color = color
	if is_red(snapped):
		snapped = _hue_outside(snapped, RED_HUE_FROM, RED_HUE_TO)
	elif is_cyan(snapped):
		snapped = _hue_outside(snapped, CYAN_HUE_FROM, CYAN_HUE_TO)
	if is_off_white(snapped):
		snapped = _off_off_white(snapped)
	return snapped


## The free-for-all colour hashed from a callsign: spread over the hues that
## stay clear of red and cyan, at a saturation that is never off-white.
static func callsign_color(seed: String) -> Color:
	var first: Array[float] = [RED_HUE_TO + SNAP_MARGIN_DEGREES, CYAN_HUE_FROM - SNAP_MARGIN_DEGREES]
	var second: Array[float] = [CYAN_HUE_TO + SNAP_MARGIN_DEGREES, RED_HUE_FROM - SNAP_MARGIN_DEGREES]
	var span: int = int(first[1] - first[0]) + int(second[1] - second[0])
	var step: int = absi(hash(seed)) % span
	var hue: float = first[0] + step
	if hue > first[1]:
		hue = second[0] + (step - int(first[1] - first[0]))
	return Color.from_hsv(hue / 360.0, 0.8, 0.9)


## Which livery a side wears. A mode that assigns the Union side gets the
## issued livery: uniformity is the point. Everyone else keeps their own.
static func livery(team: String) -> String:
	return "union" if team == "union" else "free"


## The team accent on shoulder and arm tape. Union red only on the Union side;
## the free coalition carries the warm amber of its plate. Clear when sideless.
static func team_accent(team: String, high_contrast: bool = false) -> Color:
	match team:
		"union":
			return UNION_RED
		"coalition":
			return FREE_AMBER_HIGH_CONTRAST if high_contrast else FREE_AMBER
	return Color(0, 0, 0, 0)


## The two accents of a free-versus-free match, in side order.
static func free_pair(high_contrast: bool = false) -> Array[Color]:
	if high_contrast:
		return FREE_PAIR_HIGH_CONTRAST.duplicate()
	return [FREE_EMBER, FREE_MAGENTA]


## A free side's team accent is never Union red, matte off-white or cyan.
static func free_accent_allowed(color: Color) -> bool:
	return not is_red(color) and not is_off_white(color) and not is_cyan(color)
