class_name HudRelation
extends RefCounted

## UI only. World bodies, optics, flags and nameplate faction colors retain
## their own owners. Feed arrivals freeze this token; live standings may change.
static func token(team: String, viewer_team: String) -> String:
	return MatchRules.team_relation(viewer_team, team)

static func mark_color(team: String, relation: String, on_bone: bool = false) -> Color:
	if on_bone:
		return MenuTheme.INK
	if relation == "mate":
		return MenuTheme.BONE
	if relation == "foe":
		return MenuTheme.DANGER
	if team == "union":
		return MenuTheme.DANGER
	if team == "coalition":
		return MenuTheme.EMBER
	return MenuTheme.MUTED

static func mark(team: String, relation: String, on_bone: bool = false) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.custom_minimum_size = Vector2(4, 24)
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.color = mark_color(team, relation, on_bone)
	rect.tooltip_text = MatchRules.team_name(team)
	var relative: String = MatchRules.relation_mark(relation)
	if not relative.is_empty():
		rect.tooltip_text = relative + ": " + rect.tooltip_text
	return rect
