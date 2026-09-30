class_name FlagState
extends RefCounted

## Validate the complete objective before any renderer or HUD uses it.
const TEAMS: Array[String] = ["union", "coalition"]
const STATUSES: Array[String] = ["home", "carried", "dropped"]

## The authored arena uses +X as east and -Z as north. These are display
## measurements only; all flag touches and scoring stay on the server.
static func distance_m(from_position: Array, to_position: Array) -> int:
	var delta: Vector2 = Vector2(
		float(to_position[0]) - float(from_position[0]),
		float(to_position[2]) - float(from_position[2]))
	return roundi(delta.length())


static func bearing(from_position: Array, to_position: Array) -> String:
	var dx: float = float(to_position[0]) - float(from_position[0])
	var dz: float = float(to_position[2]) - float(from_position[2])
	var directions: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var direction: String = directions[(roundi(atan2(dx, -dz) / (PI / 4.0)) + 8) % 8]
	return str(TranslationServer.translate("FLAG_BEARING_" + direction))


## Corner phrase for one flag. A carrier is pointed at their own stand.
## Everyone else is pointed at a carried or dropped flag. Scoring stays on the server.
static func status_text(flag: Dictionary, viewer_id: String, viewer_team: String, viewer_position: Array, names: Dictionary, carrying: bool) -> String:
	var status_id: String = str(flag.get("status", ""))
	if status_id == "carried":
		var carrier: String = str(flag.get("carrier", ""))
		var player_name: String = str(names.get(carrier, "?"))
		if carrier != viewer_id and _position(viewer_position) and _position(flag.get("position")):
			var away: int = distance_m(viewer_position, flag["position"])
			if away >= 1:
				return str(TranslationServer.translate("FLAG_CARRIED_BEARING")).format({
					"player": player_name,
					"distance": away,
					"bearing": bearing(viewer_position, flag["position"]),
				})
		return str(TranslationServer.translate("FLAG_CARRIED")).format({"player": player_name})
	if status_id == "dropped":
		var seconds: int = ceili(float(flag.get("return_ticks", 0)) / 20.0)
		if _position(viewer_position) and _position(flag.get("position")):
			return str(TranslationServer.translate("FLAG_DROPPED_BEARING")).format({
				"seconds": seconds,
				"distance": distance_m(viewer_position, flag["position"]),
				"bearing": bearing(viewer_position, flag["position"]),
			})
		return str(TranslationServer.translate("FLAG_DROPPED")).format({"seconds": seconds})
	if carrying and viewer_team != "" and str(flag.get("team", "")) == viewer_team and _position(viewer_position) and _position(flag.get("stand")):
		var home_distance: int = distance_m(viewer_position, flag["stand"])
		if home_distance >= 1:
			return str(TranslationServer.translate("FLAG_HOME_BEARING")).format({
				"distance": home_distance,
				"bearing": bearing(viewer_position, flag["stand"]),
			})
	return str(TranslationServer.translate("FLAG_HOME"))

static func _position(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component: Variant in value:
		if not (component is int or component is float):
			return false
		if not absf(float(component)) <= 1000000.0:
			return false
	return true


static func _score(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for side: String in TEAMS:
		var count: Variant = value.get(side)
		if not (count is int or count is float):
			return false
		if float(count) != floorf(float(count)) or float(count) < 0.0 or float(count) > 1000000.0:
			return false
	return true


static func snapshot_error(snapshot: Dictionary) -> String:
	var flags: Variant = snapshot.get("flags")
	if flags == null:
		if snapshot.get("capture_scores") != null or snapshot.get("capture_limit") != null:
			return "flag scores without flags"
		return ""
	if not flags is Array or flags.size() != 2:
		return "invalid flag roster"
	if not _score(snapshot.get("capture_scores")):
		return "invalid capture scores"
	var limit: Variant = snapshot.get("capture_limit")
	if not (limit is int or limit is float) or float(limit) != floorf(float(limit)) or float(limit) < 1.0 or float(limit) > 99.0:
		return "invalid capture limit"
	for i: int in range(2):
		var value: Variant = flags[i]
		if not value is Dictionary:
			return "invalid flag"
		var flag: Dictionary = value
		if flag.get("team") != TEAMS[i] or not STATUSES.has(flag.get("status")):
			return "invalid flag identity"
		if not _position(flag.get("stand")) or not _position(flag.get("position")):
			return "invalid flag position"
		var status: String = flag["status"]
		var carrier: Variant = flag.get("carrier")
		var remaining: Variant = flag.get("return_ticks")
		if status == "carried":
			if not carrier is String or carrier.is_empty() or remaining != null:
				return "invalid flag carrier"
		elif status == "dropped":
			if carrier != null or not (remaining is int or remaining is float) or float(remaining) != floorf(float(remaining)) or float(remaining) < 0.0 or float(remaining) > 400.0:
				return "invalid flag return clock"
		elif carrier != null or remaining != null or flag["position"] != flag["stand"]:
			return "invalid home flag"
	return ""
