extends Node3D

## A floor pickup drawn as its object: a pistol, a medkit, a box of shells.
## The sprite stands on the floor, bobs gently and reads from across a room,
## so no text floats in the world. The crate and label remain only as the
## fallback for a kind with no art, plus the one golden Railgun's name.
## Palette: bone-white / gunmetal / ember / blood-ember (not neon).

var pickup_id: String = ""
var weapon_name: String = ""
var pickup_kind: String = "weapon"
var amount: int = 0
var ammo_pool: String = ""
var available: bool = true

@onready var label: Label3D = $Label3D
@onready var body: MeshInstance3D = $Body
@onready var ammo_band: MeshInstance3D = $AmmoBand
@onready var icon: Sprite3D = $Icon

const AMMO_BODY_SIZE: Vector3 = Vector3(0.42, 0.22, 0.32)
const AMMO_BODY_Y: float = 0.11
const AMMO_LABEL_Y: float = 0.59
const AMMO_FONT_SIZE: int = 20
const AMMO_OUTLINE_SIZE: int = 5
## The sprite's lowest pixel rests this far above the pad position.
const SPRITE_FLOOR_GAP: float = 0.06
const BOB_METRES: float = 0.05
const BOB_HZ: float = 0.7

const COLORS = {
	"Flechette": Color(0.86, 0.82, 0.74),  # bone-white
	"Tack": Color(0.74, 0.63, 0.46),
	"ammo": Color(0.66, 0.60, 0.41),
	"Rail": Color(0.42, 0.46, 0.50),       # gunmetal
	"Scatter": Color(0.72, 0.38, 0.22),    # ember
	"Shiv": Color(0.78, 0.62, 0.36),       # ochre grip
	"health": Color(0.62, 0.22, 0.20),     # dried blood
	"armor": Color(0.48, 0.44, 0.38),      # scrap gunmetal
	"grenade": Color(0.60, 0.56, 0.36),    # olive casing
	"proximity_mine": Color(0.46, 0.50, 0.44), # grey puck, amber lamp
	"golden_rail": Color(1.0, 0.8, 0.28),  # the one golden Railgun
}

var _regular_mesh: Mesh
var _regular_body_position: Vector3
var _regular_label_position: Vector3
var _regular_font_size: int
var _regular_outline_size: int
var _ammo_mesh: BoxMesh
var _body_material: StandardMaterial3D
var _sprite_rest_y: float = 0.0
var _bob_phase: float = 0.0
var _bob_time: float = 0.0

func _ready() -> void:
	_regular_mesh = body.mesh
	_regular_body_position = body.position
	_regular_label_position = label.position
	_regular_font_size = label.font_size
	_regular_outline_size = label.outline_size
	_ammo_mesh = BoxMesh.new()
	_ammo_mesh.size = AMMO_BODY_SIZE
	var active_material: Material = body.get_active_material(0)
	if active_material != null:
		_body_material = active_material.duplicate() as StandardMaterial3D
	if _body_material == null:
		_body_material = StandardMaterial3D.new()
	body.set_surface_override_material(0, _body_material)
	# Upright on the floor like the fighters, sampled as pixels, and lit the
	# same everywhere so a supply never sinks into a dark corner.
	icon.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	icon.shaded = false
	_apply_look()

func setup(id: String, weapon: String, pos: Vector3, kind: String = "weapon", pad_amount: int = 0, pool: String = "") -> void:
	pickup_id = id
	weapon_name = weapon
	pickup_kind = kind if kind != "" else "weapon"
	amount = pad_amount
	ammo_pool = pool
	position = pos
	# Neighbouring pickups bob out of step, so a row of them never pulses as one.
	_bob_phase = float(hash(id) % 997) / 997.0 * TAU
	_apply_look()

func set_available(is_available: bool) -> void:
	available = is_available
	visible = available
	_apply_look()

func _process(delta: float) -> void:
	if not visible or icon == null or not icon.visible:
		return
	_bob_time += delta
	icon.position.y = _sprite_rest_y + BOB_METRES * (0.5 + 0.5 * sin(_bob_time * TAU * BOB_HZ + _bob_phase))

func _label_text() -> String:
	if pickup_kind == "ammo":
		return tr("PICKUP_AMMO").format({"amount": amount, "pool": EquipmentState.pool_name(ammo_pool).to_upper()})
	if pickup_kind == "health":
		return tr("PICKUP_MEDKIT") if amount <= 0 else tr("PICKUP_HEALTH").format({"amount": amount})
	if pickup_kind == "armor":
		return tr("PICKUP_ARMOR") if amount <= 0 else tr("PICKUP_ARMOR_AMOUNT").format({"amount": amount})
	if pickup_kind == "grenade":
		return tr("PICKUP_GRENADES").format({"amount": amount})
	if pickup_kind == "proximity_mine":
		return tr("PICKUP_MINES").format({"amount": amount})
	if pickup_kind == "golden_rail":
		return tr("PICKUP_GOLDEN_RAIL")
	if weapon_name != "":
		return EquipmentState.display_name(weapon_name).to_upper()
	return tr("PICKUP_SUPPLY")

func _tint() -> Color:
	if pickup_kind == "ammo":
		return COLORS["ammo"]
	if pickup_kind == "health":
		return COLORS["health"]
	if pickup_kind == "armor":
		return COLORS["armor"]
	if pickup_kind == "grenade":
		return COLORS["grenade"]
	if pickup_kind == "proximity_mine":
		return COLORS["proximity_mine"]
	if pickup_kind == "golden_rail":
		return COLORS["golden_rail"]
	return COLORS.get(weapon_name, Color(0.7, 0.68, 0.64))

## The sprite for this pickup, or null when it has no art.
func sprite_texture() -> Texture2D:
	return WeaponArt.pickup_texture(pickup_kind, weapon_name, ammo_pool)

func _apply_look() -> void:
	if body == null:
		return
	var texture: Texture2D = sprite_texture()
	var drawn: bool = texture != null
	var ammo: bool = pickup_kind == "ammo"
	var tint: Color = _tint()
	body.visible = not drawn
	body.mesh = _ammo_mesh if ammo else _regular_mesh
	body.position = Vector3(0.0, AMMO_BODY_Y, 0.0) if ammo else _regular_body_position
	ammo_band.visible = ammo and not drawn
	# Only the golden Railgun keeps its name in the world; every other pickup
	# reads by its picture, and the corner feed names what was taken.
	label.visible = not drawn or pickup_kind == "golden_rail"
	label.text = _label_text()
	label.modulate = tint
	label.outline_modulate = Color(0.12, 0.11, 0.10)
	label.position = Vector3(0.0, AMMO_LABEL_Y, 0.0) if ammo else _regular_label_position
	label.font_size = AMMO_FONT_SIZE if ammo else _regular_font_size
	label.outline_size = AMMO_OUTLINE_SIZE if ammo else _regular_outline_size
	if _body_material:
		_body_material.albedo_color = tint.darkened(0.25)
		_body_material.emission_enabled = true
		# Health pads get a soft ember glow (blood/ember, not neon); the
		# golden Railgun glows so it reads across the map.
		var glow: float = 0.6 if pickup_kind == "golden_rail" else (0.22 if pickup_kind == "health" else 0.18)
		_body_material.emission = tint * glow
		_body_material.emission_energy_multiplier = 0.7 if pickup_kind == "health" else 0.6
	icon.visible = drawn
	if drawn:
		icon.texture = texture
		icon.pixel_size = WeaponArt.PICKUP_TEXEL_METRES
		_sprite_rest_y = SPRITE_FLOOR_GAP + float(texture.get_height()) * icon.pixel_size * 0.5
		icon.position = Vector3(0.0, _sprite_rest_y, 0.0)
		icon.modulate = Color(1.6, 1.25, 0.45) if pickup_kind == "golden_rail" else Color.WHITE
		if pickup_kind == "golden_rail":
			label.position = Vector3(0.0, _sprite_rest_y * 2.0 + 0.35, 0.0)
