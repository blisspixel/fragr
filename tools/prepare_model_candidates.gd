extends SceneTree

## Offline preparation of a reviewed model round into the ignored candidate area.
## Measures each raw source (faces, welded open edges, scale against its intended
## solid), applies the pixel treatment (palette-locked downsampled paint at a
## target texel density, nearest filtering, no ORM maps) and exports a prepared
## GLB plus receipt. Makes no service request.
##
## The same pass prepares a picked model for shipping when its catalog entry
## says `ship`: the receipt carries the entry's provenance and marks the asset
## runtime selected, and no review paint is written beside it. Optional local
## cleanup, applied in this order and recorded in the receipt:
##   `clip`           rows {"axis": "y", "keep": "below", "at": metres} cut the
##                    fitted mesh at a plane, splitting crossing triangles so
##                    the kept part ends on a clean line (a folded pantograph,
##                    a bunk's lower berth without its upper tier)
##   `stretch`        fit each axis to `intended` instead of one uniform scale,
##                    refused beyond `max_stretch_log` (default 0.15) on any axis
##   `drop`           [[min x, y, z], [max x, y, z]] boxes in fitted metres (pivot
##                    at the floor centre); a triangle whose centroid falls
##                    inside one is removed
##   `remap`          rows {"y": [lo, hi], "x": [from_lo, from_hi, to_lo, to_hi],
##                    "z": [...]} move a band of the fitted mesh onto new
##                    bounds, e.g. a cabin onto the footprint of its kerb
##   `gain`           multiplies the paint before the palette lock
##   `swatches`       shipped venue swatches the lock may also use
##   `exclude_keys`, `exclude_classes`  ramps the lock may not use
##   `repaint`        rows {"keys": [locked ramps, "name" or "name@shade"], "to": key, "shade":
##                    optional, "box": optional [[min], [max]] in fitted
##                    metres} applied to the locked paint: every texel on a
##                    triangle whose centroid is inside the box (anywhere
##                    without one) that locked to one of `keys` takes the
##                    `to` ramp at its own shade, or at `shade` when given.
##                    Re-marks a Union band the lock lost or flattens a
##                    patch onto one ramp; never a ramp the faction excludes
##   `parts`          rows {"name", "box": [[min], [max]], "pivot": [x, y, z]} in
##                    fitted metres split the kept mesh into named child meshes
##                    stored about their pivots (a Paver's projector head, a
##                    Surveyor's lens housing); the rest stays `Body`
##
## godot --headless --path client --script ../tools/prepare_model_candidates.gd -- \
##   <catalog.json> <raw dir> <prepared dir> [exact candidate id]

const Metadata = preload("res://art/models/glb_metadata.gd")
const TARGET_TEXELS_PER_METRE: float = 32.0
const MIN_TEXTURE: int = 64
const MAX_TEXTURE: int = 512
const PRESENTED_TEXTURE: int = 1024
const SHADES: Array[float] = [0.7, 1.0, 1.2]
# Shipped M05 paint-bench swatches (client/scripts/m05_town.gd), named by the canon review.
const SHIPPED_EXTENSION: Dictionary = {"m05_rust": Color8(178, 103, 67), "m05_green": Color8(105, 144, 135), "m05_ochre": Color8(190, 161, 105)}
# Shipped Larak Lot venue paint (client/scripts/larak_lot.gd: HAZARD_YELLOW and the
# league colours). Opt-in per entry through `swatches`, never chosen otherwise.
const VENUE_SWATCHES: Dictionary = {"larak_hazard": Color8(201, 162, 58), "larak_ember": Color8(207, 111, 42), "larak_mustard": Color8(214, 162, 62),
	"larak_rust": Color8(124, 69, 41), "larak_canvas": Color8(180, 154, 104)}
const MAX_STRETCH_LOG: float = 0.15
const CLASSES: Dictionary = {
	"ink": "dark", "union_black": "dark", "union_steel": "dark", "gunmetal_dark": "dark", "outline_purple": "dark",
	"gunmetal": "steel", "gunmetal_light": "steel", "union_plate": "steel",
	"union_red": "red", "union_red_glow": "red", "blood": "red", "on_air": "red",
	"bone": "bone", "cyan_muted": "cyan", "cyan_light": "cyan",
	"institutional_green": "green", "moss": "green", "leaf_muted": "green", "m05_green": "green",
	"rust": "warm", "dust_rust": "warm", "dust_light": "warm", "ember": "warm", "ember_hot": "warm", "m05_rust": "warm", "m05_ochre": "warm",
	"larak_hazard": "warm", "larak_ember": "warm", "larak_mustard": "warm", "larak_rust": "warm", "larak_canvas": "warm",
	"magenta_muted": "magenta", "magenta_light": "magenta"}

var _ramp_colors: Array[Color] = []
var _ramp_lab: Array[Vector3] = []
var _ramp_names: PackedStringArray = PackedStringArray()
var _ramp_shades: PackedFloat32Array = PackedFloat32Array()
var _cache: Dictionary = {}
# Faction class gate for the palette lock: a ramp in an excluded class is never
# chosen, so near-miss greys cannot snap to another faction's accent.
const EXCLUDED_BY_FACTION: Dictionary = {"inheritance": ["red", "magenta"], "union": ["cyan", "magenta"], "free": ["cyan"], "utility": ["cyan"]}
var _excluded: Array = []
var _excluded_keys: Array = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3 or args.size() > 4 or not FileAccess.file_exists(args[0]) or not DirAccess.dir_exists_absolute(args[1]) or DirAccess.make_dir_recursive_absolute(args[2]) != OK:
		_fail("require catalog, raw directory, writable prepared directory and optional exact id")
		return
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not catalog is Dictionary or not catalog.get("candidates") is Array:
		_fail("invalid catalog")
		return
	if not _load_palette(ProjectSettings.globalize_path("res://../docs/palette.json")):
		return
	var repo: String = ProjectSettings.globalize_path("res://..")
	var done: int = 0
	for entry: Dictionary in catalog["candidates"]:
		if args.size() == 4 and entry["id"] != args[3]:
			continue
		if not _prepare(repo, args[1], args[2], entry):
			return
		done += 1
	if done == 0:
		_fail("unknown candidate id")
		return
	await process_frame
	print("prepare_model_candidates: PASS (%d prepared offline)" % done)
	quit(0)

func _load_palette(path: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_fail("cannot read docs/palette.json")
		return false
	var bases: Dictionary = {}
	for key: String in parsed:
		var rgba: Array = parsed[key]
		bases[key] = Color8(int(rgba[0]), int(rgba[1]), int(rgba[2]))
	for key: String in SHIPPED_EXTENSION:
		bases[key] = SHIPPED_EXTENSION[key]
	for key: String in VENUE_SWATCHES:
		bases[key] = VENUE_SWATCHES[key]
	for key: String in bases:
		if not CLASSES.has(key):
			_fail("palette key without faction class: " + key)
			return false
		for shade: float in SHADES:
			var base: Color = bases[key]
			# Quantised to 8 bits so a ramp value survives the RGBA8 paint image unchanged.
			var color: Color = Color8(roundi(clampf(base.r * shade, 0.0, 1.0) * 255.0), roundi(clampf(base.g * shade, 0.0, 1.0) * 255.0), roundi(clampf(base.b * shade, 0.0, 1.0) * 255.0))
			_ramp_colors.append(color)
			_ramp_lab.append(_oklab(color))
			_ramp_names.append(key)
			_ramp_shades.append(shade)
	return true

func _prepare(repo: String, raw_dir: String, out_dir: String, entry: Dictionary) -> bool:
	var id: String = entry["id"]
	var path: String = raw_dir.path_join(entry["file"])
	if FileAccess.get_sha256(path) != entry["sha256"]:
		_fail("raw fingerprint changed: " + id)
		return false
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(path, state) != OK:
		_fail("GLB import failed: " + id)
		return false
	var original: Node3D = document.generate_scene(state)
	root.add_child(original)
	var meshes: Array[Node] = original.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1 or (meshes[0] as MeshInstance3D).mesh.get_surface_count() != 1:
		original.free()
		_fail("one fused source mesh with one surface required: " + id)
		return false
	var source: MeshInstance3D = meshes[0] as MeshInstance3D
	var source_transform: Transform3D = source.global_transform
	var arrays: Array = source.mesh.surface_get_arrays(0)
	var raw_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var raw_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty() or uv.size() != raw_vertices.size() or raw_normals.size() != raw_vertices.size():
		original.free()
		_fail("indexed triangles with UV and normals required: " + id)
		return false
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for index: int in range(raw_vertices.size()):
		vertices.append(source_transform * raw_vertices[index])
		normals.append((source_transform.basis * raw_normals[index]).normalized())
	var bounds: AABB = _bounds(vertices)
	var topology: Dictionary = _topology(vertices, indices, bounds.get_longest_axis_size())
	var fit: Dictionary = _fit(repo, entry, bounds)
	if fit.is_empty():
		original.free()
		_fail("intended size or slot unresolved: " + id)
		return false
	var scale: float = fit["scale"]
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(float(fit["yaw_degrees"])))
	var pivot: Vector3 = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var placed: PackedVector3Array = PackedVector3Array()
	for vertex: Vector3 in vertices:
		placed.append(basis * (vertex - pivot) * scale)
	var clipped: Dictionary = {}
	if entry.get("clip") is Array:
		clipped = _clip(entry["clip"], placed, normals, uv, indices)
		if clipped.has("error"):
			original.free()
			_fail("%s: %s" % [id, clipped["error"]])
			return false
		placed = clipped["placed"]
		normals = clipped["normals"]
		uv = clipped["uv"]
		indices = clipped["indices"]
	var cleanup: Dictionary = _cleanup(entry, placed, indices)
	if not clipped.is_empty():
		(cleanup["applied"] as Dictionary)["clip"] = entry["clip"]
		(cleanup["applied"] as Dictionary)["clipped_triangles"] = clipped["split"]
	if cleanup.has("error"):
		original.free()
		_fail("%s: %s" % [id, cleanup["error"]])
		return false
	indices = cleanup["indices"]
	placed = cleanup["placed"]
	var world_area: float = 0.0
	var uv_area: float = 0.0
	for slot: int in range(0, indices.size(), 3):
		world_area += (placed[indices[slot + 1]] - placed[indices[slot]]).cross(placed[indices[slot + 2]] - placed[indices[slot]]).length() * 0.5
		var a: Vector2 = uv[indices[slot + 1]] - uv[indices[slot]]
		var b: Vector2 = uv[indices[slot + 2]] - uv[indices[slot]]
		uv_area += absf(a.x * b.y - a.y * b.x) * 0.5
	var material: StandardMaterial3D = source.get_active_material(0) as StandardMaterial3D
	if material == null or material.albedo_texture == null:
		original.free()
		_fail("embedded paint required: " + id)
		return false
	_excluded = (EXCLUDED_BY_FACTION.get(entry["faction"], []) as Array).duplicate()
	for name: String in entry.get("allow_classes", []):
		_excluded.erase(name)
	for name: String in entry.get("exclude_classes", []):
		if not name in _excluded:
			_excluded.append(name)
	_excluded_keys = (entry.get("exclude_keys", []) as Array).duplicate()
	for key: String in VENUE_SWATCHES:
		if not key in entry.get("swatches", []):
			_excluded_keys.append(key)
	_cache.clear()
	var source_paint: Image = material.albedo_texture.get_image()
	if source_paint.is_compressed() and source_paint.decompress() != OK:
		original.free()
		_fail("cannot decode paint: " + id)
		return false
	var wanted: float = TARGET_TEXELS_PER_METRE * sqrt(world_area / maxf(uv_area, 0.000001))
	var size: int = clampi(int(nearest_po2(int(ceil(wanted)))), MIN_TEXTURE, MAX_TEXTURE)
	var paint: Image = source_paint.duplicate()
	paint.convert(Image.FORMAT_RGBA8)
	# Lock at 512 so neighbouring UV islands do not average together, then point
	# sample down to the texel-density target so each texel keeps one ramp value.
	paint.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var gain: float = float(entry.get("gain", 1.0))
	if not is_equal_approx(gain, 1.0):
		for y: int in range(paint.get_height()):
			for x: int in range(paint.get_width()):
				var lit: Color = paint.get_pixel(x, y)
				paint.set_pixel(x, y, Color(minf(lit.r * gain, 1.0), minf(lit.g * gain, 1.0), minf(lit.b * gain, 1.0), lit.a))
	var locked_keys: PackedStringArray = _lock(paint)
	if entry.get("repaint") is Array:
		var repainted: Dictionary = _repaint(paint, locked_keys, entry["repaint"], placed, uv, indices)
		if repainted.has("error"):
			original.free()
			_fail("%s: %s" % [id, repainted["error"]])
			return false
		(cleanup["applied"] as Dictionary)["repaint"] = entry["repaint"]
		(cleanup["applied"] as Dictionary)["repainted_texels"] = repainted["texels"]
	paint.resize(size, size, Image.INTERPOLATE_NEAREST)
	var keys: PackedStringArray = _keys(paint)
	var presented: Image = paint.duplicate()
	presented.resize(PRESENTED_TEXTURE, PRESENTED_TEXTURE, Image.INTERPOLATE_NEAREST)
	var prepared: StandardMaterial3D = StandardMaterial3D.new()
	prepared.resource_name = "PixelPaint"
	prepared.albedo_texture = ImageTexture.create_from_image(presented)
	prepared.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	prepared.metallic = 0.08
	prepared.roughness = 0.92
	prepared.cull_mode = BaseMaterial3D.CULL_DISABLED if material.cull_mode == BaseMaterial3D.CULL_DISABLED else BaseMaterial3D.CULL_BACK
	if material.normal_texture != null:
		var normal: Image = material.normal_texture.get_image()
		if normal.is_compressed():
			normal.decompress()
		normal.convert(Image.FORMAT_RGBA8)
		normal.resize(mini(size * 2, 512), mini(size * 2, 512), Image.INTERPOLATE_LANCZOS)
		prepared.normal_enabled = true
		prepared.normal_texture = ImageTexture.create_from_image(normal)
		prepared.normal_scale = 0.2
	var colour: Dictionary = _faction_colour(paint, keys, placed, uv, indices, entry["faction"], id)
	var groups: Dictionary = _split_parts(entry.get("parts", []), placed, indices)
	if groups.has("error"):
		original.free()
		_fail("%s: %s" % [id, groups["error"]])
		return false
	var result: Node3D = Node3D.new()
	result.name = id.to_pascal_case()
	root.add_child(result)
	var part_receipts: Array = []
	for group: Dictionary in groups["groups"]:
		var pivot_at: Vector3 = group["pivot"]
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index: int in group["indices"]:
			surface.set_normal(basis * normals[index])
			surface.set_uv(uv[index])
			surface.add_vertex(placed[index] - pivot_at)
		surface.index()
		surface.generate_tangents()
		var body: MeshInstance3D = MeshInstance3D.new()
		body.name = group["name"]
		body.mesh = surface.commit()
		body.material_override = prepared
		body.position = pivot_at
		result.add_child(body)
		if group["name"] != "Body":
			part_receipts.append({"name": group["name"], "pivot_m": [pivot_at.x, pivot_at.y, pivot_at.z], "triangles": (group["indices"] as PackedInt32Array).size() / 3})
	var ship: bool = bool(entry.get("ship", false))
	var output: String = out_dir.path_join(str(entry.get("output", id)) + ".glb")
	var exporter: GLTFDocument = GLTFDocument.new()
	exporter.image_format = "PNG"
	var exported: GLTFState = GLTFState.new()
	var success: bool = exporter.append_from_scene(result, exported) == OK and exporter.write_to_filesystem(exported, output) == OK and Metadata.clean(output)
	if not ship:
		var locked: Image = paint.duplicate()
		success = success and locked.save_png(out_dir.path_join(id + "-paint.png")) == OK
	var prepared_bounds: AABB = _used_bounds(placed, indices)
	var receipt: Dictionary = {"schema": 1, "id": id, "faction": entry["faction"], "raw_file": entry["file"], "raw_sha256": entry["sha256"],
		"prepared_sha256": FileAccess.get_sha256(output) if success else "", "triangles": indices.size() / 3, "vertices": raw_vertices.size(),
		"topology": topology, "raw_bounds_units": [bounds.size.x, bounds.size.y, bounds.size.z],
		"fit": fit, "metres_per_source_unit": scale, "prepared_bounds_m": [prepared_bounds.size.x, prepared_bounds.size.y, prepared_bounds.size.z],
		"surface_area_m2": world_area, "uv_coverage": uv_area, "paint_source_px": [source_paint.get_width(), source_paint.get_height()],
		"paint_locked_px": size, "paint_presented_px": PRESENTED_TEXTURE, "texels_per_metre": float(size) * sqrt(uv_area / maxf(world_area, 0.000001)),
		"palette": "docs/palette.json x shades %s + shipped M05 rust/green/ochre" % [SHADES], "excluded_classes": _excluded, "texture_filter": "nearest", "orm_maps": false,
		"normal_map_px": mini(size * 2, 512) if material.normal_texture != null else 0, "faction_colour": colour, "runtime_selected": ship}
	if not (cleanup["applied"] as Dictionary).is_empty():
		receipt["cleanup"] = cleanup["applied"]
	if not part_receipts.is_empty():
		receipt["parts"] = part_receipts
	if entry.get("swatches") is Array:
		receipt["palette"] += " + venue swatches %s" % [entry["swatches"]]
	if entry.get("provenance") is Dictionary:
		receipt["provenance"] = entry["provenance"]
	var file: FileAccess = FileAccess.open(output + ".json", FileAccess.WRITE)
	if success and file != null:
		file.store_string(JSON.stringify(receipt, "\t") + "\n")
		file.close()
	else:
		success = false
	original.free()
	result.free()
	if not success:
		_fail("cannot export prepared candidate: " + id)
	else:
		print("prepared %s: %d tris, open edges %d (%d loops), %d px paint, %.1f texel/m, %s" % [id, indices.size() / 3, topology["boundary_edges"], topology["boundary_loops"], size, receipt["texels_per_metre"], colour["verdict"]])
	return success

## Splits the kept triangles into the named moving parts and the remaining
## Body. Each part row is {"name", "box": [[min x, y, z], [max x, y, z]],
## "pivot": [x, y, z]} in fitted metres; a triangle whose centroid falls in a
## part's box joins the first such part. A part's mesh is stored relative to
## its pivot so a presenter can rotate it there.
func _split_parts(rows: Variant, placed: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	if not rows is Array:
		return {"error": "parts must be an array"}
	var groups: Array[Dictionary] = []
	for row: Variant in rows:
		if not row is Dictionary or not row.get("box") is Array or not row.get("pivot") is Array or str(row.get("name", "")) in ["", "Body"]:
			return {"error": "parts rows need a name other than Body, a box and a pivot"}
		var box: Array = row["box"]
		groups.append({"name": str(row["name"]), "low": Vector3(box[0][0], box[0][1], box[0][2]), "high": Vector3(box[1][0], box[1][1], box[1][2]),
			"pivot": Vector3(row["pivot"][0], row["pivot"][1], row["pivot"][2]), "indices": PackedInt32Array()})
	var body: Dictionary = {"name": "Body", "pivot": Vector3.ZERO, "indices": PackedInt32Array()}
	for slot: int in range(0, indices.size(), 3):
		var centre: Vector3 = (placed[indices[slot]] + placed[indices[slot + 1]] + placed[indices[slot + 2]]) / 3.0
		var target: Dictionary = body
		for group: Dictionary in groups:
			var low: Vector3 = group["low"]
			var high: Vector3 = group["high"]
			if centre.x >= low.x and centre.y >= low.y and centre.z >= low.z and centre.x <= high.x and centre.y <= high.y and centre.z <= high.z:
				target = group
				break
		# Packed arrays are values: append to the stored copy and store it back.
		var kept: PackedInt32Array = target["indices"]
		kept.append_array([indices[slot], indices[slot + 1], indices[slot + 2]])
		target["indices"] = kept
	for group: Dictionary in groups:
		if (group["indices"] as PackedInt32Array).is_empty():
			return {"error": "part %s holds no triangles" % group["name"]}
	if (body["indices"] as PackedInt32Array).is_empty():
		return {"error": "parts took every triangle from the body"}
	var ordered: Array[Dictionary] = [body]
	ordered.append_array(groups)
	return {"groups": ordered}

## Local cleanup on the fitted mesh, in the order the header lists. Returns the
## kept indices and what was applied, or an error.
func _cleanup(entry: Dictionary, placed: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var applied: Dictionary = {}
	if bool(entry.get("stretch", false)):
		if not entry.get("intended") is Array:
			return {"error": "stretch needs intended dimensions"}
		var box: AABB = _used_bounds(placed, indices)
		var limit: float = float(entry.get("max_stretch_log", MAX_STRETCH_LOG))
		var factors: Vector3 = Vector3.ONE
		for axis: int in range(3):
			factors[axis] = float(entry["intended"][axis]) / box.size[axis]
			if absf(log(factors[axis])) > limit + 0.0001:
				return {"error": "stretch %.3f on axis %d is beyond %.2f" % [factors[axis], axis, limit]}
		for index: int in range(placed.size()):
			placed[index] = Vector3(placed[index].x * factors.x, placed[index].y * factors.y, placed[index].z * factors.z)
		applied["stretch_xyz"] = [factors.x, factors.y, factors.z]
	if entry.get("drop") is Array:
		var kept: PackedInt32Array = PackedInt32Array()
		var dropped: int = 0
		for slot: int in range(0, indices.size(), 3):
			var centre: Vector3 = (placed[indices[slot]] + placed[indices[slot + 1]] + placed[indices[slot + 2]]) / 3.0
			var inside: bool = false
			for box: Array in entry["drop"]:
				var low: Vector3 = Vector3(box[0][0], box[0][1], box[0][2])
				var high: Vector3 = Vector3(box[1][0], box[1][1], box[1][2])
				if centre.x >= low.x and centre.y >= low.y and centre.z >= low.z and centre.x <= high.x and centre.y <= high.y and centre.z <= high.z:
					inside = true
					break
			if inside:
				dropped += 1
			else:
				kept.append_array([indices[slot], indices[slot + 1], indices[slot + 2]])
		if kept.is_empty():
			return {"error": "drop removed every triangle"}
		indices = kept
		applied["drop"] = entry["drop"]
		applied["dropped_triangles"] = dropped
	if entry.get("remap") is Array:
		for row: Dictionary in entry["remap"]:
			var band: Array = row["y"]
			for index: int in range(placed.size()):
				var point: Vector3 = placed[index]
				if point.y < float(band[0]) or point.y > float(band[1]):
					continue
				for axis: String in ["x", "z"]:
					if row.get(axis) is Array:
						var span: Array = row[axis]
						var from_size: float = float(span[1]) - float(span[0])
						if absf(from_size) < 0.0001:
							return {"error": "empty remap span"}
						var t: float = (point[axis] - float(span[0])) / from_size
						point[axis] = lerpf(float(span[2]), float(span[3]), t)
				placed[index] = point
		applied["remap"] = entry["remap"]
	for key: String in ["gain", "swatches", "exclude_keys", "exclude_classes"]:
		if entry.has(key):
			applied[key] = entry[key]
	return {"indices": indices, "placed": placed, "applied": applied}

## Cuts the fitted mesh at axis-aligned planes, keeping one side. A triangle
## that crosses a plane is split there, its UV and normal interpolated, so the
## kept part ends on a clean line instead of a sawtooth of whole triangles.
func _clip(rows: Array, placed: PackedVector3Array, normals: PackedVector3Array, uv: PackedVector2Array, indices: PackedInt32Array) -> Dictionary:
	var split: int = 0
	for row: Dictionary in rows:
		var axis: int = {"x": 0, "y": 1, "z": 2}.get(str(row.get("axis", "")), -1)
		var keep_below: bool = str(row.get("keep", "")) == "below"
		if axis < 0 or str(row.get("keep", "")) not in ["below", "above"] or not (row.get("at") is float or row.get("at") is int):
			return {"error": "clip rows need axis x|y|z, keep below|above and at"}
		var plane: float = float(row["at"])
		var kept: PackedInt32Array = PackedInt32Array()
		for slot: int in range(0, indices.size(), 3):
			var corners: Array[int] = [indices[slot], indices[slot + 1], indices[slot + 2]]
			var inside: Array[bool] = []
			for corner: int in corners:
				inside.append(placed[corner][axis] <= plane if keep_below else placed[corner][axis] >= plane)
			var count: int = inside.count(true)
			if count == 3:
				kept.append_array(corners)
				continue
			if count == 0:
				continue
			split += 1
			# Walk the triangle's edges in order, emitting kept corners and the
			# crossing points, then fan the polygon back into triangles.
			var polygon: Array[int] = []
			for edge: int in range(3):
				var a: int = corners[edge]
				var b: int = corners[(edge + 1) % 3]
				if inside[edge]:
					polygon.append(a)
				if inside[edge] != inside[(edge + 1) % 3]:
					var t: float = (plane - placed[a][axis]) / (placed[b][axis] - placed[a][axis])
					placed.append(placed[a].lerp(placed[b], t))
					normals.append(normals[a].lerp(normals[b], t).normalized())
					uv.append(uv[a].lerp(uv[b], t))
					polygon.append(placed.size() - 1)
			for fan: int in range(1, polygon.size() - 1):
				kept.append_array([polygon[0], polygon[fan], polygon[fan + 1]])
		if kept.is_empty():
			return {"error": "clip removed every triangle"}
		indices = kept
	return {"placed": placed, "normals": normals, "uv": uv, "indices": indices, "split": split}

## Moves locked texels from some ramps onto another, on the triangles a row's
## box selects. Works in the locked paint's own pixels, so each texel keeps
## exactly one ramp value. Returns the texel count changed, or an error.
func _repaint(paint: Image, keys: PackedStringArray, rows: Array, placed: PackedVector3Array, uv: PackedVector2Array, indices: PackedInt32Array) -> Dictionary:
	var width: int = paint.get_width()
	var height: int = paint.get_height()
	var changed: int = 0
	for row: Dictionary in rows:
		var target: String = str(row.get("to", ""))
		if not CLASSES.has(target) or CLASSES[target] in _excluded or target in _excluded_keys:
			return {"error": "repaint target %s is not a ramp this faction may use" % target}
		var from: Array = row.get("keys", [])
		if from.is_empty():
			return {"error": "repaint row names no source ramps"}
		var shade_override: float = float(row.get("shade", -1.0))
		var low: Vector3 = Vector3(-INF, -INF, -INF)
		var high: Vector3 = Vector3(INF, INF, INF)
		if row.get("box") is Array:
			low = Vector3(row["box"][0][0], row["box"][0][1], row["box"][0][2])
			high = Vector3(row["box"][1][0], row["box"][1][1], row["box"][1][2])
		var done: Dictionary = {}
		for slot: int in range(0, indices.size(), 3):
			var centre: Vector3 = (placed[indices[slot]] + placed[indices[slot + 1]] + placed[indices[slot + 2]]) / 3.0
			if centre.x < low.x or centre.y < low.y or centre.z < low.z or centre.x > high.x or centre.y > high.y or centre.z > high.z:
				continue
			var a: Vector2 = uv[indices[slot]] * Vector2(width, height)
			var b: Vector2 = uv[indices[slot + 1]] * Vector2(width, height)
			var c: Vector2 = uv[indices[slot + 2]] * Vector2(width, height)
			var area: float = (b - a).cross(c - a)
			var x0: int = floori(minf(a.x, minf(b.x, c.x)))
			var x1: int = ceili(maxf(a.x, maxf(b.x, c.x)))
			var y0: int = floori(minf(a.y, minf(b.y, c.y)))
			var y1: int = ceili(maxf(a.y, maxf(b.y, c.y)))
			for y: int in range(y0, y1 + 1):
				for x: int in range(x0, x1 + 1):
					var p: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
					if absf(area) > 0.000001:
						var w0: float = (b - p).cross(c - p) / area
						var w1: float = (c - p).cross(a - p) / area
						var w2: float = 1.0 - w0 - w1
						# Half a texel of slack per edge so thin bands keep their edge texels.
						if w0 < -0.5 * (c - b).length() / absf(area) or w1 < -0.5 * (a - c).length() / absf(area) \
								or w2 < -0.5 * (b - a).length() / absf(area):
							continue
					var px: int = posmod(x, width)
					var py: int = posmod(y, height)
					var at: int = py * width + px
					if done.has(at):
						continue
					var key: String = keys[at]
					if not key in from and not key.get_slice("@", 0) in from:
						continue
					done[at] = true
					var shade: float = shade_override if shade_override > 0.0 else float(key.get_slice("@", 1))
					var ramp: int = _ramp_index(target, shade)
					if ramp < 0:
						return {"error": "no %s ramp at shade %.1f" % [target, shade]}
					var color: Color = _ramp_colors[ramp]
					color.a = 1.0
					paint.set_pixel(px, py, color)
					keys[at] = "%s@%.1f" % [target, _ramp_shades[ramp]]
					changed += 1
	return {"texels": changed}

func _ramp_index(name: String, shade: float) -> int:
	for slot: int in range(_ramp_names.size()):
		if _ramp_names[slot] == name and is_equal_approx(_ramp_shades[slot], shade):
			return slot
	return -1

func _used_bounds(points: PackedVector3Array, indices: PackedInt32Array) -> AABB:
	var result: AABB = AABB(points[indices[0]], Vector3.ZERO)
	for index: int in indices:
		result = result.expand(points[index])
	return result

func _fit(repo: String, entry: Dictionary, bounds: AABB) -> Dictionary:
	var target: Vector3 = Vector3.ZERO
	var slot_box: AABB = AABB()
	var has_slot: bool = entry.get("slot") is Array
	var map: Variant = JSON.parse_string(FileAccess.get_file_as_string(repo.path_join("server/maps/%s.json" % entry["map"]))) if has_slot else null
	if has_slot and not map is Dictionary:
		return {}
	if has_slot:
		var first: bool = true
		for solid: Dictionary in map["solids"]:
			if solid["id"] in entry["slot"]:
				var box: AABB = AABB(Vector3(solid["min"][0], solid["min"][1], solid["min"][2]), Vector3(solid["max"][0] - solid["min"][0], solid["max"][1] - solid["min"][1], solid["max"][2] - solid["min"][2]))
				slot_box = box if first else slot_box.merge(box)
				first = false
		if first:
			return {}
		target = slot_box.size
	elif entry.get("intended") is Array:
		target = Vector3(entry["intended"][0], entry["intended"][1], entry["intended"][2])
	var best: Dictionary = {}
	for yaw: float in [0.0, 90.0]:
		var size: Vector3 = bounds.size if yaw == 0.0 else Vector3(bounds.size.z, bounds.size.y, bounds.size.x)
		var scale: float
		if entry.get("metres") != null:
			var axis: int = _axis(entry["axis"], size)
			scale = float(entry["metres"]) / size[axis]
		else:
			scale = minf(target.x / size.x, minf(target.y / size.y, target.z / size.z))
		var fitted: Vector3 = size * scale
		var ratios: Array = []
		var worst: float = 0.0
		if target != Vector3.ZERO:
			for axis: int in range(3):
				ratios.append(fitted[axis] / target[axis])
				worst = maxf(worst, absf(log(fitted[axis] / target[axis])))
		var row: Dictionary = {"yaw_degrees": yaw, "scale": scale, "fitted_m": [fitted.x, fitted.y, fitted.z], "slot_or_intended_m": [target.x, target.y, target.z] if target != Vector3.ZERO else [],
			"fill_ratio_xyz": ratios, "worst_log_mismatch": worst, "basis": ("slot " + ",".join(PackedStringArray(entry["slot"]))) if has_slot else ("intended %s m" % (str(entry["intended"]) if entry.get("intended") is Array else "%s on %s" % [entry["metres"], entry["axis"]]))}
		if has_slot:
			row["slot_min"] = [slot_box.position.x, slot_box.position.y, slot_box.position.z]
		if best.is_empty() or (target != Vector3.ZERO and worst < float(best["worst_log_mismatch"]) - 0.0001):
			best = row
		if entry.get("metres") != null and target == Vector3.ZERO:
			break
	return best

func _axis(name: String, size: Vector3) -> int:
	match name:
		"x": return 0
		"y": return 1
		"z": return 2
	return size.max_axis_index()

func _lock(image: Image) -> PackedStringArray:
	# Broad painted values: average 3x3 before snapping to the palette ramps, then
	# one 3x3 majority pass so isolated snapped speckles join their cluster.
	var width: int = image.get_width()
	var height: int = image.get_height()
	var source: Image = image.duplicate()
	var choices: PackedInt32Array = PackedInt32Array()
	choices.resize(width * height)
	for y: int in range(height):
		for x: int in range(width):
			var pixel: Color = Color(0, 0, 0, 0)
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					pixel += source.get_pixel(clampi(x + dx, 0, width - 1), clampi(y + dy, 0, height - 1)) / 9.0
			var code: int = (int(pixel.r * 63.0) << 12) | (int(pixel.g * 63.0) << 6) | int(pixel.b * 63.0)
			var choice: int = _cache.get(code, -1)
			if choice < 0:
				var lab: Vector3 = _oklab(pixel)
				var nearest: float = INF
				for slot: int in range(_ramp_lab.size()):
					if CLASSES[_ramp_names[slot]] in _excluded or _ramp_names[slot] in _excluded_keys:
						continue
					var distance: float = lab.distance_squared_to(_ramp_lab[slot])
					if distance < nearest:
						nearest = distance
						choice = slot
				_cache[code] = choice
			choices[y * width + x] = choice
	var keys: PackedStringArray = PackedStringArray()
	keys.resize(width * height)
	for y: int in range(height):
		for x: int in range(width):
			var own: int = choices[y * width + x]
			var counts: Dictionary = {}
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var value: int = choices[clampi(y + dy, 0, height - 1) * width + clampi(x + dx, 0, width - 1)]
					counts[value] = int(counts.get(value, 0)) + 1
			var choice: int = own
			# Accents (Union red, Inheritance cyan, Splice's tape) are thin bands and
			# lamps: a run of three keeps its value instead of joining the body colour.
			if not (CLASSES[_ramp_names[own]] in ["red", "cyan", "magenta"] and counts[own] >= 3):
				for value: int in counts:
					if counts[value] > counts[choice]:
						choice = value
			var locked: Color = _ramp_colors[choice]
			locked.a = 1.0
			image.set_pixel(x, y, locked)
			keys[y * width + x] = "%s@%.1f" % [_ramp_names[choice], _ramp_shades[choice]]
	return keys

func _keys(image: Image) -> PackedStringArray:
	var keys: PackedStringArray = PackedStringArray()
	var lookup: Dictionary = {}
	for slot: int in range(_ramp_colors.size()):
		lookup[_rgb(_ramp_colors[slot])] = "%s@%.1f" % [_ramp_names[slot], _ramp_shades[slot]]
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			keys.append(lookup[_rgb(image.get_pixel(x, y))])
	return keys

func _rgb(color: Color) -> Vector3i:
	return Vector3i(roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0))

func _faction_colour(image: Image, keys: PackedStringArray, vertices: PackedVector3Array, uv: PackedVector2Array, indices: PackedInt32Array, faction: String, id: String) -> Dictionary:
	var totals: Dictionary = {"dark": 0.0, "steel": 0.0, "red": 0.0, "bone": 0.0, "cyan": 0.0, "green": 0.0, "warm": 0.0, "magenta": 0.0}
	var pale: float = 0.0
	var area_sum: float = 0.0
	var width: int = image.get_width()
	for slot: int in range(0, indices.size(), 3):
		var area: float = (vertices[indices[slot + 1]] - vertices[indices[slot]]).cross(vertices[indices[slot + 2]] - vertices[indices[slot]]).length() * 0.5
		if area <= 0.0:
			continue
		for weights: Vector3 in [Vector3(0.333, 0.333, 0.334), Vector3(0.6, 0.2, 0.2), Vector3(0.2, 0.6, 0.2), Vector3(0.2, 0.2, 0.6)]:
			var point: Vector2 = uv[indices[slot]] * weights.x + uv[indices[slot + 1]] * weights.y + uv[indices[slot + 2]] * weights.z
			var px: int = clampi(int(fposmod(point.x, 1.0) * width), 0, width - 1)
			var py: int = clampi(int(fposmod(point.y, 1.0) * image.get_height()), 0, image.get_height() - 1)
			var key: String = keys[py * width + px]
			var name: String = key.get_slice("@", 0)
			var shade: float = float(key.get_slice("@", 1))
			totals[CLASSES[name]] += area * 0.25
			if name == "bone" and shade >= 1.0:
				pale += area * 0.25
			area_sum += area * 0.25
	var shares: Dictionary = {}
	for name: String in totals:
		shares[name] = snappedf(totals[name] / area_sum, 0.001)
	shares["pale"] = snappedf(pale / area_sum, 0.001)
	var problems: PackedStringArray = PackedStringArray()
	var dark: float = shares["dark"] + shares["steel"]
	match faction:
		"inheritance":
			if shares["bone"] < 0.30 or shares["bone"] < maxf(shares["warm"], maxf(shares["green"], shares["steel"])): problems.append("matte off-white is not the dominant painted base")
			if shares["red"] > 0.01: problems.append("red on an Inheritance machine")
			if shares["cyan"] > 0.12: problems.append("cyan above a minimal indicator share")
		"union":
			var institutional: float = dark + (shares["green"] if id in ["luggage-scanner", "registration-console", "turnstile"] else 0.0)
			if institutional < 0.5: problems.append("black/dark-steel issue body below 50%")
			if shares["red"] < 0.003: problems.append("no restrained Union red")
			if shares["red"] > 0.25: problems.append("red beyond a restrained accent")
			if shares["pale"] > 0.12: problems.append("pale enamel dominates Union issue")
			if shares["cyan"] > 0.02: problems.append("cyan is the Inheritance working accent")
		"free":
			if shares["cyan"] > 0.02: problems.append("cyan is the Inheritance working accent")
			if shares["pale"] > 0.25: problems.append("matte off-white dominant base is reserved for the Inheritance")
			if shares["dark"] >= 0.35 and shares["red"] >= 0.03: problems.append("Union black+red livery is reserved")
			if shares["red"] > 0.05: problems.append("Union red on free equipment")
		_:
			if shares["cyan"] > 0.02: problems.append("cyan is the Inheritance working accent")
			if shares["pale"] > 0.25: problems.append("pale base camouflages Inheritance machines")
			if shares["red"] > 0.05: problems.append("red faction read on crew utility")
	return {"area_shares": shares, "problems": problems, "verdict": "faction colour ok" if problems.is_empty() else "faction colour: " + "; ".join(problems)}

func _topology(vertices: PackedVector3Array, indices: PackedInt32Array, extent: float) -> Dictionary:
	var quantum: float = maxf(extent, 0.000001) * 0.00001
	var weld: Dictionary = {}
	var ids: PackedInt32Array = PackedInt32Array()
	for vertex: Vector3 in vertices:
		var key: Vector3i = Vector3i(roundi(vertex.x / quantum), roundi(vertex.y / quantum), roundi(vertex.z / quantum))
		if not weld.has(key):
			weld[key] = weld.size()
		ids.append(weld[key])
	var edges: Dictionary = {}
	var degenerate: int = 0
	for slot: int in range(0, indices.size(), 3):
		var a: int = ids[indices[slot]]
		var b: int = ids[indices[slot + 1]]
		var c: int = ids[indices[slot + 2]]
		if a == b or b == c or a == c:
			degenerate += 1
			continue
		for pair: Vector2i in [Vector2i(a, b), Vector2i(b, c), Vector2i(c, a)]:
			var key: Vector2i = Vector2i(mini(pair.x, pair.y), maxi(pair.x, pair.y))
			edges[key] = int(edges.get(key, 0)) + 1
	var boundary: Array[Vector2i] = []
	var nonmanifold: int = 0
	for key: Vector2i in edges:
		if edges[key] == 1:
			boundary.append(key)
		elif edges[key] > 2:
			nonmanifold += 1
	var parent: Dictionary = {}
	for edge: Vector2i in boundary:
		var x: int = _find(parent, edge.x)
		var y: int = _find(parent, edge.y)
		if x != y:
			parent[x] = y
	var loops: Dictionary = {}
	var largest: Dictionary = {}
	for edge: Vector2i in boundary:
		var group: int = _find(parent, edge.x)
		loops[group] = int(loops.get(group, 0)) + 1
	for group: int in loops:
		largest[group] = loops[group]
	var sizes: Array = loops.values()
	sizes.sort()
	sizes.reverse()
	return {"welded_vertices": weld.size(), "boundary_edges": boundary.size(), "boundary_loops": loops.size(), "largest_loops_edges": sizes.slice(0, 5),
		"nonmanifold_edges": nonmanifold, "degenerate_triangles": degenerate, "watertight": boundary.is_empty() and nonmanifold == 0}

func _find(parent: Dictionary, value: int) -> int:
	var node: int = value
	while parent.has(node) and parent[node] != node:
		node = parent[node]
	return node

func _bounds(vertices: PackedVector3Array) -> AABB:
	var result: AABB = AABB(vertices[0], Vector3.ZERO)
	for vertex: Vector3 in vertices:
		result = result.expand(vertex)
	return result

func _oklab(color: Color) -> Vector3:
	var r: float = color.srgb_to_linear().r
	var g: float = color.srgb_to_linear().g
	var b: float = color.srgb_to_linear().b
	var l: float = pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3.0)
	var m: float = pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3.0)
	var s: float = pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3.0)
	return Vector3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)

func _fail(message: String) -> void:
	push_error("prepare_model_candidates: " + message)
	quit(1)
