class_name FighterLooks
extends RefCounted

## The fighter roster: personal looks on the two shared bodies, and the
## curated personal accent colours. A look is an offline recolour of the
## body's own art (CastPaint, baked by tools/bake_cast_paint.gd), so the rig,
## animation and hit volume never change with it. The wire carries indices
## (`dress: {"look", "accent"}`, docs/protocol.md), never a path or a colour;
## the server keeps the counts in `server/src/protocol/body.rs`.
##
## Three families read apart (docs/ART_STORY_BIBLE.md, faction readability):
## the free coalition wears these personal looks; a fighter on the Union side
## of a team match wears the issued livery instead, told apart by rank seals,
## never by personal taste; the Inheritance has no player looks.

## Look 0 is workwear for humans and painted field plate for agents.
## Labels are menu words.
const LOOKS: Dictionary[String, Array] = {
	PlayerBody.HUMAN: [
		{"label": "WORKWEAR", "person": ""},
		{"label": "MECHANIC", "person": "look_human_1"},
		{"label": "SILVER", "person": "look_human_2"},
		{"label": "COPPER", "person": "look_human_3"},
		{"label": "INDIGO", "person": "look_human_4"},
		{"label": "SALVAGE", "person": "look_human_5"},
		{"label": "CANVAS", "person": "look_human_6"},
		{"label": "BOMBER", "person": "look_human_7"},
	],
	PlayerBody.SYNTHETIC: [
		{"label": "FIELD PLATE", "person": "look_synthetic_0"},
		{"label": "MOSS", "person": "look_synthetic_1"},
		{"label": "MUSTARD", "person": "look_synthetic_2"},
		{"label": "COBALT", "person": "look_synthetic_3"},
		{"label": "PLUM", "person": "look_synthetic_4"},
	],
}
## Personal accent colours, worn as a wrist band on the free side. Every one
## stays clear of Union red, Inheritance cyan and matte off-white, so no
## choice can compose a reserved livery.
const ACCENTS: Array[Dictionary] = [
	{"label": "EMBER", "color": Color("d9682a")},
	{"label": "MARIGOLD", "color": Color("e0a832")},
	{"label": "MOSS", "color": Color("6f9a34")},
	{"label": "MAGENTA", "color": Color("c0408e")},
	{"label": "VIOLET", "color": Color("7a52c0")},
	{"label": "COBALT", "color": Color("3c5ad0")},
	{"label": "LILAC", "color": Color("b07ad8")},
	{"label": "SAND", "color": Color("c8a46a")},
]
## Union issue on the Union side: role read from repeated rank seals, the
## same for everyone who holds that rank. Index by look, so a side of
## different looks still shows a spread of ranks.
const UNION_RANKS: Array[String] = ["LINE", "REGISTRAR", "WARDEN"]
## Settings value for "let the server choose".
const AUTO: int = -1


static func count(body: String) -> int:
	return (LOOKS.get(PlayerBody.preference(body), []) as Array).size()


static func valid_look(body: String, look: Variant) -> bool:
	return look is int and int(look) >= 0 and int(look) < count(body)


static func valid_accent(accent: Variant) -> bool:
	return accent is int and int(accent) >= 0 and int(accent) < ACCENTS.size()


static func label(body: String, look: int) -> String:
	return str(LOOKS[PlayerBody.preference(body)][look]["label"]) if valid_look(body, look) else "AUTO"


static func accent_label(accent: int) -> String:
	return str(ACCENTS[accent]["label"]) if valid_accent(accent) else "CALLSIGN"


## The accent colour, or transparent when there is none.
static func accent_color(accent: int) -> Color:
	return ACCENTS[accent]["color"] if valid_accent(accent) else Color(0, 0, 0, 0)


## The CastPaint person behind a look, empty for the body's own art.
static func person(body: String, look: int) -> String:
	return str(LOOKS[PlayerBody.preference(body)][look]["person"]) if valid_look(body, look) else ""


## The baked art for a look, or null for the body's own art.
static func texture(body: String, look: int) -> Texture2D:
	var painted: String = person(body, look)
	return null if painted.is_empty() else CastPaint.texture(painted)


static func union_rank(look: int) -> int:
	return maxi(look, 0) % UNION_RANKS.size()


## A received `dress` object, checked against the roster for `body`:
## {"look": int or AUTO, "accent": int or AUTO}. Anything malformed is
## {} so the caller can refuse it, never guess.
static func parse(value: Variant, body: String) -> Dictionary:
	if value == null:
		return {"look": AUTO, "accent": AUTO}
	if not value is Dictionary:
		return {}
	var dress: Dictionary = value
	for key: Variant in dress:
		if key not in ["look", "accent"]:
			return {}
	var look: Variant = _integer(dress.get("look"))
	var accent: Variant = _integer(dress.get("accent"))
	if (dress.has("look") and not valid_look(body, look)) or (dress.has("accent") and not valid_accent(accent)):
		return {}
	return {"look": int(look) if dress.has("look") else AUTO, "accent": int(accent) if dress.has("accent") else AUTO}


## The Hello request for a saved preference: only the parts that are set.
static func request(look: int, accent: int, body: String) -> Dictionary:
	var dress: Dictionary = {}
	if valid_look(body, look):
		dress["look"] = look
	if valid_accent(accent):
		dress["accent"] = accent
	return dress


## JSON numbers arrive as floats; accept only whole values.
static func _integer(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value) and absf(value) < 1000.0:
		return int(value)
	return value


## Wear `look` (null for the body's own art) on a live body: the art its
## dress paints from becomes the look, and the shown art follows at once,
## issued-livery copy included. A Union-side caller passes null, so the
## issued livery is always made from the same own art.
static func wear(view: SkinnedCharacter, look: Texture2D) -> void:
	if view == null:
		return
	if not view.has_meta("own_art"):
		var own: Dictionary = {}
		for material: StandardMaterial3D in view._materials:
			own[material] = view._materials[material]
		view.set_meta("own_art", own)
	if view.has_meta("worn_livery") and FighterLooks.worn(view) == look and view.get_meta("worn_livery") == view.livery:
		return
	var original: Dictionary = view.get_meta("own_art")
	view.set_meta("look", look)
	view.set_meta("worn_livery", view.livery)
	for material: StandardMaterial3D in view._materials:
		var own_art: Texture2D = original.get(material)
		if own_art == null:
			continue
		var art: Texture2D = look if look != null else own_art
		view._materials[material] = art
		material.albedo_texture = BodyLivery.union_texture(art) if view.livery == "union" else art


## The look a body wears, or null for its own art.
static func worn(view: SkinnedCharacter) -> Texture2D:
	return view.get_meta("look") as Texture2D if view != null and view.has_meta("look") else null


## The personal wrist band on the free side and the Union rank marks on the
## Union side, fitted by BodyLivery; one is never worn with the other. Rank
## 1 shows the red collar, rank 2 the collar and the arm stripes.
static func mark(view: SkinnedCharacter, personal: Color, union: bool, rank: int) -> void:
	if view == null or view.skeleton == null:
		return
	var fitting: Dictionary = BodyLivery.fitting_for(view)
	var band: MeshInstance3D = view.get_meta("personal_band") as MeshInstance3D if view.has_meta("personal_band") else null
	if band == null and fitting.has("cuff"):
		band = _fit(view, fitting["cuff"], "PersonalBand", StandardMaterial3D.new())
		view.set_meta("personal_band", band)
	if band != null:
		(band.material_override as StandardMaterial3D).albedo_color = Color(personal.r, personal.g, personal.b)
		band.visible = not union and personal.a > 0.0
	if not view.has_meta("rank_marks"):
		var seal: StandardMaterial3D = StandardMaterial3D.new()
		seal.albedo_color = FactionPalette.UNION_RED
		var marks: Array[MeshInstance3D] = []
		for fit: Dictionary in fitting.get("seals", []):
			var node: MeshInstance3D = _fit(view, fit, "RankSeal", seal)
			if node != null:
				marks.append(node)
		view.set_meta("rank_marks", marks)
	var placed: Array[MeshInstance3D] = view.get_meta("rank_marks")
	for index: int in range(placed.size()):
		placed[index].visible = union and rank >= (1 if index == 0 else 2)


static func _fit(view: SkinnedCharacter, fit: Dictionary, node_name: String, material: StandardMaterial3D) -> MeshInstance3D:
	var bone: String = str(fit["bone"])
	if view.skeleton.find_bone(bone) < 0:
		return null
	material.roughness = 0.85
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.name = node_name + bone
	attachment.bone_name = bone
	view.skeleton.add_child(attachment)
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = node_name
	part.mesh = BodyLivery.tape_mesh()
	part.material_override = material
	part.transform = fit["transform"]
	part.layers = ArenaSky.ACTOR_LAYERS
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	attachment.add_child(part)
	return part


## The personal band and rank marks on a body, for checks and reviews: bone
## attachments like the faction tape, never skin.
static func marks(view: SkinnedCharacter) -> Array[MeshInstance3D]:
	var parts: Array[MeshInstance3D] = []
	if view == null:
		return parts
	if view.has_meta("personal_band") and view.get_meta("personal_band") != null:
		parts.append(view.get_meta("personal_band") as MeshInstance3D)
	if view.has_meta("rank_marks"):
		parts.append_array(view.get_meta("rank_marks"))
	return parts
