class_name ArenaConquest
extends Node3D

## A ring and floating pennant carry retained state without adding cover.
const FONT: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")
var markers: Dictionary[String, Node3D] = {}

func clear() -> void:
	for marker: Node3D in markers.values():
		remove_child(marker)
		marker.queue_free()
	markers.clear()

func apply(snapshot: Dictionary) -> void:
	var state: Variant = snapshot.get("conquest")
	if not state is Dictionary or not ConquestState.validation_error(snapshot).is_empty():
		clear()
		return
	for point: Dictionary in state.points:
		var id: String = point.id
		if not markers.has(id):
			markers[id] = _marker(float(point.radius))
			add_child(markers[id])
		var marker: Node3D = markers[id]
		marker.position = Vector3(point.position[0], point.position[1], point.position[2])
		var color: Color = ConquestState.color(point)
		var label: Label3D = marker.get_node("Name")
		label.text = ConquestState.label(id) + "\n" + ConquestState.status(point)
		label.modulate = Color("fff1c4") if point.contested else color
		var banner: MeshInstance3D = marker.get_node("Pennant")
		banner.material_override.albedo_color = color
		var ring: MeshInstance3D = marker.get_node("Ring")
		ring.material_override.albedo_color = Color(color, 0.65)

func _marker(radius: float) -> Node3D:
	var marker: Node3D = Node3D.new()
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = "Ring"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = radius - 0.09
	torus.outer_radius = radius
	torus.rings = 48
	torus.ring_segments = 4
	ring.mesh = torus
	ring.scale.y = 0.1
	ring.position.y = 0.025
	ring.material_override = _material(true)
	marker.add_child(ring)
	var banner: MeshInstance3D = MeshInstance3D.new()
	banner.name = "Pennant"
	var mesh: PrismMesh = PrismMesh.new()
	mesh.size = Vector3(0.7, 0.65, 0.04)
	banner.mesh = mesh
	banner.position.y = 4.5
	banner.material_override = _material(false)
	marker.add_child(banner)
	var label: Label3D = Label3D.new()
	label.name = "Name"
	label.font = FONT
	label.font_size = 24
	label.outline_size = 6
	label.pixel_size = 0.024
	label.position.y = 5.5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	marker.add_child(label)
	return marker

func _material(transparent: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if transparent else BaseMaterial3D.TRANSPARENCY_DISABLED
	return material
