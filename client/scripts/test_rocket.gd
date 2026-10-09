extends SceneTree

const OWNER: String = "00000000-0000-4000-8000-0000000000aa"
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_rocket: " + message)

func _flight(id: int, age: int, velocity: Array) -> Dictionary:
	return {"id": id, "owner_id": OWNER, "position": [1.0, 1.6, 0.0], "velocity": velocity, "age_ticks": age}

func _snapshot(rockets: Array, tick: int = 4) -> Dictionary:
	return {"tick": tick, "players": [{"id": OWNER}], "rockets": rockets}

func _run() -> void:
	_check(preload("res://scripts/net_client.gd").GAMEPLAY_VERSION == 46, "the client speaks the rocket gameplay contract")
	var flying: Dictionary = _snapshot([_flight(7, 0, [18.0, 0.0, 0.0])])
	_check(RocketFacts.validation_error(flying).is_empty(), "a fresh rocket in flight is accepted")
	for patch: Dictionary in [{"id": 0}, {"owner_id": "00000000-0000-0000-0000-000000000000"}, {"age_ticks": 80}, {"velocity": [21.0, 0.0, 0.0]}, {"position": [1025.0, 0.0, 0.0]}, {"extra": true}]:
		var bad: Dictionary = _snapshot([_flight(7, 0, [18.0, 0.0, 0.0])])
		bad["rockets"][0].merge(patch, true)
		_check(not RocketFacts.validation_error(bad).is_empty(), "malformed rocket refused: " + str(patch))
	var shared: Dictionary = _snapshot([_flight(7, 0, [18.0, 0.0, 0.0])])
	shared["grenades"] = [{"id": 7, "owner_id": OWNER, "position": [0, 0, 0], "fuse_ticks": 10, "bounce_count": 0}]
	_check(not RocketFacts.validation_error(shared).is_empty(), "a rocket cannot reuse another device id")
	var crowd: Array = []
	for index: int in range(1, 10):
		crowd.append(_flight(index, 0, [18.0, 0.0, 0.0]))
	_check(not RocketFacts.validation_error(_snapshot(crowd)).is_empty(), "one owner cannot have a ninth live rocket")
	var effects: GrenadeEffects = GrenadeEffects.new()
	root.add_child(effects)
	effects.apply(flying, Vector3.ZERO)
	var body: MeshInstance3D = effects.rockets[7]
	var size: Vector3 = (body.mesh as BoxMesh).size
	_check(size.z > size.x * 2.0, "the rocket body is long")
	_check((-body.basis.z).dot(Vector3.RIGHT) > 0.9, "the long axis follows server velocity")
	var gone: Dictionary = flying.duplicate(true)
	gone["tick"] = 5
	gone["rockets"] = []
	effects.apply(gone, Vector3.ZERO)
	_check(effects.rockets.is_empty(), "a resolved rocket leaves the flight mesh")
	effects.reset()
	effects.free()
	var hud: EquipmentHud = EquipmentHud.new()
	root.add_child(hud)
	hud.apply({"tick": 1, "selected": "rocket", "weapons": ["fists", "rocket"], "ammo": [{"pool": "rockets", "rounds": 4}], "loaded": [{"weapon": "rocket", "rounds": 1}], "grenades": 0, "dry_fire_count": 0})
	_check(hud.glyph_pool == "rockets" and hud.counts.text == "1|3", "the held launcher draws its rocket count")
	hud.free()
	print("test_rocket: %s" % ("PASS" if _failures == 0 else "FAIL %d" % _failures))
	quit(0 if _failures == 0 else 1)
