extends SceneTree

const OWNER: String = "00000000-0000-0000-0000-000000000043"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_assessor: " + message)

func _actor(phase: String = "windup", tick: int = 10) -> Dictionary:
	return {"id": OWNER, "name": "Assessor", "x": 0, "y": 5.5, "z": 0, "yaw": 0,
		"hp": 0 if phase == "dead" else 240, "weapon": "Fists", "collidable": phase != "dead",
		"just_fired": false, "campaign": {"side": "union", "kind": "assessor", "phase": phase,
		"phase_started": tick, "phase_ends": tick + 24}}

func _snapshot(tick: int = 12) -> Dictionary:
	return {"tick": tick, "players": [_actor()], "assessor_canisters": [{"id": 43, "owner_id": OWNER,
		"position": [0, 4.6, 0], "velocity": [12, -1, 0], "age_ticks": 0}]}

func _envelope() -> void:
	_check(ActorState.validation_error(_snapshot()).is_empty() and AssessorFacts.validation_error(_snapshot()).is_empty(), "distinct heavy drone and bounded canister accepted")
	for patch: Dictionary in [{"id":0}, {"owner_id":"bad"}, {"owner_id":"00000000-0000-0000-0000-000000000000"},
		{"position":[NAN,0,0]}, {"position":[1025,0,0]}, {"velocity":[0,33,0]}, {"velocity":[INF,0,0]},
		{"age_ticks":80}, {"age_ticks":13}, {"extra":true}]:
		var bad: Dictionary = _snapshot()
		bad["assessor_canisters"][0].merge(patch, true)
		_check(not AssessorFacts.validation_error(bad).is_empty(), "reject malformed actual fact " + str(patch))
	var duplicate: Dictionary = _snapshot()
	duplicate["assessor_canisters"].append(duplicate["assessor_canisters"][0].duplicate(true))
	_check(not AssessorFacts.validation_error(duplicate).is_empty(), "reject duplicate serial")
	var collision: Dictionary = _snapshot()
	collision["grenades"] = [{"id":43}]
	_check(not AssessorFacts.validation_error(collision).is_empty(), "one serial cannot name different active devices")
	var cap: Dictionary = _snapshot()
	for serial: int in range(44, 50):
		var fact: Dictionary = cap["assessor_canisters"][0].duplicate(true)
		fact["id"] = serial
		cap["assessor_canisters"].append(fact)
	_check(not AssessorFacts.validation_error(cap).is_empty(), "seventh live round from one owner refused")
	var stranger: Dictionary = _snapshot()
	stranger["players"][0]["campaign"]["kind"] = "notary"
	_check(not AssessorFacts.validation_error(stranger).is_empty(), "ordinary flying role cannot acquire heavy attack")
	for phase: String in ["charging", "channeling", "leaping"]:
		_check(not ActorState.validation_error({"tick":12,"players":[_actor(phase)]}).is_empty(), "heavy role rejects impossible phase " + phase)
	var contact: Dictionary = ActorContact.read_snapshot(_snapshot())
	_check(contact["error"].is_empty() and contact["bodies"].size() == 1 and contact["bodies"][0]["height"] == 1.2 and contact["bodies"][0]["radius"] == 1.3, "prediction reads actual raised heavy body without a floor")

func _run() -> void:
	_envelope()
	var rig: AssessorRig = AssessorRig.new()
	root.add_child(rig)
	_palette(rig)
	var identity: Dictionary = _actor()["campaign"]
	rig.present(identity, 10, 0.0)
	var folded: float = rig.launcher.rotation.z
	rig.present(identity, 33, 0.05)
	_check(rig.fans.size() == 4 and rig.optics.size() == 2 and rig.vents.size() == 3 and rig.launcher.rotation.z < folded, "four fans, two optics and physical windup launcher")
	_check(rig.phase == "windup", "a stale windup never invents a local attack")
	var before: float = rig.fans[0].rotation.y
	rig.advance(0.05)
	_check(rig.fans[0].rotation.y != before and rig.position == Vector3.ZERO and rig.scale == Vector3.ONE, "rotors move while the registered body never bobs or grows")
	for phase: String in ["moving", "windup", "firing", "recovery", "dead"]:
		identity["phase"] = phase
		rig.present(identity, 33, 0.05)
		_bounds(rig, rig)
	var packed: PackedScene = load("res://scenes/player.tscn")
	var pawn: Node3D = packed.instantiate()
	root.add_child(pawn)
	pawn.update_state(_actor(), 12)
	_check(pawn.enemy_view.assessor_rig != null and not pawn.body.visible, "real pawn uses original mechanical geometry without a missing sprite atlas")
	_check(pawn.get_node("AssessorFloorShadow").mesh.size == Vector2(2.8,2.8), "large drone reuses bounded cosmetic support shadow")
	pawn.set_local_fp(true)
	_check(not pawn.enemy_view.assessor_rig.visible and not pawn.body.visible, "first-person ownership hides entire body")
	pawn.set_local_fp(false)
	_check(pawn.enemy_view.assessor_rig.visible and not pawn.body.visible, "leaving first person restores only heavy geometry")
	pawn._update_body_color(true)
	_check(pawn.enemy_view.assessor_rig.get_node("Hull").material_overlay != null, "resolved pawn feedback reaches the visible mechanical hull")
	pawn._update_body_color(false)
	_check(pawn.enemy_view.assessor_rig.get_node("Hull").material_overlay == null, "health flash restores the authored mechanical materials")
	pawn.update_state(_actor("dead", 13), 13)
	_check(pawn.hp == 0 and not pawn.weapon_sprite.visible, "server death retains body and never displays a melee gun")
	var effects: GrenadeEffects = GrenadeEffects.new()
	root.add_child(effects)
	effects.apply(_snapshot(), Vector3.INF)
	_check(effects.canisters.size() == 1 and effects.throw_cues == 0, "late join synchronizes visible canister without a participant throw")
	var moved: Dictionary = _snapshot(13)
	moved["assessor_canisters"][0]["position"] = [0.6, 4.5, 0]
	moved["assessor_canisters"][0]["age_ticks"] = 1
	effects.apply(moved, Vector3.INF)
	_check(effects.canisters[43].position == Vector3(0.6,4.5,0), "actual server position drives projectile")
	var blast: Dictionary = {"tick":14,"explosions":[{"id":43,"owner_id":OWNER,"position":[1,1,0],"radius":3,"hits":[]}]}
	_check(GrenadeFacts.validation_error(blast).is_empty(), "resolved bounded canister blast accepted")
	effects.apply(blast, Vector3.INF)
	_check(effects.canisters.is_empty() and effects.bursts.size() == 1, "only actual impact removes flight and shows one burst")
	effects.apply(blast, Vector3.INF)
	_check(effects.bursts.size() == 1, "repeated fact never repeats explosion")
	effects.reset()
	_check(effects.canisters.is_empty() and effects.bursts.is_empty(), "shared map reset clears all heavy effects")
	var audio: NotaryAudio = NotaryAudio.new()
	root.add_child(audio)
	audio.configure_map({"map_id":1098,"geometry_version":2,"half_extent":30,"solids":[]})
	_check(audio.apply(_snapshot(), Vector3.ZERO) == 0 and audio.fans.size() == 1, "heavy fan shares bounded spatial pool; initial flight never replays launch")
	var real: Dictionary = _snapshot(13)
	real["assessor_canisters"][0]["id"] = 44
	_check(audio.apply(real,Vector3.ZERO) == 1 and audio.cues.size() == 1, "new actual canister cues once")
	_check(audio.apply(real,Vector3.ZERO) == 0, "duplicate launch cannot replay")
	_check(audio.fan_pool.size() <= NotaryAudio.FAN_VOICES and audio.cues.size() <= NotaryAudio.CUE_VOICES, "existing voice limits retained")
	audio.reset()
	audio.free()
	effects.free()
	pawn.free()
	rig.free()
	await process_frame
	print("test_assessor: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

func _bounds(node: Node, origin: Node3D) -> void:
	if node is MeshInstance3D:
		var mesh: MeshInstance3D = node as MeshInstance3D
		var box: AABB = mesh.get_aabb()
		for corner: int in range(8):
			var point: Vector3 = origin.to_local(mesh.to_global(box.get_endpoint(corner)))
			_check(absf(point.x) <= 1.3001 and absf(point.z) <= 1.3001 and point.y >= -0.0001 and point.y <= 1.2001, "actual mesh stays inside raised finite target: " + str(point))
	for child: Node in node.get_children():
		_bounds(child, origin)

func _palette(rig: AssessorRig) -> void:
	_check(AssessorRig.METAL.v < 0.18 and AssessorRig.PLATE.v < 0.26 and AssessorRig.PLATE.v > AssessorRig.METAL.v, "issued black hull retains slightly lighter graphite armor")
	_check(AssessorRig.PLATE.b >= AssessorRig.PLATE.g and AssessorRig.PLATE.b >= AssessorRig.PLATE.r, "armor never drifts into olive livery")
	_check(AssessorRig.RED.r > 0.7 and AssessorRig.RED.g < 0.17 and AssessorRig.RED.b < 0.17, "Union optics use saturated red rather than orange")
	var hull: StandardMaterial3D = (rig.get_node("Hull") as MeshInstance3D).material_override as StandardMaterial3D
	var plate: StandardMaterial3D = (rig.get_node("FrontPlate") as MeshInstance3D).material_override as StandardMaterial3D
	var rest_shape: Vector3
	var end_shape: Vector3
	var union_launcher: float = 0.0
	for absorbed: bool in [false, true]:
		for phase_name: String in ["idle", "windup", "recovery", "dead"]:
			var fact: Dictionary = {"side": "inheritance" if absorbed else "union", "phase": phase_name, "phase_started": 100, "phase_ends": 124}
			if absorbed:
				fact["control"] = "absorbed"
			rig.present(fact, 124, 0.0)
			_check(hull.albedo_color == AssessorRig.METAL and plate.albedo_color == AssessorRig.PLATE, "control and phase never repaint chassis")
			var optic: StandardMaterial3D = rig.optics[0].material_override as StandardMaterial3D
			_check(optic.albedo_color == (AssessorRig.DEAD_OPTIC if absorbed else AssessorRig.RED), "absorbed lens retains dead-red paint")
			_check(optic.emission == (EnemyView.WORK_GLOW if absorbed else AssessorRig.RED), "only authoritative absorption selects cyan light")
			var expected: float = 0.0 if phase_name == "dead" else ((1.5 if phase_name == "windup" else 0.65) if absorbed else (0.65 if phase_name == "windup" else 0.35))
			_check(is_equal_approx(optic.emission_energy_multiplier, expected), "bounded phase energy preserves red and existing absorbed glow")
			for vent: MeshInstance3D in rig.vents:
				var material: StandardMaterial3D = vent.material_override as StandardMaterial3D
				_check(material.albedo_color == (AssessorRig.LIGHT if phase_name == "recovery" else AssessorRig.METAL), "warm rear weakpoint appears only in recovery")
				_check(is_equal_approx(material.emission_energy_multiplier, 0.8 if phase_name == "recovery" else 0.0), "recovery vent energy is unchanged")
				_check(is_equal_approx(vent.scale.y, 1.0 if phase_name == "recovery" else 0.18), "recovery opening is unchanged")
			if phase_name == "idle":
				rest_shape = rig.optics[0].scale
			if phase_name == "windup":
				end_shape = rig.optics[0].scale
				_check(end_shape.y > rest_shape.y, "countdown still grows physically")
				if absorbed:
					_check(is_equal_approx(rig.launcher.rotation.z, union_launcher), "absorption preserves launcher timing and pose")
				else:
					union_launcher = rig.launcher.rotation.z
