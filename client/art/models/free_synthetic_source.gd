extends "res://art/models/free_human_source.gd"

## A free civilian worker, independent of faction or control role.
func source_path() -> String:
	return "res://art/models/candidates/free_synthetic.glb"

func pose_name() -> String:
	return "FreeSyntheticPose"
