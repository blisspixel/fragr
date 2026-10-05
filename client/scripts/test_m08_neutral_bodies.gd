extends SceneTree

const ArchiveFixture = preload("res://scripts/test_m08_mission.gd")
const PortFixture = preload("res://scripts/test_m06_mission.gd")
const TownFixture = preload("res://scripts/test_m07_mission.gd")
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m08_neutral_bodies: " + message)

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m08_neutral_body_vectors.json"))
	_check(parsed is Dictionary and parsed.get("cases") is Array, "shared vectors load")
	if not parsed is Dictionary or not parsed.get("cases") is Array:
		quit(1)
		return
	for vector: Dictionary in parsed["cases"]:
		var info: Dictionary = {"map_id": 1008, "geometry_version": 2, "half_extent": vector["half"], "solids": vector["solids"], "presentation": vector["presentation"]}
		var bound: Dictionary = M08NeutralBodies.layout(info)
		_check(not bound.is_empty(), "accepted panel frame " + vector["name"])
		if bound.is_empty():
			continue
		_check((bound["renn"] as Vector3).distance_to(_vector(vector["expected"]["renn"])) < 0.00001, "Renn frame " + vector["name"])
		for stage: String in ["held", "released"]:
			for index: int in range(4):
				_check((bound[stage][index] as Vector3).distance_to(_vector(vector["expected"][stage][index])) < 0.00001, "%s/%s/%d" % [vector["name"], stage, index])
		for joined: bool in [false, true]:
			for released: bool in [false, true]:
				var mission: Dictionary = {"phase": "in_progress", "m08": {"custodian_joined": joined, "custody_released": released}}
				var bodies: Dictionary = ActorContact.read_snapshot({"tick": 12, "players": []}, mission, bound)
				var expected: Array[Dictionary] = M08NeutralBodies.people(bound, joined, released)
				_check(bodies["error"].is_empty() and bodies["bodies"].size() == (5 if joined else 4), "exact visible neutral count")
				for index: int in range(expected.size()):
					var body: Dictionary = bodies["bodies"][index]
					var feet: Dictionary = body["from"]
					_check(body["key"] == expected[index]["key"] and Vector3(float(feet["x"]), float(feet["y"]), float(feet["z"])).distance_to(expected[index]["feet"]) < 0.00001, "prediction shares exact neutral feet/key")
		var missing: Dictionary = info.duplicate(true)
		missing["presentation"]["decorations"].remove_at(0)
		_check(M08NeutralBodies.layout(missing).is_empty(), "missing panel rejected")
		var duplicate: Dictionary = info.duplicate(true)
		duplicate["presentation"]["decorations"].append(duplicate["presentation"]["decorations"][0].duplicate(true))
		_check(M08NeutralBodies.layout(duplicate).is_empty(), "duplicate panel rejected")
	var info: Dictionary = ArchiveFixture.fixture_map(true)
	var bound: Dictionary = M08NeutralBodies.layout(info)
	var archive: M08Archive = M08Archive.new()
	root.add_child(archive)
	archive.configure_map(info)
	_check(archive.captives.size() == 4 and is_instance_valid(archive.renn) and not archive.renn.visible, "four captives visible and Renn hidden before accepted facts")
	for index: int in range(4):
		_check(archive.captives[index].position.distance_to(bound["held"][index] + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT) < 0.00001, "actual held Sprite3D feet equal mirrored bodies")
	archive.apply_state(ArchiveFixture.fixture_state(info, 4, {"custody_released": true})["state"])
	_check(archive.renn.visible and archive.renn.position.distance_to(bound["renn"] + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT) < 0.00001, "Renn visibility and node feet follow accepted facts")
	for index: int in range(4):
		_check(archive.captives[index].position.distance_to(bound["released"][index] + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT) < 0.00001, "actual released Sprite3D feet equal mirrored bodies")
	var prediction: LocalPrediction = LocalPrediction.new()
	prediction.configure_map(info)
	prediction.accept_snapshot({"tick": 12, "players": []}, "visitor", {"phase": "in_progress", "m08": {"custodian_joined": true, "custody_released": true}}, 1000)
	_check(prediction.contact_error.is_empty() and prediction._contact_samples.back()["bodies"].size() == 5, "live prediction MapInfo binding includes all five actual bodies")
	_check(not ActorContact.read_snapshot({"tick": 12, "players": []}, {"phase": "in_progress", "m08": {"custodian_joined": true, "custody_released": true}})["error"].is_empty(), "missing map binding never silently drops active M08 people")
	for phase: String in ["briefing", "departed"]:
		_check(ActorContact.read_snapshot({"tick": 12, "players": []}, {"phase": phase, "m08": {"custodian_joined": true, "custody_released": true}}, bound)["bodies"].is_empty(), "inactive mission omits neutral contacts")
	archive.clear_map()
	archive.queue_free()
	_moon_residents()
	await process_frame
	if failures == 0:
		print("test_m08_neutral_bodies: PASS shared panel vectors, exact visible people, actual node feet and prediction binding")
	quit(0 if failures == 0 else 1)

func _moon_residents() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/moon_resident_body_vectors.json"))
	_check(parsed is Dictionary and parsed.get("cases") is Array, "moon resident goldens load")
	if not parsed is Dictionary or not parsed.get("cases") is Array:
		return
	for info: Dictionary in parsed["cases"]:
		var residents: Array[Dictionary] = MoonResidentBodies.read(info)
		_check(MoonResidentBodies.validation_error(info).is_empty() and residents.size() == info["expected"].size(), "exact actual moon resident count")
		for index: int in range(residents.size()):
			_check((residents[index]["feet"] as Vector3).distance_to(_vector(info["expected"][index])) < 0.00001, "moon shared body feet")
		var mission: Dictionary = {"phase": "in_progress", "m06" if info["map_id"] == 1006 else "m07": {}}
		var bodies: Dictionary = ActorContact.read_snapshot({"tick": 12, "players": []}, mission, {}, residents)
		_check(bodies["error"].is_empty() and bodies["bodies"].size() == residents.size(), "moon bodies enter shared movement mirror")
		var bad: Dictionary = info.duplicate(true)
		bad["presentation"]["decorations"].append(bad["presentation"]["decorations"][0].duplicate(true))
		_check(not MoonResidentBodies.validation_error(bad).is_empty(), "duplicate resident panel refused")
	var port_info: Dictionary = PortFixture.fixture_map()
	var port: M06Port = M06Port.new()
	root.add_child(port)
	port.configure_map(port_info)
	var feet: Array[Dictionary] = MoonResidentBodies.read(port_info)
	_check(port.residents.size() == feet.size() and feet.size() == 2, "actual port nodes use two mirrored resident bodies")
	for index: int in range(feet.size()):
		_check(port.residents[index].position.distance_to(feet[index]["feet"] + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT) < 0.00001, "port actual sprite/body registration")
	port.clear_map()
	port.queue_free()
	var town_info: Dictionary = TownFixture.fixture_map()
	var town: M07Town = M07Town.new()
	root.add_child(town)
	town.configure_map(town_info)
	var town_feet: Array[Dictionary] = MoonResidentBodies.read(town_info)
	var body: Sprite3D = town.figure.get_node("Resident") as Sprite3D
	_check(town_feet.size() == 1 and body.position.distance_to(town_feet[0]["feet"] + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT) < 0.00001, "town actual sprite/body registration")
	town.clear_map()
	town.queue_free()
