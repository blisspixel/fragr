extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_latch_source: " + message)

func _run() -> void:
	var view: LatchView = LatchView.new()
	root.add_child(view)
	_check_relaxed_pose(view)
	_check_ward_context(view)
	_check_live_release_pawn()
	var skeleton: Skeleton3D = view._source_body.get_node("Armature/Skeleton3D") as Skeleton3D
	var mesh: MeshInstance3D = view._source_body.get_node("Armature/Skeleton3D/char1") as MeshInstance3D
	_check(mesh.skin != null and skeleton.get_bone_count() == 24, "the live source has weighted skin")
	var player: AnimationPlayer = view._source_body.get_node("AnimationPlayer") as AnimationPlayer
	_check(player.get_animation_list() == PackedStringArray(["walk"]), "only the bounded walking clip remains")
	var idle: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone("LeftLeg"))
	view.advance(0.05, 0.1, "following")
	var walking: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone("LeftLeg"))
	_check(not idle.is_equal_approx(walking), "actual travel deforms the weighted leg")
	view.advance(0.05, 0.0, "following")
	_check(idle.is_equal_approx(skeleton.get_bone_global_pose(skeleton.find_bone("LeftLeg"))), "idle returns the real leg to rest")
	view.set_weapon_visible(true)
	var palm: Transform3D = view._source.bone_transform(view._source_body, "RightHand")
	var weapon: Transform3D = view._right_arm.transform * view._gun.transform
	_check(weapon.origin.distance_to(palm.origin + Vector3(0, 0.025, 0.03)) < 0.001, "Tack is registered in the actual skinned palm")
	view.shot()
	_check(view._flash.visible, "only the resolved-shot callback enables flash")
	view.advance(0.11, 0.0, "following")
	_check(not view._flash.visible, "resolved flash expires without another shot")
	view.set_weapon_visible(false)
	view.shot()
	_check(not view._flash.visible, "unarmed release cannot display a shot")
	view.set_screen_expression(0.0)
	_check(view._eyes.mesh == LatchFace.mesh(view.face.state, true) and view._eyes.scale.is_equal_approx(Vector3.ONE), "closed optics preserve the mouth and head scale")
	view.set_screen_expression(2.0)
	_check(view._eyes.mesh == LatchFace.mesh(view.face.state, false), "independent optics restore the cached open expression")
	view.set_render_layers(ArenaSky.ACTOR_LAYERS)
	for node: Node in view.find_children("*", "VisualInstance3D", true, false):
		_check((node as VisualInstance3D).layers == ArenaSky.ACTOR_LAYERS, "skin and attachments preserve actor-only lighting")
	var original: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	view.set_near_camera_clip(true)
	var clipped: ShaderMaterial = mesh.material_override as ShaderMaterial
	_check(clipped.get_shader_parameter("chassis_normal") == original.normal_texture
		and clipped.get_shader_parameter("chassis_roughness_map") == original.roughness_texture
		and clipped.get_shader_parameter("chassis_metallic_map") == original.metallic_texture,
		"near fade preserves the actual PBR maps")
	view.set_near_camera_clip(false)
	_check(mesh.material_override == original, "near fade restores the exact source material")
	view.free()
	await process_frame
	if failures == 0:
		print("test_latch_source: PASS weighted travel, palm, expression, weapon, actor layers and PBR preservation")
	quit(0 if failures == 0 else 1)

func _check_relaxed_pose(view: LatchView) -> void:
	var reference: Node3D = load(LatchSource.LATCH_SOURCE).instantiate() as Node3D
	root.add_child(reference)
	var body: Node3D = view._source_body
	var current: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	var original: Skeleton3D = reference.get_node("Armature/Skeleton3D") as Skeleton3D
	_check(FileAccess.get_sha256(LatchSource.LATCH_SOURCE) == "8b1ec57399ec51a70617a42c9777a04347170d5ddf78dc54b67649b3f6992951",
		"pose tuning retains the exact selected skin, maps, UVs and weights")
	for armed: bool in [false, true]:
		for moving: bool in [false, true]:
			for phase: int in range(8):
				var stride: float = float(phase) * TAU / 8.0
				view._source.pose_live(body, stride, moving, armed, 0.0)
				_legacy_pose(view._source, reference, stride, moving, armed, 0.0)
				for bone: int in range(current.get_bone_count()):
					var name: String = current.get_bone_name(bone)
					if name in ["LeftArm", "LeftForeArm", "LeftHand"] or (not armed and name in ["RightArm", "RightForeArm", "RightHand"]):
						continue
					_check(current.get_bone_global_pose(bone).is_equal_approx(original.get_bone_global_pose(bone)),
						"calm free arms preserve head, gait, feet and the armed right chain: " + name)
				for side: String in (["Left"] if armed else ["Left", "Right"]):
					var shoulder: Vector3 = _joint(view, side + "Arm")
					var elbow: Vector3 = _joint(view, side + "ForeArm")
					var wrist: Vector3 = _joint(view, side + "Hand")
					_check(absf(elbow.x) - absf(shoulder.x) < 0.1 and rad_to_deg((elbow - shoulder).angle_to(Vector3.DOWN)) < 55.0,
						"free elbow stays beside the torso during idle and actual sampled following")
					var old_upper: float = _joint_body(view._source, reference, side + "Arm").distance_to(_joint_body(view._source, reference, side + "ForeArm"))
					var old_forearm: float = _joint_body(view._source, reference, side + "ForeArm").distance_to(_joint_body(view._source, reference, side + "Hand"))
					_check(absf(shoulder.distance_to(elbow) - old_upper) < 0.00001 and absf(elbow.distance_to(wrist) - old_forearm) < 0.00001,
						"a calmer pose never stretches either weighted arm segment")
	# Actual retained raised-elbow pose fails the new posture contract.
	_legacy_pose(view._source, reference, 0.0, false, false, 0.0)
	var old_shoulder: Vector3 = _joint_body(view._source, reference, "LeftArm")
	var old_elbow: Vector3 = _joint_body(view._source, reference, "LeftForeArm")
	_check(absf(old_elbow.x) - absf(old_shoulder.x) > 0.19 and rad_to_deg((old_elbow - old_shoulder).angle_to(Vector3.DOWN)) > 55.0,
		"retained previous idle is a real raised-elbow negative control")
	for firing: bool in [false, true]:
		view._source.pose_live(body, 0.0, false, true, 0.0, firing)
		_legacy_pose(view._source, reference, 0.0, false, true, 0.0, firing)
		for name: String in ["RightArm", "RightForeArm", "RightHand"]:
			_check(current.get_bone_global_pose(current.find_bone(name)).is_equal_approx(original.get_bone_global_pose(original.find_bone(name))),
				"actual armed and firing palm chain stays unchanged: " + name)
	for release: float in [0.01, 0.25, 0.5, 1.0, 2.0]:
		view._source.pose_live(body, 1.3, true, false, release)
		_legacy_pose(view._source, reference, 1.3, true, false, release)
		for bone: int in range(current.get_bone_count()):
			_check(current.get_bone_global_pose(bone).is_equal_approx(original.get_bone_global_pose(bone)),
				"positive release gesture preserves every actual weighted bone")
		var actual: PackedVector3Array = _skin_points(body)
		var previous: PackedVector3Array = _skin_points(reference)
		_check(actual.size() == previous.size(), "release preserves the actual weighted surface count")
		var greatest_error: float = 0.0
		for vertex: int in range(actual.size()):
			greatest_error = maxf(greatest_error, actual[vertex].distance_to(previous[vertex]))
		_check(greatest_error < 0.00001, "release preserves the complete posed skin, not just wrist endpoints")
	view._source.pose_live(body, 0.0, false, false, 0.0)
	var points: PackedVector3Array = _skin_points(body)
	var bounds: AABB = AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		bounds = bounds.expand(point)
	_check(absf(bounds.position.y) < 0.00001 and absf(bounds.size.y - 1.799972) < 0.00001,
		"calm idle keeps actual weighted adult height and floor registration")
	reference.free()
	view._stride = 0.0
	view._moving = false
	view._firing = false
	view._release = 0.0
	view._pose_source()

func _joint(view: LatchView, name: String) -> Vector3:
	return _joint_body(view._source, view._source_body, name)

func _check_ward_context(view: LatchView) -> void:
	var reference: Node3D = load(LatchSource.LATCH_SOURCE).instantiate() as Node3D
	root.add_child(reference)
	view.set_weapon_visible(false)
	for progress: float in [0.0, 0.01, 0.5, 1.0]:
		view.pose_release(progress)
		_legacy_pose(view._source, reference, 0.0, false, false, progress)
		var actual: PackedVector3Array = _skin_points(view._source_body)
		var previous: PackedVector3Array = _skin_points(reference)
		var greatest_error: float = 0.0
		for vertex: int in range(actual.size()):
			greatest_error = maxf(greatest_error, actual[vertex].distance_to(previous[vertex]))
		_check(greatest_error < 0.00001, "ward context preserves every posed vertex including zero-to-positive release")
	view.advance(0.05, 0.0, "following")
	var shoulder: Vector3 = _joint(view, "LeftArm")
	var elbow: Vector3 = _joint(view, "LeftForeArm")
	_check(not view._ward_pose and absf(elbow.x) - absf(shoulder.x) < 0.1,
		"ordinary live advance switches from ward gesture to calm following")
	view.pose_release(0.0)
	shoulder = _joint(view, "LeftArm")
	elbow = _joint(view, "LeftForeArm")
	_check(view._ward_pose and absf(elbow.x) - absf(shoulder.x) > 0.19,
		"returning to ward context preserves its original starting gesture")
	view.advance(0.05, 0.0, "following")
	reference.free()

func _joint_body(source: RefCounted, body: Node3D, name: String) -> Vector3:
	return (source.bone_transform(body, name) as Transform3D).origin

## Exercise the visible pawn path, not the hidden ward's pose_release helper.
func _check_live_release_pawn() -> void:
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate() as Node3D
	root.add_child(pawn)
	pawn.set_process(false)
	pawn.set_player_data("ally", "Latch")
	var state: Dictionary = {"id": "ally", "name": "Latch", "x": 2.0, "y": 1.5,
		"z": 3.0, "yaw": 0.0, "hp": 100, "weapon": "Tack", "just_fired": false,
		"campaign": {"side": "companion", "kind": "latch", "phase": "releasing", "phase_started": 10}}
	_check(ActorState.validation_error({"tick": 10, "players": [state]}) == "",
		"release fixture is a valid authoritative companion snapshot")
	pawn.update_state(state, 10)
	pawn.snap_authoritative_position()
	var live: LatchView = pawn.latch_view as LatchView
	var reference: Node3D = load(LatchSource.LATCH_SOURCE).instantiate() as Node3D
	root.add_child(reference)
	var mesh: MeshInstance3D = live._source_body.get_node("Armature/Skeleton3D/char1") as MeshInstance3D
	var material: Material = mesh.material_override
	for moving: bool in [false, true]:
		if moving:
			state["x"] = 2.2
			pawn.update_state(state, 11)
		pawn._process(0.05)
		_check(pawn.visible and live.visible and pawn.is_campaign_companion
			and not pawn.body.visible and not pawn.weapon_sprite.visible and not live._gun.visible,
			"actual releasing pawn presents its live skin with both weapon presenters hidden")
		_legacy_pose(live._source, reference, live._stride, live._moving, false, 0.0)
		var actual: PackedVector3Array = _skin_points(live._source_body)
		var previous: PackedVector3Array = _skin_points(reference)
		var greatest_error: float = 0.0
		for vertex: int in range(actual.size()):
			greatest_error = maxf(greatest_error, actual[vertex].distance_to(previous[vertex]))
		_check(actual.size() == previous.size() and greatest_error < 0.00001,
			"actual stationary and moving releasing pawn preserves every legacy weighted vertex")
		_check(mesh.material_override == material and live.scale == Vector3.ONE
			and live._source_body.scale == reference.scale and live.position.y == -1.5,
			"release context preserves materials, source scale and server-feet registration")
		if not moving:
			var bounds: AABB = AABB(actual[0], Vector3.ZERO)
			for point: Vector3 in actual:
				bounds = bounds.expand(point)
			_check(absf(bounds.position.y) < 0.00001 and absf(bounds.size.y - 1.799972) < 0.00001,
				"actual stationary releasing pawn keeps adult weighted height and grounded feet")
	state["campaign"]["phase"] = "following"
	pawn.update_state(state, 12)
	pawn.snap_authoritative_position()
	pawn._process(0.05)
	var shoulder: Vector3 = _joint(live, "LeftArm")
	var elbow: Vector3 = _joint(live, "LeftForeArm")
	_check(not live._ward_pose and live._gun.visible and absf(elbow.x) - absf(shoulder.x) < 0.1,
		"actual release-to-following snapshot selects calm free arm and restores Tack")
	for phase: String in ["following", "firing"]:
		state["campaign"]["phase"] = phase
		pawn.update_state(state, 13)
		pawn._process(0.05)
		_legacy_pose(live._source, reference, live._stride, live._moving, true, 0.0, phase == "firing")
		var skeleton: Skeleton3D = live._source_body.get_node("Armature/Skeleton3D") as Skeleton3D
		var previous_skeleton: Skeleton3D = reference.get_node("Armature/Skeleton3D") as Skeleton3D
		for name: String in ["RightArm", "RightForeArm", "RightHand", "Hips", "LeftLeg", "LeftFoot", "RightLeg", "RightFoot"]:
			_check(skeleton.get_bone_global_pose(skeleton.find_bone(name)).is_equal_approx(
				previous_skeleton.get_bone_global_pose(previous_skeleton.find_bone(name))),
				"actual following/firing pawn retains armed right chain and gait: " + name)
	state["campaign"]["phase"] = "releasing"
	pawn.update_state(state, 14)
	pawn._process(0.05)
	_check(live._ward_pose and not live._gun.visible,
		"a later actual releasing snapshot restores prior context instead of inheriting following")
	reference.free()
	pawn.free()

## Retained main 0b03dc2c pose contract, used only as an actual-source control.
func _legacy_pose(source: RefCounted, body: Node3D, stride: float, moving: bool, armed: bool, release: float, firing: bool = false) -> void:
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	skeleton.reset_bone_poses()
	stride = fposmod(stride, TAU)
	release = clampf(release, 0.0, 1.0)
	if moving:
		source._sample_walk(body, skeleton, stride / TAU)
	var sway: float = sin(stride) * 3.0 if moving else 0.0
	var right: Vector3 = Vector3(-27, 96 + sway, 12)
	var left: Vector3 = Vector3(27, 96 - sway, 12)
	if armed:
		right = Vector3(-28, 130, 44) if firing else Vector3(-28, 122, 35)
	source._two_bone(skeleton, "RightArm", "RightForeArm", "RightHand", right.lerp(Vector3(-26, 132, 43), release), Vector3(-58, 109, 3))
	source._two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand", left.lerp(Vector3(30, 111, 18), release), Vector3(56, 109, 3))
	source._turn(skeleton, "RightHand", Vector3.RIGHT, -0.35 * release)
	source._turn(skeleton, "RightHand", Vector3.FORWARD, -0.18 * release)

func _skin_points(body: Node3D) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	var to_body: Transform3D = body.global_transform.affine_inverse()
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var skeleton: Skeleton3D = mesh.get_node(mesh.skeleton) as Skeleton3D
		var transforms: Array[Transform3D] = []
		for bind: int in range(mesh.skin.get_bind_count()):
			var bone: int = mesh.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
			transforms.append(to_body * skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = bones.size() / vertices.size()
			for vertex: int in range(vertices.size()):
				var point: Vector3 = Vector3.ZERO
				for influence: int in range(influences):
					var at: int = vertex * influences + influence
					point += (transforms[bones[at]] * vertices[vertex]) * weights[at]
				result.append(point)
	return result
