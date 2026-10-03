extends SceneTree

## Local review exports only. Runtime acceptance is a separate explicit choice.
const INVENTORY: String = "res://../tools/spritegen/specs/production-20261003/inventory.json"
const OUTPUT: String = "res://art/production-20261003"
const REVIEW: String = "res://../.agents/art-excellence-research/contact-sheets"

func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY))
	if not parsed is Dictionary or not parsed.get("assets") is Array or parsed["assets"].size() != 147:
		_fail("invalid fixed production inventory")
		return
	for directory: String in [OUTPUT, REVIEW]:
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
			_fail("cannot create review directory")
			return
	var receipts: Array[Dictionary] = []
	var previous: Dictionary[String, Dictionary] = {}
	var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("manifest.json"))) if FileAccess.file_exists(OUTPUT.path_join("manifest.json")) else null
	if old is Dictionary and old.get("assets") is Array:
		for entry: Variant in old["assets"]:
			if entry is Dictionary and entry.get("id") is String:
				previous[entry["id"]] = entry
	var sheets: Dictionary[String, Image] = {}
	var positions: Dictionary[String, int] = {}
	for item: Variant in parsed["assets"]:
		if not item is Dictionary or not item.get("id") is String or not item.get("batch") is String:
			_fail("invalid inventory item")
			return
		var id: String = item["id"]
		var batch: String = item["batch"]
		if not id.is_valid_identifier() or not batch.begins_with("batch-") or batch.length() != 8:
			_fail("invalid asset name")
			return
		var input: String = "res://../art/raw/production-20261003/" + batch + "/" + id + "_0.png"
		if not FileAccess.file_exists(input):
			continue
		var job: Dictionary = _job(batch, id)
		if job.get("stage") != "downloaded":
			continue
		var output: String = OUTPUT.path_join(id + ".png")
		var source_hash: String = FileAccess.get_sha256(input)
		var cached: Dictionary = previous.get(id, {})
		var reuse: bool = cached.get("source_sha256") == source_hash and cached.get("request_id") == job.get("request_id") \
			and FileAccess.file_exists(output) and cached.get("sha256") == FileAccess.get_sha256(output) \
			and cached.get("original_pixels") is Array and cached["original_pixels"].size() == 2
		var source: Image = Image.load_from_file(ProjectSettings.globalize_path(output if reuse else input))
		if source == null or source.get_width() < 512 or source.get_height() < 512:
			_fail("invalid source image " + id)
			return
		var original_size: Vector2i = Vector2i(int(cached["original_pixels"][0]), int(cached["original_pixels"][1])) if reuse else source.get_size()
		source.convert(Image.FORMAT_RGBA8)
		source.resize(768, 768, Image.INTERPOLATE_LANCZOS)
		if not reuse and source.save_png(output) != OK:
			_fail("cannot save review asset " + id)
			return
		receipts.append({"id": id, "purpose": item["purpose"], "status": "source candidate, visual acceptance and runtime placement tracked separately",
			"file": id + ".png", "sha256": FileAccess.get_sha256(output), "source_sha256": source_hash,
			"original_pixels": [original_size.x, original_size.y], "spec": item["spec"], "request_id": job["request_id"], "estimated_usd": job["estimated_usd"]})
		if not sheets.has(batch):
			sheets[batch] = Image.create(1024, 512, false, Image.FORMAT_RGBA8)
			sheets[batch].fill(Color("323a36"))
			positions[batch] = 0
		var index: int = positions[batch]
		var thumbnail: Image = source.duplicate()
		thumbnail.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		sheets[batch].blit_rect(thumbnail, Rect2i(0, 0, 256, 256), Vector2i(index % 4, index / 4) * 256)
		positions[batch] += 1
	for batch: String in sheets:
		sheets[batch].save_png(REVIEW.path_join(batch + ".png"))
	var receipt: FileAccess = FileAccess.open(OUTPUT.path_join("manifest.json"), FileAccess.WRITE)
	if receipt == null:
		_fail("cannot write candidate receipt")
		return
	receipt.store_string(JSON.stringify({"schema": 1, "date": "2026-10-03", "inventory": "tools/spritegen/specs/production-20261003/inventory.json",
		"model": "marketing-studio/image", "billing": "exact request estimates, dashboard charges not yet reconciled",
		"review_pixels": [768, 768], "assets": receipts}, "\t") + "\n")
	receipt.close()
	_prepared_materials(receipts)
	print("production_review: PASS ", receipts.size(), " source candidates with durable receipts, ", sheets.size(), " contact sheets")
	quit()

func _job(batch: String, id: String) -> Dictionary:
	# Read a bounded snapshot after the producer exits. Its live ledger is
	# exclusively locked and must never be read by a concurrent review process.
	var path: String = "res://../.agents/art-excellence-research/review-receipts/" + batch + ".jsonl"
	if not FileAccess.file_exists(path):
		return {}
	var contents: String = FileAccess.get_file_as_string(path)
	if contents.length() > 1048576:
		return {}
	var job: Dictionary = {}
	for line: String in contents.split("\n", false):
		var row: Variant = JSON.parse_string(line)
		if not row is Dictionary or row.get("id") != id or not row.get("event") is Dictionary:
			continue
		var event: Dictionary = row["event"]
		job["stage"] = event.get("type", "")
		if event.get("type") == "reserved":
			job["estimated_usd"] = event["estimated_usd"]
		elif event.get("type") == "accepted":
			job["request_id"] = event["request_id"]
	return job

func _prepared_materials(receipts: Array[Dictionary]) -> void:
	var bindings: Dictionary[String, Array] = {}
	for venue: String in ["earth_union", "earth_yard", "earth_scrap", "low_water", "moon_port"]:
		for surface: String in MapGeometry.SURFACES:
			for horizontal: bool in [false, true]:
				var path: String = EnvironmentTextures.path_for(surface, venue, horizontal)
				if path.begins_with(EnvironmentTextures.PRODUCTION):
					if not bindings.has(path):
						bindings[path] = []
					bindings[path].append(venue + "/" + surface + ("/floor" if horizontal else "/wall"))
	bindings[EnvironmentTextures.PRODUCTION + "water_ripples.png"] = ["bounded shallow water normal detail", "exterior Low Water river detail"]
	var entries: Array[Dictionary] = []
	for entry: Dictionary in receipts:
		var path: String = EnvironmentTextures.PRODUCTION + entry["id"] + ".png"
		if not FileAccess.file_exists(path):
			continue
		entries.append({"file": entry["id"] + ".png", "sha256": FileAccess.get_sha256(path),
			"source_id": entry["id"], "source_sha256": entry["source_sha256"], "request_id": entry["request_id"],
			"bindings": bindings.get(path, []), "status": "selected runtime material" if bindings.has(path) else "prepared candidate, no runtime binding"})
	var file: FileAccess = FileAccess.open(EnvironmentTextures.PRODUCTION + "manifest.json", FileAccess.WRITE)
	if file == null:
		push_error("production_review: cannot record prepared material receipt")
		return
	file.store_string(JSON.stringify({"schema": 1, "pixels": [128, 128],
		"preparation": "area reduction, opposite-edge repair, canonical palette reduction",
		"seam_source_sha256": FileAccess.get_sha256("res://../tools/prepare_earth_tiles.gd"), "assets": entries}, "\t") + "\n")
	file.close()

func _fail(message: String) -> void:
	push_error("production_review: " + message)
	quit(1)
