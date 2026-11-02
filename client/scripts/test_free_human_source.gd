extends SceneTree

const HumanSource = preload("res://art/models/free_human_source.gd")
const ClerkSource = preload("res://art/models/clerk_source.gd")
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var human: RefCounted = HumanSource.new()
	var idle: Node3D = human.build_pose("idle", 0.0, true)
	var first: Node3D = human.build_pose("walk", 0.0, true)
	var second: Node3D = human.build_pose("walk", 0.5, true)
	var clerk: Node3D = ClerkSource.new().build_pose("idle", 0.0)
	for model: Node3D in [idle, first, second, clerk]:
		root.add_child(model)
	_check(idle.get_node_or_null("FreeHuman/Armature/Skeleton3D") != null and clerk.get_node_or_null("Clerk/Armature/Skeleton3D") != null,
		"shared pose cache keeps distinct civilian and issued source identities")
	var skeleton: Skeleton3D = idle.get_node("FreeHuman/Armature/Skeleton3D") as Skeleton3D
	_check(skeleton.get_bone_count() == 24, "civilian retains reviewed humanoid skin")
	_check(_bone(first, "LeftFoot").distance_to(_bone(second, "LeftFoot")) > 10.0, "retained gait moves actual feet")
	_check(absf(_bone(first, "Hips").x - _bone(second, "Hips").x) < 0.01 and absf(_bone(first, "Hips").z - _bone(second, "Hips").z) < 0.01,
		"walking remains in place rather than accumulating source root motion")
	_check(_bone(idle, "RightHand").x < -15.0 and _bone(idle, "LeftHand").x > 15.0,
		"resting empty hands stay apart from the civilian torso")
	_check(idle.find_children("Pistol", "Node3D", true, false).is_empty() and idle.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"selectable civilian source adds neither weapon nor authority")
	for candidate: Node in idle.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = candidate as MeshInstance3D
		_check(mesh.skin != null, "actual body is skinned")
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
			_check(material != null and material.albedo_texture != null and material.albedo_texture.get_size() == Vector2(1024, 1024), "prepared maps meet embedded 1K budget")
	for model: Node3D in [idle, first, second, clerk]:
		model.free()
	await process_frame
	if _failures == 0:
		print("test_free_human_source: PASS distinct skin, civilian stance, gait, in-place motion and map budget")
	quit(0 if _failures == 0 else 1)

func _bone(model: Node3D, name: String) -> Vector3:
	var skeleton: Skeleton3D = model.get_node("FreeHuman/Armature/Skeleton3D") as Skeleton3D
	return skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_free_human_source: " + message)
