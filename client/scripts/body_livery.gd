class_name BodyLivery
extends RefCounted

## Faction dress for a live body (SkinnedCharacter): where the shoulder and arm
## tape and the Union visor sit on each body kind, the issued-livery copy of
## its art, and the dominant base colour the colour picker rule checks. The
## pose implementation stays in SkinnedCharacter; this never moves a bone.

## Eye height as a share of the head's measured height, chin to crown.
const EYE_HEIGHT: float = 0.52
## The free tape's ink edges: a shape cue that survives a jacket of the same hue.
const TAPE_EDGE: Color = Color("16120e")

## Measured once per body kind from its own skinned vertices.
static var _fittings: Dictionary = {}
## The issued-livery copy of each body texture, made once per source texture.
static var _union_textures: Dictionary = {}


static func tape_mesh() -> CylinderMesh:
	var tape: CylinderMesh = CylinderMesh.new()
	tape.top_radius = 1.0
	tape.bottom_radius = 1.0
	tape.height = 1.0
	tape.radial_segments = 10
	tape.rings = 1
	return tape


## The art in issued livery: grey, then dark, so its own light panels become
## plates one step above black cloth. Made once per source texture.
static func union_texture(source: Texture2D) -> Texture2D:
	if _union_textures.has(source):
		return _union_textures[source]
	var image: Image = _readable(source)
	if image == null:
		return source
	image.clear_mipmaps()
	image.adjust_bcs(FactionPalette.UNION_LIVERY_BRIGHTNESS, 1.0, 0.0)
	var issued: ImageTexture = ImageTexture.create_from_image(image)
	_union_textures[source] = issued
	return issued


static func _readable(source: Texture2D) -> Image:
	var image: Image = source.get_image() if source != null else null
	if image == null:
		return null
	image = image.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK:
		return null
	return image


## Where tape and visor sit on this kind, measured from the vertices each
## bone carries in the bind pose, plus the dominant base colour of the art.
## Cached per kind: every instance of a body shares one source.
static func fitting_for(view: SkinnedCharacter) -> Dictionary:
	if _fittings.has(view.kind):
		return _fittings[view.kind]
	var fitting: Dictionary = {"bands": []}
	var clouds: Dictionary = {}
	var poses: Dictionary = {}
	var samples: Array[Color] = []
	for node: Node in view.source_body.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node as MeshInstance3D
		if part.skin == null or part.mesh == null or part.get_parent() != view.skeleton:
			continue
		var binds: Dictionary = {}
		for bind: int in range(part.skin.get_bind_count()):
			var bone: int = part.skin.get_bind_bone(bind)
			var bone_name: String = view.skeleton.get_bone_name(bone) if bone >= 0 \
				else str(part.skin.get_bind_name(bind))
			if bone_name in ["LeftArm", "RightArm", "Head"]:
				binds[bind] = bone_name
				poses[bone_name] = part.skin.get_bind_pose(bind)
		for surface: int in range(part.mesh.get_surface_count()):
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			_collect(arrays, binds, clouds)
			samples.append_array(_texel_samples(part.get_active_material(surface), arrays[Mesh.ARRAY_TEX_UV]))
	for side: String in ["LeftArm", "RightArm"]:
		var length: float = _bone_length(view.skeleton, side)
		if clouds.has(side) and length > 0.0:
			var band: Variant = _tape_fit(clouds[side], poses[side], length)
			if band is Transform3D:
				fitting["bands"].append({"bone": side, "transform": band})
	if clouds.has("Head"):
		var visor: Variant = _visor_fit(clouds["Head"], poses["Head"])
		if visor is Transform3D:
			fitting["visor"] = {"bone": "Head", "transform": visor}
	if not samples.is_empty():
		samples.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
		fitting["base"] = samples[samples.size() / 2]
	_fittings[view.kind] = fitting
	return fitting


## Vertices by the bone that carries most of their weight.
static func _collect(arrays: Array, binds: Dictionary, clouds: Dictionary) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if not arrays[Mesh.ARRAY_BONES] is PackedInt32Array or not arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array \
			or vertices.is_empty():
		return
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per: int = bones.size() / vertices.size()
	for vertex: int in range(vertices.size()):
		var best: int = -1
		var heaviest: float = 0.0
		for slot: int in range(per):
			if weights[vertex * per + slot] > heaviest:
				heaviest = weights[vertex * per + slot]
				best = bones[vertex * per + slot]
		if binds.has(best):
			var bone_name: String = binds[best]
			if not clouds.has(bone_name):
				clouds[bone_name] = PackedVector3Array()
			var cloud: PackedVector3Array = clouds[bone_name]
			cloud.append(vertices[vertex])
			clouds[bone_name] = cloud


static func _bone_length(rig: Skeleton3D, bone_name: String) -> float:
	var bone: int = rig.find_bone(bone_name)
	var children: PackedInt32Array = rig.get_bone_children(bone) if bone >= 0 else PackedInt32Array()
	return rig.get_bone_rest(children[0]).origin.length() if children.size() > 0 else 0.0


## Tape around the upper arm, in the bone's own frame (its Y runs down the
## arm). It covers the upper arm from a sixth to three fifths of its length and
## sits just outside the sleeve, measured from the vertices that arm carries.
static func _tape_fit(cloud: PackedVector3Array, bind: Transform3D, length: float) -> Variant:
	var band: Array[Vector3] = []
	for point: Vector3 in cloud:
		var local: Vector3 = bind * point
		if local.y >= length * 0.16 and local.y <= length * 0.6:
			band.append(local)
	if band.size() < 12:
		return null
	var centre: Vector2 = Vector2.ZERO
	for local: Vector3 in band:
		centre += Vector2(local.x, local.z)
	centre /= float(band.size())
	var across: Array[float] = []
	var deep: Array[float] = []
	for local: Vector3 in band:
		across.append(absf(local.x - centre.x))
		deep.append(absf(local.z - centre.y))
	across.sort()
	deep.sort()
	var radius_x: float = across[int(across.size() * 0.92)] * 1.1
	var radius_z: float = deep[int(deep.size() * 0.92)] * 1.1
	return Transform3D(Basis.from_scale(Vector3(radius_x, length * 0.38, radius_z)),
		Vector3(centre.x, length * 0.36, centre.y))


## A visor across the front of the head at eye height. Measured in the body's
## own space, where the figure faces +Z, then carried into the head's frame.
static func _visor_fit(cloud: PackedVector3Array, bind: Transform3D) -> Variant:
	if cloud.size() < 24:
		return null
	var low: float = INF
	var high: float = -INF
	for point: Vector3 in cloud:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	var tall: float = high - low
	var eye: float = low + tall * EYE_HEIGHT
	var xs: Array[float] = []
	var fronts: Array[float] = []
	for point: Vector3 in cloud:
		if absf(point.y - eye) <= tall * 0.08:
			xs.append(point.x)
			fronts.append(point.z)
	if xs.size() < 8:
		return null
	xs.sort()
	fronts.sort()
	var left: float = xs[int(xs.size() * 0.06)]
	var right: float = xs[int(xs.size() * 0.94)]
	# The frontmost surface at eye height: a face, or a screen standing proud
	# of the head. The visor sits just clear of it so it never sinks inside.
	var front: float = fronts[fronts.size() - 1]
	var size: Vector3 = Vector3((right - left) * 0.8, tall * 0.1, tall * 0.04)
	var centre: Vector3 = Vector3((left + right) * 0.5, eye, front + size.z * 0.35)
	return bind * Transform3D(Basis.from_scale(size), centre)


## Colours of the art under the body's own texture coordinates, a few hundred
## per surface, so the dominant base is what the figure actually shows.
static func _texel_samples(material: Material, uvs: Variant) -> Array[Color]:
	var samples: Array[Color] = []
	if not material is StandardMaterial3D or not uvs is PackedVector2Array:
		return samples
	var standard: StandardMaterial3D = material as StandardMaterial3D
	if standard.albedo_texture == null:
		samples.append(standard.albedo_color)
		return samples
	var image: Image = _readable(standard.albedo_texture)
	if image == null:
		return samples
	var coords: PackedVector2Array = uvs
	var stride: int = maxi(1, coords.size() / 600)
	var width: int = image.get_width()
	var height: int = image.get_height()
	for index: int in range(0, coords.size(), stride):
		var uv: Vector2 = coords[index]
		var x: int = clampi(int(fposmod(uv.x, 1.0) * width), 0, width - 1)
		var y: int = clampi(int(fposmod(uv.y, 1.0) * height), 0, height - 1)
		samples.append(image.get_pixel(x, y) * standard.albedo_color)
	return samples
