extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	var me: Dictionary = {"id":"player", "hp":100, "x":0.0, "y":1.5, "z":0.0, "campaign":{"side":"participant"}}
	var friend: Dictionary = me.duplicate(true)
	friend["id"] = "friend"
	friend["z"] = 1.0
	var guard: Dictionary = {"id":"guard", "hp":60, "x":0.0, "y":1.5, "z":5.0,
		"campaign":{"side":"union", "kind":"clerk", "phase":"windup"}}
	var snapshot: Dictionary = {"tick":1, "players":[me, friend, guard]}
	_check(QaCombat.visible_target(snapshot, "player", []).get("id") == "guard", "closer participant is never a target")
	var solid: Dictionary = {"min_x":-1.0, "max_x":1.0, "min_z":2.0, "max_z":3.0, "bottom":0.0, "top":3.0}
	_check(QaCombat.visible_target(snapshot, "player", [solid]).is_empty(), "wall prevents automated fire")
	solid["bottom"] = 2.4
	_check(QaCombat.visible_target(snapshot, "player", [solid]).get("id") == "guard", "raised deck leaves a real underpass")
	guard["hp"] = 0
	guard["campaign"]["phase"] = "dead"
	_check(QaCombat.visible_target(snapshot, "player", []).is_empty(), "corpse is not a target")
	var probe: QaCombat = QaCombat.new()
	probe.set("_player_id", "player")
	probe.set("_kind", "clerk")
	snapshot["shot_results"] = [{"shooter_id":"player"}, {"shooter_id":"friend"}, {"shooter_id":"guard"}]
	probe._observe(snapshot)
	probe._observe(snapshot)
	_check(probe.shots == 1 and probe.defeated.size() == 1, "repeated snapshot cannot inflate evidence")
	_check(probe.enemy_shots == 1, "a friend's shot cannot stand in for an enemy tell")
	me["hp"] = 0
	snapshot["tick"] = 2
	probe._observe(snapshot)
	me["hp"] = 100
	snapshot["tick"] = 3
	probe._observe(snapshot)
	_check(probe.participant_died, "respawn cannot hide a failed combat run")
	if _failures == 0:
		print("test_qa_combat: PASS")
	quit(0 if _failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_qa_combat: " + message)
