extends Node3D
class_name ViewLight

## The light at the first-person eye.
##
## Two jobs, one node under the view camera. It owns the muzzle light a
## shooter sees from their own gun: a short warm pulse that lights the floor,
## the near wall and anyone standing in front of the barrel, the way a shot
## does in Dusk or Boltgun. The third-person flash on the pawn cannot do this,
## because the local body is hidden in first person and its light goes with
## it. And it measures the light arriving at the held gun, so the viewmodel
## (a 2D sprite drawn over the world) can take the room's colour: warmer under
## a sodium lamp, darker in a covered bay, a beat brighter when the gun fires.
## `sample` is that measurement as a modulate colour.
##
## Presentation only. The light starts on the same local fire receipt as the
## viewmodel kick (or the followed fighter's resolved shot), and a rejected
## speculative shot cancels it with the rest of the fire feedback.

const NODE_NAME: String = "ViewLight"
const MUZZLE_NAME: String = "ViewMuzzleLight"
## Just past the viewmodel's barrel, right of centre and below the eye, so the
## pulse falls on the floor ahead and the near wall rather than on the lens.
const MUZZLE_OFFSET: Vector3 = Vector3(0.18, -0.22, -0.8)
## Where the held gun sits, for the measurement.
const GUN_OFFSET: Vector3 = Vector3(0.15, -0.25, -0.45)

## Per gun: colour, peak energy, reach in metres and how long the pulse lasts.
## Warm amber to warm white for powder, a near-white for the Rail's
## accelerator. Never red (the Union's attack tell) and never cyan (the
## Inheritance's working light). Fast guns burn dimmer so a held trigger is a
## flicker on the floor, not a strobe. Blades and fists make no light.
const FLASHES: Dictionary[String, Dictionary] = {
	"tack": {"colour": Color("ffc27a"), "energy": 4.0, "range": 7.0, "seconds": 0.07},
	"flechette": {"colour": Color("ffcd88"), "energy": 3.0, "range": 6.5, "seconds": 0.05},
	"repeater": {"colour": Color("ffc98a"), "energy": 2.2, "range": 6.0, "seconds": 0.04},
	"scatter": {"colour": Color("ffa255"), "energy": 6.0, "range": 9.5, "seconds": 0.09},
	"sniper": {"colour": Color("ffd6a0"), "energy": 4.5, "range": 8.0, "seconds": 0.06},
	"rocket": {"colour": Color("ffb066"), "energy": 5.0, "range": 9.0, "seconds": 0.12},
	"rail": {"colour": Color("eef1ee"), "energy": 5.0, "range": 10.0, "seconds": 0.12},
	"arc": {"colour": Color("fff0c4"), "energy": 2.6, "range": 6.5, "seconds": 0.05},
}
## Accessibility "screen flashes": Full, Reduced, Off (FragrSettings order).
## The muzzle light changes the whole near view, so it follows that choice.
const FLASH_SCALE: Array[float] = [1.0, 0.6, 0.0]
## The pulse holds full brightness for its first 1 - 1/FLASH_HOLD (40 percent)
## and fades linearly over the rest.
const FLASH_HOLD: float = 1.6

## The measurement maps incident light to a modulate. REFERENCE is the light
## that leaves the drawn art as authored: Recall Notice's night street under
## its canopy lamp measures about 1.3, a Larak deck under the city glow about
## 1.0 (a touch darker), the intake bay under its strips about 2.1 (the
## brightest the clamp allows). The square root and the clamp keep
## the gun readable in the darkest corner and unbleached under a lamp, and
## only part of the light's hue reaches the sprite: a sodium lamp warms the
## gun, it does not paint it orange.
const REFERENCE: float = 1.2
const MIN_BRIGHT: float = 0.6
const MAX_BRIGHT: float = 1.12
const CHROMA: float = 0.4
## A directional key behind a roof or wall still reaches the gun a little as
## bounce.
const KEY_WEIGHT: float = 0.5
const KEY_OCCLUDED: float = 0.15
## How much of the muzzle pulse reaches the gun's own sprite.
const FLASH_WEIGHT: float = 0.3
const SAMPLE_SECONDS: float = 0.1
const SMOOTH_RATE: float = 8.0
## How far toward the key light a solid can block it, in metres.
const OCCLUSION_REACH: float = 40.0

## The current modulate for the held gun; read it through `sample`.
var tint: Color = Color.WHITE
## The map's solids from MapInfo, used only to tell whether the key is blocked.
var solids: Array = []

var _muzzle: OmniLight3D = null
var _flash_colour: Color = Color.WHITE
var _flash_peak: float = 0.0
var _flash_seconds: float = 0.0
var _flash_left: float = 0.0
var _lights: Array[Light3D] = []
var _incident: Color = Color(-1.0, -1.0, -1.0)
var _since_sample: float = INF

## The ViewLight under this camera, created on first use.
static func attach(camera: Camera3D) -> ViewLight:
	if camera == null:
		return null
	var view: ViewLight = camera.get_node_or_null(NODE_NAME) as ViewLight
	if view == null:
		view = ViewLight.new()
		view.name = NODE_NAME
		camera.add_child(view)
	return view

## Fire this gun's muzzle light at the eye. `flashes` is the accessibility
## screen-flash choice. Returns whether a light was started.
static func flash(camera: Camera3D, weapon: String, flashes: int = 0) -> bool:
	var view: ViewLight = attach(camera)
	return view != null and view.fire(weapon, flashes)

## A rejected or abandoned local shot puts its light out at once.
static func cancel(camera: Camera3D) -> void:
	if camera == null:
		return
	var view: ViewLight = camera.get_node_or_null(NODE_NAME) as ViewLight
	if view != null:
		view.stop()

## The light at the held gun as a modulate for the viewmodel sprite: about
## white on an ordinary lit deck, warmer or cooler with the nearest lamps,
## darker in shade, and brighter for a moment when the gun fires. White when
## no view camera has a ViewLight yet, so a caller can always multiply by it.
static func sample(camera: Camera3D) -> Color:
	if camera == null:
		return Color.WHITE
	var view: ViewLight = camera.get_node_or_null(NODE_NAME) as ViewLight
	return view.current_tint() if view != null else Color.WHITE

static func weapon_key(weapon: String) -> String:
	return weapon.strip_edges().to_lower().replace(" ", "_")

## Incident light as a modulate. Pure, so the harness can pin the mapping.
static func tint_for(incident: Color) -> Color:
	var lum: float = maxf(incident.get_luminance(), 0.0)
	if lum <= 0.0001:
		return Color(MIN_BRIGHT, MIN_BRIGHT, MIN_BRIGHT, 1.0)
	var bright: float = clampf(sqrt(lum / REFERENCE), MIN_BRIGHT, MAX_BRIGHT)
	var hue: Color = Color(maxf(incident.r, 0.0) / lum, maxf(incident.g, 0.0) / lum, maxf(incident.b, 0.0) / lum, 1.0)
	var mixed: Color = Color.WHITE.lerp(hue, CHROMA)
	var scale: float = bright / maxf(mixed.get_luminance(), 0.0001)
	return Color(minf(mixed.r * scale, 1.6), minf(mixed.g * scale, 1.6), minf(mixed.b * scale, 1.6), 1.0)

## Godot's own omni falloff (scene_forward_lights_inc), so a lamp's share here
## matches what it paints on the wall beside the gun.
static func omni_attenuation(distance: float, reach: float, decay: float) -> float:
	if reach <= 0.0 or distance >= reach:
		return 0.0
	var nd: float = distance / reach
	nd = nd * nd
	nd = nd * nd
	nd = maxf(1.0 - nd, 0.0)
	return nd * nd * pow(maxf(distance, 0.0001), -decay)

## A MapInfo solid as a box, or an empty AABB when the entry is malformed.
static func solid_box(solid: Variant) -> AABB:
	if not solid is Dictionary:
		return AABB()
	var box: Dictionary = solid
	for key: String in ["min_x", "max_x", "min_z", "max_z"]:
		if not (box.get(key) is float or box.get(key) is int):
			return AABB()
	for key: String in ["top", "bottom"]:
		if box.has(key) and not (box[key] is float or box[key] is int):
			return AABB()
	var low: Vector3 = Vector3(float(box["min_x"]), MoveStep.solid_bottom(box), float(box["min_z"]))
	var high: Vector3 = Vector3(float(box["max_x"]), MoveStep.solid_top(box), float(box["max_z"]))
	return AABB(low, high - low)

## Whether anything solid stands between `point` and a light shining from
## `toward_light` (a unit vector pointing at the light), within reach.
static func key_blocked(point: Vector3, toward_light: Vector3, map_solids: Array) -> bool:
	var reach: Vector3 = toward_light.normalized() * OCCLUSION_REACH
	for solid: Variant in map_solids:
		var box: AABB = solid_box(solid)
		if box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0 \
			and not box.has_point(point) and box.intersects_segment(point, point + reach):
			return true
	return false

## The light reaching `point`: the flat ambient floor, each directional key
## (dimmed when a solid blocks it) and every omni or spot lamp in reach.
static func incident_at(point: Vector3, environment: Environment, lights: Array[Light3D], map_solids: Array) -> Color:
	var total: Color = Color(0.5, 0.5, 0.5, 1.0)
	var exposure: float = 1.0
	if environment != null:
		total = environment.ambient_light_color * environment.ambient_light_energy
		exposure = environment.tonemap_exposure
	for light: Light3D in lights:
		if not is_instance_valid(light) or not light.is_visible_in_tree() or light.light_energy <= 0.0:
			continue
		var share: float = 0.0
		if light is DirectionalLight3D:
			var toward: Vector3 = light.global_transform.basis.z.normalized()
			share = KEY_WEIGHT * (KEY_OCCLUDED if key_blocked(point, toward, map_solids) else 1.0)
		elif light is OmniLight3D:
			var omni: OmniLight3D = light
			share = omni_attenuation(point.distance_to(omni.global_position), omni.omni_range, omni.omni_attenuation)
		elif light is SpotLight3D:
			var spot: SpotLight3D = light
			var offset: Vector3 = point - spot.global_position
			var aim: Vector3 = -spot.global_transform.basis.z.normalized()
			if offset.length() > 0.0001 and rad_to_deg(aim.angle_to(offset.normalized())) <= spot.spot_angle:
				share = omni_attenuation(offset.length(), spot.spot_range, spot.spot_attenuation)
		if share > 0.0:
			total += light.light_color * (light.light_energy * share)
	total = total * exposure
	total.a = 1.0
	return total

func _enter_tree() -> void:
	var tree: SceneTree = get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
		tree.node_removed.connect(_on_node_removed)
	_lights.clear()
	for node: Node in tree.root.find_children("*", "Light3D", true, false):
		_on_node_added(node)

func _exit_tree() -> void:
	var tree: SceneTree = get_tree()
	if tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)
		tree.node_removed.disconnect(_on_node_removed)
	_lights.clear()

func _ready() -> void:
	_muzzle = OmniLight3D.new()
	_muzzle.name = MUZZLE_NAME
	_muzzle.position = MUZZLE_OFFSET
	_muzzle.shadow_enabled = false
	_muzzle.light_specular = 0.25
	_muzzle.omni_attenuation = 1.2
	_muzzle.light_energy = 0.0
	_muzzle.visible = false
	# This node sits at the camera's origin, so the light rides the view.
	add_child(_muzzle)

func set_solids(map_solids: Variant) -> void:
	solids = map_solids if map_solids is Array else []
	_since_sample = INF

func fire(weapon: String, flashes: int = 0) -> bool:
	var spec: Variant = FLASHES.get(weapon_key(weapon))
	var scale: float = FLASH_SCALE[clampi(flashes, 0, FLASH_SCALE.size() - 1)]
	if not spec is Dictionary or scale <= 0.0:
		return false
	_flash_colour = spec["colour"]
	_flash_peak = float(spec["energy"]) * scale
	_flash_seconds = float(spec["seconds"])
	_flash_left = _flash_seconds
	if _muzzle != null:
		_muzzle.light_color = _flash_colour
		_muzzle.omni_range = float(spec["range"])
		_muzzle.light_energy = _flash_peak
		_muzzle.visible = true
	return true

func stop() -> void:
	_flash_left = 0.0
	if _muzzle != null:
		_muzzle.light_energy = 0.0
		_muzzle.visible = false

## The muzzle light's current energy, zero when dark. It holds full for the
## first part of the pulse, so the frame that shows the muzzle flash is lit at
## full strength on any frame rate, then falls away.
func flash_energy() -> float:
	if _flash_left <= 0.0 or _flash_seconds <= 0.0:
		return 0.0
	return _flash_peak * minf(1.0, FLASH_HOLD * _flash_left / _flash_seconds)

func current_tint() -> Color:
	return tint

func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		if _muzzle != null:
			_muzzle.light_energy = flash_energy()
			_muzzle.visible = _flash_left > 0.0
	_since_sample += delta
	var camera: Camera3D = get_parent() as Camera3D
	if camera == null:
		return
	if _since_sample >= SAMPLE_SECONDS:
		_since_sample = 0.0
		var measured: Color = incident_at(camera.global_transform * GUN_OFFSET, _environment(camera), _lights, solids)
		if _incident.r < 0.0:
			_incident = measured
		else:
			_incident = _incident.lerp(measured, 1.0 - exp(-SMOOTH_RATE * SAMPLE_SECONDS))
	if _incident.r < 0.0:
		return
	var lit: Color = _incident + _flash_colour * (flash_energy() * FLASH_WEIGHT)
	tint = tint_for(lit)

func _environment(camera: Camera3D) -> Environment:
	if camera.environment != null:
		return camera.environment
	var world: World3D = camera.get_world_3d()
	return world.environment if world != null else null

func _on_node_added(node: Node) -> void:
	if not node is Light3D or node == _muzzle or node.name == ArenaSky.VIEW_FILL:
		return
	_lights.append(node as Light3D)

func _on_node_removed(node: Node) -> void:
	if node is Light3D:
		_lights.erase(node as Light3D)
