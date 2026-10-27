extends Node3D

## A floor pickup drawn as its object: a pistol, a medkit, a box of shells.
## The sprite is seated: it rests on its pad (or on the dais, pedestal or
## cradle a venue stages under it) with a contact shadow, and when its clock
## brings it back it rises with a short warm shimmer. It reads from across a
## room, so no text floats in the world. The crate and label remain only as
## the fallback for a kind with no art, plus the one golden Railgun's name.
## Palette: bone-white / gunmetal / ember / blood-ember (not neon).

var pickup_id: String = ""
var weapon_name: String = ""
var pickup_kind: String = "weapon"
var amount: int = 0
var ammo_pool: String = ""
var available: bool = true
## A gun a fragged fighter dropped (`dropped` on the wire): it lies on the
## floor where they fell, with no pad or stage under it, and blinks before
## it is gone. The server takes it away; this only warns.
var dropped: bool = false
var _dropped_age: float = 0.0

@onready var label: Label3D = $Label3D
@onready var body: MeshInstance3D = $Body
@onready var ammo_band: MeshInstance3D = $AmmoBand
@onready var icon: Sprite3D = $Icon

const AMMO_BODY_SIZE: Vector3 = Vector3(0.42, 0.22, 0.32)
const AMMO_BODY_Y: float = 0.11
const AMMO_LABEL_Y: float = 0.59
const AMMO_FONT_SIZE: int = 20
const AMMO_OUTLINE_SIZE: int = 5
## The server places a pad this far over its floor (`ArenaPickup.y` is the
## floor plus 0.4); the pickup seats itself back down on that floor.
const PAD_LIFT: float = 0.4
## The sprite's lowest pixel rests this far above its seat, so a clipped
## edge never sinks into the deck.
const SPRITE_FLOOR_GAP: float = 0.02
## A venue that stages its pads joins this group and answers
## `stage_pickup(id, kind, weapon, floor_position) -> float` with the height
## of the dais, pedestal or cradle it built under the pad.
const STAGE_GROUP: StringName = &"pickup_stage"
## The respawn shimmer: a warm column of pixel glints that rises and fades
## as the item returns. Warm bone, never the Inheritance's cyan.
const SHIMMER_SECONDS: float = 0.7
const SHIMMER_COLOR: Color = Color(1.0, 0.86, 0.6)
const CONTACT_SHADOW_ALPHA: float = 0.55

const COLORS = {
	"Flechette": Color(0.86, 0.82, 0.74),  # bone-white
	"Tack": Color(0.74, 0.63, 0.46),
	"ammo": Color(0.66, 0.60, 0.41),
	"Rail": Color(0.42, 0.46, 0.50),       # gunmetal
	"Scatter": Color(0.72, 0.38, 0.22),    # ember
	"Shiv": Color(0.78, 0.62, 0.36),       # ochre grip
	"Sniper": Color(0.30, 0.31, 0.33),     # blackened issued steel
	"Arc": Color("d6bb76"),
	"health": Color(0.62, 0.22, 0.20),     # dried blood
	"armor": Color(0.48, 0.44, 0.38),      # scrap gunmetal
	"plate": Color(0.34, 0.34, 0.37),      # Union issued steel
	"grenade": Color(0.60, 0.56, 0.36),    # olive casing
	"proximity_mine": Color(0.46, 0.50, 0.44), # grey puck, amber lamp
	"golden_rail": Color(1.0, 0.8, 0.28),  # the one golden Railgun
}

var _remote_body: Node3D
var _regular_mesh: Mesh
var _regular_body_position: Vector3
var _regular_label_position: Vector3
var _regular_font_size: int
var _regular_outline_size: int
var _ammo_mesh: BoxMesh
var _body_material: StandardMaterial3D
var _sprite_rest_y: float = 0.0
## Height of whatever the pad is seated on, over its floor.
var seat_height: float = 0.0
var _staged: bool = false
var _shadow: MeshInstance3D
var _shimmer: Sprite3D
var _shimmer_left: float = 0.0
static var _shadow_texture: Texture2D
static var _shimmer_texture: Texture2D
var reduced_motion: bool = false

## Where this pad is, heard: a return clack when its clock runs out and a
## pickup sound when somebody else takes it. Strong items carry across the
## map; ordinary guns and supplies carry across a room or two.
const RETURN_SOUND_PATH: String = "res://assets/audio/pickup/pad_return.wav"
const TAKEN_SOUND_PATHS: Dictionary[String, String] = {
	"weapon": "res://assets/audio/pickup/weapon.wav",
	"ammo": "res://assets/audio/pickup/ammo.wav",
	"health": "res://assets/audio/pickup/health.wav",
	"armor": "res://assets/audio/pickup/armor.wav",
	"plate": "res://assets/audio/pickup/armor.wav",
}
const POWER_WEAPONS: Array[String] = ["Rail", "Sniper", "Rocket", "Arc"]
const POWER_REACH_METRES: float = 70.0
const COMMON_REACH_METRES: float = 32.0
## The Custody Plate is the arena's power item and stands larger than the
## ordinary vest, so it reads from the Gallery and the Crane.
const PLATE_SCALE: float = 1.35
## Seconds the item takes to rise back to full size on its return.
const RETURN_POP_SECONDS: float = 0.28
## A dropped gun lies this long (`sim::drops::DROPPED_GUN_TICKS` / 20).
const DROPPED_SECONDS: float = 15.0
## It blinks for its last seconds, so nobody runs for a gun about to go.
const DROPPED_BLINK_SECONDS: float = 3.0

var _cue: AudioStreamPlayer3D
## The server's own availability, before any personal claim hides the pad.
## Unknown until the first snapshot, so a joiner hears nothing for pads that
## were already up or down.
var _server_up: int = -1
var _pop_left: float = 0.0
var return_cue_count: int = 0
var taken_cue_count: int = 0

func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
	if enabled and is_instance_valid(icon):
		icon.position.y = _sprite_rest_y
	if enabled and is_instance_valid(_shimmer):
		_shimmer_left = 0.0
		_shimmer.visible = false

## Local height of the seat's top: the pad's floor plus whatever it stands on.
func seat_y() -> float:
	return -PAD_LIFT + seat_height

func _ready() -> void:
	MenuTheme.world_text(label)
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
	_stage()
	_apply_look()

func setup(id: String, weapon: String, pos: Vector3, kind: String = "weapon", pad_amount: int = 0, pool: String = "", is_dropped: bool = false) -> void:
	if id != pickup_id:
		_staged = false
		seat_height = 0.0
		_dropped_age = 0.0
	dropped = is_dropped
	pickup_id = id
	weapon_name = weapon
	pickup_kind = kind if kind != "" else "weapon"
	amount = pad_amount
	ammo_pool = pool
	position = pos
	_stage()
	_apply_look()

## Ask the venue, once per pad, what it staged under this one. Outside the
## tree, or on a map with no stage, the pickup sits on its floor.
func _stage() -> void:
	if _staged or pickup_id.is_empty() or not is_inside_tree():
		return
	_staged = true
	# A dropped gun lies where its fighter fell; the venue stages pads only.
	if dropped:
		return
	for stage: Node in get_tree().get_nodes_in_group(STAGE_GROUP):
		if stage.has_method("stage_pickup"):
			var floor_at: Vector3 = global_position - Vector3(0.0, PAD_LIFT, 0.0)
			seat_height = clampf(float(stage.call("stage_pickup", pickup_id, pickup_kind, weapon_name, floor_at)), 0.0, 0.3)
			return

## The server's availability for this pad, every snapshot. A change plays
## the pad's positional cue unless `audible` is false (the listener is the
## one standing on it and already hears its own pickup).
func note_server_available(up: bool, audible: bool = true) -> void:
	var was: int = _server_up
	_server_up = 1 if up else 0
	if was < 0 or was == _server_up:
		return
	if up:
		if not reduced_motion:
			_pop_left = RETURN_POP_SECONDS
			scale = Vector3.ONE * 0.35
			_start_shimmer()
		return_cue_count += 1
		if audible:
			_play_cue(RETURN_SOUND_PATH, -2.0)
	else:
		taken_cue_count += 1
		if audible:
			_play_cue(str(TAKEN_SOUND_PATHS.get(pickup_kind, TAKEN_SOUND_PATHS["weapon"])), -6.0)

func reach_metres() -> float:
	if pickup_kind in ["golden_rail", "armor", "plate"] or weapon_name in POWER_WEAPONS:
		return POWER_REACH_METRES
	return COMMON_REACH_METRES

func _play_cue(path: String, volume_db: float) -> void:
	if not ResourceLoader.exists(path):
		return
	if _cue == null:
		_cue = AudioStreamPlayer3D.new()
		_cue.name = "PadCue"
		_cue.bus = &"Effects"
		_cue.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_cue.position = Vector3(0.0, 0.5, 0.0)
		add_child(_cue)
	_cue.unit_size = reach_metres() * 0.25
	_cue.max_distance = reach_metres()
	_cue.volume_db = volume_db
	_cue.stream = load(path)
	_cue.play()

func set_available(is_available: bool) -> void:
	available = is_available
	visible = available
	_apply_look()

func _process(delta: float) -> void:
	if _pop_left > 0.0:
		_pop_left = maxf(0.0, _pop_left - delta)
		var grown: float = 1.0 - _pop_left / RETURN_POP_SECONDS
		scale = Vector3.ONE * lerpf(0.35, 1.0, 1.0 - pow(1.0 - grown, 3.0))
	if _shimmer_left > 0.0 and is_instance_valid(_shimmer):
		_shimmer_left = maxf(0.0, _shimmer_left - delta)
		var t: float = 1.0 - _shimmer_left / SHIMMER_SECONDS
		# The glints climb a little over a metre and burn out; the item itself
		# reads a touch overbright while they do, settling as they go.
		_shimmer.visible = _shimmer_left > 0.0
		_shimmer.position.y = seat_y() + 0.1 + t * 0.9
		_shimmer.modulate = Color(SHIMMER_COLOR, (1.0 - t) * (1.0 - t))
		if is_instance_valid(icon) and pickup_kind != "golden_rail":
			icon.modulate = Color.WHITE.lerp(Color(1.5, 1.4, 1.2), (1.0 - t) * 0.8)
	if is_instance_valid(icon) and icon.visible:
		# Seated: the item rests on its pad and does not float.
		icon.position.y = _sprite_rest_y
	if dropped:
		_dropped_age += delta
		var left: float = DROPPED_SECONDS - _dropped_age
		if is_instance_valid(icon) and left < DROPPED_BLINK_SECONDS:
			# Four blinks a second (the sprite cuts out below half alpha);
			# reduced motion holds it steady and dimmed instead.
			var lit: bool = int(floor(left * 8.0)) % 2 == 0
			icon.modulate = Color(0.55, 0.55, 0.55) if reduced_motion else Color(1.0, 1.0, 1.0, 1.0 if lit else 0.0)

## Begin the return shimmer (the server just brought this pad back).
func _start_shimmer() -> void:
	if _shimmer == null:
		_shimmer = Sprite3D.new()
		_shimmer.name = "Shimmer"
		_shimmer.texture = _shimmer_texture_get()
		_shimmer.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_shimmer.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_shimmer.shaded = false
		_shimmer.transparent = true
		_shimmer.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		_shimmer.pixel_size = 1.0 / 16.0
		_shimmer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shimmer)
	_shimmer_left = SHIMMER_SECONDS
	_shimmer.visible = true
	_shimmer.position = Vector3(0.0, seat_y() + 0.1, 0.0)

## Twelve by twenty-four texels of scattered glints: one shared texture.
static func _shimmer_texture_get() -> Texture2D:
	if _shimmer_texture != null:
		return _shimmer_texture
	var image: Image = Image.create(12, 24, false, Image.FORMAT_RGBA8)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 6731
	for i: int in range(26):
		var x: int = random.randi_range(1, 10)
		var y: int = random.randi_range(0, 23)
		var bright: float = 0.55 + 0.45 * float(i % 3) / 2.0
		image.set_pixel(x, y, Color(1.0, 1.0, 1.0, bright))
		if i % 4 == 0 and y > 0:
			image.set_pixel(x, y - 1, Color(1.0, 1.0, 1.0, bright * 0.6))
	_shimmer_texture = ImageTexture.create_from_image(image)
	return _shimmer_texture

## A soft ellipse in three stepped tones, darkest under the item.
static func _shadow_texture_get() -> Texture2D:
	if _shadow_texture != null:
		return _shadow_texture
	var image: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y: int in range(16):
		for x: int in range(16):
			var d: float = Vector2((float(x) - 7.5) / 7.5, (float(y) - 7.5) / 7.5).length()
			var alpha: float = 1.0 if d < 0.45 else (0.62 if d < 0.75 else (0.3 if d < 1.0 else 0.0))
			image.set_pixel(x, y, Color(0.02, 0.02, 0.025, alpha))
	_shadow_texture = ImageTexture.create_from_image(image)
	return _shadow_texture

## The contact shadow under the seated item, sized to its sprite.
func _place_shadow(width: float) -> void:
	if _shadow == null:
		_shadow = MeshInstance3D.new()
		_shadow.name = "ContactShadow"
		var quad: PlaneMesh = PlaneMesh.new()
		quad.size = Vector2.ONE
		_shadow.mesh = quad
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_texture = _shadow_texture_get()
		material.albedo_color = Color(1.0, 1.0, 1.0, CONTACT_SHADOW_ALPHA)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow.material_override = material
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shadow)
	var across: float = clampf(width * 0.8, 0.35, 1.3)
	_shadow.scale = Vector3(across, 1.0, minf(across, 0.7))
	_shadow.position = Vector3(0.0, seat_y() + 0.008, 0.0)

func _label_text() -> String:
	if pickup_kind == "ammo":
		return tr("PICKUP_AMMO").format({"amount": amount, "pool": EquipmentState.pool_name(ammo_pool).to_upper()})
	if pickup_kind == "health":
		return tr("PICKUP_MEDKIT") if amount <= 0 else tr("PICKUP_HEALTH").format({"amount": amount})
	if pickup_kind == "armor":
		return tr("PICKUP_ARMOR") if amount <= 0 else tr("PICKUP_ARMOR_AMOUNT").format({"amount": amount})
	if pickup_kind == "plate":
		return tr("PICKUP_PLATE")
	if pickup_kind == "grenade":
		return tr("PICKUP_GRENADES").format({"amount": amount})
	if pickup_kind == "proximity_mine":
		return tr("PICKUP_MINES").format({"amount": amount})
	if pickup_kind == "remote_mine":
		return tr("PICKUP_REMOTES").format({"amount": amount})
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
	if pickup_kind == "plate":
		return COLORS["plate"]
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
	if pickup_kind == "remote_mine":
		if _remote_body == null:
			_remote_body = RemoteMineEffects.make_body()
			_remote_body.name = "RemoteStock"
			_remote_body.scale = Vector3.ONE * 2.0
			_remote_body.rotation.y = PI / 6.0
			add_child(_remote_body)
		_remote_body.position.y = seat_y() + SPRITE_FLOOR_GAP
		_remote_body.visible = true
		_place_shadow(0.6)
		label.text = _label_text()
		body.visible = false
		ammo_band.visible = false
		label.visible = false
		icon.visible = false
		return
	if _remote_body != null:
		_remote_body.visible = false
	var texture: Texture2D = sprite_texture()
	var drawn: bool = texture != null
	var ammo: bool = pickup_kind == "ammo"
	var tint: Color = _tint()
	var seat: Vector3 = Vector3(0.0, seat_y(), 0.0)
	body.visible = not drawn
	body.mesh = _ammo_mesh if ammo else _regular_mesh
	body.position = (Vector3(0.0, AMMO_BODY_Y, 0.0) if ammo else _regular_body_position) + seat
	ammo_band.position.y = 0.21 + seat.y
	ammo_band.visible = ammo and not drawn
	# Only the golden Railgun keeps its name in the world; every other pickup
	# reads by its picture, and the corner feed names what was taken.
	label.visible = not drawn or pickup_kind == "golden_rail"
	label.text = _label_text()
	label.modulate = tint
	label.outline_modulate = Color(0.12, 0.11, 0.10)
	label.position = (Vector3(0.0, AMMO_LABEL_Y, 0.0) if ammo else _regular_label_position) + seat
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
		icon.pixel_size = WeaponArt.PICKUP_TEXEL_METRES * (PLATE_SCALE if pickup_kind == "plate" else 1.0)
		var half: float = float(texture.get_height()) * icon.pixel_size * 0.5
		_sprite_rest_y = seat.y + SPRITE_FLOOR_GAP + half
		icon.position = Vector3(0.0, _sprite_rest_y, 0.0)
		icon.modulate = Color(1.6, 1.25, 0.45) if pickup_kind == "golden_rail" else Color.WHITE
		if pickup_kind == "golden_rail":
			label.position = Vector3(0.0, _sprite_rest_y + half + 0.35, 0.0)
		_place_shadow(float(texture.get_width()) * icon.pixel_size)
	else:
		_place_shadow(0.9)
