class_name ArenaSabotage
extends Node3D

## Sabotage in the world: a floating sprite plate and objective prop at each
## site, a dashed plant ring on the floor, and the charge: carried at the
## carrier's side, lying where it fell, or planted with its timer light,
## beep and hum. Every position comes from the authoritative snapshot; this
## node decides nothing and has no collision.

const PLATE_HEIGHT: float = 3.6
## World sizes in metres, so final art of any pixel size keeps them.
const PLATE_WIDTH: float = 1.6
const PROP_HEIGHT: float = 2.24
const CHARGE_WIDTH: float = 0.512
const CARRIED_WIDTH: float = 0.352
const LIGHT_WIDTH: float = 0.128
## The burst grows from this to the end width over its life.
const BURST_START: float = 3.84
const BURST_END: float = 19.2
## The body sprite centre, where the CTF grip also sits.
const CARRIED_HAND_Y: float = -0.6
const CARRIED_SIDE: float = -0.2
const CARRIED_FRONT: float = 0.4
## The charge is heard this far away, and its glow reaches this far.
const HUM_DISTANCE: float = 10.0
const BEEP_DISTANCE: float = 60.0
const LIGHT_RANGE: float = 3.0
const BURST_SECONDS: float = 0.9

var _layout: Dictionary = {}
var _sites: Array[Node3D] = []
var _charge: Node3D = null
var _charge_sprite: Sprite3D = null
var _charge_light: Sprite3D = null
var _glow: OmniLight3D = null
var _hum: AudioStreamPlayer3D = null
var _beep: AudioStreamPlayer3D = null
var _cue: AudioStreamPlayer3D = null
var _burst: Sprite3D = null
var _burst_light: OmniLight3D = null
var _burst_left: float = 0.0
var _carrier: Node3D = null
var _status: String = ""
var _beep_due: int = -1
var _charge_ticks: int = 700
var _blink: float = 0.0
var _working: bool = false
## The enemy of the carrier: no charge sprite on the carrier, but its glow and
## hum still give the carrier away up close.
var _sprite_hidden: bool = false
## The view's own pawn when it looks through that pawn's eyes.
var _first_person: String = ""


func _init() -> void:
	# Seat a carried charge after the pawns move this frame.
	process_priority = 10


func clear_layout() -> void:
	for node: Node3D in _sites:
		if is_instance_valid(node):
			node.queue_free()
	_sites.clear()
	_layout = {}
	_status = ""
	_beep_due = -1
	if _charge != null:
		_charge.visible = false
	if _hum != null:
		_hum.stop()


## The static layout from `map_info.sabotage`; empty removes everything.
func set_layout(layout: Dictionary) -> void:
	clear_layout()
	if layout.is_empty():
		return
	_layout = layout
	for site: Dictionary in layout.get("sites", []):
		var id: String = str(site.get("id", "a"))
		var center: Array = site.get("center", [0.0, 0.0, 0.0])
		var root: Node3D = Node3D.new()
		root.name = "Site" + id.to_upper()
		root.position = Vector3(float(center[0]), float(center[1]), float(center[2]))
		add_child(root)
		var ring_art: Texture2D = SabotageArt.plant_ring()
		var ring: Sprite3D = _sprite(ring_art, float(site.get("radius", 3.0)) * 2.0 / float(ring_art.get_width()))
		ring.name = "Ring"
		ring.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		ring.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		ring.position = Vector3(0.0, 0.03, 0.0)
		root.add_child(ring)
		var prop_art: Texture2D = SabotageArt.site_prop(id)
		var prop: Sprite3D = _sprite(prop_art, PROP_HEIGHT / float(prop_art.get_height()))
		prop.name = "Prop"
		prop.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		prop.position = Vector3(0.0, PROP_HEIGHT * 0.5, 0.0)
		root.add_child(prop)
		var plate_art: Texture2D = SabotageArt.site_plate(id)
		var plate: Sprite3D = _sprite(plate_art, PLATE_WIDTH / float(plate_art.get_width()))
		plate.name = "Plate"
		plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		plate.position = Vector3(0.0, PLATE_HEIGHT, 0.0)
		root.add_child(plate)
		_sites.append(root)
	_ensure_charge()


static func _charge_pixel(width: float) -> float:
	return width / float(SabotageArt.charge().get_width())


func set_charge_ticks(ticks: int) -> void:
	_charge_ticks = maxi(ticks, 1)


func set_first_person(player_id: String) -> void:
	_first_person = player_id


static func _sprite(texture: Texture2D, pixel: float) -> Sprite3D:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = pixel
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.layers = ArenaSky.WORLD_LAYERS
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	return sprite


static func _voice(label: String, stream: AudioStream, distance: float, volume_db: float) -> AudioStreamPlayer3D:
	var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	voice.name = label
	voice.stream = stream
	voice.bus = &"Effects"
	voice.max_distance = distance
	voice.unit_size = 6.0
	voice.volume_db = volume_db
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	return voice


func _ensure_charge() -> void:
	if _charge != null:
		return
	_charge = Node3D.new()
	_charge.name = "Charge"
	_charge.visible = false
	add_child(_charge)
	_charge_sprite = _sprite(SabotageArt.charge(), _charge_pixel(CHARGE_WIDTH))
	_charge_sprite.name = "Body"
	_charge_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_charge_sprite.position = Vector3(0.0, 0.2, 0.0)
	_charge.add_child(_charge_sprite)
	_charge_light = _sprite(SabotageArt.charge_light(SabotageArt.LIT), LIGHT_WIDTH / 4.0)
	_charge_light.name = "Light"
	_charge_light.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_charge_light.position = Vector3(0.0, 0.33, 0.01)
	_charge_light.render_priority = 1
	_charge.add_child(_charge_light)
	_glow = OmniLight3D.new()
	_glow.name = "Glow"
	_glow.light_color = SabotageArt.LIT
	_glow.omni_range = LIGHT_RANGE
	_glow.light_energy = 0.0
	_glow.position = Vector3(0.0, 0.4, 0.0)
	_charge.add_child(_glow)
	_hum = _voice("Hum", SabotageAudio.hum(), HUM_DISTANCE, -6.0)
	_charge.add_child(_hum)
	_beep = _voice("Beep", SabotageAudio.beep(), BEEP_DISTANCE, 0.0)
	_charge.add_child(_beep)
	_cue = _voice("Cue", SabotageAudio.arm(), BEEP_DISTANCE, 0.0)
	_charge.add_child(_cue)
	_burst = _sprite(SabotageArt.burst(), BURST_START / float(SabotageArt.burst().get_width()))
	_burst.name = "Burst"
	_burst.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_burst.visible = false
	_burst.position = Vector3(0.0, 1.2, 0.0)
	_charge.add_child(_burst)
	_burst_light = OmniLight3D.new()
	_burst_light.name = "BurstLight"
	_burst_light.light_color = SabotageArt.EMBER
	_burst_light.omni_range = 26.0
	_burst_light.light_energy = 0.0
	_burst_light.position = Vector3(0.0, 1.5, 0.0)
	_charge.add_child(_burst_light)


## One validated snapshot's round. `carriers` maps player id to pawn node.
## `viewer_team` is the joined fighter's side, or empty for a spectator.
func apply(state: Dictionary, carriers: Dictionary, viewer_team: String) -> void:
	if _layout.is_empty():
		return
	_ensure_charge()
	var charge: Variant = state.get("charge")
	if not charge is Dictionary:
		_charge.visible = false
		_hum.stop()
		_status = ""
		return
	var status: String = str(charge.get("status", ""))
	var position: Array = charge.get("position", [0.0, 0.0, 0.0])
	var carrier_id: String = str(charge.get("carrier", ""))
	var pawn: Variant = carriers.get(carrier_id)
	var progress: Variant = state.get("progress")
	_working = progress is Dictionary
	_carrier = pawn if status == "carried" and pawn is Node3D and is_instance_valid(pawn) else null
	var hidden_carry: bool = status == "carried" and (carrier_id == _first_person or _carrier == null)
	_sprite_hidden = status == "carried" and not SabotageState.shows_carrier(viewer_team)
	_charge.visible = not hidden_carry and status != "detonated"
	_charge_sprite.pixel_size = _charge_pixel(CARRIED_WIDTH if status == "carried" else CHARGE_WIDTH)
	_charge_sprite.layers = ArenaSky.ACTOR_LAYERS if status == "carried" else ArenaSky.WORLD_LAYERS
	_charge_light.layers = _charge_sprite.layers
	if _carrier == null:
		_charge.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	if status != _status:
		_on_status(status)
	_status = status
	# The hum carries ten metres for everyone, the carrier's own ears included.
	var audible: bool = status in ["carried", "dropped", "planted"] and (_carrier != null or status != "carried")
	if audible and not _hum.playing:
		_hum.play()
	elif not audible and _hum.playing:
		_hum.stop()
	if status == "planted":
		var remaining: int = int(state.get("clock_ticks", 0))
		if _beep_due < 0:
			_beep_due = SabotageAudio.next_beep(remaining + 1)
		if remaining <= _beep_due:
			_beep.pitch_scale = SabotageAudio.beep_pitch(float(remaining) / float(_charge_ticks))
			_beep.play()
			_blink = 0.15
			_beep_due = SabotageAudio.next_beep(remaining)
	else:
		_beep_due = -1


func _on_status(status: String) -> void:
	match status:
		"planted":
			_cue.stream = SabotageAudio.planted()
			_cue.play()
			_charge_light.texture = SabotageArt.charge_light(SabotageArt.LIT)
		"defused":
			_cue.stream = SabotageAudio.defused()
			_cue.play()
			_charge_light.texture = SabotageArt.charge_light(SabotageArt.GREEN)
			_glow.light_color = SabotageArt.GREEN
		"detonated":
			_cue.stream = SabotageAudio.detonation()
			_cue.unit_size = 30.0
			_cue.max_distance = 400.0
			_cue.play()
			_burst_left = BURST_SECONDS
		_:
			_charge_light.texture = SabotageArt.charge_light(SabotageArt.LIT)
			_glow.light_color = SabotageArt.LIT
			_cue.unit_size = 6.0
			_cue.max_distance = BEEP_DISTANCE


## A plant or defuse started: two clicks at the charge everyone can hear.
func play_arm_cue() -> void:
	if _cue == null:
		return
	_cue.stream = SabotageAudio.arm()
	_cue.play()


func _process(delta: float) -> void:
	if _charge == null:
		return
	if _carrier != null and is_instance_valid(_carrier):
		var view: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
		var side: Vector3 = -_carrier.global_transform.basis.z
		var front: Vector3 = _carrier.global_transform.basis.x
		if view != null:
			side = view.global_transform.basis.x
			var to_view: Vector3 = view.global_position - _carrier.global_position
			to_view.y = 0.0
			if to_view.length_squared() > 0.04:
				front = to_view.normalized()
		side.y = 0.0
		front.y = 0.0
		_charge.global_position = _carrier.global_position + Vector3(0.0, CARRIED_HAND_Y, 0.0) \
			+ side.normalized() * CARRIED_SIDE + front.normalized() * CARRIED_FRONT
	_blink = maxf(_blink - delta, 0.0)
	var lit: bool = _blink > 0.0 or (_status == "planted" and _working) or _status == "defused"
	if _status in ["carried", "dropped"]:
		lit = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.15
	_charge_light.visible = lit and not _sprite_hidden
	_glow.light_energy = 1.4 if lit else (0.25 if _status == "planted" else 0.0)
	if _burst_left > 0.0:
		_burst_left = maxf(_burst_left - delta, 0.0)
		var t: float = 1.0 - _burst_left / BURST_SECONDS
		_burst.visible = _burst_left > 0.0
		_burst.pixel_size = lerpf(BURST_START, BURST_END, t) / float(_burst.texture.get_width())
		_burst.modulate = Color(1.0, 1.0, 1.0, 1.0 - t * t)
		_burst_light.light_energy = 14.0 * (1.0 - t)
		_charge.visible = true
		_charge_sprite.visible = false
		_charge_light.visible = false
	else:
		_burst.visible = false
		_burst_light.light_energy = 0.0
		_charge_sprite.visible = not _sprite_hidden
		if _status == "detonated":
			_charge.visible = false
