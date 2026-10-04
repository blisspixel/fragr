extends "res://art/models/auditor_source.gd"

## The standing atlas keeps its existing channel cell and emitter registration.
const EMITTER_HEIGHT: float = 1.35

func build_auditor(action: String, progress: float, unarmed: bool) -> Node3D:
	return build_pose(action, progress, unarmed)
