extends SceneTree

## Sabotage on the client: strict wire validation, the one HUD line, the round
## card, the feed words, the world presenter and the picture widgets.
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_sabotage_state: " + reason)


func _layout() -> Dictionary:
	return {
		"attackers": "coalition",
		"sites": [
			{"id": "a", "center": [-38.0, 0.0, -27.0], "radius": 3.0},
			{"id": "b", "center": [-38.0, 0.0, 27.0], "radius": 3.0},
		],
		"callouts": [
			{"id": "a_frame", "min": [-44.0, -33.0], "max": [-32.0, -21.0]},
			{"id": "mid", "min": [-26.0, -26.0], "max": [26.0, 26.0]},
		],
	}


func _state() -> Dictionary:
	return {
		"format": "short", "phase": "live", "round": 3, "period": 0, "half": 1,
		"half_rounds": 4, "rounds_to_win": 5,
		"score": {"union": 2, "coalition": 0}, "alive": {"union": 4, "coalition": 3},
		"clock_ticks": 1460,
		"charge": {"status": "carried", "position": [10.0, 0.0, -2.0], "carrier": "c1"},
	}


func _run() -> void:
	# Layout validation.
	var info: Dictionary = {"sabotage": _layout()}
	_check(SabotageState.map_error(info).is_empty(), "the Sector 9 layout parses")
	_check(SabotageState.map_error({}).is_empty(), "no layout is not an error")
	var bad: Dictionary = _layout()
	bad["attackers"] = "union"
	_check(not SabotageState.map_error({"sabotage": bad}).is_empty(), "the Union never attacks")
	bad = _layout()
	(bad["sites"] as Array).reverse()
	_check(not SabotageState.map_error({"sabotage": bad}).is_empty(), "sites come a then b")
	bad = _layout()
	bad["sites"][0]["radius"] = 40.0
	_check(not SabotageState.map_error({"sabotage": bad}).is_empty(), "a plant area is bounded")
	bad = _layout()
	bad["callouts"][0]["id"] = "A Frame"
	_check(not SabotageState.map_error({"sabotage": bad}).is_empty(), "callout ids are snake_case")
	bad = _layout()
	bad["callouts"][0]["min"] = [0.0, 0.0]
	bad["callouts"][0]["max"] = [-1.0, 5.0]
	_check(not SabotageState.map_error({"sabotage": bad}).is_empty(), "callout bounds are ordered")
	_check(SabotageState.callout_at(_layout(), -38.0, -27.0) == "a_frame", "the first containing region names a point")
	_check(SabotageState.callout_at(_layout(), 90.0, 0.0) == "", "outside every region is unnamed")

	# Snapshot validation.
	var snap: Dictionary = {"sabotage": _state()}
	_check(SabotageState.snapshot_error(snap).is_empty(), "a carried charge parses")
	_check(SabotageState.snapshot_error({}).is_empty(), "no round state is not an error")
	var state: Dictionary = _state()
	state["phase"] = "overtime"
	_check(not SabotageState.snapshot_error({"sabotage": state}).is_empty(), "unknown phases are refused")
	state = _state()
	state["charge"]["status"] = "dropped"
	_check(not SabotageState.snapshot_error({"sabotage": state}).is_empty(), "a dropped charge has no carrier")
	state["charge"].erase("carrier")
	_check(SabotageState.snapshot_error({"sabotage": state}).is_empty(), "a dropped charge parses")
	state["charge"]["status"] = "planted"
	_check(not SabotageState.snapshot_error({"sabotage": state}).is_empty(), "a planted charge names its site")
	state["charge"]["site"] = "b"
	state["phase"] = "planted"
	state["progress"] = {"kind": "defuse", "player_id": "u1", "site": "b", "ticks": 60, "needed": 120}
	_check(SabotageState.snapshot_error({"sabotage": state}).is_empty(), "a defuse under way parses")
	state["progress"]["ticks"] = 121
	_check(not SabotageState.snapshot_error({"sabotage": state}).is_empty(), "progress cannot pass its total")
	state = _state()
	state["half"] = 3
	_check(not SabotageState.snapshot_error({"sabotage": state}).is_empty(), "there are two halves")
	state = _state()
	state["alive"]["coalition"] = -1
	_check(not SabotageState.snapshot_error({"sabotage": state}).is_empty(), "living counts are counts")

	# Words.
	_check(SabotageState.clock_text(1460) == "1:13", "the clock rounds up to whole seconds")
	_check(SabotageState.clock_text(1) == "0:01", "the last tick still shows a second")
	_check(SabotageState.clock_text(0) == "0:00", "an empty clock reads zero")
	var line: String = SabotageState.hud_line(_state(), "coalition")
	_check(line == "R3  ATTACK  UNION 2 : 0 FREE  1:13", "the attack's one line: " + line)
	_check(not line.contains("\n"), "the HUD line is one line")
	state = _state()
	state["phase"] = "planted"
	state["clock_ticks"] = 420
	line = SabotageState.hud_line(state, "union")
	_check(line == "R3  DEFEND  UNION 2 : 0 FREE  CHARGE 0:21", "the defence reads the charge clock: " + line)
	_check(SabotageState.hud_line(_state(), "").begins_with("SABOTAGE R3"), "a spectator reads the mode")
	_check(is_equal_approx(SabotageState.charge_fraction(state, 700), 0.6), "the charge timer drains")
	_check(SabotageState.charge_fraction(_state(), 700) < 0.0, "no timer before a plant")
	state["progress"] = {"kind": "plant", "player_id": "c1", "site": "a", "ticks": 30, "needed": 60}
	_check(is_equal_approx(SabotageState.progress_fraction(state), 0.5), "half a plant is half a bar")
	_check(SabotageState.event_line({"kind": "planted", "site": "a"}, "union") == "CHARGE PLANTED AT A FRAME", "everyone hears a plant")
	_check(SabotageState.event_line({"kind": "charge_taken", "player": "Kid"}, "union") == "", "the defence is not told who carries")
	_check(SabotageState.event_line({"kind": "charge_taken", "player": "Kid"}, "coalition") == "KID HAS THE CHARGE", "the attack is")
	_check(SabotageState.event_line({"kind": "charge_taken", "player": "Kid"}, "") == "KID HAS THE CHARGE", "and so are spectators")
	_check(SabotageState.event_line({"kind": "plant_interrupted"}, "") == "", "interruptions stay off the feed")
	_check(SabotageState.event_line({"kind": "made_up"}, "") == "", "unknown kinds are dropped")
	var end: Dictionary = {
		"event": "round_end", "winning_team": "coalition",
		"sabotage": {"reason": "detonation", "round": 4, "score": {"union": 1, "coalition": 3}, "sides_swap": true},
	}
	var card: String = SabotageState.result_text(end, "coalition")
	_check(card.begins_with("THE FREE COALITION TAKES ROUND 4"), "the card names the winner: " + card)
	_check(card.contains("THE CHARGE WENT UP") and card.contains("UNION 1 : 3 FREE"), "the card gives the reason and score")
	_check(card.contains("SIDES SWAP NEXT ROUND") and card.contains("ROUND TO YOUR SIDE"), "the card warns of the swap")
	end["sabotage"]["match_over"] = true
	end["sabotage"]["match_winner"] = "coalition"
	_check(SabotageState.result_text(end, "").contains("TAKES THE MATCH"), "the card closes the match")
	end["winning_team"] = "nobody"
	_check(SabotageState.result_text(end, "").is_empty(), "a malformed result shows no card")

	# Art and sound placeholders.
	_check(SabotageArt.site_plate("a").get_width() == 32, "a site plate is a 32 pixel sprite")
	_check(SabotageArt.site_plate("a") == SabotageArt.site_plate("a"), "textures are cached")
	_check(SabotageArt.site_prop("b").get_height() == 32 and SabotageArt.charge().get_width() == 16, "props and the charge are sprites")
	_check(SabotageAudio.beep().data.size() > 0 and SabotageAudio.hum().loop_mode == AudioStreamWAV.LOOP_FORWARD, "the beep plays and the hum loops")
	_check(SabotageAudio.detonation().data == SabotageAudio.detonation().data, "the detonation is the same every time")
	_check(SabotageAudio.next_beep(700) == 600 and SabotageAudio.next_beep(600) == 500, "beeps every five seconds at first")
	_check(SabotageAudio.next_beep(200) == 180 and SabotageAudio.next_beep(100) == 90, "then every second, then twice a second")
	_check(SabotageAudio.beep_pitch(0.0) > SabotageAudio.beep_pitch(1.0), "the beep rises as time runs out")

	# World presenter.
	var world: ArenaSabotage = ArenaSabotage.new()
	root.add_child(world)
	world.set_layout(_layout())
	var site_a: Node3D = world.get_node("SiteA") as Node3D
	_check(site_a != null and site_a.position.is_equal_approx(Vector3(-38.0, 0.0, -27.0)), "site A sits on its plant area")
	_check((site_a.get_node("Plate") as Sprite3D).texture == SabotageArt.site_plate("a"), "the site marker is a sprite, not text")
	_check(site_a.get_node_or_null("Label3D") == null, "no world text marks a site")
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	holder.position = Vector3(10.0, 1.5, -2.0)
	world.apply(_state(), {"c1": holder}, "coalition")
	var charge: Node3D = world.get_node("Charge") as Node3D
	_check(charge.visible, "the attack sees its carrier's charge")
	world.apply(_state(), {"c1": holder}, "union")
	world._process(0.0)
	_check(charge.visible and not (world.get_node("Charge/Body") as Sprite3D).visible, "the defence sees no charge on the carrier")
	_check((world.get_node("Charge/Hum") as AudioStreamPlayer3D).max_distance <= 10.0, "but its hum gives the carrier away within ten metres")
	world.set_first_person("c1")
	world.apply(_state(), {"c1": holder}, "coalition")
	_check(not charge.visible, "the carrier's own eyes see the HUD charge instead")
	world.set_first_person("")
	state = _state()
	state["phase"] = "planted"
	state["charge"] = {"status": "planted", "position": [-37.0, 0.0, -26.0], "site": "a"}
	state["clock_ticks"] = 700
	world.set_charge_ticks(700)
	world.apply(state, {}, "union")
	_check(charge.visible and charge.position.is_equal_approx(Vector3(-37.0, 0.0, -26.0)), "a planted charge is seen by everyone where it lies")
	state["charge"]["status"] = "detonated"
	world.apply(state, {}, "union")
	_check(not charge.visible or world.get_node("Charge/Burst") != null, "a detonation leaves only its burst")
	world.set_layout({})
	_check(world.get_node_or_null("SiteA") == null or world.get_node("SiteA").is_queued_for_deletion(), "an empty layout clears the sites")

	# Picture widgets.
	var widgets: SabotageHud = SabotageHud.new()
	root.add_child(widgets)
	widgets.apply(_state(), 700, false, true)
	_check(widgets.carrying and widgets.progress_shown < 0.0 and widgets.timer_shown < 0.0, "a carrier sees the charge and no bars")
	state = _state()
	state["phase"] = "planted"
	state["clock_ticks"] = 350
	state["progress"] = {"kind": "defuse", "player_id": "u1", "site": "a", "ticks": 60, "needed": 120}
	widgets.apply(state, 700, true, false)
	_check(is_equal_approx(widgets.timer_shown, 0.5) and is_equal_approx(widgets.progress_shown, 0.5), "the timer and the defuse are bars")
	widgets.apply(state, 700, false, false)
	_check(widgets.progress_shown < 0.0, "only the defuser's own view gets the bar")
	widgets.apply({}, 700, false, false)
	_check(not widgets.carrying and widgets.timer_shown < 0.0, "an empty round hides everything")

	_check(MatchRules.parse({"mode": "sabotage", "name": "Sabotage", "lives": 1}).get("mode") == "sabotage", "the rule set parses")
	_check(MatchRules.teams({"mode": "sabotage"}), "Sabotage has sides")

	holder.queue_free()
	world.queue_free()
	widgets.queue_free()
	await process_frame
	if _failures == 0:
		print("test_sabotage_state: PASS")
	quit(0 if _failures == 0 else 1)
