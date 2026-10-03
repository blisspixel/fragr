class_name ShotVfx
extends RefCounted

## Palette pictures for shots seen in the world, keyed by the wire weapon name:
## a third-person muzzle flash per gun and one atlas of impact strips. Baked
## by `tools/bake_shot_vfx.gd`; nearest sampling, hard alpha, no mipmaps.
## The Sniper Rifle's flash is ready for Level 7; its wire name is "Sniper".

const MUZZLE: Dictionary[String, Texture2D] = {
	"Tack": preload("res://assets/vfx/shots/muzzle_tack.png"),
	"Flechette": preload("res://assets/vfx/shots/muzzle_flechette.png"),
	"Scatter": preload("res://assets/vfx/shots/muzzle_scatter.png"),
	"Rail": preload("res://assets/vfx/shots/muzzle_rail.png"),
	"Sniper": preload("res://assets/vfx/shots/muzzle_sniper.png"),
}

## Four frames per row, one row per impact kind, 32 pixel cells.
const IMPACTS: Texture2D = preload("res://assets/vfx/shots/impacts.png")
const IMPACT_FRAMES: int = 4
const IMPACT_ROWS: Array[String] = ["solid", "fighter", "rail", "melee"]

## World width of an impact, metres, by row: a wall puff, a body hit, the
## Railgun's ring and a melee smack.
const IMPACT_METRES: Dictionary[String, float] = {
	"solid": 0.34,
	"fighter": 0.46,
	"rail": 0.6,
	"melee": 0.28,
}

## The flash a third-person gun shows, or null for a weapon with none.
static func muzzle(weapon: String) -> Texture2D:
	return MUZZLE.get(weapon)

## The impact row for a resolved shot: the Railgun keeps its ring on any
## surface, melee its smack, and every other gun splits wall from body.
static func impact_row(weapon: String, kind: String) -> String:
	if weapon in EquipmentState.MELEE:
		return "melee"
	if weapon == "rail":
		return "rail"
	return "fighter" if kind == "fighter" else "solid"

## Atlas UV rectangle for `row` at `age` seconds into a `lifetime`.
static func impact_uv(row: String, age: float, lifetime: float) -> Rect2:
	var frame: int = clampi(int(age / maxf(lifetime, 0.001) * IMPACT_FRAMES), 0, IMPACT_FRAMES - 1)
	var index: int = maxi(IMPACT_ROWS.find(row), 0)
	var cell: Vector2 = Vector2(1.0 / IMPACT_FRAMES, 1.0 / IMPACT_ROWS.size())
	return Rect2(Vector2(frame * cell.x, index * cell.y), cell)
