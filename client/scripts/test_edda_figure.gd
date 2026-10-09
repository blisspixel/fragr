extends SceneTree

const BerthFixture = preload("res://scripts/test_m09_mission.gd")
const ShipFixture = preload("res://scripts/test_m10_mission.gd")
const Source = preload("res://art/models/edda_source.gd")
const SHA: String = "cbf1e1e16329da194fdf058f308676e72bfefb357faeea915fc3d9500d57ea40"
var _failures: PackedStringArray = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	_check(FileAccess.get_sha256(SkinnedCharacter.SOURCES["edda"]) == SHA, "packaged skin is the independently reviewed source")
	var figure: CivilianFigure = CivilianFigure.new()
	root.add_child(figure)
	figure.set_process(false)
	figure.configure("edda", Color("b8c5c7"))
	_check(figure.skin != null and figure.skin.kind == "edda" and figure.strip == null, "named live body without a duplicate strip")
	figure.place_feet(Vector3(5, 2, 8))
	figure._process(0.2)
	var rig: Skeleton3D = figure.skin.skeleton
	var idle_leg: Quaternion = rig.get_bone_pose_rotation(rig.find_bone("LeftLeg"))
	for _sample: int in range(20):
		figure.place_feet(Vector3(5, 2, 8))
		figure._process(0.05)
	_check(is_zero_approx(figure._walked) and rig.get_bone_pose_rotation(rig.find_bone("LeftLeg")).is_equal_approx(idle_leg), "repeated stationary observations never start walking")
	figure.place_feet(Vector3(5, 2, 8.2))
	figure._process(0.05)
	_check(absf(figure._walked - 0.2) < 0.00001 and not rig.get_bone_pose_rotation(rig.find_bone("LeftLeg")).is_equal_approx(idle_leg), "actual bounded accepted travel drives real leg motion")
	var walked: float = figure._walked
	for _sample: int in range(20):
		figure.place_feet(Vector3(5, 2, 8.2))
		figure._process(0.05)
	_check(figure._walked == walked and rig.get_bone_pose_rotation(rig.find_bone("LeftLeg")).is_equal_approx(idle_leg), "stale unchanged feet expire to exact resting legs without extrapolation")
	_check(figure.position == Vector3(5, 2, 8.2), "stale presentation never changes accepted feet")
	figure.place_feet(Vector3(12, 2, 8.2))
	figure._process(0.05)
	_check(is_zero_approx(figure._walked) and rig.get_bone_pose_rotation(rig.find_bone("LeftLeg")).is_equal_approx(idle_leg), "large correction resets gait without a walking flourish")
	figure.position = Vector3.ZERO
	figure.rotation = Vector3.ZERO
	figure.skin.pose(0.0, false, false, false)
	for side: String in ["Right", "Left"]:
		var hand: Vector3 = rig.global_transform * rig.get_bone_global_pose(rig.find_bone(side + "Hand")).origin
		_check(hand.distance_to(Vector3(-0.27 if side == "Right" else 0.35, 0.97, 0.08)) < 0.001, "reachable outboard resting wrist " + side)
	var original: Node3D = (load(SkinnedCharacter.SOURCES["edda"]) as PackedScene).instantiate() as Node3D
	root.add_child(original)
	var original_rig: Skeleton3D = original.get_node("Armature/Skeleton3D") as Skeleton3D
	var sampler: RefCounted = Source.new()
	for phase: float in [0.0137, 0.217, 0.509, 0.739, 0.997]:
		original_rig.reset_bone_poses()
		sampler._sample_walk(original, original_rig, phase)
		figure.skin.pose(phase, true, false, false)
		for name: String in ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]:
			_check(rig.get_bone_pose_rotation(rig.find_bone(name)).is_equal_approx(original_rig.get_bone_pose_rotation(original_rig.find_bone(name))), "unarmed gait retains accepted original arm track " + name)
	var player: AnimationPlayer = figure.skin.source_body.get_node("AnimationPlayer") as AnimationPlayer
	_check(player.has_animation(&"Armature|walking_man|baselayer") and player.has_animation(&"walk"), "retained original clip and instance walk alias")
	_check(not (original.get_node("AnimationPlayer") as AnimationPlayer).has_animation(&"walk"), "instance alias does not mutate cached source library")
	original.free()
	var second: SkinnedCharacter = SkinnedCharacter.new()
	root.add_child(second)
	_check(second.configure("edda"), "second named skin available")
	var first_material: StandardMaterial3D = _mesh(figure.skin).get_active_material(0)
	var second_material: StandardMaterial3D = _mesh(second).get_active_material(0)
	var second_color: Color = second_material.albedo_color
	figure.skin.tint(Color(0.5, 0.7, 1.0))
	_check(first_material != second_material and second_material.albedo_color == second_color, "Edda tint stays local to the actual instance")
	figure.free()
	second.free()
	_check_mission_cast()
	await process_frame
	await process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("test_edda_figure: " + failure)
		quit(1)
		return
	print("test_edda_figure: PASS (actual named skin, accepted travel, stale idle, retained gait, independent materials and strict carried-cast eligibility)")
	quit(0)

func _check_mission_cast() -> void:
	var berth: M09Berth = M09Berth.new()
	root.add_child(berth)
	var info: Dictionary = BerthFixture.fixture_map()
	berth.configure_map(info)
	berth.apply_state(BerthFixture.fixture_state(info)["state"])
	_check(not berth._crew.has("edda"), "M09 omitted clinic carry produces no Edda figure")
	berth.configure_map(info)
	berth.apply_state(BerthFixture.fixture_state(info, 0, ["edda"])["state"])
	_check(berth._crew.has("edda") and berth._crew["edda"].skin.kind == "edda", "M09 accepted actual crew facts select Edda")
	var ship: M10Ship = M10Ship.new()
	root.add_child(ship)
	info = ShipFixture.fixture_map()
	ship.configure_map(info)
	ship.apply_state(ShipFixture.fixture_state(info)["state"])
	_check(not ship._figures.has("edda"), "M10 historical Unknown cannot invent Edda aboard")
	ship.apply_state(ShipFixture.fixture_state(info, 0, ["tern", "berth_crew_a", "berth_crew_b", "edda"])["state"])
	_check(ship._figures.has("edda") and ship._figures["edda"].skin.kind == "edda", "M10 recorded actual arrival selects the same reviewed source")
	ship.apply_state(ShipFixture.fixture_state(info)["state"])
	_check(not ship._figures.has("edda"), "retiring omitted passenger facts removes the old figure")
	berth.free()
	ship.free()

func _mesh(view: Node3D) -> MeshInstance3D:
	return view.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D

func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
