class_name SabotageHud
extends Control

## Sabotage on the screen, as pictures rather than words: living fighters as
## pips per side, the planted charge's icon and draining timer, the held plant
## or defuse as a bar under the crosshair, and the charge in the carrier's own
## view. The one line of HUD text lives in the HUD's mode chip.

const PIP_SIZE := Vector2(9, 14)
const PIP_GAP: float = 3.0
const MAX_PIPS: int = 8
const TIMER_SIZE := Vector2(132, 8)
const PROGRESS_SIZE := Vector2(240, 12)
const ICON_SCALE: float = 3.0
const DARK := Color(0.04, 0.04, 0.05, 0.85)
const URGENT_TICKS: int = 200

var _union_pips: Array[ColorRect] = []
var _coalition_pips: Array[ColorRect] = []
var _timer_icon: TextureRect = null
var _timer_back: ColorRect = null
var _timer_fill: ColorRect = null
var _progress_back: ColorRect = null
var _progress_fill: ColorRect = null
var _carried: TextureRect = null
var _urgent: bool = false
## Last values applied, for tests and the tour.
var progress_shown: float = -1.0
var timer_shown: float = -1.0
var carrying: bool = false


func _ready() -> void:
	name = "Sabotage"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i: int in range(MAX_PIPS):
		_union_pips.append(_pip(MatchRules.UNION_LABEL))
		_coalition_pips.append(_pip(MatchRules.COALITION_LABEL))
	_timer_icon = TextureRect.new()
	_timer_icon.texture = SabotageArt.charge()
	_timer_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_timer_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_timer_icon.size = Vector2(16, 12) * ICON_SCALE
	_timer_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_timer_icon)
	_timer_back = _bar(DARK)
	_timer_fill = _bar(SabotageArt.LIT)
	_progress_back = _bar(DARK)
	_progress_fill = _bar(SabotageArt.EMBER)
	_carried = TextureRect.new()
	_carried.texture = SabotageArt.charge()
	_carried.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_carried.stretch_mode = TextureRect.STRETCH_SCALE
	_carried.size = Vector2(16, 12) * 6.0
	_carried.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_carried)
	hide_all()
	resized.connect(_layout)
	_layout()


func _pip(color: Color) -> ColorRect:
	var pip: ColorRect = ColorRect.new()
	pip.color = color
	pip.size = PIP_SIZE
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pip)
	return pip


func _bar(color: Color) -> ColorRect:
	var bar: ColorRect = ColorRect.new()
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	return bar


func hide_all() -> void:
	for pip: ColorRect in _union_pips + _coalition_pips:
		pip.visible = false
	_timer_icon.visible = false
	_timer_back.visible = false
	_timer_fill.visible = false
	_progress_back.visible = false
	_progress_fill.visible = false
	_carried.visible = false
	progress_shown = -1.0
	timer_shown = -1.0
	carrying = false


func _layout() -> void:
	var width: float = size.x if size.x > 0.0 else 1280.0
	var height: float = size.y if size.y > 0.0 else 720.0
	var centre: float = width * 0.5
	var top: float = 14.0
	for i: int in range(MAX_PIPS):
		_union_pips[i].position = Vector2(centre - 44.0 - (i + 1) * (PIP_SIZE.x + PIP_GAP), top)
		_coalition_pips[i].position = Vector2(centre + 44.0 + i * (PIP_SIZE.x + PIP_GAP), top)
	_timer_icon.position = Vector2(centre - _timer_icon.size.x * 0.5, top - 4.0)
	_timer_back.position = Vector2(centre - TIMER_SIZE.x * 0.5, top + _timer_icon.size.y)
	_timer_back.size = TIMER_SIZE
	_timer_fill.position = _timer_back.position + Vector2(1, 1)
	_progress_back.position = Vector2(centre - PROGRESS_SIZE.x * 0.5, height * 0.5 + 64.0)
	_progress_back.size = PROGRESS_SIZE
	_progress_fill.position = _progress_back.position + Vector2(2, 2)
	_carried.position = Vector2(width * 0.27 - _carried.size.x * 0.5, height - _carried.size.y - 70.0)


## One snapshot. `progress_owner` is true when the plant or defuse under way
## belongs to whoever this view is looking through.
func apply(state: Dictionary, charge_ticks: int, progress_owner: bool, carried: bool) -> void:
	if state.is_empty():
		hide_all()
		return
	var alive: Dictionary = state.get("alive", {})
	_fill_pips(_union_pips, int(alive.get("union", 0)))
	_fill_pips(_coalition_pips, int(alive.get("coalition", 0)))
	var share: float = SabotageState.charge_fraction(state, charge_ticks)
	var planted: bool = share >= 0.0
	_timer_icon.visible = planted
	_timer_back.visible = planted
	_timer_fill.visible = planted
	timer_shown = share
	_urgent = planted and int(state.get("clock_ticks", 0)) <= URGENT_TICKS
	if planted:
		_timer_fill.size = Vector2((TIMER_SIZE.x - 2.0) * share, TIMER_SIZE.y - 2.0)
	var progress: float = SabotageState.progress_fraction(state) if progress_owner else -1.0
	_progress_back.visible = progress >= 0.0
	_progress_fill.visible = progress >= 0.0
	progress_shown = progress
	if progress >= 0.0:
		var kind: String = str((state.get("progress", {}) as Dictionary).get("kind", "plant"))
		_progress_fill.color = SabotageArt.EMBER if kind == "plant" else SabotageArt.BONE
		_progress_fill.size = Vector2((PROGRESS_SIZE.x - 4.0) * progress, PROGRESS_SIZE.y - 4.0)
	carrying = carried
	_carried.visible = carried


func _fill_pips(pips: Array[ColorRect], count: int) -> void:
	for i: int in range(pips.size()):
		pips[i].visible = i < count


func _process(_delta: float) -> void:
	if _timer_fill == null or not _timer_fill.visible:
		return
	# The last ten seconds flash, in time with the faster beeps.
	var on: bool = not _urgent or fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0
	_timer_fill.color = SabotageArt.LIT if on else SabotageArt.BONE
	_timer_icon.modulate = Color.WHITE if on else Color(1.0, 0.5, 0.45)
