extends RefCounted

## Rigid mechanical articulation, exported as ordinary glTF node tracks.
const CLIPS: Dictionary[String, float] = {"walk": 1.0, "raise": 0.3, "fire": 0.15, "recover": 0.4, "hit": 0.2, "death": 0.8}

static func attach(model: Node3D, source: RefCounted) -> void:
	var library: AnimationLibrary = AnimationLibrary.new()
	for action: String in CLIPS:
		var animation: Animation = Animation.new()
		animation.length = CLIPS[action]
		animation.loop_mode = Animation.LOOP_LINEAR if action == "walk" else Animation.LOOP_NONE
		var samples: Array[Dictionary] = []
		for index: int in range(17):
			var pose: Node3D = source.build_pose(true, action, float(index) / 16.0, false)
			var transforms: Dictionary[String, Transform3D] = {}
			_collect(pose, pose, transforms)
			samples.append(transforms)
			pose.free()
		for path: String in samples[0]:
			var start: Transform3D = samples[0][path]
			var moving: bool = false
			for sample: Dictionary in samples:
				moving = moving or not start.is_equal_approx(sample[path])
			if not moving:
				continue
			var position_track: int = animation.add_track(Animation.TYPE_POSITION_3D)
			var rotation_track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
			var scale_track: int = animation.add_track(Animation.TYPE_SCALE_3D)
			for track: int in [position_track, rotation_track, scale_track]:
				animation.track_set_path(track, NodePath(path))
			for index: int in range(samples.size()):
				var transform: Transform3D = samples[index][path]
				var time: float = animation.length * float(index) / 16.0
				animation.position_track_insert_key(position_track, time, transform.origin)
				animation.rotation_track_insert_key(rotation_track, time, transform.basis.get_rotation_quaternion())
				animation.scale_track_insert_key(scale_track, time, transform.basis.get_scale())
		library.add_animation(action, animation)
	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	model.add_child(player)
	player.add_animation_library("", library)

static func _collect(root: Node3D, node: Node3D, result: Dictionary[String, Transform3D]) -> void:
	for child: Node in node.get_children():
		if child is Node3D:
			result[str(root.get_path_to(child))] = child.transform
			_collect(root, child, result)
