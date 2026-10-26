class_name ShotVfx
extends RefCounted

## Palette pictures and tables for combat seen in the world, keyed by the wire
## weapon name: a third-person muzzle flash and light per gun, one atlas of
## impact strips by struck surface, the marks a shot leaves, and the blast
## set. Baked by `tools/bake_shot_vfx.gd`; nearest sampling, hard alpha, no
## mipmaps. The Sniper Rifle's flash is ready for Level 7; its wire name is
## "Sniper".
##
## Colour law: gunfire and blasts light the world amber to warm white and
## never Union red, which stays the Union attack tell. The Railgun's light is
## a cold near-white; muted cyan light belongs to the Inheritance, so the
## Railgun shows cyan only as a pale beam edge.

const MUZZLE: Dictionary[String, Texture2D] = {
	"Tack": preload("res://assets/vfx/shots/muzzle_tack.png"),
	"Flechette": preload("res://assets/vfx/shots/muzzle_flechette.png"),
	"Repeater": preload("res://assets/vfx/shots/muzzle_repeater.png"),
	"Scatter": preload("res://assets/vfx/shots/muzzle_scatter.png"),
	"Rail": preload("res://assets/vfx/shots/muzzle_rail.png"),
	"Sniper": preload("res://assets/vfx/shots/muzzle_sniper.png"),
	"Arc": preload("res://assets/weapons/arc/arc_muzzle.png"),
	"Rocket": preload("res://assets/vfx/shots/muzzle_rocket.png"),
}

## How each gun's third-person flash presents: billboard scale, seconds up,
## and its light (colour, energy, range in metres). First person reads the
## same colours through `muzzle_light`, so one table lights both views.
const MUZZLE_LOOK: Dictionary[String, Dictionary] = {
	"Tack": {"scale": 1.4, "seconds": 0.05, "light": Color("ffc480"), "energy": 2.0, "range": 3.0},
	"Flechette": {"scale": 1.7, "seconds": 0.06, "light": Color("f2b466"), "energy": 2.2, "range": 3.2},
	"Repeater": {"scale": 1.9, "seconds": 0.05, "light": Color("f2ac5c"), "energy": 2.4, "range": 3.4},
	"Scatter": {"scale": 2.6, "seconds": 0.08, "light": Color("e8903e"), "energy": 3.2, "range": 4.5},
	"Rail": {"scale": 2.8, "seconds": 0.10, "light": Color("e6ece8"), "energy": 2.4, "range": 5.5},
	"Sniper": {"scale": 1.4, "seconds": 0.05, "light": Color("f4d2a0"), "energy": 1.15, "range": 3.0},
	"Arc": {"scale": 1.8, "seconds": 0.07, "light": Color("fff0c4"), "energy": 2.2, "range": 4.0},
	"Rocket": {"scale": 2.4, "seconds": 0.09, "light": Color("ffa848"), "energy": 3.6, "range": 5.0},
}

## Fallback presentation for a gun without its own row.
const MUZZLE_DEFAULT: String = "Flechette"

## Surface classes a shot can strike. Solids map their registered material
## to concrete or metal; fighters are flesh or synthetic by their body.
const CONCRETE: String = "concrete"
const METAL: String = "metal"
const FLESH: String = "flesh"
const SYNTHETIC: String = "synthetic"
## Registered map materials by the impact they show: plaster, tile and
## concrete crumble; steel, enamelled panels and glass ring and spark.
const SURFACE_CLASS: Dictionary[String, String] = {
	"concrete": CONCRETE,
	"records_tile": CONCRETE,
	"enamel": METAL,
	"service_steel": METAL,
	"lift_panel": METAL,
	"inspection_glass": METAL,
}

## Six frames per row, one row per struck surface, 32 pixel cells.
const IMPACTS: Texture2D = preload("res://assets/vfx/shots/impacts.png")
const IMPACT_FRAMES: int = 6
const IMPACT_ROWS: Array[String] = ["concrete", "metal", "flesh", "synthetic", "rail", "melee"]

## World width of an impact, metres, by row.
const IMPACT_METRES: Dictionary[String, float] = {
	"concrete": 0.42,
	"metal": 0.38,
	"flesh": 0.5,
	"synthetic": 0.5,
	"rail": 0.7,
	"melee": 0.28,
}

## The marks a shot leaves on a solid: 16 pixel cells in one strip.
const MARKS: Texture2D = preload("res://assets/vfx/shots/marks.png")
const MARK_CELLS: Array[String] = ["concrete", "concrete_b", "metal", "metal_b", "rail", "melee"]
const MARK_METRES: float = 0.18

## The blast set. The fireball plays ten 64 pixel frames; smoke six 32 pixel
## frames; debris is four 8 pixel chunks; the scorch has two variants.
const FIREBALL: Texture2D = preload("res://assets/vfx/blast/fireball.png")
const FIREBALL_FRAMES: int = 10
const SMOKE: Texture2D = preload("res://assets/vfx/blast/smoke.png")
const SMOKE_FRAMES: int = 6
const DEBRIS: Texture2D = preload("res://assets/vfx/blast/debris.png")
const DEBRIS_CELLS: int = 4
const SCORCH: Texture2D = preload("res://assets/vfx/blast/scorch.png")
const SCORCH_VARIANTS: int = 2
const ROCKET_SKIN: Texture2D = preload("res://assets/vfx/blast/rocket_skin.png")
const ROCKET_FLAME: Texture2D = preload("res://assets/vfx/blast/rocket_flame.png")
const GRENADE_SKIN: Texture2D = preload("res://assets/vfx/blast/grenade_skin.png")
const CANISTER_SKIN: Texture2D = preload("res://assets/vfx/blast/canister_skin.png")
## A neutral wear mask (white with darker pits and edges) for small modelled
## device parts: it multiplies the part's own colour.
const WEAR: Texture2D = preload("res://assets/vfx/blast/wear.png")

## A blast lights the room amber, never red.
const BLAST_LIGHT: Color = Color("ffa850")

## The Railgun's beam: a near-white core and a pale cyan edge.
const RAIL_CORE: Color = Color("f6f2e6")
const RAIL_EDGE: Color = Color("a2d2da")
## The spiral: paler still, so the coil reads as discharge, not as a lamp.
const RAIL_SPIRAL: Color = Color("d2eaec")

## A blast within this many radii of the eye kicks the view.
const BLAST_KICK_RADII: float = 3.0
## The kick at point blank: view punch degrees and chase-camera shake metres.
const BLAST_KICK_DEGREES: float = 2.6
const BLAST_KICK_SHAKE: float = 0.14

## How hard a blast `distance` metres from the eye kicks the view, 0 to 1,
## falling off with the square of distance to nothing at the kick reach.
static func blast_kick(distance: float, radius: float) -> float:
	var reach: float = maxf(radius, 0.5) * BLAST_KICK_RADII
	if not is_finite(distance) or distance >= reach:
		return 0.0
	var near: float = 1.0 - maxf(distance, 0.0) / reach
	return near * near

## The flash a third-person gun shows, or null for a weapon with none.
static func muzzle(weapon: String) -> Texture2D:
	return MUZZLE.get(weapon)

## Scale, seconds and light for a gun's flash, the default gun's for any
## other. The returned dictionary is shared; read it, never write it.
static func muzzle_look(weapon: String) -> Dictionary:
	return MUZZLE_LOOK.get(weapon, MUZZLE_LOOK[MUZZLE_DEFAULT])

## The colour a gun's shot lights its surroundings, for both views.
static func muzzle_light(weapon: String) -> Color:
	return muzzle_look(weapon)["light"]

## The impact class of a registered map material; unknown reads as concrete.
static func surface_class(material: String) -> String:
	return SURFACE_CLASS.get(material, CONCRETE)

## The impact row for a resolved shot: the Railgun keeps its ring on any
## surface, melee its smack, and every other gun shows what it struck.
## `surface` is the struck class; a fighter defaults to flesh and a solid to
## concrete when the class is unknown.
static func impact_row(weapon: String, kind: String, surface: String = "") -> String:
	if weapon in EquipmentState.MELEE:
		return "melee"
	if weapon == "rail":
		return "rail"
	if kind == "fighter":
		return SYNTHETIC if surface == SYNTHETIC else FLESH
	return METAL if surface == METAL else CONCRETE

## Atlas UV rectangle for `row` at `age` seconds into a `lifetime`.
static func impact_uv(row: String, age: float, lifetime: float) -> Rect2:
	var frame: int = clampi(int(age / maxf(lifetime, 0.001) * IMPACT_FRAMES), 0, IMPACT_FRAMES - 1)
	var index: int = maxi(IMPACT_ROWS.find(row), 0)
	var cell: Vector2 = Vector2(1.0 / IMPACT_FRAMES, 1.0 / IMPACT_ROWS.size())
	return Rect2(Vector2(frame * cell.x, index * cell.y), cell)

## The mark cell a resolved shot leaves on a solid, or "" for none: fighters
## and misses leave nothing.
static func mark_cell(weapon: String, kind: String, surface: String, variant: int) -> String:
	if kind != "solid":
		return ""
	if weapon in EquipmentState.MELEE:
		return "melee"
	if weapon == "rail":
		return "rail"
	var base: String = METAL if surface == METAL else CONCRETE
	return base if variant % 2 == 0 else base + "_b"

## Atlas UV rectangle of a mark cell.
static func mark_uv(cell: String) -> Rect2:
	var index: int = maxi(MARK_CELLS.find(cell), 0)
	return Rect2(Vector2(float(index) / MARK_CELLS.size(), 0.0), Vector2(1.0 / MARK_CELLS.size(), 1.0))

## Atlas UV rectangle of a horizontal strip of `count` equal frames.
static func strip_uv(frame: int, count: int) -> Rect2:
	var index: int = clampi(frame, 0, count - 1)
	return Rect2(Vector2(float(index) / count, 0.0), Vector2(1.0 / count, 1.0))
