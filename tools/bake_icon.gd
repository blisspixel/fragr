extends SceneTree
## Run from the repo root: godot --headless --path client --script ../tools/bake_icon.gd
## Draws the fragr mark (ring, inverted triangle, ember eye) as hard pixels at 16
## and 32, then writes the project SVG, the Windows ICO and the macOS ICNS from
## those two grids. Larger sizes are nearest-neighbour multiples, so every size
## stays pixel-crisp. Colours come from docs/palette.json.

const PREVIEW_DIR: String = "res://../.agents/icon"
# At 16 px a computed circle breaks at the diagonals, so that size is placed by hand.
# . clear, k ink, M magenta_light, b bone, p outline_purple, e ember, h ember_hot
const GRID_16: Array[String] = [
	".....MMMMMM.....",
	"...MMkkkkkkMM...",
	"..MkkkkkkkkkkM..",
	".MkkkkkkkkkkkkM.",
	".MbbbbbbbbbbbbM.",
	"MkkbppppppppbkkM",
	"MkkkbpeeeepbkkkM",
	"MkkkbpehhepbkkkM",
	"MkkkkbpeepbkkkkM",
	"MkkkkbppppbkkkkM",
	"MkkkkkbppbkkkkkM",
	".MkkkkbppbkkkkM.",
	".MkkkkkbbkkkkkM.",
	"..MkkkkkkkkkkM..",
	"...MMkkkkkkMM...",
	".....MMMMMM.....",
]
const LEGEND: Dictionary = {"k": "ink", "M": "magenta_light", "b": "bone", "p": "outline_purple", "e": "ember", "h": "ember_hot"}
# ICO and ICNS entries: [size, source grid, integer scale].
const ICO_SIZES: Array = [[16, 16, 1], [32, 32, 1], [48, 16, 3], [64, 32, 2], [128, 32, 4], [256, 32, 8]]
const ICNS_ENTRIES: Array = [["icp4", 16, 1], ["icp5", 32, 1], ["ic11", 16, 2], ["ic12", 32, 2], ["ic07", 32, 4], ["ic08", 32, 8], ["ic13", 32, 8], ["ic09", 32, 16], ["ic14", 32, 16], ["ic10", 32, 32]]

var _palette: Dictionary = {}

func _initialize() -> void:
	if not _load_palette():
		quit(1)
		return
	var grids: Dictionary = {16: _placed(GRID_16), 32: _draw(32)}
	var svg: String = _svg(grids[32] as Image, 256)
	if not _write_text("res://icon.svg", svg):
		quit(1)
		return
	if not _write_bytes("res://icon.ico", _ico(grids)) or not _write_bytes("res://icon.icns", _icns(grids)):
		quit(1)
		return
	# The SVG must rasterize back to the exact pixel grid it was written from.
	var rendered: Image = Image.new()
	if rendered.load_svg_from_string(svg, 32.0 / 256.0) != OK or not _same(rendered, grids[32] as Image):
		push_error("icon bake: icon.svg does not rasterize to the 32 px grid")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))
	for size: int in [16, 32]:
		(grids[size] as Image).save_png(ProjectSettings.globalize_path("%s/icon_%d.png" % [PREVIEW_DIR, size]))
	_scaled(grids[32] as Image, 8).save_png(ProjectSettings.globalize_path(PREVIEW_DIR + "/icon_256.png"))
	_scaled(grids[16] as Image, 16).save_png(ProjectSettings.globalize_path(PREVIEW_DIR + "/icon_16_zoom.png"))
	print("icon bake: PASS, icon.svg, icon.ico (%d sizes) and icon.icns (%d entries) written" % [ICO_SIZES.size(), ICNS_ENTRIES.size()])
	quit()

func _load_palette() -> bool:
	var text: String = FileAccess.get_file_as_string("res://../docs/palette.json")
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("icon bake: docs/palette.json is not an object")
		return false
	for key: String in ["ink", "outline_purple", "magenta_muted", "magenta_light", "bone", "ember", "ember_hot"]:
		var value: Variant = (parsed as Dictionary).get(key)
		if not value is Array or (value as Array).size() != 4:
			push_error("icon bake: palette entry %s is missing" % key)
			return false
		var rgba: Array = value as Array
		_palette[key] = Color8(int(rgba[0]), int(rgba[1]), int(rgba[2]), int(rgba[3]))
	return true

func _placed(rows: Array[String]) -> Image:
	var image: Image = Image.create_empty(rows.size(), rows.size(), false, Image.FORMAT_RGBA8)
	for y: int in rows.size():
		for x: int in rows[y].length():
			var key: String = rows[y][x]
			if LEGEND.has(key):
				image.set_pixel(x, y, _palette[LEGEND[key]])
	return image

## Pixel-centre tests in a unit square, with two pixel strokes.
func _draw(size: int) -> Image:
	var image: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var px: float = 1.0 / size
	var stroke: float = px * 2.0
	var centre: Vector2 = Vector2(0.5, 0.5)
	var outer: float = 0.5 - px * 0.25
	var ring_in: float = outer - stroke
	# Inverted equilateral triangle inscribed in the ring's inner edge.
	var r: float = ring_in
	var a: Vector2 = centre + Vector2(-r * cos(PI / 6.0), -r * 0.5)
	var b: Vector2 = centre + Vector2(r * cos(PI / 6.0), -r * 0.5)
	var c: Vector2 = centre + Vector2(0.0, r)
	var eye: Vector2 = Vector2(0.5, a.y + (c.y - a.y) * 0.36)
	for y: int in size:
		for x: int in size:
			var p: Vector2 = Vector2((x + 0.5) * px, (y + 0.5) * px)
			var d: float = p.distance_to(centre)
			if d > outer:
				continue
			var colour: Color = _palette["ink"]
			if d > ring_in:
				colour = _palette["magenta_light"] if d > ring_in + stroke * 0.5 else _palette["magenta_muted"]
			else:
				var edge: float = minf(_edge(a, b, p), minf(_edge(b, c, p), _edge(c, a, p)))
				if edge >= 0.0:
					colour = _palette["bone"] if edge < stroke else _palette["outline_purple"]
				var e: Vector2 = (p - eye) / Vector2(px * 4.5, px * 2.5)
				if edge >= stroke and e.length() <= 1.0:
					colour = _palette["ember"]
					if (p - eye).length() <= px * 1.5:
						colour = _palette["ink"]
			image.set_pixel(x, y, colour)
	return image

## Signed distance from p to the directed edge, positive inside a clockwise triangle.
func _edge(from: Vector2, to: Vector2, p: Vector2) -> float:
	var direction: Vector2 = (to - from).normalized()
	return direction.cross(p - from)

func _scaled(source: Image, factor: int) -> Image:
	var copy: Image = source.duplicate() as Image
	copy.resize(source.get_width() * factor, source.get_height() * factor, Image.INTERPOLATE_NEAREST)
	return copy

func _same(left: Image, right: Image) -> bool:
	if left.get_size() != right.get_size():
		return false
	left.convert(Image.FORMAT_RGBA8)
	for y: int in left.get_height():
		for x: int in left.get_width():
			var l: Color = left.get_pixel(x, y)
			var r: Color = right.get_pixel(x, y)
			if l.a < 0.5 and r.a < 0.5:
				continue
			if absf(l.r - r.r) > 0.02 or absf(l.g - r.g) > 0.02 or absf(l.b - r.b) > 0.02 or absf(l.a - r.a) > 0.02:
				return false
	return true

## One rect per horizontal run of equal colour, drawn on a 32 unit grid.
func _svg(grid: Image, display: int) -> String:
	var n: int = grid.get_width()
	var lines: PackedStringArray = PackedStringArray()
	lines.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" shape-rendering="crispEdges">' % [display, display, n, n])
	for y: int in n:
		var x: int = 0
		while x < n:
			var colour: Color = grid.get_pixel(x, y)
			var run: int = 1
			while x + run < n and grid.get_pixel(x + run, y) == colour:
				run += 1
			if colour.a > 0.0:
				lines.append('<rect x="%d" y="%d" width="%d" height="1" fill="#%s"/>' % [x, y, run, colour.to_html(false)])
			x += run
	lines.append("</svg>")
	return "\n".join(lines) + "\n"

func _png(grids: Dictionary, grid: int, factor: int) -> PackedByteArray:
	return _scaled(grids[grid] as Image, factor).save_png_to_buffer()

func _ico(grids: Dictionary) -> PackedByteArray:
	var header: StreamPeerBuffer = StreamPeerBuffer.new()
	header.big_endian = false
	header.put_u16(0)
	header.put_u16(1)
	header.put_u16(ICO_SIZES.size())
	var blobs: Array[PackedByteArray] = []
	var offset: int = 6 + 16 * ICO_SIZES.size()
	for entry: Array in ICO_SIZES:
		var blob: PackedByteArray = _png(grids, int(entry[1]), int(entry[2]))
		var size: int = int(entry[0])
		header.put_u8(0 if size >= 256 else size)
		header.put_u8(0 if size >= 256 else size)
		header.put_u8(0)
		header.put_u8(0)
		header.put_u16(1)
		header.put_u16(32)
		header.put_u32(blob.size())
		header.put_u32(offset)
		offset += blob.size()
		blobs.append(blob)
	var out: PackedByteArray = header.data_array
	for blob: PackedByteArray in blobs:
		out.append_array(blob)
	return out

func _icns(grids: Dictionary) -> PackedByteArray:
	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	body.big_endian = true
	for entry: Array in ICNS_ENTRIES:
		var blob: PackedByteArray = _png(grids, int(entry[1]), int(entry[2]))
		body.put_data(str(entry[0]).to_ascii_buffer())
		body.put_u32(blob.size() + 8)
		body.put_data(blob)
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	out.big_endian = true
	out.put_data("icns".to_ascii_buffer())
	out.put_u32(body.data_array.size() + 8)
	out.put_data(body.data_array)
	return out.data_array

func _write_text(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("icon bake: could not write %s" % path)
		return false
	file.store_string(text)
	return true

func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("icon bake: could not write %s" % path)
		return false
	file.store_buffer(bytes)
	return true
