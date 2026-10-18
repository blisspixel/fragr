extends Node

## Shared lifecycle contract for focused manager tests without a rendered HUD.
## These probes still exercise the real manager's teardown and map handlers.
var event_retirements: Array[bool] = []

func reset_event_context(session: bool = false) -> void:
	event_retirements.append(session)
