extends SceneTree

const Source = preload("res://art/models/enforcer_source.gd")
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _run() -> void:
	var models: Array[Node3D] = []
	var source: RefCounted = Source.new()
	for spec: Array in [["idle", 0.0], ["raise", 1.0], ["recover", 1.0],
		["walk", 0.0], ["walk", 0.5], ["charge", 0.0], ["charge", 0.5],
		["fire", 0.0], ["hit", 0.0], ["death", 1.0]]:
		var model: Node3D = source.build_pose(str(spec[0]), float(spec[1]), true)
		root.add_child(model)
		models.append(model)
	var idle: Node3D = models[0]
	var skeleton: Skeleton3D = _skeleton(idle)
	_check(skeleton.get_bone_count() == 24, "reviewed humanoid rig retained")
	var bounds: AABB = _body_bounds(idle)
	_check(bounds.size.y > 1.65 and bounds.size.y < 2.0, "human source scale stays within the standing body")
	_check(absf(bounds.position.y) < 0.06, "idle weighted soles register at feet")
	_check(_bone(models[1], "Head").z > _bone(idle, "Head").z + 0.08,
		"windup drops the shoulders toward the committed bearing")
	_check(_bone(models[2], "Head").distance_to(_bone(idle, "Head")) < 0.001,
		"recovery returns the actual torso to rest")
	_check(_bone(models[3], "LeftFoot").distance_to(_bone(models[4], "LeftFoot")) > 0.10,
		"sampled gait moves real skin joints")
	_check(_bone(models[3], "Hips").distance_to(_bone(models[4], "Hips")) < 0.04,
		"gait never advances the root independently of server travel")
	_check(_bone(models[5], "LeftFoot").distance_to(_bone(models[6], "LeftFoot")) > 0.10,
		"committed charge retains actual leg motion")
	_check(_bone(models[5], "Head").z > _bone(models[3], "Head").z + 0.08,
		"charge has a separate forward torso posture")
	for model: Node3D in models:
		_check(model.find_children("Pistol", "Node3D", true, false).is_empty(),
			"powered suit never acquires an invented carried gun")
		_check(model.find_children("*", "CollisionObject3D", true, false).is_empty(),
			"source poses create no collision or outcome authority")
		var vents: Node3D = model.get_node("Enforcer/IssuedChargeVents") as Node3D
		_check(vents.get_child_count() == 6, "six local issued vent slits retained")
	for model: Node3D in [idle, models[3], models[4], models[5], models[6]]:
		var posed: AABB = _body_bounds(model)
		_check(posed.position.y > -0.06 and posed.position.y < 0.13,
			"weighted walking/charge soles retain floor registration")
		_check(posed.end.y < 2.0, "moving skin keeps a bounded human silhouette")
	var idle_vent: StandardMaterial3D = (idle.get_node("Enforcer/IssuedChargeVents").get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	var tell_vent: StandardMaterial3D = (models[1].get_node("Enforcer/IssuedChargeVents").get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	_check(idle_vent.albedo_color.r < 0.4 and tell_vent.albedo_color.r > 0.9,
		"only committed tell lights the issued vents")
	_check(_bone(models[9], "Head").y < 0.65, "corpse falls toward its supported floor")
	for model: Node3D in models:
		model.free()
	await process_frame
	if _failures == 0:
		print("test_enforcer_source: PASS weighted skin, feet, gait, charge, tell, recovery and corpse")
	quit(0 if _failures == 0 else 1)

func _skeleton(model: Node3D) -> Skeleton3D:
	return model.get_node("Enforcer/Armature/Skeleton3D") as Skeleton3D

func _bone(model: Node3D, name: String) -> Vector3:
	var skeleton: Skeleton3D = _skeleton(model)
	return model.to_local(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin)

func _body_bounds(model: Node3D) -> AABB:
	var bounds: AABB = AABB()
	var started: bool = false
	for candidate: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = candidate as MeshInstance3D
		if instance.skin == null:
			continue
		var skeleton: Skeleton3D = instance.get_node(instance.skeleton) as Skeleton3D
		var transforms: Array[Transform3D] = []
		for bind: int in range(instance.skin.get_bind_count()):
			var bone: int = instance.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(instance.skin.get_bind_name(bind))
			transforms.append(model.global_transform.affine_inverse() * skeleton.global_transform
				* skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind))
		for surface: int in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = int(bones.size() / vertices.size())
			for vertex: int in range(vertices.size()):
				var point: Vector3 = Vector3.ZERO
				for influence: int in range(influences):
					var slot: int = vertex * influences + influence
					point += (transforms[bones[slot]] * vertices[vertex]) * weights[slot]
				bounds = bounds.expand(point) if started else AABB(point, Vector3.ZERO)
				started = true
	_check(started, "source contains actual weighted vertices")
	return bounds

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_enforcer_source: " + message)
