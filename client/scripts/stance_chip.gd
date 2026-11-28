extends RefCounted
class_name StanceChip
## Observe-only PlayerState.behavior short codes for spectator surfaces.
## Shared by Warmup TV roster, follow HUD, nameplate (`NameplateLayout`) and Tab scoreboard.
## Never trusted for combat; display only.


static func short(behavior: String) -> String:
	# A server chip is display only. Copy it as one plain line before the
	# three-letter fallback, so a break or a hidden mark cannot reach a plate.
	var b: String = LocalExceptionSettings.one_line(behavior, 32)
	if b == "":
		return ""
	match b:
		"Aggressive":
			return "AGG"
		"Defensive":
			return "DEF"
		"Flanker":
			return "FLK"
		"Balanced":
			return "BAL"
		"Compliance":
			return "CMP"
		"push_enemy":
			return "PSH"
		"fall_back_heal":
			return "HL"
		"hold_angle":
			return "HLD"
		"kite_distance":
			return "KIT"
		_:
			return b.substr(0, mini(3, b.length())).to_upper()


static func bracket(behavior: String) -> String:
	var code := short(behavior)
	if code == "":
		return ""
	return " [" + code + "]"


static func roster_entry(player_name: String, behavior: String = "") -> String:
	var shown: String = LocalExceptionSettings.one_line(player_name, 64)
	if shown.is_empty() or shown == "Spectator":
		return ""
	return shown.to_upper() + bracket(behavior)


static func follow_line(player_name: String, behavior: String = "", weapon_desc: String = "") -> String:
	var shown: String = LocalExceptionSettings.one_line(player_name, 64)
	if shown.is_empty():
		return weapon_desc
	var line: String = "FOLLOWING: " + shown + bracket(behavior)
	if weapon_desc != "":
		line += "\n" + weapon_desc
	return line


## Ember scrap accent when a stance is present (loud without neon).
static func accent_color(has_stance: bool) -> Color:
	if has_stance:
		return Color(0.92, 0.58, 0.26, 1)
	return Color(0.7, 0.7, 0.7, 1)
