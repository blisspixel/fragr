extends SceneTree

## Prints the trial sources' meshes, materials and clips. Read-only.
func _initialize() -> void:
	for path: String in ["res://art/models/candidates/free_human.glb", "res://art/models/candidates/free_synthetic.glb",
			"res://art/models/candidates/clerk.glb"]:
		var scene: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		print("== ", path)
		for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			print("  mesh ", mesh_node.name, " surfaces ", mesh_node.mesh.get_surface_count(), " aabb ", mesh_node.get_aabb().size,
				" tris ", mesh_node.mesh.get_faces().size() / 3)
			for s: int in mesh_node.mesh.get_surface_count():
				var m: Material = mesh_node.get_active_material(s)
				if m is StandardMaterial3D:
					var sm: StandardMaterial3D = m
					var tex: Texture2D = sm.albedo_texture
					print("    mat ", sm.resource_name, " color ", sm.albedo_color, " tex ", tex.get_size() if tex else Vector2.ZERO,
						" normal ", sm.normal_enabled, " rough ", sm.roughness, " metal ", sm.metallic, " emis ", sm.emission_enabled)
				else:
					print("    mat ", m)
		for p: Node in scene.find_children("*", "AnimationPlayer", true, false):
			print("  anims ", (p as AnimationPlayer).get_animation_list())
		scene.free()
	quit()
