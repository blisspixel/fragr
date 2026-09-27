extends Node3D

## Scrap crate / pad billboard for mid-map pickups. Ammunition is a compact
## packet so a nearby optional supply does not fill the player's first view.
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

const COLORS = {
	"Flechette": Color(0.86, 0.82, 0.74),  # bone-white
	"Tack": Color(0.74, 0.63, 0.46),
	"ammo": Color(0.66, 0.60, 0.41),
	"Rail": Color(0.42, 0.46, 0.50),       # gunmetal
	"Scatter": Color(0.72, 0.38, 0.22),    # ember
	"Shiv": Color(0.78, 0.62, 0.36),       # ochre grip
	"health": Color(0.62, 0.22, 0.20),     # dried blood
	"armor": Color(0.48, 0.44, 0.38),      # scrap gunmetal
	"golden_rail": Color(1.0, 0.8, 0.28),  # the one golden Railgun
}

var weapon_textures: Dictionary[String, Texture2D] = {}
var _regular_mesh: Mesh
var _regular_body_position: Vector3
var _regular_label_position: Vector3
var _regular_font_size: int
var _regular_outline_size: int
var _ammo_mesh: BoxMesh
var _body_material: StandardMaterial3D

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
	weapon_textures["Flechette"] = load("res://assets/weapons/32/flechette.png")
	weapon_textures["Rail"] = load("res://assets/weapons/32/rail.png")
	weapon_textures["Scatter"] = load("res://assets/weapons/32/scatter.png")
	weapon_textures["Tack"] = load("res://assets/weapons/32/_future/shock_pistol.png")
	weapon_textures["Shiv"] = load("res://assets/weapons/48/shiv.png")
	_apply_look()

func setup(id: String, weapon: String, pos: Vector3, kind: String = "weapon", pad_amount: int = 0, pool: String = "") -> void:
	pickup_id = id
	weapon_name = weapon
	pickup_kind = kind if kind != "" else "weapon"
	amount = pad_amount
	ammo_pool = pool
	position = pos
	_apply_look()

func set_available(is_available: bool) -> void:
	available = is_available
	visible = available
	_apply_look()

func _label_text() -> String:
	if pickup_kind == "ammo":
		return "+%d %s" % [amount, EquipmentState.pool_name(ammo_pool).to_upper()]
	if pickup_kind == "health":
		return "MEDKIT" if amount <= 0 else ("+%d HP" % amount)
	if pickup_kind == "armor":
		return "ARMOR" if amount <= 0 else ("+%d ARM" % amount)
	if pickup_kind == "golden_rail":
		return tr("PICKUP_GOLDEN_RAIL")
	if weapon_name != "":
		return EquipmentState.display_name(weapon_name).to_upper()
	return "PAD"

func _tint() -> Color:
	if pickup_kind == "ammo":
		return COLORS["ammo"]
	if pickup_kind == "health":
		return COLORS["health"]
	if pickup_kind == "armor":
		return COLORS["armor"]
	if pickup_kind == "golden_rail":
		return COLORS["golden_rail"]
	return COLORS.get(weapon_name, Color(0.7, 0.68, 0.64))

func _apply_look() -> void:
	var ammo: bool = pickup_kind == "ammo"
	var tint: Color = _tint()
	if body:
		body.mesh = _ammo_mesh if ammo else _regular_mesh
		body.position = Vector3(0.0, AMMO_BODY_Y, 0.0) if ammo else _regular_body_position
	if ammo_band:
		ammo_band.visible = ammo
	if label:
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
	if icon:
		if (pickup_kind == "weapon" or pickup_kind == "golden_rail") and weapon_textures.has(weapon_name):
			var texture: Texture2D = weapon_textures[weapon_name]
			icon.texture = texture
			# 1.28 m across whether the icon is authored at 32 or 48 pixels.
			icon.pixel_size = 1.28 / float(maxi(texture.get_height(), 1))
			icon.visible = true
			icon.modulate = Color(1.6, 1.25, 0.45) if pickup_kind == "golden_rail" else Color(1.02, 1.0, 0.96)
		else:
			# Medkit / armor: hide weapon icon; label carries the scrap read.
			icon.visible = false
