extends SceneTree

## Bake Larak Lot's decal atlas: oil, tyre skids and burns, scorch (the Rocket
## cradle's blast mark among them), betting slips and tickets, and league
## spray tags with their drips. Every mark is drawn at 16 texels per metre in
## palette.json keys with stepped alpha, so a decal shares the surfaces'
## pixel grain and the presenter lays each cell at exactly its own size.
## Deterministic: the same seed draws the same atlas, so the committed file
## can be rebaked and diffed.
##
##   "$GODOT_BIN" --headless --path client --script ../tools/bake_larak_decals.gd
##
## The cells and the atlas path are LarakLot.DECAL_CELLS and DECAL_ATLAS; tags
## carry no letters (lettering stays in keyed world signs).

var _palette: Dictionary = {}
var _random: RandomNumberGenerator = RandomNumberGenerator.new()

func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/palette.json"))
	if not parsed is Dictionary:
		push_error("bake_larak_decals: unreadable palette")
		quit(1)
		return
	_palette = parsed
	var atlas: Image = Image.create(LarakLot.DECAL_ATLAS_SIZE.x, LarakLot.DECAL_ATLAS_SIZE.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var names: Array = LarakLot.DECAL_CELLS.keys()
	names.sort()
	for index: int in range(names.size()):
		var cell: String = names[index]
		var rect: Rect2i = LarakLot.DECAL_CELLS[cell]
		_random.seed = 67 + index * 7919
		if cell.begins_with("oil"):
			_oil(atlas, rect)
		elif cell.begins_with("scorch"):
			_scorch(atlas, rect, cell == "scorch_pad")
		elif cell.begins_with("skid"):
			_skid(atlas, rect)
		elif cell.begins_with("burn"):
			_burn(atlas, rect)
		elif cell.begins_with("slip") or cell.begins_with("ticket"):
			_slip(atlas, rect, cell.begins_with("ticket"))
		elif cell.begins_with("tag"):
			_tag(atlas, rect, ["ember_hot", "magenta_muted", "dust_light"][index % 3])
		elif cell.begins_with("drips"):
			_drips(atlas, rect)
	var path: String = LarakLot.DECAL_ATLAS
	if atlas.save_png(ProjectSettings.globalize_path(path)) != OK:
		push_error("bake_larak_decals: cannot write " + path)
		quit(1)
		return
	print("bake_larak_decals: PASS %d cells in %s" % [names.size(), path])
	quit(0)

func _key(name: String, alpha: float) -> Color:
	var value: Array = _palette[name]
	return Color8(int(value[0]), int(value[1]), int(value[2]), int(round(alpha * 255.0)))

func _put(image: Image, rect: Rect2i, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= rect.size.x or y >= rect.size.y:
		return
	var at: Vector2i = rect.position + Vector2i(x, y)
	# A mark never lightens a darker mark beneath it in its own cell.
	if image.get_pixelv(at).a <= color.a:
		image.set_pixelv(at, color)

## Smooth value noise in [0, 1) on a coarse grid, for ragged edges.
func _noise(x: float, y: float, salt: int) -> float:
	var ix: int = int(floor(x))
	var iy: int = int(floor(y))
	var fx: float = smoothstep(0.0, 1.0, x - floor(x))
	var fy: float = smoothstep(0.0, 1.0, y - floor(y))
	var a: float = _hash(ix, iy, salt)
	var b: float = _hash(ix + 1, iy, salt)
	var c: float = _hash(ix, iy + 1, salt)
	var d: float = _hash(ix + 1, iy + 1, salt)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)

func _hash(x: int, y: int, salt: int) -> float:
	var h: int = (x * 374761393 + y * 668265263 + salt * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10007.0

## A pooled stain: ink at the core, gunmetal at a ragged rim.
func _oil(image: Image, rect: Rect2i) -> void:
	var salt: int = _random.randi_range(1, 9999)
	var c: Vector2 = Vector2(rect.size) * 0.5
	for y: int in range(rect.size.y):
		for x: int in range(rect.size.x):
			var d: float = Vector2((float(x) + 0.5 - c.x) / (c.x - 0.5), (float(y) + 0.5 - c.y) / (c.y - 0.5)).length()
			d += (_noise(float(x) / 4.0, float(y) / 4.0, salt) - 0.5) * 0.55
			if d < 0.42:
				_put(image, rect, x, y, _key("ink", 0.62))
			elif d < 0.72:
				_put(image, rect, x, y, _key("ink", 0.45))
			elif d < 0.95:
				_put(image, rect, x, y, _key("gunmetal_dark", 0.32))
	for i: int in range(4):
		_put(image, rect, _random.randi_range(0, rect.size.x - 1), _random.randi_range(0, rect.size.y - 1), _key("ink", 0.4))

## Soot: a dark core, radial streaks, a thin outer haze and a few rust specks
## where the heat lifted the paint. The pad scorch is the Rocket's blast mark.
func _scorch(image: Image, rect: Rect2i, blast: bool) -> void:
	var salt: int = _random.randi_range(1, 9999)
	var c: Vector2 = Vector2(rect.size) * 0.5
	for y: int in range(rect.size.y):
		for x: int in range(rect.size.x):
			var offset: Vector2 = Vector2(float(x) + 0.5 - c.x, float(y) + 0.5 - c.y) / (c.x - 0.5)
			var d: float = offset.length()
			var streak: float = _noise(offset.angle() * (5.0 if blast else 3.0) + 20.0, d * 2.0, salt)
			d += (streak - 0.5) * (0.5 if blast else 0.35)
			if d < 0.3:
				_put(image, rect, x, y, _key("ink", 0.7))
			elif d < 0.6:
				_put(image, rect, x, y, _key("ink", 0.5))
			elif d < 0.85:
				_put(image, rect, x, y, _key("gunmetal_dark", 0.36))
			elif d < 1.0 and streak > 0.45:
				_put(image, rect, x, y, _key("gunmetal_dark", 0.2))
	for i: int in range(3 if blast else 1):
		var a: float = _random.randf() * TAU
		var r: float = (0.55 + _random.randf() * 0.25) * c.x
		_put(image, rect, int(c.x + cos(a) * r), int(c.y + sin(a) * r), _key("dust_rust", 0.55))

## One tyre's mark: a dark band with broken edges and lighter tread gaps.
func _skid(image: Image, rect: Rect2i) -> void:
	var salt: int = _random.randi_range(1, 9999)
	for x: int in range(rect.size.x):
		var fade: float = minf(float(x) + 1.0, float(rect.size.x - x)) / 3.0
		for y: int in range(rect.size.y):
			var edge: bool = y == 0 or y == rect.size.y - 1
			var n: float = _noise(float(x) / 2.0, float(y), salt)
			if edge and n < 0.5:
				continue
			var alpha: float = (0.5 if x % 3 != 0 else 0.36) * clampf(fade, 0.35, 1.0)
			_put(image, rect, x, y, _key("ink", snappedf(alpha, 0.05)))

## A doughnut burn: a curved run of rubber.
func _burn(image: Image, rect: Rect2i) -> void:
	for x: int in range(rect.size.x):
		var t: float = float(x) / float(rect.size.x - 1)
		var centre: float = float(rect.size.y - 1) * (0.2 + 0.6 * sin(t * PI))
		for y: int in range(rect.size.y):
			var d: float = absf(float(y) - centre)
			if d < 1.2:
				_put(image, rect, x, y, _key("ink", 0.6))
			elif d < 2.2:
				_put(image, rect, x, y, _key("ink", 0.32))

## A betting slip (bone with a printed line) or the league's ember ticket.
func _slip(image: Image, rect: Rect2i, ticket: bool) -> void:
	for y: int in range(rect.size.y):
		for x: int in range(rect.size.x):
			_put(image, rect, x, y, _key("ember" if ticket else "bone", 0.95))
	# A ticket's stub line is printed dark; a slip's print is a faint grey
	# corner, so at play size it reads as paper, not as a hole.
	if ticket:
		for x: int in range(1, rect.size.x - 1):
			_put(image, rect, x, 1, _key("ink", 1.0))
	else:
		_put(image, rect, rect.size.x - 1, rect.size.y - 1, _key("gunmetal_light", 1.0))

## A spray tag: a looping one-pixel stroke with a few doubled runs and drips
## falling from it. Shapes, never letters.
func _tag(image: Image, rect: Rect2i, key: String) -> void:
	var at: Vector2 = Vector2(2.0, float(rect.size.y) * 0.45)
	var heading: float = -0.3
	var steps: int = rect.size.x * 3
	for i: int in range(steps):
		heading += (_random.randf() - 0.5) * 0.9 + sin(float(i) * 0.35) * 0.25
		at += Vector2(cos(heading), sin(heading)) * 0.7
		at.x = clampf(at.x, 1.0, float(rect.size.x) - 2.0)
		at.y = clampf(at.y, 1.0, float(rect.size.y) * 0.7)
		if at.x >= float(rect.size.x) - 2.5:
			heading = PI - heading
		# A can's line is two texels wide, three where the hand slowed.
		_put(image, rect, int(at.x), int(at.y), _key(key, 0.9))
		_put(image, rect, int(at.x) + 1, int(at.y), _key(key, 0.9))
		if i % 5 == 0:
			_put(image, rect, int(at.x), int(at.y) + 1, _key(key, 0.9))
		if i % 23 == 11:
			for drop: int in range(1, _random.randi_range(2, 5)):
				_put(image, rect, int(at.x), int(at.y) + drop, _key(key, 0.75))

## A spray line with a row of drips under it, as a stencil leaves.
func _drips(image: Image, rect: Rect2i) -> void:
	for x: int in range(1, rect.size.x - 1):
		_put(image, rect, x, 2, _key("ember", 0.85))
		if x % 2 == 0:
			_put(image, rect, x, 3, _key("ember", 0.85))
		if _random.randf() < 0.3:
			for drop: int in range(4, _random.randi_range(5, rect.size.y - 1)):
				_put(image, rect, x, drop, _key("ember", 0.7))
