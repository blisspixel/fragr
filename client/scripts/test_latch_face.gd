extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, reason: String) -> void:
	if not value:
		failures += 1
		push_error("test_latch_face: " + reason)

func _run() -> void:
	var face: LatchFace = LatchFace.new()
	var signatures: Array[String] = []
	for expression: String in LatchFace.STATES:
		var open: ArrayMesh = LatchFace.mesh(expression)
		var closed: ArrayMesh = LatchFace.mesh(expression, true)
		_check(open == LatchFace.mesh(expression) and closed == LatchFace.mesh(expression, true), "face geometry is cached across instances")
		_check(open.get_aabb().position.x >= -0.0695 and open.get_aabb().end.x <= 0.0695
			and open.get_aabb().position.y >= -0.0775 and open.get_aabb().end.y <= 0.0775,
			"every pixel remains inside the retained recess")
		_check(_mouth(open) == _mouth(closed), "a blink preserves the complete mouth geometry")
		var signature: String = str(open.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
		_check(signature not in signatures, "each personal expression has distinct actual geometry")
		signatures.append(signature)
	_check(LatchFace.mesh("unknown") == LatchFace.mesh("relaxed"), "unknown drawing falls back to relaxed")
	face.advance(0.05, 0.0, "following")
	_check(face.state == "relaxed", "accepted stationary following is relaxed")
	face.advance(0.05, 0.1, "following")
	_check(face.state == "walking", "actual travel selects the distinct walking grin")
	face.advance(0.05, 0.0, "following")
	_check(face.state == "walking", "one quiet interpolation sample does not flicker the moving face")
	face.advance(0.2, 0.0, "following")
	_check(face.state == "relaxed", "stopping settles back to relaxed")
	face.advance(0.05, 0.1, "firing")
	_check(face.state == "focused", "accepted firing outranks travel")
	face.observe_health(50)
	_check(face.state == "focused", "first positive HP observation never invents a hit")
	face.observe_health(40)
	_check(face.state == "wince", "actual positive HP decrease briefly outranks firing")
	face.tick(0.25)
	face.observe_health(40)
	face.tick(0.21)
	_check(face.state == "focused", "repeated unchanged HP does not extend a wince")
	face.observe_health(0)
	face.observe_health(101)
	_check(face._health == 40 and face.state == "focused", "unsupported shutdown and invalid HP are ignored")
	face.advance(0.05, 0.0, "following")
	face.shot()
	_check(face.state == "focused", "resolved shot briefly concentrates without a phase inference")
	face.tick(0.25)
	_check(face.state == "relaxed", "resolved shot expression expires")
	face.advance(0.05, 0.0, "releasing")
	_check(face.state == "hopeful", "accepted live release starts hopeful")
	face.ward(0.0, false)
	_check(face.state == "concerned", "held ward context stays distinct from a release")
	face.ward(0.0, true)
	_check(face.state == "hopeful", "accepted release is visible at the zero-progress boundary")
	face.ward(1.0, true)
	_check(face.state == "reassured", "existing voluntary gesture ends with a warm relieved smile")
	face.advance(0.0, NAN, "unknown")
	_check(face.state == "relaxed", "unknown phase and nonfinite travel fall back without fabricated alarm")
	face.tick(NAN)
	_check(face.state == "relaxed", "invalid cosmetic time cannot poison state")
	var blink: LatchFace = LatchFace.new()
	for sample: int in range(75):
		blink.tick(0.05)
	_check(blink.blinking, "a natural bounded blink occurs after quiet time")
	blink.tick(0.12)
	_check(not blink.blinking, "blink reopens within its bounded duration")
	blink._blink_left = 0.1
	blink.advance(0.0, 0.0, "firing")
	_check(not blink.blinking, "concentration remains legible during a pending blink")
	_check(LatchFace._meshes.size() == 14, "all expression variants remain a fixed shared cache")
	await _check_live_wiring()
	_check_ward_wiring()
	if failures == 0:
		print("test_latch_face: PASS distinct cached pixels, blink, accepted transitions, HP controls and retained live presentation")
	quit(0 if failures == 0 else 1)

func _mouth(mesh: ArrayMesh) -> String:
	var points: Array[String] = []
	for point: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if point.y < 0.0:
			points.append(str(point))
	return str(points)

func _check_live_wiring() -> void:
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate()
	root.add_child(pawn)
	pawn.set_process(false)
	pawn.set_player_data("ally", "Latch")
	var snapshot: Dictionary = {"id": "ally", "name": "Latch", "x": 2.0, "y": 1.5, "z": 3.0, "yaw": 0.0,
		"hp": 50, "weapon": "Tack", "just_fired": false,
		"campaign": {"side": "companion", "kind": "latch", "phase": "following", "phase_started": 10}}
	_check(ActorState.validation_error({"tick": 10, "players": [snapshot]}) == "", "positive HP fixture crosses the actual companion validator")
	pawn.update_state(snapshot, 10)
	pawn.snap_authoritative_position()
	pawn._process(0.05)
	var live: LatchView = pawn.latch_view
	_check(live.face.state == "relaxed" and live.face._health == 50, "real pawn observes its first accepted health without a false hit")
	var optics: MeshInstance3D = live._eyes
	var clipped: Material = optics.material_override
	var count: int = live.find_children("*", "MeshInstance3D", true, false).size()
	snapshot["hp"] = 40
	pawn.update_state(snapshot, 11)
	_check(live.face.state == "wince", "real pawn HP delta reaches the face")
	live.advance(0.25, 0.0, "following")
	live.advance(0.21, 0.0, "following")
	snapshot["campaign"]["phase"] = "firing"
	pawn.update_state(snapshot, 12)
	pawn._process(0.05)
	_check(live.face.state == "focused", "real authoritative firing phase reaches the face")
	_check(live._eyes == optics and optics.material_override == clipped and clipped is ShaderMaterial
		and live.find_children("*", "MeshInstance3D", true, false).size() == count,
		"face transitions reuse the exact live near-clip material/node and bounded mesh count")
	_check(live._screen.transform.is_equal_approx(live._source.bone_delta(live._source_body, "Head") * Transform3D(Basis.IDENTITY, Vector3(0, 1.55, 0.148)))
		and optics.transform.is_equal_approx(live._screen.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.004)))
		and optics.scale.is_equal_approx(Vector3.ONE), "face follows the actual head transform without optical compression")
	live.set_near_camera_clip(false)
	_check(optics.material_override == live._ward_materials[optics], "face transitions preserve exact material restoration")
	live.set_weapon_visible(false)
	live.advance(0.25, 0.0, "following")
	live.shot()
	_check(live.face.state == "relaxed", "unarmed ward cannot invent a resolved-shot expression")
	live.pose_release(0.0)
	_check(live.face.state == "concerned", "retained ward API starts concerned")
	live.pose_release(0.0, true)
	_check(live.face.state == "hopeful", "release context is explicit even before gesture progress")
	live.pose_release(1.0, true)
	_check(live.face.state == "reassured", "retained gesture reaches relief")
	pawn.free()
	await process_frame

func _check_ward_wiring() -> void:
	var ward: M02Ward = M02Ward.new()
	root.add_child(ward)
	ward.set_process(false)
	ward.configure_map({"map_id": M02Ward.MAP_ID, "map_name": M02Ward.MAP_NAME, "m02_objectives": 3,
		"geometry_version": 2, "half_extent": 40.0,
		"solids": [{"min_x": 8.0, "max_x": 9.0, "bottom": 0.0, "top": 2.6, "min_z": -13.0, "max_z": -9.0}]})
	var state: Dictionary = {"id": MissionState.M02_ID, "attempt": 1, "m02": {
		"ward_secured": true, "side_ward_secured": false, "completed": ["ward_reached"]}}
	ward.apply_state(state)
	_check(ward._latch.face.state == "concerned", "actual held tableau selects concern")
	state["m02"]["completed"].append("companion_released")
	ward.apply_state(state)
	_check(ward._latch.face.state == "hopeful" and is_zero_approx(ward._release_elapsed), "actual release event projects hope before gesture progress")
	ward._process(M02Ward.CROSS_END + 0.3)
	_check(ward._latch.face.state == "reassured", "actual ward timeline projects relief during the voluntary gesture")
	ward.set_companion_phase("following", 50, 50)
	_check(not ward._latch.visible, "actual companion snapshot still retires the tableau body")
	state["attempt"] = 2
	state["m02"]["completed"] = ["ward_reached"]
	ward.apply_state(state)
	_check(ward._latch.face.state == "concerned" and ward._latch.visible, "retry restores actual held context instead of inheriting relief")
	ward.free()
