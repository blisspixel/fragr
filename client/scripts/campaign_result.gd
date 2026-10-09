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
	return precise_time(int(result["elapsed_ticks"]))

## Records use a 20 Hz clock. Keep its 0.05 second precision visible so two
## times inside the same displayed second cannot claim an unexplained record.
static func precise_time(ticks: int) -> String:
	var seconds: int = ticks / 20
	return "%d:%02d.%02d" % [seconds / 60, seconds % 60, (ticks % 20) * 5]

static func comparison_text(comparison: Dictionary) -> String:
	if comparison.is_empty():
		return ""
	if int(comparison["previous_ticks"]) < 0:
		return TranslationServer.translate("RESULT_FIRST_BEST").format({"time": precise_time(int(comparison["best_ticks"]))})
	var delta: int = int(comparison["delta_ticks"])
	if delta == 0:
		return TranslationServer.translate("RESULT_TIED_BEST").format({"time": precise_time(int(comparison["best_ticks"]))})
	return TranslationServer.translate("RESULT_NEW_BEST" if delta < 0 else "RESULT_BEHIND_BEST").format({
		"time": precise_time(int(comparison["best_ticks"])), "delta": precise_time(absi(delta))})

static func controls_released() -> bool:
	for action: String in ["ui_accept", "ui_cancel", "fire", "jump", "interact", "throw_grenade", "place_mine", "move_forward", "move_back", "move_left", "move_right"]:
		if Input.is_action_pressed(action):
			return false
	return true
