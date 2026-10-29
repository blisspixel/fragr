class_name GunModel
extends RefCounted

## One modelled source per gun. `tools/bake_viewmodels.gd` poses it with the
## player's gloved hands and bakes the first-person frames, the world pickup,
## the held profile and the kill icon from it, so every picture of a gun shows
## the same physical object. The same model is the gun Latch carries in the
## world. Presentation only: no shot, timing or ammunition fact lives here.
##
## Gun space: metres, the bore runs along -Z to the muzzle, +Y is up and +X is
## the shooter's right. Every part carries a `finish` (the palette ramp the
## baker paints it with) and an `outline` group (parts in one group are drawn
## as one shape; a new group gets a line where it passes in front of another).

const Workshop = preload("res://scripts/model_geometry.gd")

## Palette ramps from docs/palette.json, darkest first. The baker maps light
## onto these; a live model uses the `MID` entry as its albedo.
const RAMPS: Dictionary[String, Array] = {
	"enamel": [Color("1e1e22"), Color("2c2d32"), Color("3a3836"), Color("4e5844"), Color("5a554f"), Color("8c847a")],
	"slide": [Color("1e1e22"), Color("2c2d32"), Color("3a3836"), Color("5a554f"), Color("8c847a")],
	"blued": [Color("0a0a0c"), Color("1e1e22"), Color("2c2d32"), Color("3a3836"), Color("5a554f")],
	"steel": [Color("1e1e22"), Color("3a3836"), Color("5a554f"), Color("8c847a"), Color("e8e2d6")],
	"polymer": [Color("0a0a0c"), Color("1e1e22"), Color("2c2d32"), Color("3a3836"), Color("5a554f")],
	"bore": [Color("0a0a0c"), Color("0a0a0c"), Color("1e1e22")],
	"leather": [Color("1e1e22"), Color("3a3836"), Color("7a3a22"), Color("9f5b3b"), Color("b4754e")],
	"jacket": [Color("1e1e22"), Color("3a3836"), Color("7a3a22"), Color("9f5b3b")],
	"seam": [Color("1e1e22"), Color("3a3836"), Color("7a3a22")],
	"wood": [Color("1e1e22"), Color("3a3836"), Color("7a3a22"), Color("9f5b3b")],
	"brass": [Color("3a3836"), Color("7a3a22"), Color("c45a20"), Color("dc8c3c"), Color("e8e2d6")],
	"bone": [Color("5a554f"), Color("8c847a"), Color("e8e2d6")],
	"coil": [Color("1e1e22"), Color("3a3836"), Color("7a3a22"), Color("c45a20")],
	"glow": [Color("c45a20"), Color("dc8c3c"), Color("e8e2d6")],
}
## Which ramp entry a live (unbaked) model shows as its flat albedo.
const MID: Dictionary[String, int] = {
	"enamel": 3, "slide": 2, "blued": 2, "steel": 2, "polymer": 2, "bore": 0, "leather": 2,
	"jacket": 2, "seam": 1, "wood": 3, "brass": 2, "bone": 2, "coil": 2, "glow": 1,
}
## Finishes that light themselves: the baker keeps them in their bright half.
const SELF_LIT: Array[String] = ["glow"]

## The guns this source builds, by wire name.
const GUNS: Array[String] = ["Tack", "Scatter", "Rail", "Repeater"]

var _workshop: RefCounted = Workshop.new()
var _materials: Dictionary[String, StandardMaterial3D] = {}

## Build a gun. `hands` adds the player's gloved hands and sleeves in their
## held pose; the world pickup and Latch's carried gun leave them off.
func build(weapon: String, hands: bool = false) -> Node3D:
	var gun: Node3D = Node3D.new()
	gun.name = weapon
	match weapon:
		"Tack":
			_tack(gun)
			if hands:
				_tack_hands(gun)
		"Scatter":
			_scatter(gun)
			if hands:
				_scatter_hands(gun)
		"Rail":
			_rail(gun)
			if hands:
				_rail_hands(gun)
		"Repeater":
			_repeater(gun)
			if hands:
				_repeater_hands(gun)
		_:
			push_error("GunModel: no model for " + weapon)
	for part: Node in gun.find_children("*", "Node3D", true, false):
		var node: Node3D = part as Node3D
		node.set_meta("rest", node.transform)
	return gun

## Where the trigger hand closes on each gun, in gun space: a fighter or
## Latch carries the gun from this point.
const GRIP: Dictionary[String, Vector3] = {
	"Tack": Vector3(0.0, -0.055, 0.030),
	"Scatter": Vector3(0.0, -0.035, 0.085),
	"Rail": Vector3(0.0, -0.090, 0.130),
	"Repeater": Vector3(0.0, -0.090, 0.130),
}
## Each muzzle in gun space, matching the `Muzzle` marker the build places.
const MUZZLE: Dictionary[String, Vector3] = {
	"Tack": Vector3(0.0, 0.002, -0.183),
	"Scatter": Vector3(0.0, 0.0, -0.605),
	"Rail": Vector3(0.0, 0.0, -0.785),
	"Repeater": Vector3(0.0, 0.0, -0.805),
}
static var _carried: Dictionary[String, ArrayMesh] = {}

static func has_model(weapon: String) -> bool:
	return GRIP.has(weapon)

## The gun as one mesh for carrying in the world: no hands, no spare
## magazine, no loose shells. Built once per gun. The fighter's copy is two
## surfaces (lit parts painted by vertex colour over one metal grain, and the
## glow), so a crowd of carried guns stays a couple of draws each; `by_finish`
## keeps a surface and material per finish for presenters that recolour
## materials, such as Latch's near-camera clip.
static func carried_mesh(weapon: String, by_finish: bool = false) -> ArrayMesh:
	var cache_key: String = weapon + ("/finish" if by_finish else "")
	if _carried.has(cache_key):
		return _carried[cache_key]
	if not has_model(weapon):
		return null
	var source: GunModel = GunModel.new()
	var gun: Node3D = source.build(weapon, false)
	var painted: StandardMaterial3D = source.world_finish("steel").duplicate() as StandardMaterial3D
	painted.albedo_color = Color.WHITE
	painted.vertex_color_use_as_albedo = true
	# Ramp colours are sRGB swatches; without this they render washed out.
	painted.vertex_color_is_srgb = true
	painted.metallic = 0.15
	var tools: Dictionary[String, SurfaceTool] = {}
	for node: Node in gun.find_children("*", "MeshInstance3D", true, false):
		var piece: MeshInstance3D = node as MeshInstance3D
		var place: Transform3D = Transform3D.IDENTITY
		var visible: bool = true
		var at: Node = piece
		while at != gun:
			var spatial: Node3D = at as Node3D
			visible = visible and spatial.visible and spatial.name != "FreshMagazine" and not str(spatial.name).begins_with("Shell")
			place = spatial.transform * place
			at = at.get_parent()
		if not visible:
			continue
		var finish_key: String = str(piece.material_override.get_meta("finish", "steel"))
		var surface_key: String = finish_key if by_finish or finish_key in SELF_LIT else "painted"
		if not tools.has(surface_key):
			var tool: SurfaceTool = SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.set_material(painted if surface_key == "painted" else source.world_finish(finish_key))
			tools[surface_key] = tool
		var tint: Color = RAMPS[finish_key][MID[finish_key]]
		for surface: int in range(piece.mesh.get_surface_count()):
			var arrays: Array = piece.mesh.surface_get_arrays(surface)
			var colours: PackedColorArray = PackedColorArray()
			colours.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			colours.fill(tint)
			arrays[Mesh.ARRAY_COLOR] = colours
			var part: ArrayMesh = ArrayMesh.new()
			part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			tools[surface_key].append_from(part, 0, place)
	var mesh: ArrayMesh = ArrayMesh.new()
	for surface_key: String in tools:
		tools[surface_key].commit(mesh)
	gun.free()
	_carried[cache_key] = mesh
	return mesh

## A finish for the lit world: its mid ramp colour over the shared metal or
## wood grain, nearest sampled; glowing parts stay unshaded.
func world_finish(key: String) -> StandardMaterial3D:
	var material: StandardMaterial3D = finish(key).duplicate() as StandardMaterial3D
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if not key in SELF_LIT:
		material.albedo_texture = _workshop._grain("wood" if key in ["wood", "leather"] else "metal")
	return material

## Restore every moving part to its built transform.
static func rest(gun: Node3D) -> void:
	for part: Node in gun.find_children("*", "Node3D", true, false):
		var node: Node3D = part as Node3D
		if node.has_meta("rest"):
			node.transform = node.get_meta("rest")

# --- Materials and primitives -------------------------------------------------

func finish(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = key
	material.albedo_color = RAMPS[key][MID[key]]
	material.roughness = 0.82
	material.metallic = 0.25 if key in ["steel", "slide", "enamel"] else 0.0
	if key in SELF_LIT:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.set_meta("finish", key)
	_materials[key] = material
	return material

func _tag(node: MeshInstance3D, outline: String) -> MeshInstance3D:
	node.set_meta("outline", outline)
	return node

func _prism(parent: Node3D, label: String, outline_zy: PackedVector2Array, width: float, key: String, at: Vector3 = Vector3.ZERO, bevel: float = 0.14, group: String = "") -> MeshInstance3D:
	return _tag(_workshop.prism(parent, label, outline_zy, width, finish(key), at, bevel), group if group != "" else label)

func _block(parent: Node3D, label: String, size: Vector3, key: String, at: Vector3, group: String = "") -> MeshInstance3D:
	return _tag(_workshop.block(parent, label, size, finish(key), at), group if group != "" else label)

func _tube(parent: Node3D, label: String, radius: float, a: Vector3, b: Vector3, key: String, group: String = "", segments: int = 16) -> MeshInstance3D:
	return _tag(_workshop.rod(parent, label, a, b, radius, finish(key), segments), group if group != "" else label)

func _pipe(parent: Node3D, label: String, points: PackedVector3Array, radius: float, key: String, group: String = "") -> MeshInstance3D:
	return _tag(_workshop.pipe(parent, label, points, radius, finish(key)), group if group != "" else label)

## A rounded segment between two points: glove fingers, wrists and sleeves.
func _capsule(parent: Node3D, label: String, a: Vector3, b: Vector3, radius: float, key: String, group: String) -> MeshInstance3D:
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = a.distance_to(b) + radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 4
	var node: MeshInstance3D = _workshop.instance(parent, label, mesh, finish(key), (a + b) * 0.5)
	if a.distance_to(b) > 0.00001:
		node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return _tag(node, group)

## A flattened ellipsoid: a palm, a knuckle pad, a cuff.
func _pad(parent: Node3D, label: String, center: Vector3, radii: Vector3, basis: Basis, key: String, group: String) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var node: MeshInstance3D = _workshop.instance(parent, label, mesh, finish(key), center)
	node.basis = basis * Basis.from_scale(radii)
	return _tag(node, group)

# --- The gloved hand -----------------------------------------------------------

## A work-gloved hand and its jacket sleeve, placed by landmarks in gun
## space: `wrist`, the centre of the `knuckles` row, `across` (little finger
## toward index), `back` (out of the back of the hand), each finger's three
## joint bends toward the palm (`curl`, index first), the thumb's base, middle and
## tip points (`thumb`), and the `elbow` the sleeve runs to.
func glove(parent: Node3D, label: String, spec: Dictionary) -> Node3D:
	var hand: Node3D = Node3D.new()
	hand.name = label
	parent.add_child(hand)
	var wrist: Vector3 = spec["wrist"]
	var knuckles: Vector3 = spec["knuckles"]
	var y: Vector3 = (knuckles - wrist).normalized()
	var across: Vector3 = spec["across"]
	var x: Vector3 = (across - y * across.dot(y)).normalized()
	var z: Vector3 = x.cross(y).normalized()
	if z.dot(spec["back"]) < 0.0:
		z = -z
	var reach: float = wrist.distance_to(knuckles)
	var frame: Basis = Basis(x, y, z)
	_pad(hand, "Palm", wrist + y * reach * 0.52 - z * 0.004, Vector3(0.039, reach * 0.56, 0.019), frame, "leather", label + "Palm")
	# Raised knuckles, fingers curling toward the palm, and two stitched seams.
	var curls: Array = spec["curl"]
	var lengths: Array[Vector3] = [Vector3(0.034, 0.023, 0.018), Vector3(0.038, 0.025, 0.019), Vector3(0.035, 0.023, 0.018), Vector3(0.028, 0.018, 0.015)]
	for digit: int in range(4):
		var start: Vector3 = knuckles + x * (0.0265 - 0.0175 * digit) - y * absf(digit - 1.2) * 0.004
		_pad(hand, "Knuckle%d" % digit, start + z * 0.006, Vector3(0.0105, 0.010, 0.0095), frame, "leather", label + "Knuckle%d" % digit)
		var bends: Vector3 = curls[mini(digit, curls.size() - 1)]
		var bend: float = 0.0
		var point: Vector3 = start
		for joint: int in range(3):
			bend += bends[joint]
			var end: Vector3 = point + (y * cos(bend) - z * sin(bend)) * lengths[digit][joint]
			_capsule(hand, "Finger%d_%d" % [digit, joint], point, end, 0.0102 - 0.0008 * joint, "leather", label + "Finger%d" % digit)
			point = end
	for seam: float in [-0.011, 0.011]:
		_capsule(hand, "Seam%d" % int(seam * 1000), wrist + y * 0.016 + x * seam + z * 0.017, knuckles - y * 0.016 + x * seam * 1.3 + z * 0.015, 0.0021, "seam", label + "Seam")
	# Thumb: a heavier digit from the index side of the palm through its points.
	var thumb: Array = spec["thumb"]
	var base: Vector3 = thumb[0]
	_capsule(hand, "ThumbBase", base, thumb[1], 0.0125, "leather", label + "Thumb")
	_capsule(hand, "ThumbTip", thumb[1], thumb[2], 0.0110, "leather", label + "Thumb")
	# The glove's gauntlet, its stitched cuff band and the jacket sleeve.
	var elbow: Vector3 = spec["elbow"]
	var arm: Vector3 = (elbow - wrist).normalized()
	_capsule(hand, "Gauntlet", wrist + y * 0.012, wrist + arm * 0.040, 0.026, "leather", label + "Wrist")
	_capsule(hand, "Cuff", wrist + arm * 0.050, wrist + arm * 0.060, 0.030, "seam", label + "Cuff")
	_capsule(hand, "Sleeve", wrist + arm * 0.070, elbow, 0.034, "jacket", label + "Sleeve")
	return hand

# --- Tack ------------------------------------------------------------------------

## The arena sidearm: a compact service pistol in grey-green enamel with a
## darker slide and a polymer grip. It came off a Union rack once; the
## type-approval plate on its frame is ground back to bare metal (guns.md,
## "What the labels tell you"). Slide travel 22 mm; the magazine drops free.
func _tack(gun: Node3D) -> void:
	var slide: Node3D = _workshop.group(gun, "Slide")
	_prism(slide, "SlideBody", PackedVector2Array([
		Vector2(-0.176, -0.008), Vector2(-0.176, 0.015), Vector2(-0.171, 0.021),
		Vector2(0.006, 0.021), Vector2(0.013, 0.016), Vector2(0.013, -0.008)]), 0.029, "enamel", Vector3.ZERO, 0.2, "Slide")
	# Rear cocking serrations, cut across both flanks.
	for index: int in range(5):
		var z: float = -0.016 + index * 0.0055
		for side: float in [-1.0, 1.0]:
			_block(slide, "Serration%d%s" % [index, "L" if side < 0.0 else "R"], Vector3(0.0016, 0.019, 0.0022), "polymer", Vector3(side * 0.0142, 0.004, z), "Slide")
	# Ejection port with the barrel hood showing through it.
	_block(slide, "EjectionPort", Vector3(0.012, 0.003, 0.042), "bore", Vector3(0.006, 0.0205, -0.052), "Port")
	_block(slide, "BarrelHood", Vector3(0.009, 0.003, 0.034), "slide", Vector3(0.005, 0.0212, -0.054), "Hood")
	# Sights: a notched rear blade and a front post with a bone dot.
	for side: float in [-1.0, 1.0]:
		_block(slide, "RearSight%s" % ("L" if side < 0.0 else "R"), Vector3(0.0095, 0.009, 0.009), "polymer", Vector3(side * 0.0085, 0.0255, 0.003), "RearSight")
	_block(slide, "RearSightBase", Vector3(0.027, 0.004, 0.010), "polymer", Vector3(0.0, 0.0225, 0.003), "RearSight")
	# Two bone dots on the rear blade, one on the front post: a three-dot sight.
	for side: float in [-1.0, 1.0]:
		_block(slide, "RearDot%s" % ("L" if side < 0.0 else "R"), Vector3(0.0028, 0.0028, 0.0016), "bone", Vector3(side * 0.0085, 0.0262, 0.0078), "RearDot")
	# The slide's rear plate: an inset panel round the firing pin cap.
	_block(slide, "RearPlate", Vector3(0.018, 0.018, 0.0016), "slide", Vector3(0.0, 0.004, 0.0137), "RearPlate")
	_tube(slide, "PinCap", 0.0032, Vector3(0.0, 0.006, 0.0140), Vector3(0.0, 0.006, 0.0152), "steel", "PinCap", 10)
	_block(slide, "FrontSight", Vector3(0.0045, 0.0075, 0.007), "polymer", Vector3(0.0, 0.0245, -0.163), "FrontSight")
	_block(slide, "FrontDot", Vector3(0.0028, 0.0028, 0.0016), "bone", Vector3(0.0, 0.0262, -0.1592), "FrontDot")
	# Fixed barrel crown and its bore, ahead of the slide's nose.
	_tube(gun, "BarrelCrown", 0.0068, Vector3(0.0, 0.002, -0.172), Vector3(0.0, 0.002, -0.181), "steel", "Crown")
	_tube(gun, "Bore", 0.0042, Vector3(0.0, 0.002, -0.1805), Vector3(0.0, 0.002, -0.1825), "bore", "Bore", 10)
	# Frame: dust cover, trigger guard and the rear tang under the slide.
	_prism(gun, "Frame", PackedVector2Array([
		Vector2(-0.165, -0.008), Vector2(0.026, -0.008), Vector2(0.036, -0.014),
		Vector2(0.036, -0.023), Vector2(-0.003, -0.026), Vector2(-0.058, -0.027),
		Vector2(-0.165, -0.023)]), 0.026, "slide", Vector3.ZERO, 0.16, "Frame")
	for index: int in range(3):
		_block(gun, "Rail%d" % index, Vector3(0.020, 0.003, 0.006), "polymer", Vector3(0.0, -0.0285, -0.150 + index * 0.014), "Frame")
	# The ground-off approval plate: a scarred bright patch on the left flank.
	_block(gun, "GroundPlate", Vector3(0.0012, 0.010, 0.032), "steel", Vector3(-0.0131, -0.0175, -0.105), "Scar")
	_pipe(gun, "TriggerGuard", PackedVector3Array([
		Vector3(0.0, -0.026, -0.060), Vector3(0.0, -0.040, -0.064), Vector3(0.0, -0.050, -0.056),
		Vector3(0.0, -0.053, -0.032), Vector3(0.0, -0.047, -0.011), Vector3(0.0, -0.033, -0.004)]), 0.0032, "enamel", "Frame")
	var trigger: Node3D = _workshop.group(gun, "Trigger", Vector3(0.0, -0.027, -0.022))
	_pipe(trigger, "Blade", PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.010, -0.003), Vector3(0.0, -0.018, 0.002)]), 0.0024, "steel", "Trigger")
	var hammer: Node3D = _workshop.group(gun, "Hammer", Vector3(0.0, 0.004, 0.017))
	_block(hammer, "Spur", Vector3(0.0065, 0.009, 0.006), "steel", Vector3(0.0, 0.004, 0.002), "Hammer")
	# Raked polymer grip with two finger grooves cut into the front strap.
	_prism(gun, "Grip", PackedVector2Array([
		Vector2(-0.006, -0.022), Vector2(0.031, -0.020), Vector2(0.052, -0.116),
		Vector2(0.047, -0.124), Vector2(0.012, -0.126), Vector2(0.004, -0.098),
		Vector2(0.0, -0.084), Vector2(-0.002, -0.066), Vector2(-0.006, -0.048)]), 0.031, "polymer", Vector3.ZERO, 0.22, "Grip")
	var magazine: Node3D = _workshop.group(gun, "Magazine", Vector3(0.0, -0.068, 0.024))
	magazine.rotation.x = deg_to_rad(-12.0)
	_block(magazine, "Body", Vector3(0.020, 0.100, 0.030), "steel", Vector3(0.0, 0.004, 0.0), "Magazine")
	_block(magazine, "BasePlate", Vector3(0.030, 0.008, 0.040), "polymer", Vector3(0.0, -0.058, 0.002), "Magazine")
	# A spare magazine for the reload, carried in by the support hand.
	var fresh: Node3D = _workshop.group(gun, "FreshMagazine", Vector3(0.0, -0.068, 0.024))
	fresh.rotation.x = deg_to_rad(-12.0)
	_block(fresh, "Body", Vector3(0.020, 0.100, 0.030), "steel", Vector3(0.0, 0.004, 0.0), "FreshMagazine")
	_block(fresh, "BasePlate", Vector3(0.030, 0.008, 0.040), "polymer", Vector3(0.0, -0.058, 0.002), "FreshMagazine")
	fresh.visible = false
	_muzzle(gun, MUZZLE["Tack"])

## The muzzle marker. The shot's flash is the set's drawn flash, stamped at
## this point by the baker so every gun shares one.
func _muzzle(gun: Node3D, at: Vector3) -> void:
	var muzzle: Marker3D = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = at
	gun.add_child(muzzle)

## Two-handed thumbs-forward grip: the right hand wraps the grip, the left
## cups it from below with both thumbs along the left of the frame.
func _tack_hands(gun: Node3D) -> void:
	var hands: Node3D = _workshop.group(gun, "Hands")
	glove(hands, "TriggerHand", {
		"wrist": Vector3(0.026, -0.068, 0.095), "knuckles": Vector3(0.024, -0.072, 0.004),
		"across": Vector3(0.0, 1.0, 0.12), "back": Vector3(1.0, 0.1, 0.25),
		"curl": [Vector3(0.45, 0.9, 0.5), Vector3(0.75, 1.25, 0.9), Vector3(0.75, 1.25, 0.9), Vector3(0.75, 1.25, 0.9)],
		"thumb": [Vector3(0.012, -0.030, 0.042), Vector3(-0.016, -0.018, 0.010), Vector3(-0.021, -0.013, -0.030)],
		"elbow": Vector3(0.120, -0.500, 0.220)})
	glove(hands, "SupportHand", {
		"wrist": Vector3(-0.050, -0.105, 0.060), "knuckles": Vector3(-0.028, -0.080, -0.028),
		"across": Vector3(0.0, 1.0, 0.0), "back": Vector3(-0.8, -0.1, -0.5),
		"curl": [Vector3(0.6, 1.2, 0.8), Vector3(0.65, 1.25, 0.8), Vector3(0.65, 1.25, 0.8), Vector3(0.65, 1.25, 0.8)],
		"thumb": [Vector3(-0.030, -0.060, 0.040), Vector3(-0.032, -0.042, 0.000), Vector3(-0.026, -0.030, -0.050)],
		"elbow": Vector3(-0.140, -0.500, 0.200)})

## Pose the Tack: `slide` 0..1 of its 22 mm stroke, `magazine` metres dropped.
static func pose_tack(gun: Node3D, slide: float, magazine: float = 0.0, trigger: float = 0.0) -> void:
	rest(gun)
	(gun.get_node("Slide") as Node3D).position.z += 0.022 * clampf(slide, 0.0, 1.0)
	(gun.get_node("Hammer") as Node3D).rotation.x -= 0.9 * clampf(slide * 1.6, 0.0, 1.0)
	(gun.get_node("Trigger") as Node3D).rotation.x -= 0.25 * clampf(trigger, 0.0, 1.0)
	var mag: Node3D = gun.get_node("Magazine") as Node3D
	mag.position += mag.basis.y * -magazine
	mag.visible = magazine < 0.30

## Bring the spare magazine `rise` metres below its seat (negative hides it).
static func carry_magazine(gun: Node3D, rise: float) -> void:
	var fresh: Node3D = gun.get_node_or_null("FreshMagazine") as Node3D
	if fresh == null:
		return
	fresh.transform = fresh.get_meta("rest")
	fresh.visible = rise >= 0.0
	if rise > 0.0:
		fresh.position += fresh.basis.y * -rise

# --- Scatter -------------------------------------------------------------------------

## The arena shotgun: a side-by-side double gun, short barrels on a grey-green
## enamel action, a rust-stained walnut forend and stock. A free owner's gun:
## a hose clamp holds a cracked forend and a bone plate patches the stock
## (guns.md: stocks, finishes and repair histories show ownership). The
## barrels break open on the hinge pin for the reload.
func _scatter(gun: Node3D) -> void:
	var barrels: Node3D = _workshop.group(gun, "Barrels", Vector3(0.0, -0.022, -0.020))
	var reach: float = 0.60
	for side: float in [-1.0, 1.0]:
		var x: float = side * 0.0135
		_tag(_workshop.lathe(barrels, "Barrel%s" % ("L" if side < 0.0 else "R"), PackedVector2Array([
			Vector2(-reach, 0.0092), Vector2(-reach, 0.0128), Vector2(-reach + 0.004, 0.0132),
			Vector2(-0.18, 0.0138), Vector2(-0.10, 0.0150), Vector2(0.0, 0.0150),
			Vector2(0.0, 0.0092)]), finish("slide"), Vector3(x, 0.022, 0.020), 16), "Barrel%d" % int(side))
		_tube(barrels, "Bore%s" % ("L" if side < 0.0 else "R"), 0.0090, Vector3(x, 0.022, 0.020 - reach + 0.001), Vector3(x, 0.022, 0.020 - reach - 0.001), "bore", "Bore", 12)
		# Brass of the loaded shells, seen only when the action is open.
		_tube(barrels, "Shell%s" % ("L" if side < 0.0 else "R"), 0.0104, Vector3(x, 0.022, 0.0215), Vector3(x, 0.022, 0.0165), "brass", "Shell")
	_block(barrels, "Rib", Vector3(0.006, 0.005, reach - 0.04), "slide", Vector3(0.0, 0.0375, 0.020 - reach * 0.5), "Rib")
	_block(barrels, "Bead", Vector3(0.0045, 0.0045, 0.006), "bone", Vector3(0.0, 0.0425, 0.020 - reach + 0.012), "Bead")
	_block(barrels, "Lug", Vector3(0.020, 0.018, 0.050), "steel", Vector3(0.0, 0.004, -0.005), "Lug")
	# Forend: wood under the barrels, and the owner's hose clamp over a crack.
	_prism(barrels, "Forend", PackedVector2Array([
		Vector2(-0.30, 0.010), Vector2(-0.10, 0.010), Vector2(-0.085, 0.002),
		Vector2(-0.10, -0.012), Vector2(-0.29, -0.012), Vector2(-0.305, -0.004)]), 0.038, "wood", Vector3(0.0, 0.0, 0.0), 0.22, "Forend")
	_block(barrels, "Clamp", Vector3(0.041, 0.024, 0.008), "steel", Vector3(0.0, -0.001, -0.24), "Clamp")
	# The action: an enamel box with the top lever and the hinge pin.
	_prism(gun, "Action", PackedVector2Array([
		Vector2(-0.040, 0.010), Vector2(0.034, 0.010), Vector2(0.048, 0.004),
		Vector2(0.050, -0.030), Vector2(-0.030, -0.040), Vector2(-0.046, -0.026)]), 0.046, "enamel", Vector3.ZERO, 0.18, "Action")
	_tube(gun, "HingePin", 0.0065, Vector3(-0.024, -0.022, -0.020), Vector3(0.024, -0.022, -0.020), "steel", "Action", 10)
	var lever: Node3D = _workshop.group(gun, "Lever", Vector3(0.0, 0.012, 0.030))
	_prism(lever, "TopLever", PackedVector2Array([
		Vector2(-0.010, 0.0), Vector2(0.022, 0.0), Vector2(0.030, 0.003), Vector2(0.030, 0.007), Vector2(-0.010, 0.007)]), 0.008, "slide", Vector3.ZERO, 0.2, "Lever")
	_pipe(gun, "TriggerGuard", PackedVector3Array([
		Vector3(0.0, -0.040, -0.006), Vector3(0.0, -0.058, 0.004), Vector3(0.0, -0.064, 0.030),
		Vector3(0.0, -0.058, 0.058), Vector3(0.0, -0.044, 0.070)]), 0.0032, "enamel", "Action")
	for index: int in range(2):
		_pipe(gun, "Trigger%d" % index, PackedVector3Array([
			Vector3(0.0, -0.040, 0.016 + index * 0.018), Vector3(0.0, -0.050, 0.014 + index * 0.018), Vector3(0.0, -0.056, 0.020 + index * 0.018)]), 0.0024, "steel", "Trigger")
	# Stock: a narrow wrist into the butt, with a bone repair plate let in.
	_prism(gun, "Stock", PackedVector2Array([
		Vector2(0.046, 0.008), Vector2(0.11, -0.004), Vector2(0.38, 0.002), Vector2(0.40, -0.004),
		Vector2(0.40, -0.130), Vector2(0.36, -0.134), Vector2(0.17, -0.070), Vector2(0.090, -0.050),
		Vector2(0.050, -0.032)]), 0.040, "wood", Vector3.ZERO, 0.22, "Stock")
	_block(gun, "ButtPad", Vector3(0.042, 0.13, 0.014), "polymer", Vector3(0.0, -0.064, 0.405), "ButtPad")
	_block(gun, "RepairPlate", Vector3(0.0012, 0.022, 0.050), "bone", Vector3(-0.0205, -0.040, 0.24), "Repair")
	_muzzle(gun, MUZZLE["Scatter"])

## Right hand on the stock's wrist, left hand cupping the forend.
func _scatter_hands(gun: Node3D) -> void:
	var hands: Node3D = _workshop.group(gun, "Hands")
	glove(hands, "TriggerHand", {
		"wrist": Vector3(0.034, -0.090, 0.140), "knuckles": Vector3(0.026, -0.060, 0.074),
		"across": Vector3(0.0, 0.9, -0.4), "back": Vector3(1.0, 0.2, 0.1),
		"curl": [Vector3(0.5, 0.9, 0.5), Vector3(0.8, 1.2, 0.9), Vector3(0.8, 1.2, 0.9), Vector3(0.8, 1.2, 0.9)],
		"thumb": [Vector3(0.020, -0.010, 0.110), Vector3(-0.004, 0.006, 0.090), Vector3(-0.018, 0.004, 0.058)],
		"elbow": Vector3(0.150, -0.40, 0.42)})
	var support: Node3D = glove(hands, "SupportHand", {
		"wrist": Vector3(-0.050, -0.062, -0.160), "knuckles": Vector3(0.006, -0.056, -0.200),
		"across": Vector3(0.0, 0.0, -1.0), "back": Vector3(0.0, -1.0, 0.0),
		"curl": [Vector3(0.55, 0.7, 0.3), Vector3(0.6, 0.75, 0.3), Vector3(0.6, 0.75, 0.3), Vector3(0.6, 0.75, 0.3)],
		"thumb": [Vector3(-0.034, -0.040, -0.180), Vector3(-0.030, -0.022, -0.212), Vector3(-0.024, -0.010, -0.248)],
		"elbow": Vector3(-0.200, -0.40, 0.10)})
	# The support hand rides the barrels when they break open.
	hands.remove_child(support)
	gun.get_node("Barrels").add_child(support)
	support.position -= (gun.get_node("Barrels") as Node3D).position

## Pose the Scatter: `open` 0..1 of its 34 degree break, `shells` 1 when the
## loaded shells sit in the chambers, 0 when they are out.
static func pose_scatter(gun: Node3D, open: float, shells: float = 1.0, eject: float = 0.0) -> void:
	rest(gun)
	var barrels: Node3D = gun.get_node("Barrels") as Node3D
	barrels.rotation.x = -deg_to_rad(34.0) * clampf(open, 0.0, 1.0)
	(gun.get_node("Lever") as Node3D).rotation.y = -0.5 * clampf(open * 3.0, 0.0, 1.0)
	for side: String in ["L", "R"]:
		var shell: Node3D = barrels.get_node("Shell" + side) as Node3D
		shell.visible = shells > 0.0 or eject > 0.0
		shell.position.z += 0.025 * eject
		shell.position.y += 0.035 * eject

# --- Rail ------------------------------------------------------------------------------

## The Railgun: a magnetic accelerator built for anti-materiel work and
## requisitioned for people (guns.md). Two open rails run through a stack of
## coil rings that glow warm when charged (ember to bone, never the Union's red
## or the Inheritance's cyan), on an enamel receiver with a swappable cell pack
## on its right flank. This one's issue plate is ground off its receiver.
func _rail(gun: Node3D) -> void:
	for side: float in [-1.0, 1.0]:
		_prism(gun, "Rail%s" % ("Top" if side > 0.0 else "Bottom"), PackedVector2Array([
			Vector2(-0.78, -0.008), Vector2(-0.78, 0.006), Vector2(-0.77, 0.009),
			Vector2(-0.02, 0.009), Vector2(-0.02, -0.008)]), 0.024, "slide", Vector3(0.0, side * 0.022, 0.0), 0.2, "Rails")
	var coils: Node3D = _workshop.group(gun, "Coils")
	for index: int in range(7):
		var z: float = -0.70 + index * 0.095
		_tag(_workshop.lathe(coils, "Coil%d" % index, PackedVector2Array([
			Vector2(-0.016, 0.026), Vector2(-0.016, 0.034), Vector2(-0.012, 0.038),
			Vector2(0.012, 0.038), Vector2(0.016, 0.034), Vector2(0.016, 0.026)]), finish("coil"), Vector3(0.0, 0.0, z), 16), "Coil%d" % index)
		# The charge between the rails, lit with the coils, and its glow along
		# the top rail between each pair of rings.
		_block(coils, "Charge%d" % index, Vector3(0.010, 0.026, 0.020), "glow", Vector3(0.0, 0.0, z), "Charge")
		if index < 6:
			_block(coils, "ChargeTop%d" % index, Vector3(0.008, 0.003, 0.060), "glow", Vector3(0.0, 0.0325, z + 0.0475), "ChargeTop")
	# Receiver with an optic housing on top and the ground-off plate on its flank.
	_prism(gun, "Receiver", PackedVector2Array([
		Vector2(-0.06, 0.046), Vector2(0.20, 0.046), Vector2(0.22, 0.030), Vector2(0.22, -0.040),
		Vector2(0.05, -0.050), Vector2(-0.06, -0.040), Vector2(-0.07, 0.0)]), 0.064, "enamel", Vector3.ZERO, 0.16, "Receiver")
	_block(gun, "SightRail", Vector3(0.020, 0.010, 0.120), "polymer", Vector3(0.0, 0.051, 0.060), "Sight")
	for index: int in range(3):
		_block(gun, "Vent%d" % index, Vector3(0.040, 0.003, 0.010), "bore", Vector3(0.0, 0.0465, -0.035 + index * 0.020), "Vent")
	_block(gun, "RearSight", Vector3(0.024, 0.014, 0.008), "polymer", Vector3(0.0, 0.062, 0.110), "Sight")
	_block(gun, "GroundPlate", Vector3(0.0012, 0.026, 0.060), "steel", Vector3(-0.0325, 0.004, 0.100), "Scar")
	# The cell pack: a canister on the right flank with an amber charge lamp.
	var cell: Node3D = _workshop.group(gun, "Cell", Vector3(0.050, 0.000, 0.090))
	_tube(cell, "Canister", 0.024, Vector3(0.0, 0.0, -0.065), Vector3(0.0, 0.0, 0.065), "steel", "Cell")
	_tube(cell, "CapFront", 0.026, Vector3(0.0, 0.0, -0.070), Vector3(0.0, 0.0, -0.058), "polymer", "Cell")
	_tube(cell, "CapRear", 0.026, Vector3(0.0, 0.0, 0.058), Vector3(0.0, 0.0, 0.070), "polymer", "Cell")
	_block(cell, "Lamp", Vector3(0.008, 0.010, 0.016), "glow", Vector3(0.014, 0.020, 0.0), "Lamp").set_meta("glow", 0.80)
	# Pistol grip, trigger and guard under the receiver; a vertical foregrip.
	_prism(gun, "Grip", PackedVector2Array([
		Vector2(0.10, -0.045), Vector2(0.15, -0.045), Vector2(0.175, -0.150), Vector2(0.140, -0.156), Vector2(0.115, -0.060)]), 0.034, "polymer", Vector3.ZERO, 0.22, "Grip")
	_pipe(gun, "TriggerGuard", PackedVector3Array([
		Vector3(0.0, -0.048, 0.030), Vector3(0.0, -0.075, 0.040), Vector3(0.0, -0.082, 0.070), Vector3(0.0, -0.070, 0.105)]), 0.0035, "enamel", "Receiver")
	_pipe(gun, "Trigger", PackedVector3Array([Vector3(0.0, -0.050, 0.068), Vector3(0.0, -0.064, 0.064), Vector3(0.0, -0.072, 0.072)]), 0.0026, "steel", "Trigger")
	_prism(gun, "Foregrip", PackedVector2Array([
		Vector2(-0.30, -0.030), Vector2(-0.25, -0.030), Vector2(-0.255, -0.120), Vector2(-0.290, -0.124)]), 0.030, "polymer", Vector3.ZERO, 0.22, "Foregrip")
	_block(gun, "ForegripClamp", Vector3(0.040, 0.016, 0.060), "slide", Vector3(0.0, -0.034, -0.275), "Foregrip")
	_prism(gun, "Stock", PackedVector2Array([
		Vector2(0.22, 0.030), Vector2(0.42, 0.020), Vector2(0.43, -0.100), Vector2(0.40, -0.104), Vector2(0.22, -0.040)]), 0.040, "polymer", Vector3.ZERO, 0.2, "Stock")
	_muzzle(gun, MUZZLE["Rail"])

## Right hand on the pistol grip, left hand on the foregrip.
func _rail_hands(gun: Node3D) -> void:
	var hands: Node3D = _workshop.group(gun, "Hands")
	glove(hands, "TriggerHand", {
		"wrist": Vector3(0.040, -0.110, 0.200), "knuckles": Vector3(0.030, -0.090, 0.112),
		"across": Vector3(0.0, 1.0, -0.2), "back": Vector3(1.0, 0.1, 0.1),
		"curl": [Vector3(0.5, 0.9, 0.5), Vector3(0.8, 1.25, 0.9), Vector3(0.8, 1.25, 0.9), Vector3(0.8, 1.25, 0.9)],
		"thumb": [Vector3(0.010, -0.050, 0.170), Vector3(-0.012, -0.040, 0.140), Vector3(-0.024, -0.040, 0.110)],
		"elbow": Vector3(0.170, -0.42, 0.50)})
	glove(hands, "SupportHand", {
		"wrist": Vector3(-0.050, -0.110, -0.200), "knuckles": Vector3(-0.024, -0.085, -0.290),
		"across": Vector3(0.0, 1.0, 0.1), "back": Vector3(-1.0, 0.0, -0.2),
		"curl": [Vector3(0.7, 1.2, 0.8), Vector3(0.75, 1.25, 0.8), Vector3(0.75, 1.25, 0.8), Vector3(0.75, 1.25, 0.8)],
		"thumb": [Vector3(-0.030, -0.060, -0.230), Vector3(-0.026, -0.040, -0.265), Vector3(-0.020, -0.034, -0.300)],
		"elbow": Vector3(-0.200, -0.42, 0.10)})

## Pose the Rail: `cell` metres the cell pack has slid back out of its seat
## (it is gone past 0.2).
static func pose_rail(gun: Node3D, cell: float) -> void:
	rest(gun)
	var pack: Node3D = gun.get_node("Cell") as Node3D
	pack.position.z += cell
	pack.position.x += cell * 0.3
	pack.visible = cell < 0.2

# --- Repeater ------------------------------------------------------------------

## A personally maintained, motor-driven support gun: broad vented shroud,
## side motor and squat drum. Warm repair straps interrupt the issued metal;
## it has neither the Rifle's narrow receiver nor the Railgun's glowing coils.
func _repeater(gun: Node3D) -> void:
	_prism(gun, "Receiver", PackedVector2Array([Vector2(-0.30, -0.05), Vector2(-0.31, 0.055), Vector2(0.15, 0.065), Vector2(0.19, -0.05)]), 0.12, "enamel")
	_block(gun, "TopCover", Vector3(0.105, 0.025, 0.28), "steel", Vector3(0, 0.076, -0.09))
	_block(gun, "RearBand", Vector3(0.122, 0.018, 0.035), "leather", Vector3(0, 0.02, 0.18))
	for index: int in range(4):
		_block(gun, "CoverRib", Vector3(0.11, 0.008, 0.012), "enamel", Vector3(0, 0.092, -0.17 + index * 0.06))
	_tube(gun, "CoolingShroud", 0.065, Vector3(0, 0, -0.29), Vector3(0, 0, -0.74), "blued", "Shroud", 12)
	for index: int in range(8):
		var z: float = -0.32 - index * 0.05
		for side: float in [-1.0, 1.0]:
			_block(gun, "Vent", Vector3(0.008, 0.035, 0.025), "bore", Vector3(side * 0.063, 0, z), "Shroud")
	_tube(gun, "MuzzleCollar", 0.048, Vector3(0, 0, -0.73), Vector3(0, 0, -0.79), "steel")
	_tube(gun, "MuzzleBore", 0.025, Vector3(0, 0, -0.79), Vector3(0, 0, -0.805), "bore")
	_tube(gun, "DriveMotor", 0.043, Vector3(0.09, -0.01, -0.11), Vector3(0.09, -0.01, 0.08), "steel")
	for z: float in [-0.08, 0.05]:
		_block(gun, "MotorStrap", Vector3(0.024, 0.094, 0.018), "leather", Vector3(0.09, -0.01, z))
	var drum: Node3D = _workshop.group(gun, "Drum")
	_tube(drum, "DrumBody", 0.095, Vector3(-0.065, -0.12, -0.055), Vector3(0.065, -0.12, -0.055), "enamel")
	_tube(drum, "DrumRim", 0.098, Vector3(0.066, -0.12, -0.055), Vector3(0.073, -0.12, -0.055), "steel")
	_tube(drum, "DrumHub", 0.026, Vector3(0.073, -0.12, -0.055), Vector3(0.079, -0.12, -0.055), "leather")
	_prism(gun, "Grip", PackedVector2Array([Vector2(0.06, -0.04), Vector2(0.12, -0.04), Vector2(0.17, -0.18), Vector2(0.10, -0.18)]), 0.046, "wood")
	_block(gun, "Foregrip", Vector3(0.04, 0.12, 0.055), "wood", Vector3(-0.015, -0.11, -0.25))
	_prism(gun, "Stock", PackedVector2Array([Vector2(0.16, 0.035), Vector2(0.35, 0.02), Vector2(0.38, -0.095), Vector2(0.32, -0.11), Vector2(0.17, -0.04)]), 0.065, "wood")
	_block(gun, "RearSight", Vector3(0.075, 0.03, 0.02), "blued", Vector3(0, 0.105, 0.055))
	_block(gun, "RearNotch", Vector3(0.014, 0.02, 0.023), "bore", Vector3(0, 0.12, 0.055))
	_block(gun, "FrontSight", Vector3(0.012, 0.055, 0.02), "steel", Vector3(0, 0.07, -0.715))
	# A ground-off registration plate and a small owner-applied repair strap.
	_block(gun, "GroundPlate", Vector3(0.004, 0.035, 0.08), "steel", Vector3(-0.062, 0.01, -0.11))
	_block(gun, "RepairStrap", Vector3(0.13, 0.012, 0.025), "leather", Vector3(0, 0.09, -0.2))
	_muzzle(gun, MUZZLE["Repeater"])

func _repeater_hands(gun: Node3D) -> void:
	var hands: Node3D = _workshop.group(gun, "Hands")
	glove(hands, "TriggerHand", {
		"wrist": Vector3(0.040, -0.110, 0.200), "knuckles": Vector3(0.030, -0.090, 0.112),
		"across": Vector3(0.0, 1.0, -0.2), "back": Vector3(1.0, 0.1, 0.1),
		"curl": [Vector3(0.5, 0.9, 0.5), Vector3(0.8, 1.25, 0.9), Vector3(0.8, 1.25, 0.9), Vector3(0.8, 1.25, 0.9)],
		"thumb": [Vector3(0.010, -0.050, 0.170), Vector3(-0.012, -0.040, 0.140), Vector3(-0.024, -0.040, 0.110)],
		"elbow": Vector3(0.170, -0.42, 0.50)})
	glove(hands, "SupportHand", {
		"wrist": Vector3(-0.070, -0.14, -0.19), "knuckles": Vector3(-0.04, -0.11, -0.26),
		"across": Vector3(0, 1, 0.1), "back": Vector3(-1, 0, -0.2),
		"curl": [Vector3(0.7, 1.2, 0.8), Vector3(0.75, 1.25, 0.8), Vector3(0.75, 1.25, 0.8), Vector3(0.75, 1.25, 0.8)],
		"thumb": [Vector3(-0.035, -0.075, -0.20), Vector3(-0.026, -0.060, -0.24), Vector3(-0.02, -0.05, -0.28)],
		"elbow": Vector3(-0.23, -0.42, 0.10)})

static func pose_repeater(gun: Node3D, drum: float) -> void:
	rest(gun)
	var magazine: Node3D = gun.get_node("Drum") as Node3D
	magazine.position.y -= drum
	magazine.visible = drum < 0.25
