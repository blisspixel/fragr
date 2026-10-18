class_name HudNoticeQueue
extends RefCounted

## Advance old admissions before filling vacancies. A new row never loses the
## interval before it arrived, and a cover advances neither time nor admission.
var active: Array[Dictionary] = []
var pending: Array[Dictionary] = []
var rejected: int = 0
var _visible_limit: int
var _pending_limit: int
var _lifetime: float
var _serial: int = 0

func _init(visible_limit: int, pending_limit: int, lifetime: float) -> void:
	assert(visible_limit > 0 and pending_limit > 0 and is_finite(lifetime) and lifetime > 0.0)
	_visible_limit = visible_limit
	_pending_limit = pending_limit
	_lifetime = lifetime

func push(payload: Dictionary) -> bool:
	if pending.size() >= _pending_limit:
		rejected += 1
		return false
	pending.append(payload.duplicate(true))
	return true

func advance(delta: float, covered: bool = false) -> void:
	if covered or not is_finite(delta) or delta < 0.0:
		return
	for index: int in range(active.size() - 1, -1, -1):
		active[index].remaining -= delta
		if active[index].remaining <= 0.0:
			active.remove_at(index)
	while active.size() < _visible_limit and not pending.is_empty():
		_serial += 1
		active.append({"serial": _serial, "payload": pending.pop_front(), "remaining": _lifetime})

func clear() -> void:
	active.clear()
	pending.clear()
	rejected = 0
