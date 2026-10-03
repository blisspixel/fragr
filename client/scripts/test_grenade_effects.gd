extends SceneTree

const OWNER: String = "00000000-0000-0000-0000-000000000002"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_grenade_effects: " + message)

func _live(tick: int, count: int = 0) -> Dictionary:
	return {"tick": tick, "grenades": [{"id": 1, "owner_id": OWNER, "position": [0, 1, float(tick) * 0.1], "fuse_ticks": 40 - tick, "bounce_count": count}]}

func _blast(tick: int) -> Dictionary:
	return {"tick": tick, "explosions": [{"id": 1, "owner_id": OWNER, "position": [0, 1, 2], "radius": 4,
		"hits": [{"target_id": OWNER, "hp_damage": 42, "armor_damage": 0, "target_hp_after": -12, "killed": true}]}]}

func _run() -> void:
	_check(GrenadeFacts.validation_error(_live(1)).is_empty() and GrenadeFacts.validation_error(_blast(20)).is_empty(), "actual live and overkill resolved outcome envelopes accepted")
	for patch: Dictionary in [{"id": 0}, {"owner_id": "bad"}, {"position": [NAN, 0, 0]}, {"fuse_ticks": 41}, {"bounce_count": 641}, {"extra": true}]:
		var bad: Dictionary = _live(1)
		bad["grenades"][0].merge(patch, true)
		_check(not GrenadeFacts.validation_error(bad).is_empty(), "malformed live fact rejected: " + str(patch))
	var duplicated: Dictionary = _live(1)
	duplicated["grenades"].append(duplicated["grenades"][0].duplicate(true))
	_check(not GrenadeFacts.validation_error(duplicated).is_empty(), "duplicate active serial refused")
	var presenter: GrenadeEffects = GrenadeEffects.new()
	root.add_child(presenter)
	presenter.apply(_live(1, 2), Vector3.ZERO)
	_check(presenter.bodies.size() == 1 and presenter.bounce_cues == 0 and presenter.throw_cues == 0,
		"late-join contacts and bodies already in flight do not replay")
	presenter.apply(_live(2, 2), Vector3.ZERO)
	_check(presenter.bounce_cues == 0, "ordinary authoritative motion never invents a bounce")
	presenter.apply(_live(3, 3), Vector3.ZERO)
	_check(presenter.bounce_cues == 1 and presenter.voices[0].bus == &"Effects", "new confirmed contact cues once through Effects")
	presenter.apply(_live(3, 4), Vector3.ZERO)
	presenter.apply(_live(2, 4), Vector3.ZERO)
	_check(presenter.bounce_cues == 1, "duplicate and stale snapshots cannot replay audio")
	var thrown: Dictionary = _live(4, 3)
	thrown["grenades"].append({"id": 2, "owner_id": OWNER, "position": [1, 1.4, 0], "fuse_ticks": 40, "bounce_count": 0})
	presenter.apply(thrown, Vector3.ZERO)
	presenter.apply(thrown, Vector3.ZERO)
	_check(presenter.throw_cues == 1 and presenter.bounce_cues == 1,
		"a body first seen after synchronization cues one throw, and only once")
	_check(GrenadeEffects.THROW.get_length() > 0.1 and GrenadeEffects.THROW.get_length() < 0.6,
		"the throw cue is a short one-shot")
	presenter.apply(_blast(20), Vector3.ZERO)
	_check(presenter.bodies.is_empty() and presenter.bursts.size() == 1 and presenter.blast_cues == 1, "resolved explosion removes live body and shows one actual blast")
	presenter.apply(_blast(21), Vector3.ZERO)
	_check(presenter.blast_cues == 1, "same resolved serial cannot replay on later tick")
	for tick: int in range(22, 50):
		var explosion: Dictionary = _blast(tick)
		explosion["explosions"][0]["id"] = tick
		presenter.apply(explosion, Vector3.ZERO)
	_check(presenter.bursts.size() <= GrenadeEffects.MAX_BURSTS and presenter.voices.size() <= GrenadeEffects.VOICES, "effects and spatial voices remain bounded")
	presenter._process(1.0)
	_check(presenter.bursts.is_empty(), "finite visual lifetime retires all bursts")
	presenter.reset()
	_check(presenter.last_tick == -1 and presenter.bounce_counts.is_empty(), "map/disconnect reset clears history")
	var counts: Dictionary = PlayerRecord.empty_counts()
	counts["alive_ticks"] = 10
	counts["grenades"] = {"attacks": 1, "damaging_attacks": 1, "kills": 2, "hp_damage": 83, "armor_damage": 10}
	_check(PlayerRecord.valid_counts(counts) and PlayerRecord.sum_combat(counts, "kills") == 2 and counts["weapons"].size() == EquipmentState.WEAPONS.size(), "multi-target grenade facts retain independent counters beside one column per gun")
	var total: Dictionary = PlayerRecord.empty_counts()
	PlayerRecord.add_counts(total, counts)
	_check(PlayerRecord.contains(total, counts) and PlayerRecord.grenade_count(total, "kills") == 2, "record aggregation retains actual grenade effort")
	presenter.queue_free()
	await process_frame
	if failures == 0:
		print("test_grenade_effects: PASS strict resolved facts, no inferred bounce, dedup/lifetime/voice budgets and independent records")
	quit(0 if failures == 0 else 1)
