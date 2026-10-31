class_name M17Dressing
extends M06Dressing

## The Forever Office (docs/campaign/l17-peace-without-interruption.md,
## docs/design/earth.md "M15-17 reckoning"): the civic approach, the occupied
## assembly hall, the administration ring, the lane to the security core, the
## assembly chamber and the command galleries. The server owns every solid;
## this presenter only furnishes them: work left on the desks, chairs pushed back,
## the plotting table's city, a status board where command sites go dark one
## by one, tall windows on the burning city at dawn, issued wall floods over
## the galleries, and the warm service lamps that lead from the assembly hall
## to the outer stair. Nothing here collides or stops a shot, nothing glows
## red or cyan, and nothing carries words: the room says who worked here and
## what is failing without a sign.

const OFFICE_MAP_ID: int = 1017
## Issued graphite, the walnut of civic furniture, paper and the people who
## sat here: a cardigan, a mug, a lunch. Paper is a warm grey, never off-white.
const GRAPHITE: Color = Color("33373a")
const WALNUT: Color = Color("5e4838")
const PAPER: Color = Color("b4ab98")
const AMBER: Color = Color("c49a45")
const WORK_GREEN: Color = Color("6fa264")
const SCREEN: Color = Color("5f7a6c")
const BELONGINGS: Array[Color] = [Color("8a5a3c"), Color("6f8a4e"), Color("7c5a8c"), Color("4f6f8a"), Color("a8552c")]
## Union black cloth and the thin red line it is edged with: paint, never light.
const CLOTH: Color = Color("1d1e22")
const SEAL_LINE: Color = Color("7a1c1f")
const STEEL: Color = Color("2c2f31")
const ROOMS: Array[String] = ["CommandFloor", "NorthGallery", "EastGallery", "ServiceStair", "Windows",
	"Approach", "AssemblyHall", "AdministrationRing", "SecurityCore", "Chamber"]

## The Forever Office's own command block: the north gallery deck, the
## sheltered stair's screen, the exposed stair's top step and the service
## landing. A custom map reusing the id gets no furniture rather than
## floating props.
static func office_layout(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != OFFICE_MAP_ID or not info.get("solids") is Array:
		return false
	var wanted: Array = [
		[Vector3(-34, 2.6, 14), Vector3(-8, 3, 18)],
		[Vector3(-31.5, 0, 8.6), Vector3(-31, 4, 14)],
		[Vector3(-20, 0, 13.6), Vector3(-17.5, 3, 14)],
		[Vector3(-7, 0, 0), Vector3(-5, 3, 4)],
	]
	for pair: Array in wanted:
		if M06Workmanship._host(info["solids"], pair[0], pair[1]).is_empty():
			return false
	return true

func configure_map(info: Dictionary) -> void:
	if active() and office_layout(info):
		return
	clear_map()
	if not office_layout(info):
		return
	_build_floor()
	_build_north_gallery()
	_build_east_gallery()
	_build_service_stair()
	_build_windows()
	_build_approach()
	_build_hall()
	_build_ring()
	_build_core()
	_build_chamber()
	for room: Node3D in _unattached:
		_finish(room)
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

func _mat(key: String, tint: Color, metallic: float = 0.0, roughness: float = 0.82) -> StandardMaterial3D:
	return _shape.material("m17_" + key, tint, metallic, roughness)

# --- textures ---------------------------------------------------------------

static func _image_texture(image: Image) -> ImageTexture:
	return ImageTexture.create_from_image(image)

## The plotting table's city: a dark river bend through district blocks, the
## Office's own district marked in amber, and whole districts gone dark where
## the uprising has cut command's feeds. No words, no red.
static func city_plot() -> Texture2D:
	var image: Image = Image.create(48, 24, false, Image.FORMAT_RGB8)
	image.fill(Color("1e272b"))
	for x: int in range(48):
		for y: int in range(24):
			if x % 6 != 0 and y % 4 != 0:
				image.set_pixel(x, y, Color("3a4a4c"))
	for x: int in range(48):
		var river: int = 12 + int(round(sin(float(x) / 7.0) * 5.0))
		for y: int in range(river - 1, river + 1):
			image.set_pixel(x, clampi(y, 0, 23), Color("566e6a"))
	for x: int in range(30, 47):
		for y: int in range(1, 11):
			if x % 6 != 0 and y % 4 != 0:
				image.set_pixel(x, y, Color("232b2e"))
	for marker: Vector2i in [Vector2i(20, 7), Vector2i(22, 7), Vector2i(21, 6), Vector2i(9, 17), Vector2i(26, 18), Vector2i(40, 19)]:
		image.set_pixel(marker.x, marker.y, AMBER)
	return _image_texture(image)

## The status board: rows of regional command sites. Most still burn amber
## or working green; a growing share has gone dark tonight.
static func status_board() -> Texture2D:
	var image: Image = Image.create(64, 16, false, Image.FORMAT_RGB8)
	image.fill(Color("15191b"))
	for row: int in range(4):
		for column: int in range(16):
			var seed_value: int = (row * 31 + column * 17 + column * row * 5) % 11
			var cell: Color = Color("2a2f31")
			if seed_value < 4:
				cell = AMBER
			elif seed_value < 7:
				cell = WORK_GREEN
			for x: int in range(column * 4 + 1, column * 4 + 3):
				for y: int in range(row * 4 + 1, row * 4 + 3):
					image.set_pixel(x, y, cell)
	return _image_texture(image)

## A tall window on the city at dawn: smoke grey above, the fires' warmth on
## the horizon, a dark skyline with a few lit rooms.
static func dawn_window() -> Texture2D:
	var image: Image = Image.create(12, 24, false, Image.FORMAT_RGB8)
	for y: int in range(24):
		var t: float = float(y) / 23.0
		var sky: Color = Color("3a4252").lerp(Color("b07a5c"), t * t)
		for x: int in range(12):
			image.set_pixel(x, y, sky)
	var heights: Array[int] = [5, 7, 4, 9, 6, 3, 8, 5, 6, 4, 7, 5]
	for x: int in range(12):
		for y: int in range(24 - heights[x], 24):
			image.set_pixel(x, y, Color("22262b"))
	for lit: Vector2i in [Vector2i(1, 21), Vector2i(3, 17), Vector2i(6, 20), Vector2i(9, 22)]:
		image.set_pixel(lit.x, lit.y, Color("d6a464"))
	return _image_texture(image)

# --- rooms ------------------------------------------------------------------

## A desk where somebody was working: a monitor facing the chair, files and
## loose paper, a desk lamp, a chair pushed back, sometimes a personal thing.
func _workstation(room: Node3D, desk_top: Vector3, facing_north: bool, index: int) -> void:
	var props: Node3D = _props(room)
	var toward: float = 1.0 if facing_north else -1.0
	var housing: StandardMaterial3D = _mat("monitor", GRAPHITE, 0.3, 0.6)
	var screen_at: Vector3 = desk_top + Vector3(0, 0.24, 0.18 * toward)
	_block(props, "Monitor", Vector3(0.52, 0.36, 0.06), housing, screen_at)
	_block(props, "MonitorFoot", Vector3(0.12, 0.06, 0.12), housing, desk_top + Vector3(0, 0.03, 0.2 * toward))
	_block(props, "MonitorScreen", Vector3(0.46, 0.3, 0.01), _glow("screen", SCREEN, 0.55), screen_at + Vector3(0, 0, -0.035 * toward))
	_block(props, "Keyboard", Vector3(0.44, 0.02, 0.15), housing, desk_top + Vector3(0, 0.01, -0.12 * toward))
	for sheet: int in range(3):
		var offset: Vector3 = Vector3(0.55 + 0.04 * sheet, 0.005 + 0.004 * sheet, -0.05 * toward + 0.03 * sheet)
		var paper: MeshInstance3D = _block(props, "Paper", Vector3(0.21, 0.004, 0.3), _mat("paper", PAPER), desk_top + offset)
		paper.rotation.y = 0.12 * float(sheet - 1)
	_block(props, "Files", Vector3(0.26, 0.12, 0.34), _mat("file_board", Color("5d6658")), desk_top + Vector3(-0.62, 0.06, 0.05 * toward))
	_block(props, "FilesPaper", Vector3(0.24, 0.1, 0.33), _mat("paper", PAPER), desk_top + Vector3(-0.62, 0.06, 0.05 * toward))
	_desk_lamp(room, desk_top + Vector3(-0.95, 0.0, 0.15 * toward), desk_top + Vector3(-0.3, 0, -0.1 * toward))
	# The chair sits where it was left, pushed back from the desk.
	var chair: Vector3 = Vector3(desk_top.x + 0.1 * float(index % 2), 0.0, desk_top.z - 0.75 * toward)
	var frame: StandardMaterial3D = _mat("chair_frame", Color("2d3032"), 0.4, 0.6)
	var cloth: StandardMaterial3D = _mat("chair_cloth", Color("4a4440"))
	_block(props, "ChairSeat", Vector3(0.46, 0.07, 0.44), cloth, chair + Vector3(0, 0.47, 0))
	_block(props, "ChairBack", Vector3(0.44, 0.48, 0.06), cloth, chair + Vector3(0, 0.78, -0.22 * toward))
	_shape.rod(props, "ChairPost", chair + Vector3(0, 0.08, 0), chair + Vector3(0, 0.44, 0), 0.025, frame, 6)
	for leg: int in range(4):
		var angle: float = TAU * float(leg) / 4.0 + 0.4
		_shape.rod(props, "ChairLeg", chair + Vector3(0, 0.08, 0), chair + Vector3(cos(angle) * 0.26, 0.03, sin(angle) * 0.26), 0.015, frame, 4)
	if index % 2 == 0:
		# Somebody's cardigan over the chair back, and their mug.
		_block(props, "Cardigan", Vector3(0.46, 0.3, 0.09), _mat("personal_%d" % index, BELONGINGS[index % BELONGINGS.size()]), chair + Vector3(0, 0.84, -0.25 * toward))
		_shape.cylinder(props, "Mug", 0.045, 0.1, _mat("mug_%d" % index, BELONGINGS[(index + 2) % BELONGINGS.size()]), desk_top + Vector3(0.95, 0.05, 0.1 * toward), 10).rotation.x = PI * 0.5

func _build_floor() -> void:
	var room: Node3D = _room("CommandFloor")
	var props: Node3D = _props(room)
	# Operators sit south of their desks, facing the galleries and the board.
	for x: float in [-29.0, -27.4]:
		_workstation(room, Vector3(x, 1.1, 10.8), true, int(x))
	_workstation(room, Vector3(-14.6, 1.1, 9.2), true, 1)
	# The plotting table reads as one: a graphite rim and the lit city under glass.
	var rim: StandardMaterial3D = _mat("plot_rim", GRAPHITE, 0.4, 0.5)
	_block(props, "PlotRimNorth", Vector3(2.5, 0.06, 0.1), rim, Vector3(-24.25, 1.03, 10.55))
	_block(props, "PlotRimSouth", Vector3(2.5, 0.06, 0.1), rim, Vector3(-24.25, 1.03, 9.45))
	_block(props, "PlotRimWest", Vector3(0.1, 0.06, 1.2), rim, Vector3(-25.45, 1.03, 10.0))
	_block(props, "PlotRimEast", Vector3(0.1, 0.06, 1.2), rim, Vector3(-23.05, 1.03, 10.0))
	_picture(room, "CityPlot", city_plot(), Vector2(2.3, 1.0), Vector3(-24.25, 1.012, 10.0), "up", 1.6)
	# Rack panels flush on the wall under the north gallery, with lamp rows,
	# and a cold strip under the deck so the back of the floor is not a cave.
	for x: float in [-32.5, -29.5, -16.0, -10.5]:
		_block(props, "Rack", Vector3(1.8, 2.0, 0.08), _mat("rack", Color("3b3f42"), 0.3, 0.6), Vector3(x, 1.25, 17.94))
		for lamp: int in range(6):
			var tint: Color = AMBER if (lamp + int(x)) % 3 == 0 else WORK_GREEN
			_block(props, "RackLamp", Vector3(0.08, 0.05, 0.02), _glow("rack_" + tint.to_html(false), tint, 1.6), Vector3(x - 0.6 + 0.24 * lamp, 1.9, 17.89))
	_omni(room, "UnderGalleryStrip", Vector3(-22.0, 2.4, 16.0), COLD, 1.4, 7.5)
	# An issued beam over the floor carries two cold floods.
	var beam: StandardMaterial3D = _mat("beam", Color("3a3e41"), 0.4, 0.55)
	_block(props, "FloodBeam", Vector3(26.0, 0.24, 0.3), beam, Vector3(-21.0, 6.95, 10.5))
	_pool(room, Vector3(-27.0, 6.6, 10.5), 2.4, 9.0, 52.0, 6.83)
	_pool(room, Vector3(-15.0, 6.6, 10.5), 2.4, 9.0, 52.0, 6.83)

func _build_north_gallery() -> void:
	var room: Node3D = _room("NorthGallery")
	var props: Node3D = _props(room)
	# The status board above the gallery: regions going dark tonight.
	var housing: StandardMaterial3D = _mat("board_housing", GRAPHITE, 0.3, 0.6)
	_block(props, "StatusBoardHousing", Vector3(7.6, 1.9, 0.12), housing, Vector3(-24.4, 5.9, 17.92))
	_picture(room, "StatusBoard", status_board(), Vector2(7.2, 1.6), Vector3(-24.4, 5.9, 17.85), "north", 0.8)
	# The override console reads as a console: a raked panel with its keys.
	_block(props, "ConsoleRake", Vector3(1.9, 0.08, 0.5), _mat("console_top", Color("3d4245"), 0.3, 0.6), Vector3(-24.0, 4.24, 17.0))
	for key: int in range(6):
		_block(props, "ConsoleKey", Vector3(0.12, 0.02, 0.08), _glow("console_keys", AMBER.darkened(0.25), 0.5), Vector3(-24.45 + 0.18 * key, 4.29, 16.85))
	# Work on the gallery: a chair at the console, files on the rail-side desk.
	_block(props, "GalleryChair", Vector3(0.46, 0.07, 0.44), _mat("chair_cloth", Color("4a4440")), Vector3(-22.6, 3.47, 15.9))
	_block(props, "GalleryChairBack", Vector3(0.44, 0.48, 0.06), _mat("chair_cloth", Color("4a4440")), Vector3(-22.6, 3.78, 16.12))
	# A steel cap on the rail, so the waist-high parapet reads as a rail.
	var cap: StandardMaterial3D = _mat("rail_cap", Color("2c2f31"), 0.5, 0.45)
	_block(props, "RailCapWest", Vector3(11.5, 0.06, 0.32), cap, Vector3(-25.75, 4.03, 14.125))
	_block(props, "RailCapEast", Vector3(5.5, 0.06, 0.32), cap, Vector3(-14.75, 4.03, 14.125))
	_pool(room, Vector3(-22.0, 6.7, 16.6), 2.4, 8.5, 60.0, 6.7)

func _build_east_gallery() -> void:
	var room: Node3D = _room("EastGallery")
	var props: Node3D = _props(room)
	# Record racks flush on the east wall: binders on shelves, no body to stop anyone.
	for z: float in [7.5, 9.5, 11.5]:
		_block(props, "RecordRack", Vector3(0.06, 1.75, 1.8), _mat("rack", Color("3b3f42"), 0.3, 0.6), Vector3(-8.03, 3.88, z))
		for shelf: int in range(3):
			_block(props, "Shelf", Vector3(0.26, 0.03, 1.8), _mat("rack", Color("3b3f42"), 0.3, 0.6), Vector3(-8.15, 3.115 + 0.55 * shelf, z))
			for binder: int in range(7):
				var tint: Color = Color("5d6658") if (binder + shelf) % 3 else Color("6b5a44")
				_block(props, "Binder", Vector3(0.18, 0.34, 0.07), _mat("binder_" + tint.to_html(false), tint), Vector3(-8.15, 3.3 + 0.55 * shelf, z - 0.6 + 0.2 * binder))
	_block(props, "RailCapEastGallery", Vector3(0.32, 0.06, 8.0), _mat("rail_cap", Color("2c2f31"), 0.5, 0.45), Vector3(-11.875, 4.03, 10.0))
	_pool(room, Vector3(-9.0, 6.7, 9.5), 1.8, 7.0, 50.0, 6.7)

## The way from the assembly hall to the galleries is lit like a service run:
## a caged warm lamp over the door that reads from mid-hall, and warm lamps up
## the flight, so the opening glows against the hall's cold stone.
func _build_service_stair() -> void:
	var room: Node3D = _room("ServiceStair")
	var props: Node3D = _props(room)
	_lamp(room, Vector3(-14.5, 3.2, -2.35), 5.0, 9.5, 6.8)
	_omni(room, "DoorwayGlow", Vector3(-14.5, 1.6, -0.6), WARM, 2.2, 4.5)
	_lamp(room, Vector3(-14.5, 3.4, 1.0), 2.4, 6.5, 6.8)
	_lamp(room, Vector3(-6.0, 5.6, 2.0), 2.4, 6.5, 6.8)
	# The door's steel frame, flush on the hall face.
	var frame: StandardMaterial3D = _mat("door_frame", Color("2e3133"), 0.4, 0.55)
	for x: float in [-15.55, -13.45]:
		_block(props, "DoorJamb", Vector3(0.1, 2.6, 0.06), frame, Vector3(x, 1.3, -2.03))
	_block(props, "DoorHead", Vector3(2.2, 0.12, 0.06), frame, Vector3(-14.5, 2.62, -2.03))
	# Ochre safety nosing on the steel flight: issued, worn, not red.
	for step: int in range(15):
		_block(props, "Nosing", Vector3(0.06, 0.012, 2.1), _mat("nosing", Color("8c7a45")), Vector3(-12.97 + 0.4 * step, 0.2 * (step + 1) + 0.006, 1.1))

## Tall windows on the city at dawn in the west wall, above the sheltered
## stair's screen and on the gallery: light and depth, and the fires outside.
func _build_windows() -> void:
	var room: Node3D = _room("Windows")
	var props: Node3D = _props(room)
	var view: Texture2D = dawn_window()
	var mullion: StandardMaterial3D = _mat("mullion", Color("2a2d30"), 0.4, 0.5)
	for z: float in [8.6, 11.6, 16.0]:
		_picture(room, "DawnWindow", view, Vector2(1.6, 2.6), Vector3(-33.985, 5.4, z), "east", 1.0)
		_block(props, "MullionHead", Vector3(0.08, 0.12, 1.8), mullion, Vector3(-33.96, 6.76, z))
		_block(props, "MullionSill", Vector3(0.14, 0.1, 1.8), mullion, Vector3(-33.93, 4.06, z))
		_block(props, "MullionMid", Vector3(0.06, 2.6, 0.08), mullion, Vector3(-33.96, 5.4, z))
		_block(props, "MullionTransom", Vector3(0.06, 0.08, 1.6), mullion, Vector3(-33.96, 5.9, z))
	_omni(room, "WindowLight", Vector3(-32.5, 5.3, 12.0), Color("b7a4a0"), 1.1, 9.0)

# --- the rest of the Office -------------------------------------------------

## An issued flood on a steel arm from a wall top: hood, lens and a hard pool.
## `out` points from the wall into the room.
func _arm_pool(room: Node3D, wall: Vector3, out: Vector3, energy: float, reach: float = 8.0, angle: float = 50.0) -> void:
	var at: Vector3 = wall + out * 1.1
	_block(_props(room), "FloodArm", Vector3(absf(out.x) * 1.1 + absf(out.z) * 0.08 + 0.02, 0.08, absf(out.z) * 1.1 + absf(out.x) * 0.08 + 0.02), _mat("beam", Color("3a3e41"), 0.4, 0.55), wall + out * 0.55 + Vector3(0, 0.22, 0))
	_pool(room, at, energy, reach, angle, 0.0)

## A long issued beam resting on two wall tops, carrying cold floods.
func _beam(room: Node3D, from: Vector3, to: Vector3) -> void:
	var span: Vector3 = to - from
	var size: Vector3 = Vector3(maxf(absf(span.x), 0.3), 0.24, maxf(absf(span.z), 0.3))
	_block(_props(room), "Beam", size, _mat("beam", Color("3a3e41"), 0.4, 0.55), (from + to) * 0.5)

## A wall panel of pinned forms: a graphite board and blank sheets, no words.
func _form_board(room: Node3D, centre: Vector3, face: String, width: float) -> void:
	var props: Node3D = _props(room)
	var normal: Vector3 = MapDecoration.face_basis(face).z
	var along: Vector3 = MapDecoration.face_basis(face).x
	var board: Vector3 = Vector3(width, 1.1, 0.04)
	var size: Vector3 = Vector3(absf(along.x) * board.x + absf(normal.x) * board.z, board.y, absf(along.z) * board.x + absf(normal.z) * board.z)
	_block(props, "FormBoard", size, _mat("board_housing", GRAPHITE, 0.3, 0.6), centre + normal * 0.02)
	var sheets: int = int(width / 0.42)
	for index: int in range(sheets):
		var at: Vector3 = centre + along * (-width * 0.5 + 0.26 + 0.42 * float(index)) + normal * 0.045 + Vector3(0, 0.12 * float(index % 2) - 0.06, 0)
		var sheet: Vector3 = Vector3(0.3, 0.42, 0.006)
		_block(props, "Form", Vector3(absf(along.x) * sheet.x + absf(normal.x) * sheet.z, sheet.y, absf(along.z) * sheet.x + absf(normal.z) * sheet.z), _mat("paper", PAPER), at)

## A shallow bank of wall cabinets, flush, 0.3 m deep: grey steel drawers
## with dark pulls. Too shallow to read as cover.
func _cabinets(room: Node3D, start: Vector3, face: String, count: int) -> void:
	var props: Node3D = _props(room)
	var normal: Vector3 = MapDecoration.face_basis(face).z
	var along: Vector3 = MapDecoration.face_basis(face).x
	for index: int in range(count):
		var at: Vector3 = start + along * (0.5 + 0.92 * float(index)) + normal * 0.15 + Vector3(0, 0.66, 0)
		_block(props, "Cabinet", Vector3(absf(along.x) * 0.9 + absf(normal.x) * 0.3, 1.32, absf(along.z) * 0.9 + absf(normal.z) * 0.3), _mat("cabinet", Color("4d5254"), 0.35, 0.6), at)
		for drawer: int in range(4):
			var pull: Vector3 = at + normal * 0.155 + Vector3(0, -0.45 + 0.3 * float(drawer), 0)
			_block(props, "Pull", Vector3(absf(along.x) * 0.2 + absf(normal.x) * 0.02, 0.03, absf(along.z) * 0.2 + absf(normal.z) * 0.02), _mat("rail_cap", STEEL, 0.5, 0.45), pull)
			_block(props, "DrawerSeam", Vector3(absf(along.x) * 0.86 + absf(normal.x) * 0.01, 0.012, absf(along.z) * 0.86 + absf(normal.z) * 0.01), _mat("drawer_seam", Color("2a2d2f")), pull + normal * -0.005 + Vector3(0, 0.12, 0))

## A shallow wall bench, seat and back, flush to a wall: where the public waited.
func _wall_bench(room: Node3D, centre: Vector3, face: String, length: float) -> void:
	var props: Node3D = _props(room)
	var normal: Vector3 = MapDecoration.face_basis(face).z
	var along: Vector3 = MapDecoration.face_basis(face).x
	var seat: Vector3 = Vector3(absf(along.x) * length + absf(normal.x) * 0.3, 0.06, absf(along.z) * length + absf(normal.z) * 0.3)
	_block(props, "BenchSeat", seat, _mat("walnut", WALNUT, 0.0, 0.7), centre + normal * 0.15 + Vector3(0, 0.45, 0))
	_block(props, "BenchBack", Vector3(absf(along.x) * length + absf(normal.x) * 0.04, 0.4, absf(along.z) * length + absf(normal.z) * 0.04), _mat("walnut", WALNUT, 0.0, 0.7), centre + normal * 0.02 + Vector3(0, 0.82, 0))
	for leg: float in [-0.5, 0.5]:
		_block(props, "BenchLeg", Vector3(absf(along.x) * 0.06 + absf(normal.x) * 0.26, 0.42, absf(along.z) * 0.06 + absf(normal.z) * 0.26), _mat("rail_cap", STEEL, 0.5, 0.45), centre + along * (leg * (length - 0.3)) + normal * 0.15 + Vector3(0, 0.21, 0))

## A round wall clock with no numerals: a dark rim, a grey face and hands.
func _clock(room: Node3D, at: Vector3, face: String) -> void:
	var props: Node3D = _props(room)
	var normal: Vector3 = MapDecoration.face_basis(face).z
	var rim: MeshInstance3D = _shape.cylinder(props, "ClockRim", 0.28, 0.06, _mat("rail_cap_round", STEEL, 0.5, 0.45), at + normal * 0.03, 16)
	rim.basis = MapDecoration.face_basis(face)
	var dial: MeshInstance3D = _shape.cylinder(props, "ClockFace", 0.24, 0.01, _mat("clock_face", Color("a39d8e")), at + normal * 0.065, 16)
	dial.basis = rim.basis
	_shape.rod(props, "ClockHand", at + normal * 0.075, at + normal * 0.075 + Vector3(0, 0.17, 0), 0.012, _mat("chair_frame", Color("2d3032"), 0.4, 0.6), 4)
	var along: Vector3 = MapDecoration.face_basis(face).x
	_shape.rod(props, "ClockHand", at + normal * 0.078, at + normal * 0.078 + along * 0.11 + Vector3(0, -0.04, 0), 0.012, _mat("chair_frame", Color("2d3032"), 0.4, 0.6), 4)

## Black cloth with a thin red line down each edge: the Union's own hanging.
func _hanging(room: Node3D, centre: Vector3, face: String, width: float, height: float) -> void:
	var props: Node3D = _props(room)
	var normal: Vector3 = MapDecoration.face_basis(face).z
	var along: Vector3 = MapDecoration.face_basis(face).x
	_block(props, "Hanging", Vector3(absf(along.x) * width + absf(normal.x) * 0.03, height, absf(along.z) * width + absf(normal.z) * 0.03), _mat("cloth", CLOTH, 0.0, 0.95), centre + normal * 0.02)
	for side: float in [-1.0, 1.0]:
		_block(props, "HangingLine", Vector3(absf(along.x) * 0.06 + absf(normal.x) * 0.032, height, absf(along.z) * 0.06 + absf(normal.z) * 0.032), _mat("seal_line", SEAL_LINE, 0.0, 0.9), centre + normal * 0.022 + along * side * (width * 0.5 - 0.12))
	_block(props, "HangingRod", Vector3(absf(along.x) * (width + 0.3) + absf(normal.x) * 0.05, 0.05, absf(along.z) * (width + 0.3) + absf(normal.z) * 0.05), _mat("rail_cap", STEEL, 0.5, 0.45), centre + normal * 0.05 + Vector3(0, height * 0.5 + 0.03, 0))

## The approach the public queued along: piers banded in the institution's
## red line and capped with cold lanterns, issued floods on arms from both
## walls, worn guide paint to the door, forms on the walls and the papers
## people dropped when the queue broke.
func _build_approach() -> void:
	var room: Node3D = _room("Approach")
	var props: Node3D = _props(room)
	for z: float in [-41.0, -35.0, -29.0, -24.0]:
		_arm_pool(room, Vector3(-6.0, 4.3, z), Vector3.RIGHT, 2.2)
	for z: float in [-38.0, -32.0, -26.0]:
		_arm_pool(room, Vector3(6.0, 4.3, z), Vector3.LEFT, 2.2)
	for pier: Vector3 in [Vector3(-3, 0, -34), Vector3(3, 0, -28)]:
		_block(props, "PierBand", Vector3(2.04, 0.08, 4.04), _mat("seal_line", SEAL_LINE, 0.0, 0.9), pier + Vector3(0, 3.6, 0))
		_block(props, "PierPlinth", Vector3(2.08, 0.3, 4.08), _mat("plinth", Color("3d4143"), 0.2, 0.7), pier + Vector3(0, 0.15, 0))
		_block(props, "PierCap", Vector3(2.2, 0.12, 4.2), _mat("rail_cap", STEEL, 0.5, 0.45), pier + Vector3(0, 4.56, 0))
		_block(props, "Lantern", Vector3(0.36, 0.5, 0.36), _glow("lantern", Color("d8dcd4"), 1.6), pier + Vector3(0, 4.87, 0))
		_omni(room, "PierLantern", pier + Vector3(0, 4.5, 0), COLD, 1.2, 8.0)
	# Guide paint: the queue line to the door, worn through where people stood.
	var paint: StandardMaterial3D = _mat("nosing", Color("8c7a45"))
	for x: float in [-1.2, 1.2]:
		for index: int in range(9):
			_paint_line(props, Vector3(x, 0, -43.0 + 2.2 * index), Vector3(x, 0, -41.6 + 2.2 * index), 0.1, paint)
	# Forms behind glass on the walls; benches where people waited.
	for z: float in [-38.0, -26.0]:
		_form_board(room, Vector3(-5.99, 1.8, z), "east", 2.4)
	_form_board(room, Vector3(5.99, 1.8, -32.0), "west", 2.4)
	_wall_bench(room, Vector3(-6.0, 0, -31.5), "east", 3.0)
	_wall_bench(room, Vector3(6.0, 0, -38.0), "west", 3.0)
	_wall_bench(room, Vector3(6.0, 0, -24.5), "west", 2.2)
	# The door into the hall: a dark steel frame and the seal line over it.
	var frame: StandardMaterial3D = _mat("door_frame", Color("2e3133"), 0.4, 0.55)
	for x: float in [-3.1, 3.1]:
		_block(props, "HallDoorJamb", Vector3(0.2, 4.5, 0.1), frame, Vector3(x, 2.25, -22.05))
	_block(props, "HallDoorHead", Vector3(6.4, 0.3, 0.1), frame, Vector3(0, 4.35, -22.05))
	_block(props, "HallDoorLine", Vector3(6.4, 0.06, 0.11), _mat("seal_line", SEAL_LINE, 0.0, 0.9), Vector3(0, 4.12, -22.05))
	# Papers dropped when the queue broke, and somebody's bag.
	for index: int in range(14):
		var at: Vector3 = Vector3(-4.6 + fmod(float(index) * 2.37, 9.2), 0.004 + 0.001 * index, -42.0 + fmod(float(index) * 3.1, 18.0))
		_block(props, "DroppedForm", Vector3(0.21, 0.004, 0.3), _mat("paper", PAPER), at).rotation.y = float(index) * 0.7
	_block(props, "LeftBag", Vector3(0.42, 0.28, 0.24), _mat("personal_2", BELONGINGS[2]), Vector3(5.6, 0.14, -36.6))

## The assembly hall was in session: coats and papers on the public benches,
## the rostrum's lectern and its microphone, the institution's hangings,
## cabinets and a clock with no numerals on the walls, and floods on two
## beams across the hall so its far side is never a cave.
func _build_hall() -> void:
	var room: Node3D = _room("AssemblyHall")
	var props: Node3D = _props(room)
	for z: float in [-15.0, -7.0]:
		_beam(room, Vector3(-16, 4.62, z), Vector3(16, 4.62, z))
		for x: float in [-10.0, 0.0, 10.0]:
			_pool(room, Vector3(x, 4.35, z), 2.8, 9.5, 58.0, 4.5)
	# The public benches: seat boards, left coats, papers, cups and bags.
	for bench: Vector3 in [Vector3(-9, 1.1, -14), Vector3(9, 1.1, -14)]:
		for row: float in [-1.4, 0.0, 1.4]:
			_block(props, "BenchBoard", Vector3(5.8, 0.04, 0.9), _mat("walnut", WALNUT, 0.0, 0.7), bench + Vector3(0, 0.02, row))
		for index: int in range(5):
			var at: Vector3 = bench + Vector3(-2.4 + 1.2 * float(index), 0.04, -1.4 + 1.4 * float(index % 3))
			match index % 3:
				0:
					_block(props, "LeftCoat", Vector3(0.55, 0.08, 0.4), _mat("personal_%d" % index, BELONGINGS[index % BELONGINGS.size()]), at + Vector3(0, 0.04, 0))
				1:
					_block(props, "LeftPapers", Vector3(0.24, 0.03, 0.32), _mat("paper", PAPER), at + Vector3(0, 0.015, 0)).rotation.y = 0.3
					_shape.cylinder(props, "Cup", 0.04, 0.1, _mat("mug_%d" % index, BELONGINGS[(index + 2) % BELONGINGS.size()]), at + Vector3(0.3, 0.05, 0.1), 8).rotation.x = PI * 0.5
				_:
					_block(props, "LeftBag", Vector3(0.4, 0.26, 0.22), _mat("personal_%d" % index, BELONGINGS[(index + 1) % BELONGINGS.size()]), at + Vector3(0, 0.13, 0))
	# The rostrum: a lectern, its microphone, a glass, and the seal line.
	_block(props, "RostrumCloth", Vector3(6.02, 1.0, 0.03), _mat("cloth", CLOTH, 0.0, 0.95), Vector3(0, 0.55, -8.02))
	_block(props, "RostrumLine", Vector3(6.04, 0.06, 0.035), _mat("seal_line", SEAL_LINE, 0.0, 0.9), Vector3(0, 1.0, -8.025))
	_block(props, "Lectern", Vector3(0.7, 1.0, 0.45), _mat("walnut", WALNUT, 0.0, 0.7), Vector3(0, 1.7, -6.0))
	_block(props, "LecternTop", Vector3(0.8, 0.05, 0.56), _mat("walnut_top", WALNUT.darkened(0.2), 0.0, 0.6), Vector3(0, 2.22, -6.0))
	_shape.rod(props, "Microphone", Vector3(0.25, 2.24, -6.1), Vector3(0.25, 2.55, -6.35), 0.012, _mat("rail_cap_round", STEEL, 0.5, 0.45), 4)
	_block(props, "MicrophoneHead", Vector3(0.06, 0.06, 0.08), _mat("rail_cap", STEEL, 0.5, 0.45), Vector3(0.25, 2.56, -6.38))
	_block(props, "Speech", Vector3(0.21, 0.004, 0.3), _mat("paper", PAPER), Vector3(-0.15, 2.25, -6.0))
	_shape.cylinder(props, "Glass", 0.035, 0.12, _mat("glass_water", Color("8e9a98"), 0.2, 0.2), Vector3(-2.3, 1.26, -6.2), 8).rotation.x = PI * 0.5
	# Hangings on the north wall either side of the lane, cabinets on the
	# east wall, benches along the south wall and a clock over the door.
	for x: float in [-8.5, 9.5]:
		_hanging(room, Vector3(x, 2.4, -2.0), "north", 1.6, 3.4)
	_cabinets(room, Vector3(16.0, 0, -2.5), "west", 6)
	_cabinets(room, Vector3(16.0, 0, -12.0), "west", 6)
	for x: float in [-11.5, 11.5]:
		_wall_bench(room, Vector3(x, 0, -20.0), "south", 5.0)
	_clock(room, Vector3(0, 3.9, -20.0), "south")
	_form_board(room, Vector3(-16.0, 1.8, -16.0), "east", 3.0)
	# The service door's lamp is ServiceStair's; the ring door gets a frame.
	var frame: StandardMaterial3D = _mat("door_frame", Color("2e3133"), 0.4, 0.55)
	for z: float in [-12.05, -5.95]:
		_block(props, "RingDoorJamb", Vector3(0.1, 4.5, 0.2), frame, Vector3(-15.98, 2.25, z))

## The administration ring, where Kessel's committee worked: the committee
## desk still covered in files, the records core's drawer faces, shallow
## cabinets along the outer wall, forms pinned up and cold floods on arms.
func _build_ring() -> void:
	var room: Node3D = _room("AdministrationRing")
	var props: Node3D = _props(room)
	for x: float in [-30.0, -21.0]:
		_arm_pool(room, Vector3(x, 4.3, -16.0), Vector3.BACK, 2.2, 7.5)
	_arm_pool(room, Vector3(-34.0, 4.3, -6.0), Vector3.RIGHT, 2.2, 7.5)
	_arm_pool(room, Vector3(-34.0, 4.3, -12.0), Vector3.RIGHT, 1.8, 7.5)
	_arm_pool(room, Vector3(-28.0, 4.3, 2.0), Vector3.FORWARD, 1.8, 7.5)
	# The committee desk: two monitors, file stacks, stamps, a lamp, a mug.
	var top: Vector3 = Vector3(-26.0, 1.1, -12.5)
	var housing: StandardMaterial3D = _mat("monitor", GRAPHITE, 0.3, 0.6)
	for x: float in [-1.1, 1.0]:
		_block(props, "Monitor", Vector3(0.52, 0.36, 0.06), housing, top + Vector3(x, 0.24, -0.9))
		_block(props, "MonitorScreen", Vector3(0.46, 0.3, 0.01), _glow("screen", SCREEN, 0.55), top + Vector3(x, 0.24, -0.865))
		_block(props, "MonitorFoot", Vector3(0.12, 0.06, 0.12), housing, top + Vector3(x, 0.03, -0.92))
	for index: int in range(6):
		var stack: Vector3 = top + Vector3(-1.6 + 0.62 * float(index), 0.0, 0.5 + 0.25 * float(index % 2))
		var height: float = 0.06 + 0.05 * float((index * 7) % 4)
		_block(props, "FileStack", Vector3(0.26, height, 0.34), _mat("file_board", Color("5d6658")), stack + Vector3(0, height * 0.5, 0))
		_block(props, "FileStackPaper", Vector3(0.24, height - 0.01, 0.33), _mat("paper", PAPER), stack + Vector3(0, height * 0.5, 0.008))
	_block(props, "Stamp", Vector3(0.06, 0.1, 0.06), _mat("rail_cap", STEEL, 0.5, 0.45), top + Vector3(0.3, 0.05, 0.1))
	_block(props, "InkPad", Vector3(0.14, 0.02, 0.1), _mat("cloth", CLOTH, 0.0, 0.95), top + Vector3(0.48, 0.01, 0.1))
	_shape.cylinder(props, "Mug", 0.045, 0.1, _mat("mug_ring", BELONGINGS[3]), top + Vector3(1.6, 0.05, -0.2), 10).rotation.x = PI * 0.5
	_desk_lamp(room, top + Vector3(-1.7, 0, -0.6), top + Vector3(-0.8, 0, 0.2))
	_block(props, "DeskLine", Vector3(4.02, 0.05, 0.03), _mat("seal_line", SEAL_LINE, 0.0, 0.9), Vector3(-26.0, 0.95, -10.98))
	# The records core: drawer faces on its four walls.
	for face: Array in [[Vector3(-26.0, 0, -6.0), "north"], [Vector3(-26.0, 0, -2.0), "south"]]:
		for column: int in range(4):
			for row: int in range(4):
				var at: Vector3 = face[0] + Vector3(-1.5 + float(column), 0.5 + 0.55 * float(row), 0) + MapDecoration.face_basis(face[1]).z * 0.012
				_block(props, "RecordDrawer", Vector3(0.86, 0.46, 0.02), _mat("cabinet", Color("4d5254"), 0.35, 0.6), at)
				_block(props, "RecordPull", Vector3(0.18, 0.03, 0.03), _mat("rail_cap", STEEL, 0.5, 0.45), at + MapDecoration.face_basis(face[1]).z * 0.02)
	_cabinets(room, Vector3(-34.0, 0, -15.5), "east", 5)
	_cabinets(room, Vector3(-34.0, 0, -4.0), "east", 3)
	_form_board(room, Vector3(-24.0, 1.8, -16.0), "south", 3.4)
	_form_board(room, Vector3(-18.0, 1.8, 0.0), "west", 3.0)
	_clock(room, Vector3(-31.0, 3.6, -16.0), "south")
	_wall_bench(room, Vector3(-20.0, 0, -16.0), "south", 3.0)

## The lane to the security core is all machinery: cable trays and conduit
## high on both walls, junction boxes, the seal's heavy frame and bolt rows,
## its control panel and the floor stripe a guard was told not to cross.
func _build_core() -> void:
	var room: Node3D = _room("SecurityCore")
	var props: Node3D = _props(room)
	var steel: StandardMaterial3D = _mat("rail_cap", STEEL, 0.5, 0.45)
	# Turned parts keep their own material: a merged surface cannot mix
	# them with boxes.
	var conduit_round: StandardMaterial3D = _mat("conduit_round", Color("62676a"), 0.45, 0.55)
	for side: float in [-1.0, 1.0]:
		var wall: float = 3.0 * side
		_block(props, "CableTray", Vector3(0.36, 0.1, 18.0), _mat("junction", Color("6a6f71"), 0.35, 0.55), Vector3(wall - side * 0.18, 5.6, 9.0))
		for lift: float in [0.0, 0.07]:
			_shape.rod(props, "Cable", Vector3(wall - side * (0.08 + lift), 5.68, 0.0), Vector3(wall - side * (0.08 + lift), 5.68, 18.0), 0.03, _mat("cable", Color("1f2224")), 4)
		_shape.rod(props, "Conduit", Vector3(wall - side * 0.06, 4.6, 0.2), Vector3(wall - side * 0.06, 4.6, 17.8), 0.05, conduit_round, 6)
		for z: float in [3.0, 9.0, 15.0]:
			_block(props, "JunctionBox", Vector3(0.14, 0.6, 0.5), _mat("junction", Color("6a6f71"), 0.35, 0.55), Vector3(wall - side * 0.07, 4.2, z))
			_block(props, "JunctionLamp", Vector3(0.02, 0.06, 0.06), _glow("console_keys", AMBER.darkened(0.25), 0.5), Vector3(wall - side * 0.145, 4.38, z + 0.15))
			_shape.rod(props, "Drop", Vector3(wall - side * 0.06, 4.45, z), Vector3(wall - side * 0.06, 4.6, z), 0.04, conduit_round, 6)
		for z: float in [4.0, 12.0]:
			_arm_pool(room, Vector3(wall, 6.8, z), Vector3(-side, 0, 0), 1.8, 9.5, 46.0)
	# The seal: jamb plates, a head beam, hinge blocks and bolt rows.
	for x: float in [-2.75, 2.75]:
		_block(props, "SealJamb", Vector3(0.5, 3.5, 0.12), steel, Vector3(x, 1.75, 17.94))
		for y: float in [0.7, 1.9, 3.1]:
			_block(props, "SealHinge", Vector3(0.22, 0.4, 0.18), _mat("conduit", Color("4a4f50"), 0.45, 0.55), Vector3(x, y, 17.88))
	_block(props, "SealHead", Vector3(6.0, 0.4, 0.14), steel, Vector3(0, 4.3, 17.93))
	for x: int in range(9):
		for y: float in [0.6, 3.0]:
			_block(props, "SealBolt", Vector3(0.09, 0.09, 0.04), _mat("bolt", Color("6d6a5c"), 0.5, 0.5), Vector3(-2.0 + 0.5 * float(x), y, 17.98))
	# The floor stripe in front of it, issued ochre, worn.
	for index: int in range(6):
		_block(props, "Stripe", Vector3(0.5, 0.006, 0.18), _mat("nosing", Color("8c7a45")), Vector3(-2.5 + 1.0 * float(index), 0.004, 16.6)).rotation.y = 0.6
	# The seal's panel on the lane wall: a housing and its amber keys.
	_block(props, "SealPanel", Vector3(0.1, 0.8, 0.6), _mat("console_top", Color("3d4245"), 0.3, 0.6), Vector3(2.95, 1.4, 16.4))
	for key: int in range(6):
		_block(props, "SealKey", Vector3(0.02, 0.07, 0.1), _glow("console_keys", AMBER.darkened(0.25), 0.5), Vector3(2.89, 1.2 + 0.12 * float(key % 3), 16.25 + 0.3 * float(key / 3)))

## Voss's assembly chamber: hangings on the north wall either side of the
## Union seal and the sitting terminal, a runner from the seal to her desk, the desk's cloth and
## microphones, benches for the delegates along both walls and floods on two
## beams. Decoration only: the people in this room and what happens to them
## belong to the mission, not to this dressing.
func _build_chamber() -> void:
	var room: Node3D = _room("Chamber")
	var props: Node3D = _props(room)
	for z: float in [24.0, 30.0]:
		_beam(room, Vector3(-14, 4.62, z), Vector3(14, 4.62, z))
		for x: float in [-8.0, 0.0, 8.0]:
			_pool(room, Vector3(x, 4.35, z), 2.6, 9.0, 56.0, 4.5)
	for x: float in [-9.0, 9.0]:
		_hanging(room, Vector3(x, 2.4, 34.0), "north", 2.4, 3.6)
	# A runner from the seal to the desk in the Union's black cloth, edged
	# with its thin red line: paint on the floor, not a light or a red carpet.
	_block(props, "Runner", Vector3(2.0, 0.006, 9.6), _mat("cloth", CLOTH, 0.0, 0.95), Vector3(0, 0.003, 25.0))
	for x: float in [-0.94, 0.94]:
		_block(props, "RunnerEdge", Vector3(0.05, 0.007, 9.6), _mat("seal_line", SEAL_LINE, 0.0, 0.9), Vector3(x, 0.0035, 25.0))
	# The desk's front cloth, its microphones and papers along the front edge.
	_block(props, "DeskCloth", Vector3(6.02, 1.1, 0.03), _mat("cloth", CLOTH, 0.0, 0.95), Vector3(0, 0.6, 29.98))
	_block(props, "DeskClothLine", Vector3(6.04, 0.06, 0.035), _mat("seal_line", SEAL_LINE, 0.0, 0.9), Vector3(0, 1.08, 29.975))
	for x: float in [-2.2, 2.2]:
		_shape.rod(props, "DeskMicrophone", Vector3(x, 1.22, 30.5), Vector3(x, 1.5, 30.25), 0.012, _mat("rail_cap_round", STEEL, 0.5, 0.45), 4)
		_block(props, "DeskPapers", Vector3(0.3, 0.02, 0.4), _mat("paper", PAPER), Vector3(x + 0.5, 1.21, 30.6))
	# Delegates' benches along both walls, and a clock with no numerals.
	for side: Array in [[-14.0, "east", 20.3], [14.0, "west", 23.7]]:
		_wall_bench(room, Vector3(side[0], 0, 32.0), side[1], 3.4)
		_cabinets(room, Vector3(side[0], 0, side[2]), side[1], 3)
	_clock(room, Vector3(-6.0, 3.9, 20.0), "south")
