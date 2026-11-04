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
## Tern's berth crew in their own work colours.
const BERTH_DECKHAND_JACKET: Color = Color("7d4a5c")
const BERTH_DECKHAND_SHIRT: Color = Color("b49a6a")
const BERTH_RIGGER_PLATES: Color = Color("3a7550")

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
	# The Common Carrier's berth crew (Levels 9 and 10), Tern's people: a
	# deckhand in a berry work jacket over a sand shirt, and an agent rigger
	# in bottle-green plates. Mid-value beside Tern's gunmetal and
	# Splice's ochre, so the four free crew never read as one figure.
	"berth_crew_a": [
		{"hue": [0.0, 45.0], "sat": [0.42, 1.01], "val": [0.0, 0.8], "to": BERTH_DECKHAND_JACKET, "ref": 0.5},
		{"hue": [160.0, 240.0], "sat": [0.15, 1.01], "val": [0.0, 1.01], "to": BERTH_DECKHAND_SHIRT, "ref": 0.45},
	],
	"berth_crew_b": [
		{"sat": [0.0, 0.3], "val": [0.28, 0.66], "to": BERTH_RIGGER_PLATES, "ref": 0.45},
	],
}
## The body each campaign person wears, where it is not their own model.
const BODIES: Dictionary[String, String] = {
	"renn": "human",
	"captive_0": "human",
	"captive_1": "synthetic",
	"captive_2": "synthetic",
	"captive_3": "synthetic",
	"berth_crew_a": "human",
	"berth_crew_b": "synthetic",
}
## Small height differences so held people never stand as a cloned row.
const HEIGHTS: Dictionary[String, float] = {
	"renn": 1.02,
	"captive_0": 0.95,
	"captive_1": 1.04,
	"captive_2": 0.92,
	"captive_3": 0.99,
	"berth_crew_a": 0.97,
	"berth_crew_b": 1.06,
}

## Baked paint, one texture per person: painting a 1024 pixel atlas in
## GDScript takes most of a second, so `tools/bake_cast_paint.gd` paints
## offline and the live client only loads the result.
const BAKED: String = "res://assets/characters/cast/"


## Multiplayer and campaign fighter looks (FighterLooks): the free coalition
## in their own clothes on the shared human body. Each row repaints skin,
## hair, jacket, shirt and trousers, in that order, keeping the shading;
## boots stay their worn leather. Nobody in a uniform, nobody in Union black
## and red, nobody in off-white or cyan.
const HUMAN_LOOK_PAINT: Dictionary[String, Array] = {
	# A mechanic in a mustard work jacket over an olive shirt.
	"look_human_1": [Color("6b4430"), Color("1c1a1a"), Color("b08a2a"), Color("4f5a3a"), Color("3a3f4a")],
	# A grandmother with silver hair in a plum jacket: Gen Alpha, aged.
	"look_human_2": [Color("c08a64"), Color("a9a8a4"), Color("6a3a6e"), Color("b4904a"), Color("3e3530")],
	# Copper hair, a forest-green field jacket and khaki trousers.
	"look_human_3": [Color("e8b598"), Color("a4532a"), Color("3e6a3a"), Color("a87a50"), Color("6e6248")],
	# Grey at the temples, a faded indigo jacket and an ember shirt.
	"look_human_4": [Color("4f3224"), Color("8c8a86"), Color("3e508c"), Color("b4602e"), Color("3a3a2a")],
	# Dyed berry hair and a safety-orange salvage jacket.
	"look_human_5": [Color("a77452"), Color("6a2a5a"), Color("c86a24"), Color("2e2e30"), Color("48505a")],
	# Blond, a waxed canvas coat and a brick shirt.
	"look_human_6": [Color("d8a07c"), Color("c8a45a"), Color("9a7e4e"), Color("8c4a34"), Color("4a3a2c")],
	# A violet bomber over a mustard shirt.
	"look_human_7": [Color("5c3a2a"), Color("181616"), Color("5a3e8a"), Color("b49a4a"), Color("6a5a44")],
}
## Free agents on the shared synthetic body: the mid plates in the owner's
## own paint, the pale plates in a second colour so no free agent stands on
## a bone base. The dark frame and the screen face stay.
const SYNTHETIC_LOOK_PAINT: Dictionary[String, Array] = {
	# Field plate: olive-grey work plates and copper-coloured repairs.
	"look_synthetic_0": [Color("657064"), Color("a46740")],
	"look_synthetic_1": [Color("5d7a34"), Color("b0883a")],
	"look_synthetic_2": [Color("a8892c"), Color("5a4030")],
	"look_synthetic_3": [Color("3e4e96"), Color("c0703a")],
	"look_synthetic_4": [Color("6e3a64"), Color("b08a3c")],
}


## Every person this painter knows: campaign people and fighter looks.
static func people() -> Array[String]:
	var all: Array[String] = []
	for person: String in SCHEMES:
		all.append(person)
	for person: String in HUMAN_LOOK_PAINT:
		all.append(person)
	for person: String in SYNTHETIC_LOOK_PAINT:
		all.append(person)
	all.sort()
	return all


## The rules that paint `person`, or empty for an unknown person.
static func scheme(person: String) -> Array:
	if SCHEMES.has(person):
		return SCHEMES[person]
	if HUMAN_LOOK_PAINT.has(person):
		var paint: Array = HUMAN_LOOK_PAINT[person]
		return [
			# Skin on the face, neck and hands: lighter and less saturated
			# than the leather jacket around it.
			{"zone": ["head", "hands", "torso"], "hue": [0.0, 45.0], "sat": [0.2, 0.52], "val": [0.56, 1.01], "to": paint[0], "ref": 0.84},
			# Hair and brows: the dark of the head.
			{"zone": ["head"], "sat": [0.0, 0.62], "val": [0.0, 0.4], "to": paint[1], "ref": 0.2},
			# The jacket, collar to hem.
			{"zone": ["head", "torso", "arms", "legs"], "hue": [0.0, 45.0], "sat": [0.42, 1.01], "val": [0.0, 0.9], "to": paint[2], "ref": 0.55},
			{"zone": ["head", "torso", "arms", "legs"], "hue": [345.0, 360.0], "sat": [0.42, 1.01], "val": [0.0, 0.9], "to": paint[2], "ref": 0.55},
			# The shirt under it.
			{"zone": ["torso", "arms"], "hue": [160.0, 260.0], "sat": [0.1, 1.01], "val": [0.0, 1.01], "to": paint[3], "ref": 0.3},
			# Trousers.
			{"zone": ["legs", "torso"], "sat": [0.0, 0.32], "val": [0.0, 0.45], "to": paint[4], "ref": 0.22},
		]
	if SYNTHETIC_LOOK_PAINT.has(person):
		var plates: Array = SYNTHETIC_LOOK_PAINT[person]
		return [
			{"sat": [0.0, 0.3], "val": [0.28, 0.66], "to": plates[0], "ref": 0.45},
			{"sat": [0.0, 0.3], "val": [0.66, 1.01], "to": plates[1], "ref": 0.82},
		]
	return []


## Body zones, by the bone that carries most of each triangle: a rule may
## name zones so hair on the head is told from boots of the same brown.
const ZONES: Dictionary[String, int] = {"head": 1, "torso": 2, "arms": 3, "hands": 4, "legs": 5, "feet": 6}
const _ZONE_BONES: Dictionary[String, String] = {
	"neck": "head", "Head": "head", "head_end": "head", "headfront": "head",
	"Hips": "torso", "Spine": "torso", "Spine01": "torso", "Spine02": "torso",
	"LeftShoulder": "torso", "RightShoulder": "torso",
	"LeftArm": "arms", "RightArm": "arms", "LeftForeArm": "arms", "RightForeArm": "arms",
	"LeftHand": "hands", "RightHand": "hands",
	"LeftUpLeg": "legs", "RightUpLeg": "legs", "LeftLeg": "legs", "RightLeg": "legs",
	"LeftFoot": "feet", "RightFoot": "feet", "LeftToeBase": "feet", "RightToeBase": "feet",
}


## The zone of every texel of a body's atlas, as an L8 image (0 where no
## triangle lands), rasterised from the UVs of each skinned triangle. Offline
## only: the bake and its checks call it, the live client never does.
static func zones(root: Node, size: Vector2i) -> Image:
	var map: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_L8)
	if root == null:
		return map
	var skeleton: Skeleton3D = root.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node as MeshInstance3D
		if part.skin == null or part.mesh == null or skeleton == null:
			continue
		var owner: Dictionary[int, int] = {}
		for bind: int in range(part.skin.get_bind_count()):
			var bone: int = part.skin.get_bind_bone(bind)
			var bone_name: String = skeleton.get_bone_name(bone) if bone >= 0 else str(part.skin.get_bind_name(bind))
			if _ZONE_BONES.has(bone_name):
				owner[bind] = ZONES[_ZONE_BONES[bone_name]]
		for surface: int in range(part.mesh.get_surface_count()):
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			if not arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array or not arrays[Mesh.ARRAY_BONES] is PackedInt32Array \
					or not arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array or not arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				continue
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var per: int = bones.size() / maxi(uvs.size(), 1)
			for first: int in range(0, indices.size() - 2, 3):
				# The bone with the most weight across the triangle's corners.
				var totals: Dictionary[int, float] = {}
				for corner: int in range(3):
					var vertex: int = indices[first + corner]
					for slot: int in range(per):
						var bind: int = bones[vertex * per + slot]
						totals[bind] = totals.get(bind, 0.0) + weights[vertex * per + slot]
				var best: int = -1
				var heaviest: float = 0.0
				for bind: int in totals:
					if totals[bind] > heaviest:
						heaviest = totals[bind]
						best = bind
				if not owner.has(best):
					continue
				_fill(map, owner[best], uvs[indices[first]] * Vector2(size), uvs[indices[first + 1]] * Vector2(size),
					uvs[indices[first + 2]] * Vector2(size))
	return map


static func _fill(map: Image, zone: int, a: Vector2, b: Vector2, c: Vector2) -> void:
	var low: Vector2 = a.min(b).min(c)
	var high: Vector2 = a.max(b).max(c)
	var zone_color: Color = Color8(zone, zone, zone)
	for y: int in range(maxi(int(floor(low.y)), 0), mini(int(ceil(high.y)) + 1, map.get_height())):
		for x: int in range(maxi(int(floor(low.x)), 0), mini(int(ceil(high.x)) + 1, map.get_width())):
			if Geometry2D.point_is_inside_triangle(Vector2(x + 0.5, y + 0.5), a, b, c):
				map.set_pixel(x, y, zone_color)


static func zone_at(map: Image, x: int, y: int) -> int:
	if map == null or x < 0 or y < 0 or x >= map.get_width() or y >= map.get_height():
		return 0
	return map.get_pixel(x, y).r8


static func source_for(person: String) -> String:
	if person == "splice":
		return SpliceCharacter.SOURCE
	if person == "tern":
		return SkinnedCharacter.SOURCES["tern"]
	if HUMAN_LOOK_PAINT.has(person):
		return SkinnedCharacter.SOURCES[PlayerBody.HUMAN]
	if SYNTHETIC_LOOK_PAINT.has(person):
		return SkinnedCharacter.SOURCES[PlayerBody.SYNTHETIC]
	return SkinnedCharacter.SOURCES.get(BODIES.get(person, ""), "")


static func baked_path(person: String) -> String:
	return BAKED + person + ".png"


## The baked texture for `person`, or null when it is missing.
static func texture(person: String) -> Texture2D:
	var path: String = baked_path(person)
	if scheme(person).is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		return null
	return load(path) as Texture2D


## The source art in `person`'s paint, for the offline bake and checks.
## Unknown schemes and unreadable art return null. `zone_map` (from
## `zones`) lets zoned rules match; without it they match nothing.
static func painted(source: Texture2D, person: String, zone_map: Image = null) -> Image:
	if source == null or scheme(person).is_empty():
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
	var rules: Array = scheme(person)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var texel: Color = image.get_pixel(x, y)
			var rule: Dictionary = _rule(rules, texel, zone_at(zone_map, x, y))
			if not rule.is_empty():
				image.set_pixel(x, y, paint(texel, rule))
	return image


static func _rule(rules: Array, texel: Color, zone: int = 0) -> Dictionary:
	for rule: Dictionary in rules:
		if rule.has("zone") and not _in_zone(rule["zone"], zone):
			continue
		if texel.s < rule["sat"][0] or texel.s >= rule["sat"][1] \
				or texel.v < rule["val"][0] or texel.v >= rule["val"][1]:
			continue
		if rule.has("hue"):
			var hue: float = FactionPalette.hue_degrees(texel)
			if hue < rule["hue"][0] or hue >= rule["hue"][1]:
				continue
		return rule
	return {}


static func _in_zone(names: Array, zone: int) -> bool:
	for zone_name: Variant in names:
		if ZONES.get(zone_name, -1) == zone:
			return true
	return false


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
