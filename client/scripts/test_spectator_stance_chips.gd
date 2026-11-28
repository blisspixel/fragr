extends SceneTree

# Headless gate: Tab-less stance chips share one short map across surfaces.
# Run: godot --path client --headless --script res://scripts/test_spectator_stance_chips.gd

func _initialize() -> void:
	var ok: bool = true
	var chip: GDScript = load("res://scripts/stance_chip.gd") as GDScript
	if chip == null:
		push_error("test_spectator_stance_chips: failed to load stance_chip.gd")
		quit(1)
		return

	var cases := {
		"Aggressive": "AGG",
		"Defensive": "DEF",
		"Flanker": "FLK",
		"Balanced": "BAL",
		"Compliance": "CMP",
		"push_enemy": "PSH",
		"fall_back_heal": "HL",
		"hold_angle": "HLD",
		"kite_distance": "KIT",
	}
	for raw: String in cases.keys():
		var got: String = str(chip.call("short", raw))
		var want: String = str(cases[raw])
		if got != want:
			push_error("test_spectator_stance_chips: short(%s)=%s want %s" % [raw, got, want])
			ok = false

	var empty: String = str(chip.call("short", "  "))
	if empty != "":
		push_error("test_spectator_stance_chips: blank behavior should short to empty")
		ok = false
	var custom: String = str(chip.call("short", "Scout"))
	if custom != "SCO":
		push_error("test_spectator_stance_chips: a custom chip keeps its first three letters: %s" % custom)
		ok = false
	var marked_chip: String = str(chip.call("short", "\n" + String.chr(0x202E) + "ab"))
	if marked_chip != "AB":
		push_error("test_spectator_stance_chips: a stance chip drops a break and a hidden mark: %s" % marked_chip.c_escape())
		ok = false
	if str(chip.call("short", String.chr(0x202E))) != "":
		push_error("test_spectator_stance_chips: a hidden stance chip is empty")
		ok = false
	var marked_follow_chip: String = str(chip.call("follow_line", "Jev", "\n" + String.chr(0x202E) + "xy", "RAIL"))
	if marked_follow_chip != "FOLLOWING: Jev [XY]\nRAIL":
		push_error("test_spectator_stance_chips: the follow line keeps one chip: %s" % marked_follow_chip.c_escape())
		ok = false
	var marked_plate: String = NameplateLayout.plate_text("Nightfall", "\nxx", " +2")
	if marked_plate != "Nightfall [XX] +2":
		push_error("test_spectator_stance_chips: a nameplate chip stays one line: %s" % marked_plate.c_escape())
		ok = false

	var roster: String = str(chip.call("roster_entry", "Dead Air Dan", "Aggressive"))
	if roster != "DEAD AIR DAN [AGG]":
		push_error("test_spectator_stance_chips: roster_entry got %s" % roster)
		ok = false
	var marked_roster: String = str(chip.call("roster_entry", "Ada" + String.chr(0x202E) + "x", "Aggressive"))
	if marked_roster != "ADAX [AGG]":
		push_error("test_spectator_stance_chips: a roster chip kept a bidirectional mark: %s" % marked_roster)
		ok = false

	var follow: String = str(chip.call("follow_line", "Jev", "push_enemy", ""))
	if follow != "FOLLOWING: Jev [PSH]":
		push_error("test_spectator_stance_chips: follow without weapon got %s" % follow)
		ok = false
	var marked_follow: String = str(chip.call("follow_line", "Ada" + String.chr(0x202E) + "x", "push_enemy", "RAIL"))
	if marked_follow != "FOLLOWING: Adax [PSH]\nRAIL":
		push_error("test_spectator_stance_chips: a follow line kept a bidirectional mark: %s" % marked_follow)
		ok = false

	var follow_w: String = str(chip.call("follow_line", "Jev", "hold_angle", "RAIL (long)"))
	if follow_w != "FOLLOWING: Jev [HLD]\nRAIL (long)":
		push_error("test_spectator_stance_chips: follow with weapon got %s" % follow_w)
		ok = false

	# The plate keeps the true chip beside the callsign; health is the bar.
	var plate: String = NameplateLayout.plate_text("Nightfall", "Defensive", " +2")
	if plate != "Nightfall [DEF] +2":
		push_error("test_spectator_stance_chips: nameplate got %s" % plate)
		ok = false

	var accent: Color = chip.call("accent_color", true) as Color
	if accent.r < 0.85 or accent.g < 0.5:
		push_error("test_spectator_stance_chips: accent should be ember scrap, got %s" % accent)
		ok = false

	if ok:
		print("test_spectator_stance_chips: PASS shorts=", cases.size(), " surfaces=3")
		quit(0)
	else:
		push_error("test_spectator_stance_chips: FAIL")
		quit(1)
