class_name ArenaFlags
extends Node3D

## Two neutral league markers in side colours. Every position comes from the
## authoritative snapshot; this node has no collision or scoring logic.
const POLE_LABEL := Vector3(0.0, 2.7, 0.0)
const CLOTH_LABEL := Vector3(0.66, 2.7, 0.0)

var _stands: Array[Node3D] = []
var _markers: Array[Node3D] = []

static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	return material


static func _box(parent: Node3D, size: Vector3, offset: Vector3, color: Color) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _material(color)
	part.position = offset
	part.layers = ArenaSky.WORLD_LAYERS
	parent.add_child(part)


static func _world_label(team: String, status: String) -> String:
	var key: String = "FLAG_WORLD_" + team.to_upper()
	if status == "dropped":
		key += "_DOWN"
	elif status == "carried":
		key += "_CARRIED"
	return str(TranslationServer.translate(key))


static func _marker(team: String) -> Node3D:
	var root: Node3D = Node3D.new()
	var color: Color = MatchRules.team_label_color(team)
	var body: Color = MatchRules.team_body_color(team)
	_box(root, Vector3(0.12, 2.1, 0.12), Vector3(0.0, 1.05, 0.0), body)
	_box(root, Vector3(1.28, 0.72, 0.08), Vector3(0.66, 1.68, 0.0), color)
	var drop_mark: Node3D = Node3D.new()
	drop_mark.name = "DropMark"
	_box(drop_mark, Vector3(2.4, 0.08, 0.22), Vector3(0.0, 0.04, 0.0), color)
	_box(drop_mark, Vector3(0.22, 0.08, 2.4), Vector3(0.0, 0.04, 0.0), color)
	drop_mark.visible = false
	root.add_child(drop_mark)
	var label: Label3D = Label3D.new()
	label.name = "FlagLabel"
	label.text = _world_label(team, "home")
	label.font_size = 52
	label.pixel_size = 0.005
	label.position = POLE_LABEL
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.layers = ArenaSky.WORLD_LAYERS
	root.add_child(label)
	return root


func clear_flags() -> void:
	for node: Node3D in _stands + _markers:
		if is_instance_valid(node):
			node.queue_free()
	_stands.clear()
	_markers.clear()


func apply(flags: Variant) -> void:
	if not flags is Array or flags.size() != 2:
		clear_flags()
		return
	if _markers.size() != 2:
		clear_flags()
		for i: int in range(2):
			var flag: Dictionary = flags[i]
			var stand: Node3D = Node3D.new()
			_box(stand, Vector3(2.3, 0.16, 2.3), Vector3(0.0, 0.08, 0.0), MatchRules.team_label_color(str(flag["team"])))
			add_child(stand)
			_stands.append(stand)
			var marker: Node3D = _marker(str(flag["team"]))
			add_child(marker)
			_markers.append(marker)
	for i: int in range(2):
		var flag: Dictionary = flags[i]
		var stand: Array = flag["stand"]
		var position: Array = flag["position"]
		var status: String = str(flag["status"])
		_stands[i].position = Vector3(float(stand[0]), float(stand[1]), float(stand[2]))
		_markers[i].position = Vector3(float(position[0]), float(position[1]) + (0.6 if status == "carried" else 0.0), float(position[2]))
		_markers[i].get_node("DropMark").visible = status == "dropped"
		var label: Label3D = _markers[i].get_node("FlagLabel")
		label.text = _world_label(str(flag["team"]), status)
		label.position = CLOTH_LABEL if status == "carried" else POLE_LABEL
