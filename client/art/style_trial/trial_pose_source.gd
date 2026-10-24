extends "res://art/models/clerk_source.gd"

## Art style trial only. Gives the two free bodies the Clerk's authored combat
## pose set (raise, fire, recover, hit, collapse) on their own prepared skins,
## so every treatment of every trial unit starts from identical poses. The
## shipped free bodies keep their own sources and eight-cell strips.

const SOURCES: Dictionary[String, String] = {
	"human": "res://art/models/candidates/free_human.glb",
	"synthetic": "res://art/models/candidates/free_synthetic.glb",
	"clerk": "res://art/models/candidates/clerk.glb",
}
var unit: String = "clerk"

func _init(trial_unit: String = "clerk") -> void:
	unit = trial_unit

func source_path() -> String:
	return SOURCES[unit]

func pose_name() -> String:
	return "TrialPose_" + unit
