class_name CastPaint
extends RefCounted

## Personal paint for named cast and campaign civilians on existing bodies
## (docs/lore/cast.md, "Visual continuity"; the faction readability contract
## in docs/ART_STORY_BIBLE.md). Each scheme recolours bands of a body's own
## art and keeps its shading, so a person reads as themselves at play
## distance without new geometry. A free body never ends on a matte off-white
## base or on black plus red. Presentation only; no outcome depends on it.

## Splice's own plates in the ochre of the Low Water paint bench, so rust
## repairs and the magenta wrist band stay theirs and nothing reads bone.
const SPLICE_OCHRE: Color = Color("a8782e")
## Tern's chassis in a darker, bluer gunmetal than the pale silver it read as
## under ship light, with the canon ember shoulder panel.
const TERN_GUNMETAL: Color = Color("4a5262")
const TERN_EMBER: Color = Color("d9682a")
## Renn's issued coat: Union black with its rank and red removed.
const RENN_COAT: Color = Color("1d1e22")
const RENN_SHIRT: Color = Color("55585f")

## Each rule matches a band of the source art, hue in degrees (optional) and
## saturation and value from 0 to 1, and paints it `to`. `ref` is the source
## value that lands exactly on `to`; brighter or darker texels keep their
## relative shading. The first matching rule wins.
const SCHEMES: Dictionary[String, Array] = {
	"splice": [
		{"sat": [0.0, 0.22], "val": [0.6, 1.01], "to": SPLICE_OCHRE, "ref": 0.86},
	],
	"tern": [
		{"sat": [0.0, 0.22], "val": [0.0, 1.01], "to": TERN_GUNMETAL, "ref": 0.36},
	],
	"renn": [
		# Rust utility jacket to the issued black coat; skin is lighter and
		# less saturated and stays.
		{"hue": [0.0, 45.0], "sat": [0.42, 1.01], "val": [0.0, 0.8], "to": RENN_COAT, "ref": 0.5},
		{"hue": [345.0, 360.0], "sat": [0.42, 1.01], "val": [0.0, 0.8], "to": RENN_COAT, "ref": 0.5},
		{"hue": [160.0, 240.0], "sat": [0.15, 1.01], "val": [0.0, 1.01], "to": RENN_SHIRT, "ref": 0.45},
	],
	# Level 8's held people: their own clothes and plates, no two alike.
	"captive_0": [
		{"hue": [0.0, 45.0], "sat": [0.42, 1.01], "val": [0.0, 0.8], "to": Color("566b34"), "ref": 0.5},
		{"hue": [160.0, 240.0], "sat": [0.15, 1.01], "val": [0.0, 1.01], "to": Color("c49a3e"), "ref": 0.45},
	],
	"captive_1": [
		{"sat": [0.0, 0.3], "val": [0.28, 0.66], "to": Color("9c5a2a"), "ref": 0.45},
	],
	"captive_2": [
		{"sat": [0.0, 0.3], "val": [0.28, 0.66], "to": Color("6e4a78"), "ref": 0.45},
	],
	"captive_3": [
		{"sat": [0.0, 0.3], "val": [0.28, 0.66], "to": Color("4f6a8e"), "ref": 0.45},
	],
}
## The body each campaign person wears, where it is not their own model.
const BODIES: Dictionary[String, String] = {
	"renn": "human",
	"captive_0": "human",
	"captive_1": "synthetic",
	"captive_2": "synthetic",
	"captive_3": "synthetic",
}
## Small height differences so held people never stand as a cloned row.
const HEIGHTS: Dictionary[String, float] = {
	"renn": 1.02,
	"captive_0": 0.95,
	"captive_1": 1.04,
	"captive_2": 0.92,
	"captive_3": 0.99,
}

## Baked paint, one texture per person: painting a 1024 pixel atlas in
## GDScript takes most of a second, so `tools/bake_cast_paint.gd` paints
## offline and the live client only loads the result.
const BAKED: String = "res://assets/characters/cast/"


static func source_for(person: String) -> String:
	if person == "splice":
		return SpliceCharacter.SOURCE
	if person == "tern":
		return SkinnedCharacter.SOURCES["tern"]
	return SkinnedCharacter.SOURCES.get(BODIES.get(person, ""), "")


static func baked_path(person: String) -> String:
	return BAKED + person + ".png"


## The baked texture for `person`, or null when it is missing.
static func texture(person: String) -> Texture2D:
	var path: String = baked_path(person)
	if not SCHEMES.has(person) or not ResourceLoader.exists(path, "Texture2D"):
		return null
	return load(path) as Texture2D


## The source art in `person`'s paint, for the offline bake and checks.
## Unknown schemes and unreadable art return null.
static func painted(source: Texture2D, person: String) -> Image:
	if source == null or not SCHEMES.has(person):
		return null
	var image: Image = source.get_image()
	if image == null:
		return null
	image = image.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK:
		return null
	image.clear_mipmaps()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var rules: Array = SCHEMES[person]
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var texel: Color = image.get_pixel(x, y)
			var rule: Dictionary = _rule(rules, texel)
			if not rule.is_empty():
				image.set_pixel(x, y, paint(texel, rule))
	return image


static func _rule(rules: Array, texel: Color) -> Dictionary:
	for rule: Dictionary in rules:
		if texel.s < rule["sat"][0] or texel.s >= rule["sat"][1] \
				or texel.v < rule["val"][0] or texel.v >= rule["val"][1]:
			continue
		if rule.has("hue"):
			var hue: float = FactionPalette.hue_degrees(texel)
			if hue < rule["hue"][0] or hue >= rule["hue"][1]:
				continue
		return rule
	return {}


## One texel in a rule's paint, keeping its value relative to the rule's
## reference so folds, seams and wear survive the new colour.
static func paint(texel: Color, rule: Dictionary) -> Color:
	var to: Color = rule["to"]
	var value: float = clampf(to.v * texel.v / maxf(float(rule["ref"]), 0.01), 0.0, 1.0)
	return Color.from_hsv(to.h, to.s, value, texel.a)


## The one body texture a person's source art is painted on, or null when
## the source holds none or more than one.
static func source_texture(root: Node) -> Texture2D:
	var found: Texture2D = null
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node as MeshInstance3D
		if part.mesh == null:
			continue
		for surface: int in range(part.mesh.get_surface_count()):
			var material: StandardMaterial3D = part.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null or material.albedo_texture == null:
				continue
			if found != null and found != material.albedo_texture:
				return null
			found = material.albedo_texture
	return found


## Wear `person`'s baked paint on every textured surface under `root`, with
## instance materials; the shared imported resources stay untouched. A body
## that SkinnedCharacter.dress() later dresses goes back to its own art, so
## only undressed civilians wear this. Returns the surfaces painted.
static func apply(root: Node, person: String) -> int:
	var baked: Texture2D = texture(person)
	if root == null or baked == null:
		return 0
	var count: int = 0
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node as MeshInstance3D
		if part.mesh == null:
			continue
		for surface: int in range(part.mesh.get_surface_count()):
			var material: StandardMaterial3D = part.get_active_material(surface) as StandardMaterial3D
			if material == null or material.albedo_texture == null:
				continue
			var own: StandardMaterial3D = material if part.get_surface_override_material(surface) == material \
				else material.duplicate() as StandardMaterial3D
			own.albedo_texture = baked
			own.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			part.set_surface_override_material(surface, own)
			count += 1
	return count


## A painted panel over one shoulder of a live body, fitted where the team
## tape would sit but shorter and without ink edges: a person's own mark, not
## a team accent.
static func shoulder_panel(view: SkinnedCharacter, bone: String, color: Color) -> MeshInstance3D:
	if view == null or view.skeleton == null or view.skeleton.find_bone(bone) < 0:
		return null
	for band: Dictionary in BodyLivery.fitting_for(view).get("bands", []):
		if str(band["bone"]) != bone:
			continue
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		var attachment: BoneAttachment3D = BoneAttachment3D.new()
		attachment.name = "ShoulderPanel" + bone
		attachment.bone_name = bone
		view.skeleton.add_child(attachment)
		var panel: MeshInstance3D = MeshInstance3D.new()
		panel.name = "ShoulderPanel"
		panel.mesh = BodyLivery.tape_mesh()
		panel.material_override = material
		panel.transform = (band["transform"] as Transform3D) \
			* Transform3D(Basis.from_scale(Vector3(1.08, 0.8, 1.08)), Vector3(0, -0.15, 0))
		panel.layers = ArenaSky.ACTOR_LAYERS
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		attachment.add_child(panel)
		return panel
	return null
