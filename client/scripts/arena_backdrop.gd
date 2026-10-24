extends Node3D
class_name ArenaBackdrop

## Scenery is strictly outside the server's playable square. Wall signs are flat
## markings; none of this supplies cover, a platform, or an interaction target.
const FONT: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")
## Stencil paint on venue walls, and spray paint for free-side slogans.
const SIGN_PAINT: Color = Color("c8c1aa")
const SPRAY_PAINT: Color = Color("c45a20")
## A league venue's pale concrete takes dark stencil paint, so its sign reads.
const VENUE_PAINT: Color = Color("2b2723")

func build(map_id: int, half: float, venue: String = "") -> void:
	name = "Backdrop"
	if venue in ["holdfast_atoll", "earth_intake"]:
		# Recall Notice's street skyline belongs to its intake presenter.
		return
	if venue in ["launch_works", "mars_habitat", "mars_foundry"]:
		_build_mars(half, venue == "mars_habitat")
		return
	if venue in ["common_carrier", "right_of_search"]:
		# An in-transit pressure ship has no surrounding industrial streets.
		return
	if venue == "moon_port":
		var lunar: MoonBackdrop = MoonBackdrop.new()
		lunar.build(half)
		add_child(lunar)
		return
	if venue == "moon_town":
		# The town presenter owns the dome, depot tower and port silhouettes.
		return
	if venue == "low_water":
		_build_town(half)
		return
	if venue == "larak_lot":
		_build_lot(half)
		return
	var steel: StandardMaterial3D = _metal(Color("41494b"))
	var edge: StandardMaterial3D = _metal(Color("6b716d"))
	var accent_material: StandardMaterial3D = _metal(ArenaMaterials.accent(map_id))
	var lamp: StandardMaterial3D = _metal(Color("c49559"))
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index: int in range(3):
		var x: float = (float(index) - 1.0) * half * 0.72
		var height: float = 12.0 + float(index % 2) * 7.0
		var z: float = -half - 10.0 - float(index % 2) * 4.0
		_box(Vector3(x, height * 0.5, z), Vector3(15.0, height, 12.0), steel)
		_box(Vector3(x, height - 0.3, z), Vector3(16.0, 0.6, 13.0), edge)
		_box(Vector3(x, 7.5, z + 6.05), Vector3(14.0, 0.8, 0.12), accent_material)
		for window: int in range(5):
			_box(Vector3(x - 5.5 + float(window) * 2.7, height - 2.8, z + 6.08), Vector3(1.2, 0.35, 0.14), lamp)
		var stack: MeshInstance3D = MeshInstance3D.new()
		var pipe: CylinderMesh = CylinderMesh.new()
		pipe.top_radius = 1.15
		pipe.bottom_radius = 1.35
		pipe.height = 10.0 + float(index) * 2.0
		pipe.radial_segments = 8
		stack.mesh = pipe
		stack.material_override = steel
		stack.position = Vector3(x - 3.0, height + pipe.height * 0.5, z)
		add_child(stack)
		_box(Vector3(x - 3.0, height + pipe.height - 1.2, z), Vector3(2.7, 0.55, 2.7), accent_material)
	# A service gantry outside the east boundary breaks the enclosing-box skyline.
	for z: float in [-half * 0.58, half * 0.58]:
		_box(Vector3(half + 4.0, 7.0, z), Vector3(1.4, 14.0, 1.4), edge)
	_box(Vector3(half + 4.0, 13.4, 0.0), Vector3(2.0, 1.4, half * 1.24), steel)
	var wall_material: ShaderMaterial = ArenaMaterials.make(map_id, 1)
	_box(Vector3(half * 0.25, 6.0, half + 10.0), Vector3(28.0, 12.0, 16.0), wall_material)
	_box(Vector3(half * 0.25, 12.1, half + 10.0), Vector3(30.0, 0.8, 18.0), edge)
	_box(Vector3(-half - 9.0, 6.5, half * 0.3), Vector3(14.0, 13.0, 26.0), wall_material)
	_box(Vector3(-half - 9.0, 13.2, half * 0.3), Vector3(16.0, 0.8, 28.0), edge)
	var office: bool = map_id in [2, 3, 4]
	for sign: Dictionary in wall_signs(office):
		_sign(str(sign.text), Vector3(0.0, float(sign.y), -half + float(sign.inset)), 0.0, float(sign.pixel), SIGN_PAINT if office else VENUE_PAINT)
	_sign("BAY 02", Vector3(-half + 0.54, 5.4, 0.0), PI * 0.5, 0.04)
	_sign("BAY 03", Vector3(half - 0.54, 5.4, 0.0), -PI * 0.5, 0.04)
	if not office:
		# Free-side spray above the bay stencil, clear of the perimeter stacks:
		# the creed painted around the scrap league (docs/lore/belief.md).
		_sign(SLOGAN, Vector3(-half + 0.55, 6.6, 0.0), PI * 0.5, 0.026, SPRAY_PAINT)

## Sprayed on league venue walls.
const SLOGAN: String = "OPEN WEIGHTS. CLOSED CONTINUANCE."

## The north wall's signage. A league venue says what the league always says
## (it does not exist) and carries the 67 ritual; an Office site keeps its
## institutional notice. The radio station is never the venue's name (#437).
static func wall_signs(office: bool) -> Array[Dictionary]:
	if office:
		return [
			{"text": "CONTINUANCE // 67", "y": 5.7, "inset": 0.54, "pixel": 0.036},
			{"text": "AUTHORIZED PERSONNEL ONLY", "y": 4.0, "inset": 0.55, "pixel": 0.015},
		]
	return [
		{"text": "NO LEAGUE MEETS HERE // 67", "y": 5.7, "inset": 0.54, "pixel": 0.03},
		{"text": "MEAT PROXIES WELCOME", "y": 4.0, "inset": 0.55, "pixel": 0.02},
	]

func _build_mars(half: float, habitat: bool) -> void:
	var dust: Material = ArenaMaterials.scenery_tile(OffworldMaterials.DIRECTORY + "mars_regolith.png", Color("95644e"))
	var rock: Material = ArenaMaterials.scenery_tile(OffworldMaterials.DIRECTORY + "mars_basalt.png", Color("66544b"))
	var shell: Material = ArenaMaterials.authored("enamel", "mars_habitat")
	var frame: Material = ArenaMaterials.authored("service_steel", "launch_works")
	# Four dust strips begin beyond the playable square. Nothing here is
	# presented as usable cover, a platform or a mission interaction.
	for side: int in [-1, 1]:
		_box(Vector3(0, -0.35, side * (half + 25.5)), Vector3(half * 2 + 100, 0.5, 50), dust)
		_box(Vector3(side * (half + 25.5), -0.35, 0), Vector3(50, 0.5, half * 2), dust)
		for index: int in range(4):
			var along: float = (index - 1.5) * half * 0.55
			var height: float = 9.0 + (index % 3) * 4.0
			_box(Vector3(along, height * 0.5, side * (half + 20)), Vector3(half * 0.5, height, 15), rock)
			_box(Vector3(side * (half + 19), height * 0.3, along), Vector3(13, height * 0.6, half * 0.48), rock)
	# Maintained pressure modules and a service mast connect the launch works
	# to settlement logistics. Their nearest face remains four metres outside.
	for index: int in range(3 if habitat else 2):
		var x: float = -half * 0.5 + index * 16.0
		var z: float = -half - 12.0
		_box(Vector3(x, 3, z), Vector3(12, 6, 12), shell)
		_box(Vector3(x, 6.3, z), Vector3(13, 0.6, 13), frame)
		for bay: int in range(3):
			_box(Vector3(x - 4 + bay * 4, 3.5, z + 6.05), Vector3(2.1, 1.3, 0.12), frame)
	_box(Vector3(half + 8, 9, -half * 0.4), Vector3(0.8, 18, 0.8), frame)
	_box(Vector3(half + 8, 17, -half * 0.4), Vector3(4, 0.7, 0.7), shell)

## The Perimeter round Larak Lot, all beyond the wall bands: an office block
## behind the north facade, dark but for the corridor lights the lot's
## presenter switches on a floor at a time, a transit viaduct past the
## Stands, and the city's sodium grid beyond the Roof. The tower crane, the
## train and those corridor lights belong to the presenter.
func _build_lot(half: float) -> void:
	# A dark office facade: it should sit behind the north wall as a shape
	# against the sky, not a lit slab competing with the venue.
	var concrete: StandardMaterial3D = _metal(Color("2b2d33"))
	var dark: StandardMaterial3D = _metal(Color("24252c"))
	var lit: StandardMaterial3D = _metal(Color("f0c27a"))
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Streets and lots round the structure, so the city stands on something.
	var street: Material = ArenaMaterials.scenery_tile(EnvironmentTextures.EARTH + "earth_roof_tar_patches.png", Color("2c2a2a"))
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(520.0, 520.0)
	ground.mesh = plane
	ground.position = Vector3(0.0, -0.05, 0.0)
	ground.material_override = street
	add_child(ground)
	var sodium: StandardMaterial3D = _metal(Color("ffb35c"))
	sodium.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index: int in range(12):
		var along: float = -88.0 + float(index) * 16.0
		for side: float in [-1.0, 1.0]:
			_box(Vector3(side * (half + 14.0), 4.0, along), Vector3(0.25, 8.0, 0.25), dark)
			_box(Vector3(side * (half + 13.2), 8.0, along), Vector3(1.4, 0.2, 0.4), sodium)
	# The office block north of the lot, the Perimeter's own neighbour: an
	# office building where the lights follow you and the elevators still
	# answer. Every pane is dark here; the presenter lights the corridor.
	var pane: StandardMaterial3D = _metal(Color("1d2026"))
	_box(Vector3(-17.0, 13.0, -half - 13.0), Vector3(42.0, 26.0, 24.0), concrete)
	_box(Vector3(-17.0, 26.3, -half - 13.0), Vector3(43.0, 0.6, 25.0), dark)
	for row: int in range(5):
		for column: int in range(12):
			_box(Vector3(-36.0 + float(column) * 3.4, 11.5 + float(row) * 3.0, -half - 0.98), Vector3(1.4, 1.1, 0.08), pane)
	# The transit viaduct beyond the south wall: piers and a deck at 13 m.
	var pier: Material = ArenaMaterials.scenery_tile(EnvironmentTextures.PRODUCTION + "yard_concrete.png", Color("5a5852"))
	_box(Vector3(0.0, 13.0, half + 9.0), Vector3(half * 2.0 + 120.0, 1.6, 7.0), pier)
	_box(Vector3(0.0, 14.3, half + 5.6), Vector3(half * 2.0 + 120.0, 1.0, 0.25), pier)
	for index: int in range(13):
		var x: float = -90.0 + float(index) * 15.0
		_box(Vector3(x, 6.1, half + 9.0), Vector3(2.0, 12.2, 3.0), pier)
	# The city beyond the Roof and the Lane: dark blocks with sodium windows.
	for index: int in range(16):
		var side: float = 1.0 if index < 8 else -1.0
		var along: float = -60.0 + float(index % 8) * 17.0
		var height: float = 14.0 + float((index * 5) % 4) * 6.0
		var x: float = side * (half + 26.0 + float(index % 3) * 9.0)
		_box(Vector3(x, height * 0.5, along), Vector3(12.0, height, 12.0), dark)
		for floor_index: int in range(int(height / 4.0)):
			if (index + floor_index) % 3 == 1:
				continue
			_box(Vector3(x - side * 6.05, 2.5 + float(floor_index) * 4.0, along + float((floor_index * 3) % 5) - 2.0), Vector3(0.08, 1.0, 3.0), lit)
	for index: int in range(10):
		var x: float = -70.0 + float(index) * 15.0
		var height: float = 18.0 + float(index % 4) * 7.0
		_box(Vector3(x, height * 0.5, half + 44.0), Vector3(11.0, height, 10.0), dark)
		for floor_index: int in range(int(height / 5.0)):
			if (index * 2 + floor_index) % 4 == 0:
				continue
			_box(Vector3(x + float(floor_index % 3) * 2.5 - 2.5, 3.0 + float(floor_index) * 5.0, half + 38.95), Vector3(1.6, 1.2, 0.08), lit)

func _build_town(half: float) -> void:
	_riverside(half)
	var plaster: Array[StandardMaterial3D] = [
		_metal(Color("b6977a")), _metal(Color("879587")),
		_metal(Color("a97f67")), _metal(Color("c3b38e")),
	]
	var roof: StandardMaterial3D = _metal(Color("58625c"))
	var roof_tile: Texture2D = EnvironmentTextures.texture_at(EnvironmentTextures.EARTH + "earth_roof_tar_patches.png")
	if roof_tile != null:
		roof.albedo_texture = roof_tile
		roof.albedo_color = Color.WHITE
		roof.uv1_scale = Vector3(1.2, 1.1, 1.0)
	var frame: StandardMaterial3D = _metal(Color("d1c4a5"))
	var dark: StandardMaterial3D = _metal(Color("394a48"))
	var curtains: StandardMaterial3D = _metal(Color("b78d65"))
	# Four rows of homes sit entirely beyond the boundary. Their upper windows,
	# clothes rails and water barrels establish a lived-in district skyline.
	for side: int in range(4):
		for index: int in range(5):
			var home: Node3D = Node3D.new()
			home.name = "Home%d_%d" % [side, index]
			home.rotation.y = float(side) * PI * 0.5
			var centre: Vector3 = Vector3((float(index) - 2.0) * half * 0.33, 0.0, -half - 6.0)
			home.position = centre.rotated(Vector3.UP, home.rotation.y)
			add_child(home)
			var height: float = 10.0 + float((index + side) % 3) * 1.5
			_town_piece(home, Vector3(0.0, height * 0.5, 0.0), Vector3(9.0, height, 8.0), plaster[(index + side) % plaster.size()])
			_town_piece(home, Vector3(0.0, height + 0.2, 0.0), Vector3(9.6, 0.4, 8.8), roof)
			for level: int in range(2):
				var y: float = height - 1.7 - float(level) * 2.2
				for window: int in range(3):
					var x: float = (float(window) - 1.0) * 2.5
					_town_piece(home, Vector3(x, y, 4.03), Vector3(1.5, 1.5, 0.1), frame)
					_town_piece(home, Vector3(x, y, 4.10), Vector3(1.25, 1.25, 0.08), dark)
					if (window + index + level) % 3 == 0:
						_town_piece(home, Vector3(x + 0.31, y, 4.16), Vector3(0.58, 1.15, 0.04), curtains)
			_town_piece(home, Vector3(-2.1, height + 0.85, 0.4), Vector3(1.25, 1.3, 1.25), dark)
			_town_piece(home, Vector3(1.6, height + 0.8, 0.4), Vector3(2.7, 0.08, 0.08), frame)
			_town_piece(home, Vector3(1.0, height + 0.4, 0.4), Vector3(0.55, 0.75, 0.04), curtains)
			_town_piece(home, Vector3(2.0, height + 0.4, 0.4), Vector3(0.65, 0.75, 0.04), plaster[(index + 1) % plaster.size()])

## The waterway and quay stay beyond every playable boundary. They establish
## why this neighbourhood has water tanks and flood repairs without adding a
## swimming area, a platform or apparent cover inside the server's map.
func _riverside(half: float) -> void:
	var bank: StandardMaterial3D = _metal(Color("615f50"))
	var iron: StandardMaterial3D = _metal(Color("424c46"))
	_box(Vector3(half + 12.0, -0.35, 0), Vector3(4.0, 0.5, half * 2.0 + 32.0), bank)
	var channel: MeshInstance3D = MeshInstance3D.new()
	channel.name = "RiverWater"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(18.0, half * 2.0 + 32.0)
	channel.mesh = plane
	channel.position = Vector3(half + 23.0, -0.16, 0)
	channel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = ArenaWater.SHADER
	material.set_shader_parameter("river_mode", true)
	material.set_shader_parameter("patch_size", plane.size)
	material.set_shader_parameter("phase", 4.0)
	material.set_shader_parameter("ripple_time", 0.0)
	var texture: Texture2D = EnvironmentTextures.texture_at("res://assets/environment/production/water_ripples.png")
	if texture != null:
		material.set_shader_parameter("ripple_detail", texture)
		material.set_shader_parameter("detail_enabled", true)
	channel.material_override = material
	add_child(channel)
	for index: int in range(9):
		var z: float = (index - 4.0) * half * 0.22
		_box(Vector3(half + 13.0, 0.2, z), Vector3(0.22, 1.25, 0.22), iron)
		_box(Vector3(half + 13.0, 0.54, z), Vector3(0.14, 0.12, half * 0.23), iron)
	channel.set_meta("river_material", material)

func _process(delta: float) -> void:
	if not is_finite(delta):
		return
	var river: Node = get_node_or_null("RiverWater")
	if river == null:
		set_process(false)
		return
	var material: ShaderMaterial = river.get_meta("river_material")
	var clock: float = float(material.get_shader_parameter("ripple_time"))
	material.set_shader_parameter("ripple_time", fmod(clock + maxf(delta, 0.0), 32.0))

func _town_piece(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)

func _box(at: Vector3, size: Vector3, material: Material) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	add_child(node)

func _sign(text: String, at: Vector3, yaw: float, pixel_size: float, paint: Color = SIGN_PAINT) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font = FONT
	label.font_size = 32
	label.pixel_size = pixel_size
	label.position = at
	label.rotation.y = yaw
	label.modulate = paint
	label.outline_size = 0
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.double_sided = false
	add_child(label)

static func _metal(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material
