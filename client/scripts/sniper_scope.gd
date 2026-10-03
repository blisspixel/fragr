class_name SniperScope
extends Control

## Presentation-only Sniper Rifle scope: a sprite overlay and a narrower view
## while the scope input is held with the Sniper Rifle selected. It never
## decides a hit; aim and fire still travel as the ordinary absolute action.
## Ink beside the square plate, as the art pass specifies.
const SURROUND: Color = Color("0a0a0c")

## 0 is the open view, 1 is fully scoped.
var amount: float = 0.0
var wanted: bool = false
var aperture: TextureRect
var _left: ColorRect
var _right: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left = _bar("ScopeLeft")
	_right = _bar("ScopeRight")
	aperture = TextureRect.new()
	aperture.name = "ScopeAperture"
	aperture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aperture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	aperture.stretch_mode = TextureRect.STRETCH_SCALE
	aperture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	aperture.texture = WeaponArt.SCOPE_OVERLAY
	add_child(aperture)
	visible = false


func _bar(bar_name: String) -> ColorRect:
	var bar: ColorRect = ColorRect.new()
	bar.name = bar_name
	bar.color = SURROUND
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	return bar


## The scope opens only for a scoped weapon in a live first-person view.
static func active_for(weapon: String, held: bool, enabled: bool) -> bool:
	return enabled and held and weapon.to_lower() in EquipmentState.SCOPED


## Advance toward the wanted state and return the field-of-view factor.
func update_scope(delta: float, weapon: String, held: bool, enabled: bool) -> float:
	wanted = active_for(weapon, held, enabled)
	if not enabled:
		amount = 0.0
	else:
		var step: float = maxf(delta, 0.0) / L07Assets.SCOPE_SETTLE_SECONDS
		amount = move_toward(amount, 1.0 if wanted else 0.0, step)
	visible = scoped()
	if visible:
		layout(get_viewport_rect().size)
	return fov_factor()


func fov_factor() -> float:
	return lerpf(1.0, L07Assets.SCOPE_FOV_FACTOR, amount)


func scoped() -> bool:
	return amount >= 0.5


## A square aperture as tall as the view, with solid bars beside it.
func layout(view: Vector2) -> void:
	if aperture == null or not view.is_finite() or view.x <= 0.0 or view.y <= 0.0:
		return
	var side: float = minf(view.x, view.y)
	aperture.position = Vector2((view.x - side) * 0.5, (view.y - side) * 0.5).round()
	aperture.size = Vector2(side, side)
	_left.position = Vector2.ZERO
	_left.size = Vector2(aperture.position.x + 1.0, view.y)
	_right.position = Vector2(aperture.position.x + side - 1.0, 0.0)
	_right.size = Vector2(view.x - _right.position.x, view.y)
