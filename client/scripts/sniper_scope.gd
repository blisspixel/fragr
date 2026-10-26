class_name SniperScope
extends Control

## Presentation-only Sniper Rifle scope: a sprite overlay and a narrower view
## with hold, toggle or stepped magnification on the Sniper Rifle. It never
## decides a hit; aim and fire still travel as the ordinary absolute action.
## Ink beside the square plate, as the art pass specifies.
const SURROUND: Color = MenuTheme.INK

## 0 is the open view, 1 is fully scoped.
var amount: float = 0.0
var wanted: bool = false
## Hold 4x, toggle 4x, or successive presses for 2x / 4x / open.
var mode: int = 0
var _level: int = 0
var _held_last: bool = false
var _view_factor: float = 1.0
var aperture: TextureRect
var power: Label
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
	power = Label.new()
	power.name = "ScopePower"
	power.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.pixel_text(power, MenuTheme.BODY, MenuTheme.BONE, 2)
	add_child(power)
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
	var pressed: bool = held and not _held_last
	_held_last = held
	if not enabled or weapon.to_lower() not in EquipmentState.SCOPED:
		_level = 0
		wanted = false
		amount = 0.0
		_view_factor = 1.0
	else:
		if mode == 0:
			_level = 2 if held else 0
		elif pressed:
			_level = (0 if _level > 0 else 2) if mode == 1 else (_level + 1) % 3
		wanted = _level > 0
		var step: float = maxf(delta, 0.0) / L07Assets.SCOPE_SETTLE_SECONDS
		amount = move_toward(amount, 1.0 if wanted else 0.0, step)
		var target: float = 1.0 if _level == 0 else (0.5 if _level == 1 else L07Assets.SCOPE_FOV_FACTOR)
		_view_factor = move_toward(_view_factor, target, step)
	visible = scoped()
	if visible:
		power.text = "2x" if _level == 1 else "4x"
		layout(get_viewport_rect().size)
	return fov_factor()

func set_mode(value: int) -> void:
	var next: int = clampi(value, 0, 2)
	if mode != next:
		mode = next
		_level = 0
		wanted = false
		amount = 0.0
		_view_factor = 1.0
		visible = false

func fov_factor() -> float:
	return _view_factor


func scoped() -> bool:
	return amount >= 0.5


## A square aperture as tall as the view, with solid bars beside it.
func layout(view: Vector2) -> void:
	if aperture == null or not view.is_finite() or view.x <= 0.0 or view.y <= 0.0:
		return
	var side: float = minf(view.x, view.y)
	aperture.position = Vector2((view.x - side) * 0.5, (view.y - side) * 0.5).round()
	aperture.size = Vector2(side, side)
	power.position = aperture.position + Vector2(side * 0.72, side * 0.82)
	_left.position = Vector2.ZERO
	_left.size = Vector2(aperture.position.x + 1.0, view.y)
	_right.position = Vector2(aperture.position.x + side - 1.0, 0.0)
	_right.size = Vector2(view.x - _right.position.x, view.y)
