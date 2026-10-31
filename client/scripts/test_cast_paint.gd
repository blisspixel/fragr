extends SceneTree

## Campaign people wear their own baked paint on existing bodies: Splice and
## Tern off the pale reserved base, Renn in the issued coat without red, and
## Level 8's held people no longer one cloned figure.
var _failures: PackedStringArray = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _run() -> void:
	_baked()
	_rules()
	_figures()
	await process_frame
	_finish()

func _baked() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(CastPaint.BAKED + "manifest.json"))
	_expect(manifest is Dictionary and manifest.get("schema") == 1 and manifest.get("entries") is Array, "manifest present")
	if not manifest is Dictionary:
		return
	_expect(manifest.get("painter_sha256") == FileAccess.get_sha256("res://scripts/cast_paint.gd"), "baked paint binds the current painter; rerun tools/bake_cast_paint.gd")
	var listed: Array[String] = []
	var bases: Dictionary[String, Color] = {}
	var paints: Dictionary[String, Color] = {}
	for entry: Dictionary in manifest["entries"]:
		var person: String = str(entry.get("person"))
		listed.append(person)
		var path: String = CastPaint.baked_path(person)
		_expect(entry.get("source") == CastPaint.source_for(person), "recorded source " + person)
		_expect(entry.get("source_sha256") == FileAccess.get_sha256(CastPaint.source_for(person)), "source art unchanged since bake " + person)
		_expect(entry.get("sha256") == FileAccess.get_sha256(path), "baked bytes match manifest " + person)
		var baked: Texture2D = CastPaint.texture(person)
		_expect(baked != null, "baked texture loads " + person)
		if baked == null:
			continue
		var image: Image = baked.get_image()
		if image.is_compressed():
			image.decompress()
		# Spot-check the bake against the painter on the person's own source.
		var body: Node = (load(CastPaint.source_for(person)) as PackedScene).instantiate()
		var source: Texture2D = CastPaint.source_texture(body)
		body.free()
		_expect(source != null and source.get_size() == baked.get_size(), "bake keeps the source atlas size " + person)
		if source == null:
			continue
		var original: Image = source.get_image()
		if original.is_compressed():
			original.decompress()
		var mismatched: int = 0
		var painted: int = 0
		var samples: Array[Color] = []
		var paint_sum: Color = Color(0, 0, 0, 0)
		for index: int in range(4096):
			var x: int = (index * 7919) % image.get_width()
			var y: int = (index * 104729 / image.get_width() + index * 31) % image.get_height()
			var texel: Color = original.get_pixel(x, y)
			var rule: Dictionary = CastPaint._rule(CastPaint.SCHEMES[person], texel)
			var expected: Color = texel if rule.is_empty() else CastPaint.paint(texel, rule)
			painted += 0 if rule.is_empty() else 1
			var actual: Color = image.get_pixel(x, y)
			if not rule.is_empty():
				paint_sum += actual
			if absf(actual.r - expected.r) > 0.01 or absf(actual.g - expected.g) > 0.01 or absf(actual.b - expected.b) > 0.01:
				mismatched += 1
			if actual.a > 0.5:
				samples.append(actual)
		_expect(mismatched == 0, "baked texels equal the painter " + person)
		_expect(painted > 400, "scheme repaints a real share of the art " + person)
		samples.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
		var base: Color = samples[samples.size() / 2]
		bases[person] = base
		paints[person] = paint_sum / float(maxi(painted, 1))
		# The colour picker rule on the composed body: never off-white or
		# black plus red. Renn's black coat carries no red at all.
		var checked: Dictionary = FactionPalette.check({"base": base})
		_expect(not checked["changed"], "colour picker rule keeps base " + person)
		_expect(not (base.v >= FactionPalette.OFF_WHITE_VALUE and base.s <= FactionPalette.OFF_WHITE_SATURATION), "no matte off-white base " + person)
	var expected_people: Array = CastPaint.SCHEMES.keys()
	expected_people.sort()
	listed.sort()
	_expect(listed == expected_people, "every scheme baked once")
	var held: Array[String] = ["captive_0", "captive_1", "captive_2", "captive_3", "splice", "tern", "renn"]
	for a: int in range(held.size()):
		for b: int in range(a + 1, held.size()):
			if paints.has(held[a]) and paints.has(held[b]):
				var one: Color = paints[held[a]]
				var two: Color = paints[held[b]]
				var apart: float = Vector3(one.r - two.r, one.g - two.g, one.b - two.b).length()
				_expect(apart > 0.12, "%s and %s read apart (%.3f)" % [held[a], held[b], apart])

func _rules() -> void:
	var rule: Dictionary = CastPaint.SCHEMES["splice"][0]
	var bone: Color = Color("ddd8cc")
	_expect(not CastPaint._rule(CastPaint.SCHEMES["splice"], bone).is_empty(), "Splice's pale plates match their rule")
	var ochre: Color = CastPaint.paint(bone, rule)
	_expect(ochre.v < FactionPalette.OFF_WHITE_VALUE and ochre.s > 0.4, "pale plate becomes saturated mid-value paint")
	_expect(is_equal_approx(CastPaint.paint(bone, rule).a, bone.a), "paint keeps alpha")
	var shade: Color = CastPaint.paint(bone.darkened(0.3), rule)
	_expect(shade.v < ochre.v, "paint keeps relative shading")
	_expect(CastPaint._rule(CastPaint.SCHEMES["splice"], Color("8a3e1c")).is_empty(), "rust repairs keep their own colour")
	_expect(CastPaint._rule(CastPaint.SCHEMES["renn"], Color("e3a888")).is_empty(), "Renn's face keeps its own skin")
	_expect(CastPaint.painted(null, "splice") == null and CastPaint.texture("nobody") == null, "unknown or missing art paints nothing")
	_expect(CastPaint.apply(null, "renn") == 0 and CastPaint.apply(root, "nobody") == 0, "apply refuses missing roots and schemes")

func _figures() -> void:
	var worn: Dictionary[String, Texture2D] = {}
	for person: String in ["splice", "tern", "renn", "captive_0", "captive_1", "captive_2", "captive_3"]:
		var figure: CivilianFigure = CivilianFigure.new()
		root.add_child(figure)
		figure.configure(person, Color.WHITE)
		var body: Node3D = figure.rigid.source_body if figure.rigid != null else (figure.skin.source_body if figure.skin != null else null)
		_expect(body != null and figure.strip == null, "live body, not the shared strip: " + person)
		if body == null:
			figure.free()
			continue
		var surfaces: int = 0
		for node: Node in body.find_children("*", "MeshInstance3D", true, false):
			var part: MeshInstance3D = node as MeshInstance3D
			for surface: int in range(part.mesh.get_surface_count()):
				var material: StandardMaterial3D = part.get_active_material(surface) as StandardMaterial3D
				if material != null and material.albedo_texture != null:
					_expect(material.albedo_texture == CastPaint.texture(person), "every textured surface wears baked paint: " + person)
					_expect(part.mesh.surface_get_material(surface) != material, "shared imported material untouched: " + person)
					worn[person] = material.albedo_texture
					surfaces += 1
		_expect(surfaces > 0, "painted surfaces present: " + person)
		if CastPaint.BODIES.has(person):
			_expect(figure.skin != null and figure.skin.kind == CastPaint.BODIES[person], "worn body kind " + person)
			_expect(is_equal_approx(figure.skin.scale.y, float(CastPaint.HEIGHTS[person])), "own height " + person)
			_expect(figure.skin.livery.is_empty(), "no faction livery or team tape on " + person)
		if person == "tern":
			var panels: Array[Node] = figure.skin.find_children("ShoulderPanel", "MeshInstance3D", true, false)
			_expect(panels.size() == 1 and ((panels[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color == CastPaint.TERN_EMBER, "Tern wears one ember shoulder panel")
		figure.free()
	_expect(worn.size() == 7 and worn.values().filter(func(t: Texture2D) -> bool: return worn.values().count(t) > 1).is_empty(), "no two people share one paint")
	var renn: CivilianFigure = CivilianFigure.new()
	root.add_child(renn)
	renn.configure("renn", Color.WHITE)
	_expect(renn.skin != null and renn.skin.accent_parts().is_empty(), "Renn carries no red armband or visor")
	renn.free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	for failure: String in _failures:
		push_error("test_cast_paint: " + failure)
	if _failures.is_empty():
		print("test_cast_paint: PASS baked personal paint, faction contract, distinct people and live figures")
	quit(0 if _failures.is_empty() else 1)
