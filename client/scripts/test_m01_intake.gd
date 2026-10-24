extends SceneTree

## Recall Notice intake presenter: authored-layout guard, room dressing, warm
## lamps, the looped address and the caption that survives a shot screen.
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m01_intake: " + message)

static func _solid(low: Vector3, high: Vector3) -> Dictionary:
	return {"min_x": low.x, "max_x": high.x, "bottom": low.y, "top": high.y, "min_z": low.z, "max_z": high.z}

static func _info(map_id: int = 1001, bench_x: float = -10.0) -> Dictionary:
	return {"map_id": map_id, "map_name": "Recall Notice", "solids": [
		_solid(Vector3(bench_x, 0, -26), Vector3(-6, 1, -23)),
		_solid(Vector3(-4, 0, 6), Vector3(4, 2.4, 7)),
		_solid(Vector3(-9, 3, 23), Vector3(-6, 4.2, 25)),
		_solid(Vector3(-11.9, 0, -26.8), Vector3(-10.4, 0.95, -23.2)),
	]}

static func _shot(end: Vector3, kind: String = "solid") -> Dictionary:
	return {"shooter_id": "p", "trace": {"weapon": "tack", "origin": [0.0, 1.6, -8.0], "end": [end.x, end.y, end.z], "impact": {"kind": kind, "normal": [0.0, 0.0, -1.0]}}}

func _run() -> void:
	_expect(M01Intake.authored(_info()), "the authored intake layout is recognized")
	_expect(not M01Intake.authored(_info(1002)), "another mission never receives the intake dressing")
	_expect(not M01Intake.authored(_info(1001, -9.0)), "a reused id with different furniture gets no floating props")
	_expect(not M01Intake.authored({"map_id": 1001}), "a malformed map is refused")
	var intake: M01Intake = M01Intake.new()
	root.add_child(intake)
	intake.configure_map(_info(1001, -9.0))
	_expect(intake.get_child_count() == 0 and not intake.is_processing(), "unrecognized layouts stay bare")
	intake.configure_map(_info())
	for room: String in ["Skyline", "Street", "Bay", "Hall", "Service", "Records"]:
		_expect(room in intake.rooms and intake.has_node(room), "room dressed: " + room)
	_expect(intake.lamps >= 14, "warm service lamps shape the rooms, found %d" % intake.lamps)
	var warm: int = 0
	for light: Node in intake.find_children("*", "OmniLight3D", true, false):
		var omni: OmniLight3D = light as OmniLight3D
		_expect(not omni.shadow_enabled, "presenter lamps never add shadow maps: " + omni.name)
		_expect(omni.omni_range <= 9.5, "presenter lamps stay local: " + omni.name)
		if omni.light_color.r > omni.light_color.b + 0.2:
			warm += 1
		_expect(not (omni.light_color.r > 0.7 and omni.light_color.g < 0.3 and omni.light_color.b < 0.3), "no red light outside Union attack tells: " + omni.name)
	_expect(warm >= 12, "service lamps read warm against the institutional strips")
	for node: Node in intake.find_children("*", "VisualInstance3D", true, false):
		_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing stays off the actor fill layer: " + node.name)
	var merged: int = 0
	for room: String in intake.rooms:
		var props: Node = intake.get_node(room).get_node_or_null("Props")
		if props != null:
			_expect(props.get_child_count() == 1, "each room's static props merge into one mesh: " + room)
			merged += 1
	_expect(merged == intake.rooms.size(), "every room merged its props")
	_expect(intake.find_children("BallastHum*", "AudioStreamPlayer3D", true, false).size() == M01Intake.HUM_POINTS.size(), "each strip fixture carries quiet room tone")
	var hum: AudioStreamWAV = M01Intake.hum_stream()
	_expect(hum.loop_mode == AudioStreamWAV.LOOP_FORWARD and hum.loop_end * 2 == hum.data.size(), "room tone loops seamlessly over its whole buffer")
	_expect(intake.radio_level_db(M01Intake.RADIO_POINT + Vector3(0.5, 0.4, 0)) >= M01Intake.RADIO_NEAR_DB - 0.5, "the confiscated set is faintly audible at the bench")
	_expect(intake.radio_level_db(Vector3(0, 1.6, -5)) == M01Intake.RADIO_SILENT_DB, "the intake hall has no radio")
	_expect(intake.radio_level_db(Vector3.INF) == M01Intake.RADIO_SILENT_DB, "an unplaced listener hears no radio")
	var captions: Array[Node] = intake.find_children("Copy_WORLD_M01_CAPTION_*", "Label3D", true, false)
	_expect(captions.size() == 1, "one official caption line over the main picture")
	var line: Vector3 = (captions[0] as Node3D).position
	_expect(absf(line.x) < 1.2 and line.y > 0.48 and line.y < 2.28 and line.z < 5.868, "the caption sits on the main picture, so it survives over the static")
	_expect(intake.find_children("Copy_WORLD_M01_OFFICIAL_CAPTION", "Label3D", true, false).size() == 1, "the official track carries its own label")
	await process_frame
	intake.observe_shots([_shot(Vector3(6.0, 1.2, 6.0))])
	intake.observe_shots([_shot(Vector3(0.0, 1.2, 6.0), "fighter")])
	intake.observe_shots([{"trace": "bad"}, null, 3])
	_expect(not intake.broken, "misses, fighter hits and malformed traces leave the loop running")
	intake.apply_state({"id": MissionState.ID, "attempt": 1})
	intake.observe_shots([_shot(Vector3(0.4, 1.3, 5.87))])
	_expect(intake.broken, "a server-confirmed solid impact on the screen breaks it to static")
	var caption: WorldSign = intake.find_children("Copy_WORLD_M01_CAPTION_*", "Label3D", true, false)[0] as WorldSign
	_expect(caption.message_key == M01Intake.SURVIVING_CAPTION and caption.text == "Continuity assured.", "the caption keeps scrolling over the noise")
	for index: int in range(30):
		await process_frame
	_expect(caption.message_key == M01Intake.SURVIVING_CAPTION, "the surviving caption stays after the break")
	intake.apply_state({"id": MissionState.ID, "attempt": 1})
	_expect(intake.broken, "the same attempt keeps the broken screen")
	intake.apply_state({"id": MissionState.ID, "attempt": 2})
	_expect(not intake.broken, "a continue restores the building's loop")
	intake.clear_map()
	await process_frame
	_expect(intake.get_child_count() == 0 and intake.lamps == 0 and not intake.is_processing(), "clearing the map removes every dressing node")
	_expect(intake.radio_level_db(Vector3.ZERO) == 0.0 and not intake.active(), "other maps keep the radio's own level")
	intake.queue_free()
	await process_frame
	if failures == 0:
		print("test_m01_intake: PASS authored guard, six dressed rooms, warm local lamps, merged props, looped address and surviving caption")
	quit(0 if failures == 0 else 1)
