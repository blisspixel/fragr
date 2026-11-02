extends SceneTree

const Source = preload("res://art/models/clerk_source.gd")
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var source: RefCounted = Source.new()
	var idle: Node3D = source.build_pose("idle", 0.0)
	root.add_child(idle)
	var skeleton: Skeleton3D = idle.get_node("Clerk/Armature/Skeleton3D") as Skeleton3D
	_check(skeleton.get_bone_count() == 24, "source retains the reviewed humanoid skin")
	var resting_hand: Vector3 = _bone(idle, "RightHand")
	var raised: Node3D = source.build_pose("raise", 1.0)
	root.add_child(raised)
	_check(_bone(raised, "RightHand").y > resting_hand.y + 25.0,
		"attack raises the posed hand, rather than only moving the weapon")
	_check(_bone(raised, "RightHand").distance_to(Vector3(-42, 131, 28)) < 1.0,
		"attack grip reaches its authored position")
	var recovered: Node3D = source.build_pose("recover", 1.0)
	root.add_child(recovered)
	_check(_bone(recovered, "RightHand").distance_to(resting_hand) < 0.01,
		"recovery settles to the original grip")
	var step_a: Node3D = source.build_pose("walk", 0.0)
	var step_b: Node3D = source.build_pose("walk", 0.5)
	root.add_child(step_a)
	root.add_child(step_b)
	_check(_bone(step_a, "LeftFoot").distance_to(_bone(step_b, "LeftFoot")) > 10.0,
		"sampled gait changes physical feet")
	var fists: Node3D = source.build_pose("fire", 0.0, true)
	root.add_child(fists)
	_check(fists.find_children("Pistol", "Node3D", true, false).is_empty(),
		"exhausted melee never presents a firearm")
	var fists_ready: Node3D = source.build_pose("raise", 1.0, true)
	root.add_child(fists_ready)
	_check(_bone(fists, "RightHand").z > _bone(fists_ready, "RightHand").z + 15.0,
		"melee follows through toward the target instead of recoiling like a pistol")
	var seated: Node3D = source.build_pose("seated", 0.0)
	root.add_child(seated)
	_check(_bone(seated, "LeftLeg").z > _bone(idle, "LeftLeg").z + 20.0,
		"M02 seated posture actually bends the knees")
	var hit: Node3D = source.build_pose("hit", 0.0)
	root.add_child(hit)
	var hit_skeleton: Skeleton3D = hit.get_node("Clerk/Armature/Skeleton3D") as Skeleton3D
	_check(not hit_skeleton.get_bone_pose_rotation(hit_skeleton.find_bone("Spine")).is_equal_approx(
		skeleton.get_bone_pose_rotation(skeleton.find_bone("Spine"))),
		"the first of the two hit cells contains a physical reaction")
	for model: Node3D in [idle, raised, recovered, step_a, step_b, fists, fists_ready, seated, hit]:
		model.free()
	var albedo: Image = (load("res://assets/characters/union/clerk.png") as Texture2D).get_image()
	var normals: Image = (load("res://assets/characters/union/clerk_normals.png") as Texture2D).get_image()
	_check(albedo.get_size() == normals.get_size() and not normals.has_mipmaps(),
		"paired normal cells retain the pixel layout")
	var mismatches: int = 0
	for y: int in range(0, albedo.get_height(), 3):
		for x: int in range(0, albedo.get_width(), 3):
			if (albedo.get_pixel(x, y).a > 0.5) != (normals.get_pixel(x, y).a > 0.5):
				mismatches += 1
	_check(mismatches == 0, "paired normal silhouettes align across all directions and phases")
	await process_frame
	if _failures == 0:
		print("test_clerk_source: PASS skin, grip, gait, melee, seated posture and paired alpha")
	quit(0 if _failures == 0 else 1)

func _bone(model: Node3D, name: String) -> Vector3:
	var skeleton: Skeleton3D = model.get_node("Clerk/Armature/Skeleton3D") as Skeleton3D
	return skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_clerk_source: " + message)
