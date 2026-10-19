extends RefCounted
class_name HudStyle

## Immutable HUD style specification derived from user accessibility preferences.
## Gameplay HUD scale is applied once to body and display fonts, without mutating
## cached Themes or recursively multiplying font sizes.

var scale: float = 1.0
var text_size: int = FragrSettings.TEXT_STANDARD
var high_contrast_teams: bool = false
var revision: int = 0

func _init(p_scale: float = 1.0, p_text_size: int = FragrSettings.TEXT_STANDARD, p_high_contrast: bool = false, p_rev: int = 0) -> void:
	scale = clampf(p_scale, 0.75, 1.50)
	text_size = FragrSettings.TEXT_LARGE if p_text_size == FragrSettings.TEXT_LARGE else FragrSettings.TEXT_STANDARD
	high_contrast_teams = p_high_contrast
	revision = p_rev

func body_font_size() -> int:
	var base: float = 32.0 if text_size == FragrSettings.TEXT_LARGE else 24.0
	return maxi(12, int(round(base * scale)))

func display_font_size(base: int) -> int:
	return maxi(16, int(round(float(base) * scale)))

func scaled_size(base: float) -> float:
	return round(base * scale)

func scaled_vec2(base: Vector2) -> Vector2:
	return (base * scale).round()

static func from_settings(settings: FragrSettings, rev: int = 0) -> HudStyle:
	var s: float = float(settings.hud_scale()) / 100.0
	var t: int = settings.text_size()
	var c: bool = settings.team_colours() == FragrSettings.TEAM_HIGH_CONTRAST
	return HudStyle.new(s, t, c, rev)
