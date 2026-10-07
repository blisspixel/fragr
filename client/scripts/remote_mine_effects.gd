class_name RemoteMineEffects
extends Node3D

## Rectangular deliberate charges stay distinct from round proximity mines.
## Every visible phase is read from the server; local time never arms a charge.
var bodies: Dictionary[int, Node3D] = {}
var phases: Dictionary[int, String] = {}
var last_tick: int = -1
var lamps_lit: int = 0

func reset() -> void:
	for body: Node3D in bodies.values():
		body.queue_free()
	bodies.clear()
	phases.clear()
	last_tick = -1
	lamps_lit = 0

func apply(snapshot: Dictionary) -> void:
	if not CustodyFacts.validation_error(snapshot).is_empty() or int(snapshot["tick"]) <= last_tick:
		return
	last_tick = int(snapshot["tick"])
	lamps_lit = 0
	var current: Dictionary[int, bool] = {}
	for fact: Dictionary in snapshot.get("remote_mines", []):
		var id: int = int(fact["id"])
		current[id] = true
		if not bodies.has(id):
			bodies[id] = make_body()
			bodies[id].name = "RemoteMine_%d" % id
			add_child(bodies[id])
		var body: Node3D = bodies[id]
		body.position = GrenadeFacts.vector(fact["position"])
		var normal: Vector3 = GrenadeFacts.vector(fact["normal"])
		if normal.length_squared() > 0.5:
			var side: Vector3 = Vector3.RIGHT if absf(normal.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			var forward: Vector3 = side.cross(normal).normalized()
			body.basis = Basis(normal.cross(forward).normalized(), normal, forward)
		var phase: String = str(fact["phase"])
		phases[id] = phase
		var lit: bool = phase == "arming" or phase == "armed" or phase == "triggered" and posmod(last_tick, 2) == 0
		lamps_lit += int(lit)
		var lamp: MeshInstance3D = body.get_node("Lamp") as MeshInstance3D
		var material: StandardMaterial3D = lamp.material_override as StandardMaterial3D
		var color: Color = Color("e69e46") if phase == "arming" else Color("cae1d4") if phase == "armed" else Color("f44332")
		material.albedo_color = color if lit else Color("251c20")
		material.emission = color if lit else Color.BLACK
	for id: int in bodies.keys():
		if not current.has(id):
			bodies[id].queue_free()
			bodies.erase(id)
			phases.erase(id)

static func make_body() -> Node3D:
	var body: Node3D = Node3D.new()
	_part(body, "Charge", Vector3(0.30, 0.06, 0.22), Vector3(0, 0.03, 0), Color("414344"))
	_part(body, "StrapA", Vector3(0.04, 0.015, 0.235), Vector3(-0.08, 0.065, 0), Color("9a917b"))
	_part(body, "StrapB", Vector3(0.04, 0.015, 0.235), Vector3(0.08, 0.065, 0), Color("9a917b"))
	_part(body, "Receiver", Vector3(0.08, 0.035, 0.065), Vector3(0, 0.075, 0.02), Color("25262b"))
	_part(body, "Lamp", Vector3(0.045, 0.012, 0.025), Vector3(0, 0.098, 0.02), Color("251c20"))
	return body

static func _part(body: Node3D, label: String, size: Vector3, position: Vector3, color: Color) -> void:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = position
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.emission_enabled = label == "Lamp"
	part.material_override = material
	body.add_child(part)
