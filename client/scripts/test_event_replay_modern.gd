extends "res://scripts/test_event_replay.gd"

func _fixture_path() -> String:
	return "res://qa/fixtures/busy-round-modern-events-20261018.json"

func _harness_name() -> String:
	return "test_event_replay_modern"
