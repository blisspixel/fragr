extends SceneTree

const OWNER: String = "00000000-0000-0000-0000-000000000002"
const AUDITOR: String = "00000000-0000-0000-0000-0000000000a1"
const BODY: String = "00000000-0000-0000-0000-0000000000b1"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_custody_devices: " + message)

func _mine(tick: int, phase: String, started: int) -> Dictionary:
	var ends: int = started
	if phase == "arming":
		ends = started + CustodyFacts.ARMING_TICKS
	elif phase == "tripped":
		ends = started + CustodyFacts.TRIP_TICKS
	var normal: Array = [0, 0, 0] if phase == "flying" else [-1, 0, 0]
	return {"tick": tick, "mines": [{"id": 7, "owner_id": OWNER, "position": [2.88, 1.2, 0.5], "normal": normal,
		"phase": phase, "phase_started": started, "phase_ends": ends}]}

func _auditors(tick: int, left: int, target: String = "") -> Dictionary:
	var fact: Dictionary = {"id": AUDITOR, "repairs_left": left}
	if not target.is_empty():
		fact["channel_target"] = target
	return {"tick": tick, "auditors": [fact]}

func _blast(radius: float, damage: int) -> Dictionary:
	return {"tick": 30, "explosions": [{"id": 9, "owner_id": OWNER, "position": [0, 1, 2], "radius": radius,
		"hits": [{"target_id": BODY, "hp_damage": damage, "armor_damage": 0, "target_hp_after": 80 - damage, "killed": 80 - damage <= 0}]}]}

func _run() -> void:
	# Strict facts.
	for phase: String in CustodyFacts.MINE_PHASES:
		_check(CustodyFacts.validation_error(_mine(50, phase, 10)).is_empty(), "actual %s mine accepted" % phase)
	for patch: Dictionary in [{"id": 0}, {"owner_id": "bad"}, {"position": [NAN, 0, 0]}, {"normal": [0, 0, 0]},
			{"phase": "live"}, {"phase_started": 51}, {"phase_ends": 11}, {"extra": true}]:
		var bad: Dictionary = _mine(50, "arming", 10)
		bad["mines"][0].merge(patch, true)
		_check(not CustodyFacts.validation_error(bad).is_empty(), "malformed mine rejected: " + str(patch))
	var flying_normal: Dictionary = _mine(50, "flying", 10)
	flying_normal["mines"][0]["normal"] = [0, 1, 0]
	_check(not CustodyFacts.validation_error(flying_normal).is_empty(), "a flying mine has no surface yet")
	_check(CustodyFacts.validation_error(_auditors(5, 2)).is_empty() and CustodyFacts.validation_error(_auditors(5, 1, BODY)).is_empty(), "budgets and channels accepted")
	for bad: Dictionary in [_auditors(5, 3), _auditors(5, 1, AUDITOR), _auditors(5, 1, "bad")]:
		_check(not CustodyFacts.validation_error(bad).is_empty(), "malformed Auditor fact rejected")
	var doubled: Dictionary = _auditors(5, 2)
	doubled["auditors"].append(doubled["auditors"][0].duplicate())
	_check(not CustodyFacts.validation_error(doubled).is_empty(), "duplicate Auditor refused")
	_check(GrenadeFacts.validation_error(_blast(4.5, 104)).is_empty(), "a mine blast names itself by radius and may exceed a grenade peak")
	_check(not GrenadeFacts.validation_error(_blast(4.5, 131)).is_empty(), "a mine blast never exceeds its own peak")
	_check(not GrenadeFacts.validation_error(_blast(4.0, 104)).is_empty(), "a grenade blast keeps its lower peak")
	_check(not GrenadeFacts.validation_error(_blast(5.0, 10)).is_empty(), "an unknown device radius is refused")
	# Lamp reads: steady while arming, a slow blink live, a fast flicker tripped.
	var arming: Dictionary = _mine(20, "arming", 10)["mines"][0]
	_check(CustodyFacts.lamp_lit(arming, 20) and CustodyFacts.lamp_lit(arming, 45), "arming lamp holds steady")
	var armed: Dictionary = _mine(60, "armed", 50)["mines"][0]
	var lit: int = 0
	for tick: int in range(50, 70):
		lit += int(CustodyFacts.lamp_lit(armed, tick))
	_check(lit == 3, "a live mine blinks three ticks in twenty")
	var tripped: Dictionary = _mine(80, "tripped", 78)["mines"][0]
	_check(CustodyFacts.lamp_lit(tripped, 80) != CustodyFacts.lamp_lit(tripped, 81), "a tripped mine flickers every tick")
	# Presentation.
	var presenter: GrenadeEffects = GrenadeEffects.new()
	root.add_child(presenter)
	presenter.apply(_mine(5, "flying", 4), Vector3.ZERO)
	_check(presenter.mines.size() == 1 and presenter.stick_cues == 0, "a flying mine appears without a cue")
	presenter.apply(_mine(9, "arming", 9), Vector3.ZERO)
	_check(presenter.stick_cues == 1 and presenter.lamps_lit == 1, "sticking cues once and lights the arming lamp")
	var body: Node3D = presenter.mines[7]
	_check(body.basis.y.is_equal_approx(Vector3(-1, 0, 0)), "the puck lies flat against the wall it stuck to")
	var face: Sprite3D = body.get_node("Face")
	_check(face.axis == Vector3.AXIS_Y and face.texture == WeaponArt.MINE_DEVICE["arming"], "the drawn device faces out of the wall with its amber arming lamp")
	presenter.apply(_mine(10, "arming", 9), Vector3.ZERO)
	_check(presenter.stick_cues == 1, "a held phase never replays the stick cue")
	presenter.apply(_mine(52, "armed", 50), Vector3.ZERO)
	_check(presenter.lamps_lit == 1, "a live mine blinks on its first tick")
	_check(face.texture == WeaponArt.MINE_DEVICE["live"], "a lit blink shows the red lamp")
	presenter.apply(_mine(55, "armed", 50), Vector3.ZERO)
	_check(presenter.lamps_lit == 0, "and goes dark between blinks")
	_check(face.texture == WeaponArt.MINE_DEVICE["dark"], "and the dark lamp between blinks")
	presenter.apply({"tick": 60}, Vector3.ZERO)
	_check(presenter.mines.is_empty(), "a mine leaving the facts leaves the world")
	presenter.apply(_mine(61, "armed", 50), Vector3.ZERO)
	presenter.reset()
	_check(presenter.mines.is_empty() and presenter.mine_phases.is_empty() and presenter.last_tick == -1, "reset clears placed mines")
	var placements: Array[String] = []
	presenter.placed.connect(func(owner: String) -> void: placements.append(owner))
	presenter.apply({"tick": 70}, Vector3.ZERO)
	presenter.apply(_mine(71, "flying", 71), Vector3.ZERO)
	presenter.apply(_mine(72, "flying", 71), Vector3.ZERO)
	_check(placements.size() == 1 and placements[0] == OWNER, "a newly placed mine raises its owner's hand once")
	presenter.reset()
	presenter.queue_free()
	# Auditor channels.
	var pawns: Dictionary = {}
	for id: String in [AUDITOR, BODY]:
		var pawn: Node3D = Node3D.new()
		root.add_child(pawn)
		pawns[id] = pawn
	(pawns[BODY] as Node3D).position = Vector3(3, 1.5, 0)
	var channels: AuditorChannels = AuditorChannels.new()
	channels.pawns = pawns
	root.add_child(channels)
	channels.apply(_auditors(1, 2))
	_check(channels.channels.is_empty() and channels.budgets[AUDITOR] == 2, "an idle Auditor shows its budget and no beam")
	channels.apply(_auditors(2, 2, BODY))
	_check(channels.channels.size() == 1 and channels.channels[AUDITOR]["target"] == BODY, "a channel draws one beam to its body")
	channels._process(0.1)
	var links: Node3D = channels.channels[AUDITOR]["links"]
	_check(links.visible and links.get_child(0) is MeshInstance3D, "the beam is placed between the pawns")
	channels.apply(_auditors(3, 1))
	_check(channels.channels.is_empty() and channels.repair_cues == 1, "a completed repair ends the beam and cues once")
	channels.apply(_auditors(3, 1))
	_check(channels.repair_cues == 1, "a repeated snapshot cannot replay the repair cue")
	channels.apply(_auditors(4, 1, BODY))
	channels.apply(_auditors(5, 1))
	_check(channels.repair_cues == 1, "a snapped channel spends nothing and cues nothing")
	channels.apply({"tick": 6})
	_check(channels.budgets.is_empty(), "a fallen Auditor leaves no budget behind")
	channels.reset()
	_check(channels.last_tick == -1, "reset clears channel history")
	channels.queue_free()
	for pawn: Node3D in pawns.values():
		pawn.queue_free()
	# Equipment, actors, poses and records.
	var loadout: Dictionary = {"player_id": OWNER, "tick": 3, "selected": "fists", "weapons": ["fists"],
		"ammo": [{"pool": "bullets", "rounds": 0}, {"pool": "shells", "rounds": 0}, {"pool": "cells", "rounds": 0}],
		"grenades": 0, "personal_claims": [], "dry_fire_count": 0}
	_check(EquipmentState.validation_error(loadout, OWNER).is_empty(), "a loadout without mines stays valid")
	for count: Variant in [1, 4]:
		var carried: Dictionary = loadout.duplicate(true)
		carried["proximity_mines"] = count
		_check(EquipmentState.validation_error(carried, OWNER).is_empty(), "carried mines accepted: %s" % str(count))
	for count: Variant in [0, 5, -1, 1.5, "2"]:
		var bad: Dictionary = loadout.duplicate(true)
		bad["proximity_mines"] = count
		_check(not EquipmentState.validation_error(bad, OWNER).is_empty(), "invalid mine count refused: %s" % str(count))
	var actor: Dictionary = {"id": AUDITOR, "x": 0, "y": 1.5, "z": 0, "yaw": 0, "hp": 120, "weapon": "Tack",
		"campaign": {"side": "union", "kind": "auditor", "phase": "channeling", "phase_started": 4, "phase_ends": 48}}
	_check(ActorState.validation_error({"tick": 10, "players": [actor]}).is_empty(), "a channeling Auditor is a valid actor")
	var sweeper: Dictionary = actor.duplicate(true)
	sweeper["campaign"]["kind"] = "sweeper"
	_check(not ActorState.validation_error({"tick": 10, "players": [sweeper]}).is_empty(), "only an Auditor channels")
	var channel_frame: int = EnemyView.custody_frame(actor["campaign"], "Tack", 10, 0.0, 0, false)
	_check(channel_frame == EnemyAnimation.pose_frame("seated", false, 0.0), "the channel holds the Auditor atlas's channel cell")
	var up: Dictionary = {"kind": "sweeper", "phase": "recovery", "phase_started": 10, "phase_ends": 30}
	var rising: int = EnemyView.custody_frame(up, "Flechette", 10, 0.0, 0, true)
	_check(rising == EnemyAnimation.pose_frame("death", false, 1.0), "a repaired bot starts from its fallen pose")
	_check(EnemyView.custody_frame(up, "Flechette", 30, 0.0, 0, true) == EnemyAnimation.pose_frame("death", false, 0.0), "and ends standing")
	_check(EnemyView.custody_frame(up, "Flechette", 30, 0.0, 0, false) == -1, "an ordinary recovery keeps the shared phase table")
	var counts: Dictionary = PlayerRecord.empty_counts()
	counts["alive_ticks"] = 10
	counts["mines"] = {"attacks": 2, "damaging_attacks": 1, "kills": 2, "hp_damage": 160, "armor_damage": 0}
	_check(PlayerRecord.valid_counts(counts) and PlayerRecord.sum_combat(counts, "kills") == 2, "the mine column counts kills beside the guns")
	var total: Dictionary = PlayerRecord.empty_counts()
	PlayerRecord.add_counts(total, counts)
	_check(PlayerRecord.contains(total, counts) and PlayerRecord.mine_count(total, "attacks") == 2 and not total.has("grenades"), "aggregation keeps the mine column separate")
	counts["mines"]["damaging_attacks"] = 3
	_check(not PlayerRecord.valid_counts(counts), "more damaging placements than placements is refused")
	_check("place_mine" in InputBindings.ACTIONS and InputMap.has_action("place_mine"), "the mine has its own rebindable control")
	_check(tr("ACTION_PLACE_MINE") != "ACTION_PLACE_MINE" and tr("RECORD_MINES") != "RECORD_MINES", "keyed control and record words exist")
	await process_frame
	if failures == 0:
		print("test_custody_devices: PASS strict mine and channel facts, blink and beam presentation, mine counts, poses and records")
	quit(0 if failures == 0 else 1)
