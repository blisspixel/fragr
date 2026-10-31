class_name M17Dressing
extends M06Dressing

## The Forever Office's command galleries (docs/campaign/l17-peace-without-interruption.md,
## docs/design/earth.md "M15-17 reckoning"). The server owns every solid; this
## presenter only furnishes them: work left on the desks, chairs pushed back,
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
const ROOMS: Array[String] = ["CommandFloor", "NorthGallery", "EastGallery", "ServiceStair", "Windows"]

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
