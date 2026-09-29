class_name ArenaFlags
extends Node3D

## Two neutral league markers in side colours. Every position comes from the
## authoritative snapshot; this node has no collision or scoring logic.
## A carried flag leaves the stand and sits in the carrier's hand. Home and
## dropped flags keep the stand pole.
const HOME_POLE_SIZE := Vector3(0.12, 2.1, 0.12)
const HOME_POLE_AT := Vector3(0.0, 1.05, 0.0)
const HOME_CLOTH_SIZE := Vector3(1.28, 0.72, 0.08)
const HOME_CLOTH_AT := Vector3(0.66, 1.68, 0.0)
const POLE_LABEL := Vector3(0.0, 2.7, 0.0)
## The body sprite is centred here: the same point the held weapon uses.
## A banner at the pawn origin sits on the neck and reads as a missed take.
const CARRIED_HAND_Y := -0.6
## Into the off-hand side of the torso, then forward of the billboard so the
## grip draws over the arm instead of beside the silhouette.
const CARRIED_SIDE := 0.16
const CARRIED_FRONT := 0.42
const CARRIED_POLE_SIZE := Vector3(0.06, 0.44, 0.06)
const CARRIED_POLE_AT := Vector3(0.0, 0.22, 0.0)
const CARRIED_CLOTH_SIZE := Vector3(0.46, 0.30, 0.045)
const CARRIED_CLOTH_AT := Vector3(0.26, 0.36, 0.0)
const CARRIED_LABEL_AT := Vector3(0.26, 0.56, 0.0)
const HOME_PAD_SIZE := Vector3(2.3, 0.16, 2.3)
const HOME_PAD_AT := Vector3(0.0, 0.08, 0.0)
const EMPTY_PAD_SIZE := Vector3(1.15, 0.04, 1.15)
const EMPTY_PAD_AT := Vector3(0.0, 0.02, 0.0)
const EMPTY_STAND := Color(0.07, 0.07, 0.08)

var _stands: Array[Node3D] = []
var _markers: Array[Node3D] = []
var _carriers: Array = []


func _init() -> void:
	# Pawns move in their own process. Seat the flag after that, on the body
	# the spectator actually sees.
	process_priority = 10


static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	return material


static func _box(parent: Node3D, size: Vector3, offset: Vector3, color: Color, node_name: String = "") -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var part: MeshInstance3D = MeshInstance3D.new()
	if node_name != "":
		part.name = node_name
	part.mesh = mesh
	part.material_override = _material(color)
	part.position = offset
	part.layers = ArenaSky.WORLD_LAYERS
	parent.add_child(part)
	return part


static func _world_label(team: String, status: String) -> String:
	var key: String = "FLAG_WORLD_" + team.to_upper()
	if status == "dropped":
		key += "_DOWN"
	elif status == "carried":
		key += "_CARRIED"
	return str(TranslationServer.translate(key))


static func _pad_color(team: String, at_home: bool) -> Color:
	var color: Color = MatchRules.team_label_color(team)
	if at_home:
		return color
	return color.lerp(EMPTY_STAND, 0.94)


static func _marker(team: String) -> Node3D:
	var root: Node3D = Node3D.new()
	var color: Color = MatchRules.team_label_color(team)
	var body: Color = MatchRules.team_body_color(team)
	_box(root, HOME_POLE_SIZE, HOME_POLE_AT, body, "Pole")
	_box(root, HOME_CLOTH_SIZE, HOME_CLOTH_AT, color, "Cloth")
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


func _dress(marker: Node3D, status: String) -> void:
	var carried: bool = status == "carried"
	var pole: MeshInstance3D = marker.get_node("Pole") as MeshInstance3D
	var cloth: MeshInstance3D = marker.get_node("Cloth") as MeshInstance3D
	pole.visible = true
	(pole.mesh as BoxMesh).size = CARRIED_POLE_SIZE if carried else HOME_POLE_SIZE
	pole.position = CARRIED_POLE_AT if carried else HOME_POLE_AT
	(cloth.mesh as BoxMesh).size = CARRIED_CLOTH_SIZE if carried else HOME_CLOTH_SIZE
	cloth.position = CARRIED_CLOTH_AT if carried else HOME_CLOTH_AT
	var surface: StandardMaterial3D = cloth.material_override as StandardMaterial3D
	if surface != null:
		# The marker itself is aimed at the camera. A second billboard yaws
		# the cloth off the grip.
		surface.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if carried else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var label: Label3D = marker.get_node("FlagLabel") as Label3D
	label.position = CARRIED_LABEL_AT if carried else POLE_LABEL
	label.pixel_size = 0.0024 if carried else 0.005
	# Draw with the fighter. A world-layer banner loses to the sprite and the
	# part that should cover the hand disappears behind the jacket.
	var draw_layer: int = ArenaSky.ACTOR_LAYERS if carried else ArenaSky.WORLD_LAYERS
	pole.layers = draw_layer
	cloth.layers = draw_layer
	label.layers = draw_layer
	var shadow: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if carried else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pole.cast_shadow = shadow
	cloth.cast_shadow = shadow


## Grip in the off hand: camera-right of the torso, in front of the billboard,
## at the same height as the held weapon. No camera uses the pawn's own left
## and forward, which is what the harness asserts.
static func carried_origin(pawn: Node3D, view: Camera3D) -> Vector3:
	var side: Vector3 = -pawn.global_transform.basis.z
	var front: Vector3 = pawn.global_transform.basis.x
	if view != null:
		side = view.global_transform.basis.x
		var to_view: Vector3 = view.global_position - pawn.global_position
		to_view.y = 0.0
		if to_view.length_squared() > 0.04:
			front = to_view
	side.y = 0.0
	front.y = 0.0
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	if front.length_squared() < 0.0001:
		front = Vector3.FORWARD
	side = side.normalized()
	front = front.normalized()
	if absf(side.dot(front)) > 0.98:
		front = side.cross(Vector3.UP)
	if front.length_squared() < 0.0001:
		front = Vector3.FORWARD
	front = front.normalized()
	return pawn.global_position + Vector3(0.0, CARRIED_HAND_Y, 0.0) + side * CARRIED_SIDE + front * CARRIED_FRONT


static func carried_basis(side: Vector3) -> Basis:
	var x_axis: Vector3 = side
	x_axis.y = 0.0
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	return Basis(x_axis, Vector3.UP, x_axis.cross(Vector3.UP))


func _seat(marker: Node3D, pawn: Node3D) -> void:
	var view: Camera3D = marker.get_viewport().get_camera_3d() if marker.is_inside_tree() else null
	var side: Vector3 = -pawn.global_transform.basis.z
	if view != null:
		side = view.global_transform.basis.x
	marker.global_transform = Transform3D(carried_basis(side), carried_origin(pawn, view))


func _process(_delta: float) -> void:
	for i: int in range(_markers.size()):
		if i >= _carriers.size():
			return
		var pawn: Variant = _carriers[i]
		var marker: Node3D = _markers[i]
		if not is_instance_valid(marker):
			continue
		if not pawn is Node3D or not is_instance_valid(pawn):
			continue
		_seat(marker, pawn as Node3D)


## Screen rects a nameplate must not cover: each flag's words and its cloth.
func blocker_rects(view: Camera3D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if view == null:
		return rects
	for marker: Node3D in _markers:
		if not is_instance_valid(marker) or not marker.visible:
			continue
		var label: Label3D = marker.get_node_or_null("FlagLabel") as Label3D
		if label != null and label.visible:
			var words: Rect2 = NameplateLayout.project_label(view, label)
			if words.size != Vector2.ZERO:
				rects.append(words)
		var cloth: MeshInstance3D = marker.get_node_or_null("Cloth") as MeshInstance3D
		if cloth == null or cloth.mesh == null:
			continue
		var box: BoxMesh = cloth.mesh as BoxMesh
		var span: Rect2 = NameplateLayout.project_span(view, cloth.global_position, box.size.x * 0.5, box.size.y * 0.5)
		if span.size != Vector2.ZERO:
			rects.append(span)
	return rects


func clear_flags() -> void:
	for node: Node3D in _stands + _markers:
		if is_instance_valid(node):
			node.queue_free()
	_stands.clear()
	_markers.clear()
	_carriers.clear()


func apply(flags: Variant, carriers: Dictionary = {}) -> void:
	if not flags is Array or flags.size() != 2:
		clear_flags()
		return
	if _markers.size() != 2:
		clear_flags()
		for i: int in range(2):
			var flag: Dictionary = flags[i]
			var stand: Node3D = Node3D.new()
			_box(stand, Vector3(2.3, 0.16, 2.3), Vector3(0.0, 0.08, 0.0), MatchRules.team_label_color(str(flag["team"])), "Pad")
			add_child(stand)
			_stands.append(stand)
			var marker: Node3D = _marker(str(flag["team"]))
			add_child(marker)
			_markers.append(marker)
		_carriers = [null, null]
	for i: int in range(2):
		var flag: Dictionary = flags[i]
		var stand: Array = flag["stand"]
		var position: Array = flag["position"]
		var status: String = str(flag["status"])
		_stands[i].position = Vector3(float(stand[0]), float(stand[1]), float(stand[2]))
		var at_home: bool = status == "home"
		var pad: MeshInstance3D = _stands[i].get_node("Pad") as MeshInstance3D
		(pad.mesh as BoxMesh).size = HOME_PAD_SIZE if at_home else EMPTY_PAD_SIZE
		pad.position = HOME_PAD_AT if at_home else EMPTY_PAD_AT
		var pad_surface: StandardMaterial3D = pad.material_override as StandardMaterial3D
		if pad_surface != null:
			pad_surface.albedo_color = _pad_color(str(flag["team"]), at_home)
		var marker: Node3D = _markers[i]
		_dress(marker, status)
		marker.get_node("DropMark").visible = status == "dropped"
		var label: Label3D = marker.get_node("FlagLabel") as Label3D
		label.text = _world_label(str(flag["team"]), status)
		var carrier_id: String = str(flag.get("carrier", ""))
		var pawn: Variant = carriers.get(carrier_id)
		if status == "carried" and pawn is Node3D and is_instance_valid(pawn):
			_carriers[i] = pawn
			_seat(marker, pawn as Node3D)
		else:
			_carriers[i] = null
			marker.rotation = Vector3.ZERO
			marker.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
