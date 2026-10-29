extends "res://qa/live_crew_tour.gd"

## Reuse the real finite-carry route; never grant a review-only gun.
func _load_manifest() -> Dictionary:
	var tour: Dictionary = super._load_manifest()
	var states: Array = (tour["states"] as Array).slice(0, 4)
	states.append({"name": "repeater_case_approach", "camera": "first_person", "walk_to": [[-6.55, 2, -15.5], [-0.5, 2, -15.5]], "look_at": [1.5, 2.3, -14], "expect_m10_completed": []})
	states.append(tour["states"][4])
	states.append({"name": "repeater_held_fire", "camera": "first_person", "weapon": "Repeater", "look_at": [7, 3.2, -14], "trigger": "fire", "strip_frames": 16, "strip_interval_seconds": 0.05, "record_audio_start": true})
	states.append({"name": "repeater_release", "camera": "first_person", "strip_frames": 8, "strip_interval_seconds": 0.05, "record_audio_stop": true})
	states.append({"name": "repeater_reload", "camera": "first_person", "trigger": "reload", "strip_frames": 14, "strip_interval_seconds": 0.09})
	tour["states"] = states
	return tour
