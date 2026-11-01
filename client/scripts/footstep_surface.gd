class_name FootstepSurface
extends RefCounted

## Which footstep set a floor sounds like, from the MapInfo the client already
## holds. A map that registers surface kits (`presentation`: one per solid and
## one for the ground) is heard by kit; a map without them is concrete.
## Presentation only: it never changes where anybody stands.

const CONCRETE: String = "concrete"
const METAL: String = "metal"
const TILE: String = "tile"
const SETS: Array[String] = [CONCRETE, METAL, TILE]
## Registered kit to footstep set (MapGeometry.SURFACES).
const BY_KIT: Dictionary[String, String] = {
	"concrete": CONCRETE,
	"service_steel": METAL,
	"lift_panel": METAL,
	"enamel": TILE,
	"records_tile": TILE,
	"inspection_glass": TILE,
}
## A solid top this close under the feet holds them up.
const SUPPORT_SLACK: float = 0.08
## And a top up to this far below still counts: a step down is mid-stride.
const SUPPORT_REACH: float = 0.7

static var _solids: Array[Dictionary] = []
static var _kits: Array[String] = []
static var _ground: String = CONCRETE


## Read the current map. Anything malformed falls back to concrete everywhere.
static func configure(info: Dictionary) -> void:
	_solids.clear()
	_kits.clear()
	_ground = CONCRETE
	if not MapGeometry.validation_error(info).is_empty():
		return
	for solid: Variant in info["solids"]:
		_solids.append(solid as Dictionary)
	var presentation: Variant = info.get("presentation")
	if not presentation is Dictionary:
		return
	var kits: Variant = (presentation as Dictionary).get("solids")
	if not kits is Array or (kits as Array).size() != _solids.size():
		return
	for kit: Variant in kits:
		_kits.append(BY_KIT.get(str(kit), CONCRETE))
	_ground = BY_KIT.get(str((presentation as Dictionary).get("ground", "")), CONCRETE)


static func clear() -> void:
	_solids.clear()
	_kits.clear()
	_ground = CONCRETE


## The set for feet at `feet` (world metres, the bottom of the body).
static func at(feet: Vector3) -> String:
	var best: float = -INF
	var kit: String = _ground
	for index: int in range(_solids.size()):
		var solid: Dictionary = _solids[index]
		var top: float = MoveStep.solid_top(solid)
		if top > feet.y + SUPPORT_SLACK or top < feet.y - SUPPORT_REACH or top <= best:
			continue
		if not MoveStep.solid_covers(solid, feet.x, feet.z):
			continue
		best = top
		kit = _kits[index] if index < _kits.size() else CONCRETE
	return kit
