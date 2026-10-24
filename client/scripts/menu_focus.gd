extends Node
class_name MenuFocus

## One activation target for mixed mouse, keyboard and gamepad menus (#435).
##
## Godot keeps pointer hover and keyboard focus as separate states, so a
## stationary pointer could leave one row lit while the arrows lit another and
## Enter chose the second. The shared policy here is active-input ownership:
## deliberate pointer motion over an enabled button moves focus to it, so the
## row under a moving pointer is the row Enter or A activates. Keyboard and
## gamepad navigation then move focus away as usual, and the theme draws
## leftover hover as a quiet frame that never looks selected (MenuTheme).
##
## A stationary pointer never steals focus: only motion of at least
## InputDevice.MOUSE_COUNTS takes it, the first motion after the window regains
## focus only re-anchors, a focused text field keeps focus, and a row that is
## partly scrolled out of view is not taken (taking it would scroll the list
## under the pointer).

const META: StringName = &"fragr_menu_focus"
## Same bump threshold InputDevice uses before it says the mouse is in use.
const POINTER_MOTION: float = InputDevice.MOUSE_COUNTS

## The next motion after the window regains focus re-anchors the pointer
## instead of moving focus: a returning player has not pointed at anything yet.
var _settle_pointer: bool = false
var _pending: bool = false

## The owner for this node's viewport, created on first use. A SubViewport
## (the rendered capture harness) gets its own owner.
static func attach(node: Node) -> MenuFocus:
	var viewport: Viewport = node.get_viewport() if node.is_inside_tree() else null
	if viewport == null:
		return null
	var existing: Variant = viewport.get_meta(META) if viewport.has_meta(META) else null
	if is_instance_valid(existing) and existing is MenuFocus:
		return existing as MenuFocus
	var owner: MenuFocus = MenuFocus.new()
	owner.name = "MenuFocus"
	owner.process_mode = Node.PROCESS_MODE_ALWAYS
	viewport.set_meta(META, owner)
	# Callers attach from _ready, while the viewport may be adding children.
	viewport.add_child.call_deferred(owner)
	return owner

## A control the pointer may give focus to: an enabled, visible button that
## keyboard navigation can also reach.
static func can_take_pointer_focus(control: Control) -> bool:
	if control == null or not control is BaseButton:
		return false
	var button: BaseButton = control as BaseButton
	return button.is_visible_in_tree() and not button.disabled and button.focus_mode == Control.FOCUS_ALL

## True when no clipping ancestor (a scroll list) hides any part of the control.
static func fully_visible(control: Control) -> bool:
	var rect: Rect2 = control.get_global_rect()
	var node: Node = control.get_parent()
	while node is Control:
		var parent: Control = node as Control
		if parent.clip_contents and not parent.get_global_rect().grow(0.5).encloses(rect):
			return false
		node = parent.get_parent()
	return true

## Text entry keeps focus until the player leaves it with keys or a click.
static func holds_focus(control: Control) -> bool:
	return control is LineEdit or control is TextEdit

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_settle_pointer = true

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return
	if _settle_pointer:
		_settle_pointer = false
		return
	if (event as InputEventMouseMotion).screen_relative.length() < POINTER_MOTION:
		return
	# Hover is resolved by the GUI pass after _input. Follow once it settles.
	if not _pending:
		_pending = true
		_follow_pointer.call_deferred()

func _follow_pointer() -> void:
	_pending = false
	if not is_inside_tree():
		return
	follow(get_viewport())

## Move focus to the hovered control when the policy allows. Returns the
## control that owns focus afterwards.
static func follow(viewport: Viewport) -> Control:
	var owner: Control = viewport.gui_get_focus_owner()
	var hovered: Control = viewport.gui_get_hovered_control()
	if not can_take_pointer_focus(hovered) or not fully_visible(hovered):
		return owner
	if owner == hovered:
		# A click can leave focus hidden. Pointing at it makes it visible.
		if not hovered.has_focus(true):
			hovered.grab_focus()
		return hovered
	if owner != null and holds_focus(owner):
		return owner
	hovered.grab_focus()
	return hovered
