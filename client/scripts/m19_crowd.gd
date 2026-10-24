extends RefCounted

## Low Water's people leaving: free humans and free agents, each one dressed
## and repaired in their own way. Bodies, clothes, bundles and screen faces vary
## per person in mid and warm values, and nobody walks in rank: families, pairs
## carrying a crate, someone resting on a case. Free agents carry warm screen
## faces or lamps, never red optics, cyan glow or a matte off-white base.
## Presentation only; nothing here is collision, cover or a target.

const COATS: Array[Color] = [
	Color("9a5a3c"), Color("b08a4a"), Color("4f6a8a"), Color("6f7a4a"), Color("c09a3a"),
	Color("8e4a40"), Color("7a5068"), Color("a89272"), Color("5f7a5a"), Color("b07850"),
	Color("6a7d8c"), Color("a0623e"), Color("8a7a3e"), Color("5a5f88"),
]
const LEGS: Array[Color] = [Color("3e4a5a"), Color("5a4a3a"), Color("4a5040"), Color("6a5a48"), Color("504a58"), Color("5c5444")]
const SKIN: Array[Color] = [Color("8a6d58"), Color("c49a7c"), Color("5e4232"), Color("a87a5a"), Color("d1a98a"), Color("74513c")]
const HAIR: Array[Color] = [Color("2e241c"), Color("6a4a2a"), Color("8a8478"), Color("3a2a22"), Color("a8743c")]
const ACCENTS: Array[Color] = [Color("d0a040"), Color("b84c3a"), Color("8a5aa0"), Color("e0c088"), Color("5a8a6a"), Color("c87a3a")]
const LOADS: Array[Color] = [Color("7d6b4f"), Color("5b4a3a"), Color("8a5a3a"), Color("4d5a52"), Color("9c7b55"), Color("6e5a3c")]
## Free agents' own paint over steel: personal, warm or mid, never the
## reserved black-and-red or a clean off-white base.
const AGENT_PAINT: Array[Color] = [Color("b0663a"), Color("c8a048"), Color("5a7898"), Color("7a8a4a"), Color("9a4e5a")]
const AGENT_STEEL: Color = Color("4a4f50")
const PHOSPHOR: Color = Color("ffb860")
const SCREEN: Color = Color("5a3416")

## Deterministic variety: one look per seed, so a capture is repeatable.
static func look(seed: int) -> Dictionary:
	var at: int = absi(seed * 7919 + 104729)
	return {
		"coat": COATS[at % COATS.size()],
		"legs": LEGS[(at / 3) % LEGS.size()],
		"skin": SKIN[(at / 7) % SKIN.size()],
		"hair": HAIR[(at / 11) % HAIR.size()],
		"accent": ACCENTS[(at / 13) % ACCENTS.size()],
		"load": LOADS[(at / 17) % LOADS.size()],
		"height": 0.92 + float((at / 19) % 5) * 0.04,
		"width": 0.9 + float((at / 23) % 4) * 0.07,
		"hat": (at / 29) % 4 == 0,
		"scarf": (at / 31) % 3 == 0,
		"pack": (at / 37) % 3,
		"agent": (at / 41) % 5 == 0,
	}

static func lit(colour: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material

static func glow(colour: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = lit(colour)
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = energy
	return material

static func box(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node

## A standing person facing +Z. Legs carry a "side" meta for the walk swing;
## `child` scales the body down. One look in five is a free agent instead.
static func person(seed: int, child: bool = false) -> Node3D:
	var l: Dictionary = look(seed)
	if bool(l["agent"]) and not child:
		return agent(seed)
	var scale: float = (0.68 if child else 1.0) * float(l["height"])
	var width: float = float(l["width"])
	var node: Node3D = Node3D.new()
	node.name = "Evacuee"
	var coat: StandardMaterial3D = lit(l["coat"])
	var legs: StandardMaterial3D = lit(l["legs"])
	box(node, "Coat", Vector3(0.0, 1.12, 0.0) * scale, Vector3(0.5 * width, 0.74, 0.3) * scale, coat)
	# A hem or patch in another colour breaks every coat's large panel.
	box(node, "Patch", Vector3(0.12 * width, 1.0, 0.152) * scale, Vector3(0.14, 0.12, 0.01) * scale, lit(l["accent"]))
	box(node, "Head", Vector3(0.0, 1.66, 0.0) * scale, Vector3(0.26, 0.28, 0.26) * scale, lit(l["skin"]))
	if bool(l["hat"]):
		box(node, "Cap", Vector3(0.0, 1.83, 0.02) * scale, Vector3(0.3, 0.08, 0.32) * scale, lit(l["accent"]))
	else:
		box(node, "Hair", Vector3(0.0, 1.78, -0.03) * scale, Vector3(0.28, 0.08, 0.24) * scale, lit(l["hair"]))
	if bool(l["scarf"]):
		box(node, "Scarf", Vector3(0.0, 1.47, 0.0) * scale, Vector3(0.34 * width, 0.08, 0.34) * scale, lit(l["accent"]))
	for side: float in [-1.0, 1.0]:
		var leg: MeshInstance3D = box(node, "Leg", Vector3(side * 0.12, 0.4, 0.0) * scale, Vector3(0.17, 0.8, 0.18) * scale, legs)
		leg.set_meta("side", side)
		box(node, "Arm", Vector3(side * (0.29 * width), 1.12, 0.0) * scale, Vector3(0.1, 0.62, 0.14) * scale, coat)
	if child:
		return node
	match int(l["pack"]):
		0:
			box(node, "Bundle", Vector3(0.0, 1.05, -0.24), Vector3(0.36, 0.42, 0.2), lit(l["load"]))
		1:
			box(node, "ShoulderBag", Vector3(0.3 * width, 0.88, 0.04), Vector3(0.12, 0.3, 0.28), lit(l["load"]))
		_:
			box(node, "Case", Vector3(0.36 * width, 0.5, 0.0), Vector3(0.12, 0.36, 0.5), lit(l["load"]))
	return node

## A free agent: a repaired chassis in its own paint, a CRT head with a warm
## phosphor face, one antenna. Never a Union Sweeper's plates or red optics.
static func agent(seed: int) -> Node3D:
	var l: Dictionary = look(seed)
	var paint: Color = AGENT_PAINT[absi(seed * 31 + 7) % AGENT_PAINT.size()]
	var node: Node3D = Node3D.new()
	node.name = "FreeAgent"
	var shell: StandardMaterial3D = lit(paint, 0.7)
	var steel: StandardMaterial3D = lit(AGENT_STEEL, 0.6)
	box(node, "Torso", Vector3(0.0, 1.14, 0.0), Vector3(0.46, 0.66, 0.3), shell)
	# Mismatched repair plate and a sticker: individuality before anything.
	box(node, "RepairPlate", Vector3(-0.12, 1.2, 0.152), Vector3(0.16, 0.2, 0.01), lit(Color("7a4a2a")))
	box(node, "Sticker", Vector3(0.12, 1.02, 0.152), Vector3(0.09, 0.09, 0.01), lit(l["accent"]))
	box(node, "Neck", Vector3(0.0, 1.5, 0.0), Vector3(0.1, 0.08, 0.1), steel)
	box(node, "Head", Vector3(0.0, 1.66, 0.0), Vector3(0.3, 0.26, 0.24), steel)
	# A dim warm screen with two pixel eyes: a face, not a lamp.
	box(node, "Screen", Vector3(0.0, 1.66, 0.121), Vector3(0.22, 0.17, 0.01), glow(SCREEN, 0.9))
	var eye: StandardMaterial3D = glow(PHOSPHOR, 1.6)
	for side: float in [-1.0, 1.0]:
		box(node, "Eye", Vector3(side * 0.05, 1.68, 0.127), Vector3(0.035, 0.035, 0.004), eye)
	box(node, "Antenna", Vector3(0.12, 1.86, 0.0), Vector3(0.02, 0.2, 0.02), steel)
	for side: float in [-1.0, 1.0]:
		var leg: MeshInstance3D = box(node, "Leg", Vector3(side * 0.11, 0.4, 0.0), Vector3(0.14, 0.8, 0.16), steel)
		leg.set_meta("side", side)
		box(node, "Arm", Vector3(side * 0.28, 1.1, 0.0), Vector3(0.09, 0.6, 0.12), shell if side > 0.0 else steel)
	box(node, "Bundle", Vector3(0.0, 1.08, -0.22), Vector3(0.34, 0.4, 0.16), lit(l["load"]))
	return node

## Someone sitting at the seat height of the node's origin, facing +Z.
static func seated(seed: int, child: bool = false) -> Node3D:
	var l: Dictionary = look(seed)
	var scale: float = (0.7 if child else 1.0) * float(l["height"])
	var node: Node3D = Node3D.new()
	node.name = "Waiting"
	var coat: StandardMaterial3D = lit(l["coat"])
	var legs: StandardMaterial3D = lit(l["legs"])
	box(node, "Coat", Vector3(0.0, 0.36, -0.12) * scale, Vector3(0.5 * float(l["width"]), 0.7, 0.3) * scale, coat)
	box(node, "Head", Vector3(0.0, 0.86, -0.1) * scale, Vector3(0.26, 0.28, 0.26) * scale, lit(l["skin"]))
	box(node, "Hair", Vector3(0.0, 0.98, -0.13) * scale, Vector3(0.28, 0.07, 0.24) * scale, lit(l["hair"]))
	if bool(l["scarf"]):
		box(node, "Scarf", Vector3(0.0, 0.68, -0.1) * scale, Vector3(0.34, 0.08, 0.34) * scale, lit(l["accent"]))
	for side: float in [-1.0, 1.0]:
		box(node, "Thigh", Vector3(side * 0.12, 0.06, 0.12) * scale, Vector3(0.17, 0.14, 0.46) * scale, legs)
		box(node, "Shin", Vector3(side * 0.12, -0.42, 0.4) * scale, Vector3(0.17, 0.84, 0.17) * scale, legs)
	if not child:
		box(node, "Bag", Vector3(0.0, 0.26, 0.24), Vector3(0.36, 0.3, 0.2), lit(l["load"]))
	return node

## A hand lamp: warm personal light on the ground or a crate.
static func hand_lamp(parent: Node3D, at: Vector3, energy: float = 0.9) -> OmniLight3D:
	box(parent, "HandLamp", at, Vector3(0.14, 0.22, 0.14), glow(Color("ffc06e"), 3.0))
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "HandLampLight"
	light.light_color = Color("ffb862")
	light.light_energy = energy
	light.omni_range = 3.6
	light.shadow_enabled = false
	light.position = at + Vector3(0.0, 0.2, 0.0)
	parent.add_child(light)
	return light

## A household walking together: two adults with a child between them,
## sharing one lane. Returns the group root; members keep "side" legs.
static func family(seed: int) -> Node3D:
	var group: Node3D = Node3D.new()
	group.name = "Family"
	var first: Node3D = person(seed * 3 + 1)
	first.position = Vector3(-0.55, 0.0, 0.0)
	group.add_child(first)
	var kid: Node3D = person(seed * 3 + 2, true)
	kid.position = Vector3(0.0, 0.0, 0.15)
	group.add_child(kid)
	var second: Node3D = person(seed * 3 + 5)
	second.position = Vector3(0.6, 0.0, -0.1)
	group.add_child(second)
	return group

## Two people carrying a crate between them.
static func crate_pair(seed: int) -> Node3D:
	var group: Node3D = Node3D.new()
	group.name = "CratePair"
	var front: Node3D = person(seed * 5 + 3)
	front.position = Vector3(0.0, 0.0, 0.75)
	group.add_child(front)
	var back: Node3D = person(seed * 5 + 4)
	back.position = Vector3(0.0, 0.0, -0.75)
	group.add_child(back)
	box(group, "Crate", Vector3(0.0, 0.92, 0.0), Vector3(0.6, 0.4, 0.8), lit(Color("7a5a3a")))
	return group

## Swing the legs of one walker, or of every walker in a group, each member
## a little out of step with the next.
static func stride(node: Node3D, phase: float) -> void:
	if _swing(node, phase):
		return
	for member: Node in node.get_children():
		if member is Node3D:
			_swing(member as Node3D, phase + float(member.get_index()) * 1.7)

static func _swing(walker: Node3D, phase: float) -> bool:
	var legs: bool = false
	var swing: float = sin(phase)
	for part: Node in walker.get_children():
		if part.has_meta("side"):
			legs = true
			(part as Node3D).rotation.x = swing * 0.35 * float(part.get_meta("side"))
	return legs
