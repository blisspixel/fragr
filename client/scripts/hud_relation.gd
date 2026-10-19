class_name HudRelation
extends RefCounted

## UI only. World bodies, optics, flags and nameplate faction colors retain
## their own owners. Feed arrivals freeze this token; live standings may change.
static func token(team: String, viewer_team: String) -> String:
	return MatchRules.team_relation(viewer_team, team)

class MarkControl extends Control:
	var bar_color: Color = MenuTheme.MUTED
	var open: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(6, 24)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, MenuTheme.INK)
		var inner := Rect2(1.0, 1.0, maxf(1.0, size.x - 2.0), maxf(1.0, size.y - 2.0))
		if open:
			draw_rect(inner, bar_color, false, 1.0)
		else:
			draw_rect(inner, bar_color, true)

static func mark_color(team: String, relation: String, on_bone: bool = false, high_contrast: bool = false) -> Color:
	if high_contrast:
		if team == "union":
			return MenuTheme.DANGER
		if team == "coalition":
			return MenuTheme.BONE
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

static func mark(team: String, relation: String, on_bone: bool = false, high_contrast: bool = false) -> Control:
	var mark_ctrl := MarkControl.new()
	mark_ctrl.open = (team == "coalition")
	mark_ctrl.bar_color = mark_color(team, relation, on_bone, high_contrast)
	mark_ctrl.tooltip_text = MatchRules.team_name(team)
	var relative: String = MatchRules.relation_mark(relation)
	if not relative.is_empty():
		mark_ctrl.tooltip_text = relative + ": " + mark_ctrl.tooltip_text
	return mark_ctrl
