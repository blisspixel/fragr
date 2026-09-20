extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	_check(QaCombat.valid_search_route([[1, 2.0, 3]]), "finite route accepted")
	for invalid: Variant in [null, {}, [[1, 2]], [[1, INF, 3]], [[1, "2", 3]]]:
		_check(not QaCombat.valid_search_route(invalid), "invalid route rejected")
	var me: Dictionary = {"id":"player", "hp":100, "x":0.0, "y":1.5, "z":0.0, "campaign":{"side":"participant"}}
	var friend: Dictionary = me.duplicate(true)
	friend["id"] = "friend"
	friend["z"] = 1.0
	var guard: Dictionary = {"id":"guard", "hp":60, "x":0.0, "y":1.5, "z":5.0,
		"campaign":{"side":"union", "kind":"clerk", "phase":"windup"}}
	var snapshot: Dictionary = {"tick":1, "players":[me, friend, guard]}
	_check(QaCombat.visible_target(snapshot, "player", []).get("id") == "guard", "closer participant is never a target")
	_check(not QaCombat.visible_target(snapshot, "player", [], true).is_empty(), "visible windup permits evasive input")
	_check(QaCombat.visible_target(snapshot, "player", [], false, 24.0).get("id") == "guard", "travel engages a nearby threat")
	guard["z"] = 34.0
	_check(QaCombat.visible_target(snapshot, "player", [], false, 24.0).is_empty(), "travel continues past a distant sightline")
	_check(QaCombat.visible_target(snapshot, "player", []).get("id") == "guard", "combat can still resolve a distant required guard")
	guard["z"] = 5.0
	var solid: Dictionary = {"min_x":-1.0, "max_x":1.0, "min_z":2.0, "max_z":3.0, "bottom":0.0, "top":3.0}
	_check(QaCombat.visible_target(snapshot, "player", [solid]).is_empty(), "wall prevents automated fire")
	_check(QaCombat.visible_target(snapshot, "player", [solid], true).is_empty(), "hidden windup cannot drive evasion")
	var low_cover: Dictionary = {"min_x":-1.0, "max_x":1.0, "min_z":3.0, "max_z":4.0, "bottom":0.0, "top":1.3}
	var exposed: Vector3 = QaCombat.exposed_point(guard, Vector3(0, 1.6, 0), [low_cover])
	_check(exposed.y > 1.3 and exposed.y < MoveStep.BODY_HEIGHT, "low cover permits an exposed upper-body shot within the real hit volume")
	_check(QaCombat.visible_target(snapshot, "player", [low_cover], true).get("id") == "guard", "visible upper-body tell permits evasion")
	solid["bottom"] = 2.4
	_check(QaCombat.visible_target(snapshot, "player", [solid]).get("id") == "guard", "raised deck leaves a real underpass")
	guard["campaign"]["phase"] = "idle"
	_check(QaCombat.visible_target(snapshot, "player", [], true).is_empty(), "idle guard has no committed tell")
	guard["hp"] = 0
	guard["campaign"]["phase"] = "dead"
	_check(QaCombat.visible_target(snapshot, "player", []).is_empty(), "corpse is not a target")
	var probe: QaCombat = QaCombat.new()
	probe.set("_player_id", "player")
	probe.set("_kind", "clerk")
	probe.set("_recording", true)
	snapshot["shot_results"] = [{"shooter_id":"player"}, {"shooter_id":"friend"}, {"shooter_id":"guard"}]
	probe._observe(snapshot)
	probe._observe(snapshot)
	_check(probe.shots == 1 and probe.defeated.size() == 1, "repeated snapshot cannot inflate evidence")
	_check(probe.enemy_shots == 1, "a friend's shot cannot stand in for an enemy tell")
	var next_room: QaCombat = QaCombat.new()
	next_room.set("_player_id", "player")
	next_room.set("_kind", "union")
	next_room.set("_recording", true)
	var old_corpses: Dictionary[String, bool] = {"guard": true}
	next_room.set("_initial_dead", old_corpses)
	next_room._observe(snapshot)
	_check(next_room.defeated.is_empty(), "preceding room's corpse cannot satisfy a new encounter")
	var second: Dictionary = guard.duplicate(true)
	second["id"] = "second"
	second["campaign"]["kind"] = "sweeper"
	snapshot["players"].append(second)
	me["hp"] = 0
	snapshot["tick"] = 2
	probe._observe(snapshot)
	next_room._observe(snapshot)
	_check(next_room.defeated.size() == 1 and next_room.defeated.has("second"), "mixed encounter counts a new bot defeat")
	me["hp"] = 100
	snapshot["tick"] = 3
	probe._observe(snapshot)
	_check(probe.participant_died, "respawn cannot hide a failed combat run")
	var history: QaCombat = QaCombat.new()
	guard["name"] = "early_guard"
	second["name"] = "other_guard"
	history._observe(snapshot)
	_check(history.confirmed(["early_guard", "missing_guard"]).size() == 1, "an unrelated guard cannot satisfy a named encounter")
	snapshot["tick"] = 4
	history._observe(snapshot)
	_check(history.confirmed(["early_guard"])["early_guard"] == 3, "later corpse snapshots preserve the first observed death tick")
	snapshot["tick"] = 5
	snapshot["players"] = [me]
	history._observe(snapshot)
	_check(history.confirmed(["early_guard"]).has("early_guard"), "a verified earlier death survives corpse cleanup")
	_check(history.defeated.is_empty(), "between-fight history cannot inflate per-fight defeats")
	var absence: QaCombat = QaCombat.new()
	absence.set("_player_id", "player")
	absence._observe(snapshot)
	snapshot["players"] = []
	snapshot["tick"] = 6
	absence._observe(snapshot)
	snapshot["players"] = [me]
	snapshot["tick"] = 7
	absence._observe(snapshot)
	_check(absence.participant_died, "omitted respawning participant cannot hide a death between fights")
	if _failures == 0:
		print("test_qa_combat: PASS")
	quit(0 if _failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_qa_combat: " + message)
