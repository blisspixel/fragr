extends "res://art/models/enforcer_source.gd"

func build_enforcer(action: String, progress: float, unarmed: bool = false) -> Node3D:
	return build_pose(action, progress, unarmed)
