class_name ConquestState
extends RefCounted

## Retained facts only. Capture and ticket arithmetic stay on the server.
const SITES: Array[String] = ["harbour", "village", "airfield", "server_halls", "lighthouse"]

static func validation_error(snapshot: Dictionary) -> String:
	var state: Variant = snapshot.get("conquest")
	if state == null:
		return ""
	if not state is Dictionary or not M03MissionState._exact(state, ["tickets", "initial_tickets", "capture_ticks", "points"]):
		return "invalid conquest state"
	var initial: int = SabotageState._count(state.get("initial_tickets"), 1000000)
	var ticks: int = SabotageState._count(state.get("capture_ticks"), 65535)
	if initial < 1 or ticks < 1:
		return "invalid conquest limits"
	var tickets: Variant = state.get("tickets")
	if not tickets is Dictionary or not M03MissionState._exact(tickets, ["union", "coalition"]) or not SabotageState._sides(tickets, initial):
		return "invalid conquest tickets"
	var points: Variant = state.get("points")
	if not points is Array or points.size() != SITES.size():
		return "invalid conquest points"
	var seen: Array[String] = []
	for point: Variant in points:
		if not point is Dictionary or not M03MissionState._exact(point, ["id", "position", "radius", "owner", "capturing", "progress", "contested"]):
			return "invalid conquest point"
		var id: Variant = point.get("id")
		if not id is String or not SITES.has(id) or seen.has(id):
			return "invalid conquest point id"
		seen.append(id)
		if not GrenadeFacts.point(point.get("position")) or not SabotageState._number(point.get("radius")) or float(point.radius) < 1.0 or float(point.radius) > 32.0:
			return "invalid conquest point geometry"
		for field: String in ["owner", "capturing"]:
			if point[field] != null and MatchRules.valid_team(point[field]).is_empty():
				return "invalid conquest side"
		var progress: int = SabotageState._count(point.get("progress"), ticks)
		if progress < 0 or not point.get("contested") is bool or (point.capturing == null and progress != 0):
			return "invalid conquest progress"
	return ""

static func label(id: String) -> String:
	return str(TranslationServer.translate("CONQUEST_SITE_" + id.to_upper())) if SITES.has(id) else ""

static func color(point: Dictionary) -> Color:
	return Color("d8cda8") if point.get("owner") == null else MatchRules.team_label_color(str(point.owner))

static func status(point: Dictionary) -> String:
	if point.get("contested", false):
		return str(TranslationServer.translate("CONQUEST_CONTESTED"))
	if point.get("capturing") != null:
		return str(TranslationServer.translate("CONQUEST_NEUTRALIZING" if point.get("owner") != null else "CONQUEST_CAPTURING"))
	return str(TranslationServer.translate("CONQUEST_NEUTRAL")) if point.get("owner") == null else MatchRules.team_short(str(point.owner))
