extends SceneTree

## A story moment in play, such as Level 18's turn, takes the air. The radio's
## hold is recomputed every frame, so the moment must stay part of that rule;
## otherwise the next frame releases the station and it plays through the beat.

class HushManager extends "res://scripts/game_manager.gd":
	func _apply_arena_sky(_map_name: String = "") -> void:
		pass

var _failures: int = 0


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_story_hush: " + message)


func _initialize() -> void:
	var manager: HushManager = HushManager.new()
	_check(not manager.radio_scene_hold(), "with no page or moment the radio is free to play")
	manager._hush_for_story(true)
	_check(manager.radio_scene_hold(), "a story moment in play holds the radio")
	# Frames later the rule still holds: the per-frame recompute cannot release it.
	for _frame: int in range(3):
		_check(manager.radio_scene_hold(), "the hold survives the per-frame recompute")
	manager._hush_for_story(false)
	_check(not manager.radio_scene_hold(), "the station is released when the moment ends")
	manager.free()
	if _failures == 0:
		print("test_story_hush: PASS a story moment in play holds the radio across frames and releases it after")
	quit(0 if _failures == 0 else 1)
