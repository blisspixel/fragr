class_name M18Square
extends Node3D

## All Systems Normal's recovery square on an ordinary morning
## (docs/campaign/l18-all-systems-normal.md): Low Water's people rebuilding
## across town. The server owns every solid; this furnishes them: plastered
## and glazed fronts open for business, the stalls under their striped
## awnings with goods and a string of bulbs, the tram stalled on its rails
## while its motor comes, the clinic's lamp on the route, the overlook's tower
## on the skyline above the service stairs, a district far off past it, the
## square's people at their stalls and the rubble work's machinery noise.
##
## The turn is a server fact (`m18.turn_started`); the transit presenter
## hands this its age in ticks. When everything stops the work noise stops
## dead, the bulbs and the clinic's lamp go out together
## and the people stand still. When the heads come round, the tram's lamps,
## the tower's lamp and the far district's windows come on in the
## Inheritance's working light and carry the depot rhythm with the machines.
## After it the square's people leave by the corners and the infrastructure
## keeps the rhythm. Nothing here collides, stops a shot, carries words or
## decides anything: a late join past the turn sees only its after.

const TownDressing = preload("res://scripts/low_water_dressing.gd")
const Geometry = preload("res://scripts/model_geometry.gd")
const MAP_ID: int = 1018
## The authored solids this dressing needs, exactly: the stalled tram, the
## overlook's tower, the square's north wall and the first stall.
const ANCHORS: Array = [
	[Vector3(-31, 0, -22.5), Vector3(-22, 3.2, -19.5)],
	[Vector3(22, 0, 26), Vector3(26, 18, 28)],
	[Vector3(-60, 0, 24), Vector3(-20, 6, 26)],
	[Vector3(-53, 0, 19.8), Vector3(-49, 1, 21.3)],
]
const TRAM_LOW: Vector3 = Vector3(-31, 0, -22.5)
const TRAM_HIGH: Vector3 = Vector3(-22, 3.2, -19.5)
const TOWER_LOW: Vector3 = Vector3(22, 0, 26)
const TOWER_HIGH: Vector3 = Vector3(26, 18, 28)
## Shopfronts, homes over them, the depot and the aid post, and the clinic
## street's two fronts, in TownDressing's face shapes.
const FACES: Array[Dictionary] = [
	{"low": Vector3(-60, 0, 24), "high": Vector3(-20, 6, 26), "face": "north", "paint": 0, "ground": "shops"},
	{"low": Vector3(-60, 0, -26), "high": Vector3(-20, 6, -24), "face": "south", "paint": 3, "ground": "doors"},
	{"low": Vector3(-70, 0, -70), "high": Vector3(-60, 9, 70), "face": "east", "paint": 5, "ground": "doors", "span": Vector2(-24, 24)},
	{"low": Vector3(-42, 0, 8), "high": Vector3(-32, 4.5, 20), "face": "north", "paint": 2, "ground": "shops"},
	{"low": Vector3(-42, 0, 8), "high": Vector3(-32, 4.5, 20), "face": "west", "paint": 4, "ground": "doors"},
	{"low": Vector3(-42, 0, 8), "high": Vector3(-32, 4.5, 20), "face": "east", "paint": 4, "ground": "doors"},
	{"low": Vector3(-42, 0, 8), "high": Vector3(-32, 4.5, 20), "face": "south", "paint": 2, "ground": "doors"},
	{"low": Vector3(-44, 0, -18), "high": Vector3(-34, 3.5, -8), "face": "south", "paint": 1, "ground": "shops"},
	{"low": Vector3(-44, 0, -18), "high": Vector3(-34, 3.5, -8), "face": "east", "paint": 1, "ground": "doors"},
	{"low": Vector3(-44, 0, -18), "high": Vector3(-34, 3.5, -8), "face": "west", "paint": 1, "ground": "doors"},
	{"low": Vector3(-20, 0, 10), "high": Vector3(6, 6, 14), "face": "north", "paint": 6, "ground": "doors"},
	{"low": Vector3(-20, 0, 10), "high": Vector3(6, 6, 14), "face": "west", "paint": 6, "ground": "shops"},
	{"low": Vector3(-20, 0, -14), "high": Vector3(6, 6, -10), "face": "south", "paint": 1, "ground": "shops"},
	{"low": Vector3(-20, 0, -14), "high": Vector3(6, 6, -10), "face": "west", "paint": 1, "ground": "doors"},
]
const AWNINGS: Array[Dictionary] = [
	{"low": Vector3(-54, 2.6, 19), "high": Vector3(-48, 2.8, 23)},
	{"low": Vector3(-48, 2.6, 19), "high": Vector3(-42, 2.8, 23)},
	{"low": Vector3(-58, 2.6, -19), "high": Vector3(-52, 2.8, -15)},
	{"low": Vector3(-52, 2.6, -19), "high": Vector3(-46, 2.8, -15)},
]
## Each stall's counter, and the side its keeper stands (+1 behind it on +Z).
const STALLS: Array[Dictionary] = [
	{"low": Vector3(-53, 0, 19.8), "high": Vector3(-49, 1, 21.3), "keeper": 1.0, "goods": "produce"},
	{"low": Vector3(-47, 0, 19.8), "high": Vector3(-43, 1, 21.3), "keeper": 1.0, "goods": "parts"},
	{"low": Vector3(-57, 0, -17.3), "high": Vector3(-53, 1, -15.8), "keeper": -1.0, "goods": "bread"},
	{"low": Vector3(-51, 0, -17.3), "high": Vector3(-47, 1, -15.8), "keeper": -1.0, "goods": "cloth"},
]
## Where the square's people go when it is over: the corners the server's
## supervisor runs to (`people_exits`), round the stalls.
const EXIT_NORTH: Vector3 = Vector3(-58.5, 0, 23.0)
const EXIT_SOUTH: Vector3 = Vector3(-58.5, 0, -22.8)
## Ticks into the turn, mirrored from M18Transit (protocol/m18.rs).
const HEADS_TURN_TICKS: int = 10
const TURN_TICKS: int = 60
const TICK_SECONDS: float = 0.05
const WALK_SPEED: float = 2.6
const BULB: Color = Color("ffd59a")
const CLINIC: Color = Color("6fbf86")
const TOWER_LAMP: Color = Color("e8b060")
const STONE: Color = Color("8a857a")

enum Stage { MORNING, STOPPED, SIGNAL, AFTER }

var town: RefCounted = null
var stage: Stage = Stage.MORNING
## Seconds since the heads came round, carried between snapshots.
var signal_seconds: float = 0.0
var people: Array[CivilianFigure] = []
var _routes: Array = []
var bulbs: Array[MeshInstance3D] = []
var _stall_lights: Array[OmniLight3D] = []
var _clinic: Array[MeshInstance3D] = []
var _clinic_light: OmniLight3D = null
var tram_lamps: Array[MeshInstance3D] = []
var _tower_lamp: MeshInstance3D = null
var _tower_light: OmniLight3D = null
var far_windows: Array[MeshInstance3D] = []
var _work_noise: Array[AudioStreamPlayer3D] = []
var _stop_noise: AudioStreamPlayer3D = null
var _materials: Dictionary[String, StandardMaterial3D] = {}
## How far along its way out each person is, by index.
var _routes_progress: Dictionary[int, int] = {}

static func authored(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != MAP_ID or not info.get("solids") is Array:
		return false
	for pair: Array in ANCHORS:
		if TownDressing._find(info["solids"], pair[0], pair[1]).is_empty():
			return false
	return true

func active() -> bool:
	return town != null

func clear() -> void:
	town = null
	people.clear()
	_routes_progress.clear()
	_routes.clear()
	bulbs.clear()
	_stall_lights.clear()
	_clinic.clear()
	_clinic_light = null
	tram_lamps.clear()
	_tower_lamp = null
	_tower_light = null
	far_windows.clear()
	_work_noise.clear()
	_stop_noise = null
	stage = Stage.MORNING
	signal_seconds = 0.0
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func configure(info: Dictionary) -> bool:
	clear()
	if not authored(info):
		return false
	town = TownDressing.new()
	town.mood = "morning"
	town.layout = {"faces": FACES, "awnings": AWNINGS, "tanks": [], "trams": [], "planters": [], "wells": [],
		"roofs": [], "aerials": [], "lamps": [], "rails": []}
	town.build(self, info)
	_build_rails()
	for index: int in range(STALLS.size()):
		_build_stall(STALLS[index], AWNINGS[index], index)
	_build_tram_lamps()
	_build_clinic_lamp()
	_build_tower()
	_build_district()
	_build_people()
	_build_noise()
	ArenaSky.mark_world(self)
	for figure: CivilianFigure in people:
		_actor_layers(figure)
	_apply_stage(Stage.MORNING)
	return true

## A retry starts the morning over.
func reset() -> void:
	if not active():
		return
	signal_seconds = 0.0
	for index: int in range(people.size()):
		var figure: CivilianFigure = people[index]
		figure.visible = true
		figure.place_feet(_routes[index][0])
		figure.rotation.y = float(_routes[index][1])
	_routes_progress.clear()
	_apply_stage(Stage.MORNING)
	for player: AudioStreamPlayer3D in _work_noise:
		if player.stream != null and player.is_inside_tree() and not player.playing:
			player.play()

## One step of the turn at `age` ticks. `staged` is false for a client that
## first saw the level already past the turn: it gets the after, silently.
func present(age: int, staged: bool) -> void:
	if not active() or age < 0:
		return
	if not staged:
		signal_seconds = maxf(signal_seconds, float(age - HEADS_TURN_TICKS) * TICK_SECONDS)
		if stage != Stage.AFTER:
			for figure: CivilianFigure in people:
				figure.visible = false
			_apply_stage(Stage.AFTER)
		return
	var wanted: Stage = Stage.STOPPED
	if age >= TURN_TICKS:
		wanted = Stage.AFTER
	elif age >= HEADS_TURN_TICKS:
		wanted = Stage.SIGNAL
	if age >= HEADS_TURN_TICKS:
		# The snapshot clock is the beat; _process carries it between ticks.
		signal_seconds = float(age - HEADS_TURN_TICKS) * TICK_SECONDS
	if wanted != stage:
		if stage == Stage.MORNING and _stop_noise != null and _stop_noise.stream != null and _stop_noise.is_inside_tree():
			_stop_noise.play()
		_apply_stage(wanted)
	elif stage in [Stage.SIGNAL, Stage.AFTER]:
		_pulse()

func _process(delta: float) -> void:
	if not active():
		return
	if stage in [Stage.SIGNAL, Stage.AFTER]:
		signal_seconds += delta
		_pulse()
	if stage == Stage.AFTER:
		_walk_people(delta)

func _apply_stage(next: Stage) -> void:
	stage = next
	var morning: bool = next == Stage.MORNING
	for bulb: MeshInstance3D in bulbs:
		bulb.material_override = _glow("bulb", BULB, 3.0) if morning else _lit("bulb_dark", Color("4a443a"))
	for light: OmniLight3D in _stall_lights:
		light.visible = morning
	for part: MeshInstance3D in _clinic:
		part.material_override = _glow("clinic", CLINIC, 2.2) if morning else _lit("clinic_dark", Color("2c3a32"))
	if _clinic_light != null:
		_clinic_light.visible = morning
	if _tower_lamp != null:
		_tower_lamp.material_override = _glow("tower", TOWER_LAMP, 2.4) if morning else _lit("tower_dark", Color("3a3630"))
	if _tower_light != null:
		_tower_light.visible = morning
	if not morning:
		for player: AudioStreamPlayer3D in _work_noise:
			player.stop()
	if next in [Stage.SIGNAL, Stage.AFTER]:
		_pulse()
	else:
		for part: MeshInstance3D in tram_lamps + far_windows:
			part.visible = false

## The depot rhythm on the Inheritance's working light, the same clock as the
## absorbed bots' optics (EnemyView.signal_window). After the turn the tram
## and the tower hold it steady and the far district keeps repeating it.
func _pulse() -> void:
	var lit: bool = M08Archive.noise_lit(signal_seconds)
	var holding: bool = stage == Stage.AFTER
	for part: MeshInstance3D in tram_lamps:
		part.visible = holding or lit
		part.material_override = _glow("work_steady", EnemyView.WORK_GLOW, 1.2) if holding else _glow("work_lit", EnemyView.WORK_GLOW, 2.6)
	if _tower_lamp != null:
		_tower_lamp.material_override = _glow("work_steady", EnemyView.WORK_GLOW, 1.2) if holding or lit else _lit("tower_dark", Color("3a3630"))
	for window: MeshInstance3D in far_windows:
		window.visible = lit

# --- people -------------------------------------------------------------------

func _build_people() -> void:
	# Stallholders behind their counters, a shopper at the bread stall, and
	# Tern at the stalled tram with its crew's paperwork. Free agents keep
	# their own paint; the stall keepers' tape is their own colour.
	var cast: Array = [
		["free_human", Color("c09a3a"), Vector3(-51.0, 0, 22.2), PI, [EXIT_NORTH]],
		["free_synthetic", Color("5a7898"), Vector3(-45.0, 0, 22.2), PI, [Vector3(-45.0, 0, 23.0), EXIT_NORTH]],
		["free_human", Color("8a5aa0"), Vector3(-55.0, 0, -18.4), 0.0, [EXIT_SOUTH]],
		["free_synthetic", Color("b0663a"), Vector3(-49.0, 0, -18.4), 0.0, [EXIT_SOUTH]],
		["free_human", Color("5a8a6a"), Vector3(-53.6, 0, -14.6), PI, [Vector3(-45.5, 0, -14.0), Vector3(-45.5, 0, -19.6), EXIT_SOUTH]],
		["tern", Color("d0a040"), Vector3(-20.8, 0, -21.0), -PI * 0.5, [Vector3(-21.0, 0, -18.4), Vector3(-32.5, 0, -18.4), Vector3(-45.0, 0, -19.8), EXIT_SOUTH]],
	]
	for row: Array in cast:
		var figure: CivilianFigure = CivilianFigure.new()
		figure.name = "SquarePerson%d" % people.size()
		add_child(figure)
		figure.configure(str(row[0]), row[1])
		figure.place_feet(row[2])
		figure.rotation.y = float(row[3])
		people.append(figure)
		_routes.append([row[2], float(row[3]), row[4]])

func _walk_people(delta: float) -> void:
	for index: int in range(people.size()):
		var figure: CivilianFigure = people[index]
		if not figure.visible:
			continue
		var path: Array = _routes[index][2]
		var step: int = int(_routes_progress.get(index, 0))
		if step >= path.size():
			figure.visible = false
			continue
		var goal: Vector3 = path[step]
		var to_goal: Vector3 = goal - figure.position
		to_goal.y = 0.0
		# Not all at once: each leaves a beat after the one before.
		if signal_seconds < 3.2 + 0.45 * float(index):
			continue
		var travel: float = WALK_SPEED * delta
		if to_goal.length() <= travel:
			figure.place_feet(goal)
			_routes_progress[index] = step + 1
		else:
			figure.place_feet(figure.position + to_goal.normalized() * travel)

static func _actor_layers(root: Node) -> void:
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = ArenaSky.ACTOR_LAYERS

# --- the stalls ---------------------------------------------------------------

func _build_stall(stall: Dictionary, awning: Dictionary, index: int) -> void:
	var low: Vector3 = stall["low"]
	var high: Vector3 = stall["high"]
	var top: float = high.y
	var centre: Vector3 = (low + high) * 0.5
	var props: Node3D = Node3D.new()
	props.name = "Stall%d" % index
	add_child(props)
	# A cloth over the counter top and down its customer face.
	var front: float = -float(stall["keeper"])
	var cloth: Color = [Color("9c4a36"), Color("4f6a8a"), Color("b08a4a"), Color("5f7a5a")][index]
	_box(props, "CounterCloth", Vector3(centre.x, top + 0.006, centre.z), Vector3(high.x - low.x + 0.04, 0.012, high.z - low.z + 0.04), _lit("cloth%d" % index, cloth))
	_box(props, "CounterSkirt", Vector3(centre.x, top - 0.25, centre.z + front * ((high.z - low.z) * 0.5 + 0.012)), Vector3(high.x - low.x, 0.5, 0.012), _lit("cloth%d" % index, cloth))
	# Goods sit low on the counter: shallow trays, nothing taller than a hand.
	var span: float = high.x - low.x
	for slot: int in range(5):
		var x: float = low.x + span * (0.12 + 0.19 * float(slot))
		var at: Vector3 = Vector3(x, top + 0.06, centre.z - front * 0.12)
		match str(stall["goods"]):
			"produce":
				_box(props, "Tray", at, Vector3(0.6, 0.1, 0.5), _lit("tray", Color("6a5038")))
				var fruit: Color = [Color("c4644a"), Color("d8a23c"), Color("6f8a3e"), Color("b85a3a"), Color("8a6a2e")][slot]
				_box(props, "Produce", at + Vector3(0, 0.07, 0), Vector3(0.5, 0.06, 0.4), _lit("fruit%d" % slot, fruit))
			"parts":
				var steel: Color = [Color("6a7270"), Color("8a7a5a"), Color("4f5a5c"), Color("7a6a4a"), Color("5f6763")][slot]
				_box(props, "Part", at + Vector3(0, 0.02, 0), Vector3(0.42, 0.14, 0.3), _lit("part%d" % slot, steel))
				if slot % 2 == 0:
					_box(props, "Coil", at + Vector3(0.0, 0.12, 0.0), Vector3(0.2, 0.08, 0.2), _lit("copper", Color("a8743c")))
			"bread":
				_box(props, "Basket", at, Vector3(0.62, 0.12, 0.46), _lit("basket", Color("8a6a40")))
				_box(props, "Loaves", at + Vector3(0, 0.08, 0), Vector3(0.5, 0.06, 0.34), _lit("loaf", Color("c49a5c")))
			_:
				var bolt: Color = [Color("7a5068"), Color("4f6a8a"), Color("a0623e"), Color("5a8a6a"), Color("c0a060")][slot]
				_box(props, "Bolt", at + Vector3(0, 0.02, 0), Vector3(0.5, 0.14, 0.36), _lit("bolt%d" % slot, bolt))
	# Corner posts under the awning, so the canvas stands on something.
	var a_low: Vector3 = awning["low"]
	var a_high: Vector3 = awning["high"]
	var post: StandardMaterial3D = _lit("post", Color("3a3530"))
	# The posts stand at the keeper's side, against the counter, inside its
	# footprint where the counter already stops a body.
	for x: float in [low.x + 0.06, high.x - 0.06]:
		var z: float = (high.z - 0.06) if stall["keeper"] > 0.0 else (low.z + 0.06)
		_box(props, "AwningPost", Vector3(x, (top + a_low.y) * 0.5, z), Vector3(0.08, a_low.y - top, 0.08), post)
	# A string of bulbs along the customer-side hem, over everyone's head.
	var hem_z: float = a_low.z + 0.04 if stall["keeper"] > 0.0 else a_high.z - 0.04
	var count: int = 9
	for bulb_index: int in range(count):
		var x: float = a_low.x + 0.3 + (a_high.x - a_low.x - 0.6) * float(bulb_index) / float(count - 1)
		var sag: float = 0.12 * sin(PI * float(bulb_index % 4) / 3.0)
		var bulb: MeshInstance3D = _box(props, "Bulb", Vector3(x, a_low.y - 0.48 - sag, hem_z), Vector3(0.09, 0.11, 0.09), _glow("bulb", BULB, 3.0))
		bulbs.append(bulb)
	_box(props, "FestoonWire", Vector3((a_low.x + a_high.x) * 0.5, a_low.y - 0.42, hem_z), Vector3(a_high.x - a_low.x - 0.5, 0.015, 0.015), _lit("wire", Color("1e1c1a")))
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "StallLight"
	light.light_color = BULB
	light.light_energy = 0.7
	light.omni_range = 4.5
	light.shadow_enabled = false
	light.position = Vector3(centre.x, a_low.y - 0.6, (a_low.z + a_high.z) * 0.5)
	props.add_child(light)
	_stall_lights.append(light)

# --- the tram line ------------------------------------------------------------

## Grooved rails flush in the square under the stalled car, and its overhead
## wire on brackets from the south wall: nothing a body can touch.
func _build_rails() -> void:
	var line: Node3D = Node3D.new()
	line.name = "TramLine"
	add_child(line)
	var iron: StandardMaterial3D = _lit("iron", Color("262b2b"))
	var groove: StandardMaterial3D = _lit("groove", Color("4a4844"))
	var z: float = (TRAM_LOW.z + TRAM_HIGH.z) * 0.5
	for gauge: float in [-0.72, 0.72]:
		_box(line, "Rail", Vector3(-39.75, 0.008, z + gauge), Vector3(39.5, 0.016, 0.1), iron)
		_box(line, "Groove", Vector3(-39.75, 0.009, z + gauge + 0.07 * signf(gauge)), Vector3(39.5, 0.016, 0.04), groove)
	_box(line, "Wire", Vector3(-39.75, 5.3, z), Vector3(39.5, 0.04, 0.04), iron)
	for x: float in [-56.0, -46.0, -36.0, -26.0]:
		var reach: float = z - (-24.0)
		_box(line, "Bracket", Vector3(x, 5.62, -24.0 + reach * 0.5), Vector3(0.08, 0.08, reach), iron)
		_box(line, "Hanger", Vector3(x, 5.46, z), Vector3(0.03, 0.32, 0.03), iron)
		_box(line, "WallPlate", Vector3(x, 5.62, -23.97), Vector3(0.3, 0.4, 0.04), iron)

## The car's headlamps, flush on its end faces. Dark in the morning: it is
## stalled, waiting for its motor.
func _build_tram_lamps() -> void:
	var tram: Node3D = Node3D.new()
	tram.name = "TramLamps"
	add_child(tram)
	var z: float = (TRAM_LOW.z + TRAM_HIGH.z) * 0.5
	for end: float in [TRAM_LOW.x - 0.03, TRAM_HIGH.x + 0.03]:
		for side: float in [-0.95, 0.95]:
			tram_lamps.append(_box(tram, "Headlamp", Vector3(end, 0.78, z + side), Vector3(0.05, 0.22, 0.32), _glow("work_lit", EnemyView.WORK_GLOW, 2.6)))

# --- the clinic and the tower ---------------------------------------------------

## The clinic's lamp on the corner of the route: a plain lit cross on a dark
## plate, the only sign the clinic needs.
func _build_clinic_lamp() -> void:
	var lamp: Node3D = Node3D.new()
	lamp.name = "ClinicLamp"
	add_child(lamp)
	var at: Vector3 = Vector3(-20.0, 3.9, 12.6)
	_box(lamp, "Bracket", at + Vector3(-0.35, 0.0, 0.0), Vector3(0.7, 0.08, 0.08), _lit("iron", Color("262b2b")))
	_box(lamp, "Plate", at + Vector3(-0.72, 0.0, 0.0), Vector3(0.1, 0.9, 0.9), _lit("plate", Color("2b2f2c")))
	_clinic.append(_box(lamp, "CrossUpright", at + Vector3(-0.78, 0.0, 0.0), Vector3(0.03, 0.66, 0.2), _glow("clinic", CLINIC, 2.2)))
	_clinic.append(_box(lamp, "CrossBar", at + Vector3(-0.78, 0.0, 0.0), Vector3(0.03, 0.2, 0.66), _glow("clinic", CLINIC, 2.2)))
	_clinic.append(_box(lamp, "CrossUprightBack", at + Vector3(-0.66, 0.0, 0.0), Vector3(0.03, 0.66, 0.2), _glow("clinic", CLINIC, 2.2)))
	_clinic_light = OmniLight3D.new()
	_clinic_light.name = "ClinicGlow"
	_clinic_light.light_color = CLINIC
	_clinic_light.light_energy = 0.6
	_clinic_light.omni_range = 3.5
	_clinic_light.position = at + Vector3(-1.2, -0.2, 0.0)
	lamp.add_child(_clinic_light)

## The overlook's tower above the service stairs: a plain civic signal
## shaft, banded, with a ladder cage, a lamp and a mast. An ordinary piece of
## skyline from the square in the morning.
func _build_tower() -> void:
	var tower: Node3D = Node3D.new()
	tower.name = "OverlookTower"
	add_child(tower)
	var size: Vector3 = TOWER_HIGH - TOWER_LOW
	var centre: Vector3 = (TOWER_LOW + TOWER_HIGH) * 0.5
	var band: StandardMaterial3D = _lit("tower_band", Color("6a655c"))
	var iron: StandardMaterial3D = _lit("iron", Color("262b2b"))
	for level: int in range(1, 6):
		_box(tower, "Band", Vector3(centre.x, float(level) * 3.0, centre.z), Vector3(size.x + 0.06, 0.18, size.z + 0.06), band)
	# The ladder cage up the square-facing west side.
	for rung: int in range(30):
		_box(tower, "Rung", Vector3(TOWER_LOW.x - 0.06, 4.0 + 0.45 * float(rung), centre.z), Vector3(0.04, 0.03, 0.5), iron)
	for side: float in [-0.27, 0.27]:
		_box(tower, "Stile", Vector3(TOWER_LOW.x - 0.06, 10.6, centre.z + side), Vector3(0.04, 13.4, 0.04), iron)
	# The cap, the lamp housing and the mast.
	_box(tower, "Cap", Vector3(centre.x, TOWER_HIGH.y + 0.15, centre.z), Vector3(size.x + 0.4, 0.3, size.z + 0.4), _lit("cap", Color("4a4844")))
	_box(tower, "LampHousing", Vector3(centre.x, TOWER_HIGH.y + 0.55, centre.z), Vector3(0.7, 0.5, 0.7), iron)
	_tower_lamp = _box(tower, "Lamp", Vector3(centre.x, TOWER_HIGH.y + 0.55, centre.z), Vector3(0.74, 0.3, 0.74), _glow("tower", TOWER_LAMP, 2.4))
	_box(tower, "Mast", Vector3(centre.x, TOWER_HIGH.y + 3.8, centre.z), Vector3(0.08, 6.0, 0.08), iron)
	_tower_light = OmniLight3D.new()
	_tower_light.name = "TowerGlow"
	_tower_light.light_color = TOWER_LAMP
	_tower_light.light_energy = 0.8
	_tower_light.omni_range = 5.0
	_tower_light.position = Vector3(centre.x, TOWER_HIGH.y + 0.5, centre.z)
	tower.add_child(_tower_light)

# --- the far district -------------------------------------------------------------

## Another district well past the map's edge, east and north-east of the
## overlook: housing blocks in the morning haze, in mid values that sit
## back toward the sky (never a clean off-white, which is the Inheritance's
## late in the story). In the morning only their facades and dark windows
## show; after the heads come round, their windows carry the same rhythm on
## the same light. Far scenery, nobody can walk there.
func _build_district() -> void:
	var district: Node3D = Node3D.new()
	district.name = "FarDistrict"
	add_child(district)
	var walls: Array[StandardMaterial3D] = [_lit("far_a", Color("757c80")), _lit("far_b", Color("817a70")), _lit("far_c", Color("6e777a"))]
	var shape: RefCounted = Geometry.new()
	var dark: SurfaceTool = SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit: SurfaceTool = SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var row: int = 0
	for block: Array in [
		[Vector3(150, 0, -60), Vector3(16, 34, 14)], [Vector3(168, 0, -30), Vector3(14, 46, 14)],
		[Vector3(160, 0, 4), Vector3(18, 28, 16)], [Vector3(176, 0, 34), Vector3(14, 52, 14)],
		[Vector3(150, 0, 62), Vector3(16, 38, 14)], [Vector3(128, 0, 104), Vector3(14, 44, 14)],
		[Vector3(96, 0, 132), Vector3(16, 30, 16)], [Vector3(60, 0, 150), Vector3(14, 48, 14)],
		[Vector3(196, 0, -4), Vector3(14, 60, 14)], [Vector3(200, 0, 72), Vector3(16, 40, 14)],
	]:
		var feet: Vector3 = block[0]
		var size: Vector3 = block[1]
		var body: MeshInstance3D = _box(district, "Block", feet + Vector3(0, size.y * 0.5, 0), size, walls[row % walls.size()])
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box(district, "Roof", feet + Vector3(0, size.y + 0.4, 0), Vector3(size.x * 0.4, 0.8, size.z * 0.4), _lit("far_roof", Color("6c7072")))
		# Windows on the faces toward the overlook (west and south): a dark
		# pane in every bay of every storey, and on some storeys the same
		# panes in the working light, drawn just proud of them.
		for normal: Vector3 in [Vector3(-1, 0, 0), Vector3(0, 0, -1)]:
			var right: Vector3 = Vector3.UP.cross(normal)
			var width: float = absf(right.dot(size))
			var face: Vector3 = feet + normal * (absf(normal.dot(size)) * 0.5)
			var bays: int = int((width - 1.6) / 3.0)
			for level: int in range(1, int(size.y / 3.2) - 1):
				var y: float = float(level) * 3.2 + 0.9
				var glowing: bool = (level + row) % 3 != 0
				for bay: int in range(bays):
					var u: float = -float(bays - 1) * 1.5 + float(bay) * 3.0
					var centre: Vector3 = face + right * u + Vector3(0, y + 0.8, 0)
					_pane(shape, dark, centre + normal * 0.05, right, normal, 1.6, 1.5)
					if glowing and (bay + level * 3 + row) % 5 != 0:
						_pane(shape, lit, centre + normal * 0.09, right, normal, 1.6, 1.5)
		row += 1
	var panes: MeshInstance3D = MeshInstance3D.new()
	panes.name = "FarPanes"
	panes.mesh = dark.commit()
	panes.material_override = _lit("far_glass", Color("3f474b"))
	panes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	district.add_child(panes)
	var glow: MeshInstance3D = MeshInstance3D.new()
	glow.name = "LitWindows"
	glow.mesh = lit.commit()
	glow.material_override = _glow("far_work", EnemyView.WORK_GLOW, 3.4)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.visible = false
	district.add_child(glow)
	far_windows.append(glow)

func _pane(shape: RefCounted, tool: SurfaceTool, centre: Vector3, right: Vector3, normal: Vector3, width: float, height: float) -> void:
	var half_w: Vector3 = right * width * 0.5
	var half_h: Vector3 = Vector3(0, height * 0.5, 0)
	shape.quad(tool, centre - half_w - half_h, centre + half_w - half_h, centre + half_w + half_h, centre - half_w + half_h, normal)

# --- sound ------------------------------------------------------------------------

## The rubble work's machinery where the square's machines work, and the
## sound of it stopping. Existing baked cues; nothing new is generated.
func _build_noise() -> void:
	for at: Vector3 in [Vector3(-29.0, 1.0, -3.0), Vector3(-25.0, 1.0, -11.0)]:
		var player: AudioStreamPlayer3D = _audio("WorkNoise", "res://assets/audio/m02/floor_machinery_loop.wav", at, -14.0)
		player.autoplay = true
		_work_noise.append(player)
	_stop_noise = _audio("WorkStops", "res://assets/audio/m02/ward_machine_stop.wav", Vector3(-27.0, 1.0, -6.0), -4.0)

func _audio(label: String, path: String, at: Vector3, volume: float) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.name = label
	player.position = at
	player.bus = &"Effects"
	player.unit_size = 8.0
	player.max_distance = 40.0
	player.volume_db = volume
	if ResourceLoader.exists(path):
		player.stream = load(path) as AudioStream
	add_child(player)
	return player

# --- materials ----------------------------------------------------------------------

func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node

func _lit(key: String, colour: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.88
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_materials[key] = material
	return _materials[key]

func _glow(key: String, colour: Color, energy: float) -> StandardMaterial3D:
	if not _materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = colour
		material.emission_enabled = true
		material.emission = colour
		material.emission_energy_multiplier = energy
		_materials[key] = material
	return _materials[key]
