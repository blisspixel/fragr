extends "res://scripts/qa_tour.gd"

func _run() -> void:
	var snapshot: Dictionary = {"tick": 42, "players": [
		{"id": "officer", "name": "gallery_auditor", "hp": 120},
		{"id": "machine", "name": "upper_sweeper_middle", "hp": 0}],
		"auditors": [{"id": "officer", "channel_target": "machine", "repairs_left": 2}]}
	var expected: Dictionary = {"name": "gallery_auditor", "target": "upper_sweeper_middle", "channel": true, "repairs_left": 2}
	assert(not auditor_observation(snapshot, expected).is_empty())
	snapshot["auditors"][0]["channel_target"] = "another_body"
	assert(auditor_observation(snapshot, expected).is_empty())
	snapshot["auditors"][0].erase("channel_target")
	assert(auditor_observation(snapshot, expected).is_empty())
	expected["channel"] = false
	expected["target_alive"] = true
	expected["repairs_left"] = 1
	assert(auditor_observation(snapshot, expected).is_empty())
	snapshot["players"][1]["hp"] = 50
	snapshot["auditors"][0]["repairs_left"] = 1
	assert(not auditor_observation(snapshot, expected).is_empty())
	snapshot["players"][0]["hp"] = 0
	assert(auditor_observation(snapshot, expected).is_empty())
	print("test_qa_auditor: PASS (named live channel and reactivation require matching server facts)")
	quit(0)
