extends SceneTree

## Compliance Yard's and Low Water's presenters against the server's own
## MapInfo (client/golden/compliance_yard_map_info.json and
## low_water_map_info.json, held to the server by the maps' golden tests).
##
## Each presenter applies only to its own map; Low Water dresses every face,
## lamp, tank and the tram it names on an exact server solid; its market goods
## lie flat, its bunting and every lamp head hang overhead; the yard's floor
## paint lies flat and its work lamps hang from the wall tops. Both maps take
## their registered venue, and nothing either presenter adds is collision.

const YARD: String = "res://golden/compliance_yard_map_info.json"
const WATER: String = "res://golden/low_water_map_info.json"
const STREET: float = 3.0

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_yard_water_dressing: " + message)

func _load(path: String) -> Dictionary:
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(info is Dictionary and MapGeometry.validation_error(info).is_empty(), path + " is a valid MapInfo")
	return info if info is Dictionary else {}

func _meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_meshes(child, out)

func _no_collision(node: Node, label: String) -> void:
	if node is CollisionObject3D or node is CollisionShape3D:
		_check(false, label + " adds collision: " + str(node.get_path()))
	for child: Node in node.get_children():
		_no_collision(child, label)

func _run() -> void:
	var yard: Dictionary = _load(YARD)
	var water: Dictionary = _load(WATER)
	if yard.is_empty() or water.is_empty():
		quit(1)
		return
	_check(ArenaCover.venue_for(yard) == "compliance_yard", "the yard takes its Union venue")
	_check(ArenaCover.venue_for(water) == "low_water", "Low Water keeps its town venue")
	_check(ComplianceYard.applies(yard) and not ComplianceYard.applies(water), "the yard presenter is the yard's alone")
	_check(LowWaterTown.applies(water) and not LowWaterTown.applies(yard), "the town presenter is map 8's alone")
	var campaign: Dictionary = water.duplicate(true)
	campaign["m19"] = {}
	_check(not LowWaterTown.applies(campaign), "Planned Works keeps its own night dressing")

	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var town: LowWaterTown = LowWaterTown.new()
	holder.add_child(town)
	town.build(water)
	var dressed: Node3D = town.dressing.root
	_check(int(dressed.get_meta("faces")) == LowWaterTown.FACES.size(), "every named face stands on a server solid (%d of %d)" % [int(dressed.get_meta("faces")), LowWaterTown.FACES.size()])
	_check(int(dressed.get_meta("lamps")) == LowWaterTown.LAMPS.size(), "every street lamp stands on its post")
	_check(int(dressed.get_meta("tanks")) == 1 and int(dressed.get_meta("trams")) == 1, "the tank and the stopped tram are dressed")
	_no_collision(town, "Low Water")
	var meshes: Array[MeshInstance3D] = []
	_meshes(town, meshes)
	var goods: int = 0
	var flags: int = 0
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh is PrismMesh:
			flags += 1
			var bottom: float = mesh.global_position.y - 0.21
			_check(bottom > STREET + 2.4, "bunting hangs overhead (%.2f)" % bottom)
		elif mesh.mesh is BoxMesh and absf(mesh.global_position.y - STREET) < 0.3 and (mesh.mesh as BoxMesh).size.y < 0.3:
			goods += 1
	_check(goods >= 20, "market goods lie on their cloths (%d)" % goods)
	_check(flags >= 20, "the bunting is strung (%d flags)" % flags)

	var yard_holder: Node3D = Node3D.new()
	root.add_child(yard_holder)
	var dressing: ComplianceYard = ComplianceYard.new()
	yard_holder.add_child(dressing)
	dressing.build(yard)
	_no_collision(dressing, "Compliance Yard")
	var lamps: int = 0
	var marks: Array[MeshInstance3D] = []
	_meshes(dressing, marks)
	for mark: MeshInstance3D in marks:
		var at: float = mark.global_position.y
		_check(at < 0.05 or at > 3.6, "yard dressing lies flat or hangs from a wall top (%.2f)" % at)
	for child: Node in dressing.get_children():
		if child.name.begins_with("WorkLamp"):
			lamps += 1
	_check(lamps == ComplianceYard.LAMPS.size(), "every work lamp hangs (%d)" % lamps)
	if _failures == 0:
		print("test_yard_water_dressing: PASS both presenters apply to their own maps, stand on the server's solids, lie flat or hang overhead, and add no collision")
	quit(0 if _failures == 0 else 1)
