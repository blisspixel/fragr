class_name CampaignResult
extends RefCounted

## Completed private records are the sole source of tally facts. Mission state
## has already crossed MissionState's boundary before reaching this selector.
static func select(record: Dictionary, mission: Dictionary, owner: Variant) -> Dictionary:
	if not PlayerRecord.validation_error(record, owner).is_empty() or record["status"] != "complete":
		return {}
	var scope: Dictionary = record["scope"]
	if scope["kind"] != "mission" or mission.get("phase") != "departed" \
		or scope["mission"] != mission.get("id") or scope["attempt"] != mission.get("attempt") \
		or scope["rules"] != mission.get("rules"):
		return {}
	return {
		"key": PlayerRecord.key(record) + "/%d" % int(scope["attempt"]),
		"map_name": record["map_name"],
		"attempt_number": int(scope["attempt"]),
		"attempt": counts(record["attempt"]),
		"total": counts(record["total"]),
		"elapsed_ticks": record.get("mission_elapsed_ticks"),
		"ticks_per_second": int(record["ticks_per_second"]),
	}

static func counts(value: Dictionary) -> Dictionary:
	return {"kills": PlayerRecord.sum_combat(value, "kills"),
		"secrets": PlayerRecord.secrets(value), "deaths": int(value["deaths"])}

static func elapsed_text(result: Dictionary) -> String:
	if result.get("elapsed_ticks") == null:
		return TranslationServer.translate("RESULT_TIME_UNAVAILABLE")
	var seconds: int = int(result["elapsed_ticks"]) / int(result["ticks_per_second"])
	return "%d:%02d" % [seconds / 60, seconds % 60]

static func controls_released() -> bool:
	for action: String in ["ui_accept", "ui_cancel", "fire", "jump", "interact", "throw_grenade", "place_mine", "move_forward", "move_back", "move_left", "move_right"]:
		if Input.is_action_pressed(action):
			return false
	return true
