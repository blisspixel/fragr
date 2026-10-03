extends SceneTree

## Offline level 7 placeholders from existing project files and deterministic
## pixel and sample placement. No service call and no generated asset request.
## The art and sound tracks replace these through `client/scripts/l07_assets.gd`.
const SOURCE: String = "res://../tools/bake_sniper_placeholders.gd"
const RAIL_VIEW: String = "res://assets/weapons/viewmodels/px_rail_issued_0.png"
const RAIL_ICON: String = "res://assets/weapons/32/rail.png"
const RAIL_FIRE: String = "res://assets/audio/fire_rail.wav"
const SNIPER_VIEW: String = "res://assets/weapons/viewmodels/px_sniper_placeholder_0.png"
const SNIPER_ICON: String = "res://assets/weapons/32/sniper_placeholder.png"
const SCOPE: String = "res://assets/weapons/scope/sniper_scope_placeholder.png"
const SNIPER_FIRE: String = "res://assets/audio/sniper/fire_placeholder.wav"
const GLINT: String = "res://assets/audio/ranged_sweeper/glint_placeholder.wav"
const WEAPON_MANIFEST: String = "res://assets/weapons/scope/placeholder-manifest.json"
const AUDIO_MANIFEST: String = "res://assets/audio/sniper/placeholder-manifest.json"
const GLINT_MANIFEST: String = "res://assets/audio/ranged_sweeper/placeholder-manifest.json"
## Blackened issued steel: the long gun reads darker and cooler than the Rail.
const STEEL: Color = Color8(46, 47, 52)
const STEEL_LIGHT: Color = Color8(92, 94, 101)
const INK: Color = Color8(16, 18, 18)
const LENS: Color = Color8(150, 162, 168)
const EMBER: Color = Color8(220, 140, 60)
const SCOPE_SIZE: int = 512
const SURROUND: Color = Color("0b0c0c")
## The Railgun report played back at three quarters speed: lower and longer.
const FIRE_RATE_SCALE: float = 0.75
const GLINT_RATE: int = 24000
const GLINT_SECONDS: float = 0.42


func _initialize() -> void:
	var failures: Array[String] = []
	var images: Array[Dictionary] = []
	for job: Array in [[RAIL_VIEW, SNIPER_VIEW, true], [RAIL_ICON, SNIPER_ICON, false]]:
		var image: Image = _recolor(str(job[0]), bool(job[2]))
		if image == null or not _save_png(image, str(job[1])):
			failures.append(str(job[1]))
		else:
			images.append(_entry(str(job[1]), "recolored from " + str(job[0]) + " with an added scope tube"))
	var scope: Image = _scope()
	if not _save_png(scope, SCOPE):
		failures.append(SCOPE)
	else:
		images.append(_entry(SCOPE, "deterministic aperture, reticle and surround"))
	var fire: Dictionary = _slowed_copy(RAIL_FIRE, SNIPER_FIRE)
	if fire.is_empty():
		failures.append(SNIPER_FIRE)
	var glint: Dictionary = _glint()
	if glint.is_empty():
		failures.append(GLINT)
	if not failures.is_empty():
		push_error("sniper_placeholders: failed " + ", ".join(failures))
		quit(1)
		return
	var ok: bool = _manifest(WEAPON_MANIFEST, {"files": images})
	ok = _manifest(AUDIO_MANIFEST, {"files": [fire]}) and ok
	ok = _manifest(GLINT_MANIFEST, {"files": [glint]}) and ok
	if not ok:
		quit(1)
		return
	print("sniper_placeholders: PASS ", images.size(), " images and 2 sounds")
	quit(0)


func _entry(path: String, method: String) -> Dictionary:
	return {"file": path, "sha256": FileAccess.get_sha256(path), "method": method}


func _manifest(path: String, body: Dictionary) -> bool:
	body["format"] = 1
	body["kind"] = "original_offline_placeholder"
	body["spend_usd"] = 0
	body["engine"] = "Godot 4.7.2-stable"
	body["source"] = SOURCE
	body["source_sha256"] = FileAccess.get_sha256(SOURCE)
	body["replaced_by"] = "client/scripts/l07_assets.gd when delivered art or sound arrives"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("sniper_placeholders: cannot write " + path)
		return false
	file.store_string(JSON.stringify(body, "  ", true) + "\n")
	file.close()
	return true


func _save_png(image: Image, path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	return image.save_png(absolute) == OK


## Darken toward issued steel, quench the Rail's red coils, then add a scope
## tube above the receiver. Alpha and hand registration stay untouched.
func _recolor(path: String, viewmodel: bool) -> Image:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty() or image.detect_alpha() == Image.ALPHA_NONE:
		push_error("sniper_placeholders: unusable source " + path)
		return null
	image.convert(Image.FORMAT_RGBA8)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a == 0.0:
				continue
			var value: float = pixel.get_luminance()
			var warm: bool = pixel.r > pixel.g * 1.35 and pixel.r > 0.3
			# Skin and gloves keep their hue; the coils and paint turn to steel.
			var shade: Color = STEEL.lerp(STEEL_LIGHT, clampf(value * 1.6, 0.0, 1.0))
			if warm and not _is_hand(x, y, image, viewmodel):
				image.set_pixel(x, y, Color(shade, pixel.a))
			elif not _is_hand(x, y, image, viewmodel):
				image.set_pixel(x, y, Color(pixel.lerp(shade, 0.55), pixel.a))
	if viewmodel:
		_scope_tube(image, 120, 54, 15, 50)
	else:
		_scope_tube(image, 16, 9, 4, 10)
	return image


## The lower third of the viewmodel is the hands. The icon has none.
func _is_hand(_x: int, y: int, image: Image, viewmodel: bool) -> bool:
	return viewmodel and y > int(image.get_height() * 0.68)


## A tube seen from behind, narrowing toward the far objective: rings, a dark
## body with one lit edge, and a pale eyepiece nearest the shooter.
func _scope_tube(image: Image, centre_x: int, top: int, half_width: int, length: int) -> void:
	var bottom: int = mini(top + length, image.get_height())
	for y: int in range(top, bottom):
		var near: float = float(y - top) / maxf(1.0, float(length - 1))
		var half: int = roundi(lerpf(half_width * 0.6, half_width, near))
		for x: int in range(centre_x - half, centre_x + half + 1):
			if x < 0 or x >= image.get_width():
				continue
			var edge: bool = absi(x - centre_x) >= half - 1
			var ring: bool = (y - top) % 12 == 0
			var lit: bool = x - (centre_x - half) == 2
			image.set_pixel(x, y, INK if edge or ring else (STEEL_LIGHT if lit else STEEL))
	var lens_y: int = bottom - 4
	for dy: int in range(0, 3):
		var reach: int = half_width - 3 - dy
		for dx: int in range(-reach, reach + 1):
			image.set_pixel(centre_x + dx, lens_y + dy, LENS.darkened(0.12 * dy))


## Opaque surround, a clear round aperture, a thin cross with a gap at the
## centre, range marks and an ember point. Nearest sampled at screen height.
func _scope() -> Image:
	var image: Image = Image.create(SCOPE_SIZE, SCOPE_SIZE, false, Image.FORMAT_RGBA8)
	var centre: float = (SCOPE_SIZE - 1) * 0.5
	var radius: float = SCOPE_SIZE * 0.47
	for y: int in range(SCOPE_SIZE):
		for x: int in range(SCOPE_SIZE):
			var distance: float = Vector2(x - centre, y - centre).length()
			if distance > radius:
				image.set_pixel(x, y, SURROUND)
			elif distance > radius - 7.0:
				image.set_pixel(x, y, INK)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	var mid: int = SCOPE_SIZE / 2
	for offset: int in range(int(radius) - 8):
		if offset < 14:
			continue
		# Fine wires near the centre, heavy posts toward the edge.
		var half: int = 1 if offset < int(radius * 0.55) else 3
		for along: int in [mid + offset, mid - offset - 1]:
			for thick: int in range(mid - half, mid + half):
				image.set_pixel(along, thick, INK)
				image.set_pixel(thick, along, INK)
	for mark: int in [40, 80, 120, 160]:
		for side: int in [-1, 1]:
			var at: int = mid + side * mark
			for w: int in range(-4, 4):
				image.set_pixel(at, mid + w, INK)
				image.set_pixel(mid + w, at, INK)
	for dx: int in range(-2, 2):
		for dy: int in range(-2, 2):
			image.set_pixel(mid + dx, mid + dy, EMBER)
	return image


## Copy a PCM WAV and lower its declared rate: the same samples play slower and
## lower. Every other chunk byte is retained.
func _slowed_copy(from_path: String, to_path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(from_path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" \
			or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		push_error("sniper_placeholders: unreadable source " + from_path)
		return {}
	var offset: int = 12
	while offset + 8 <= bytes.size():
		var id: String = bytes.slice(offset, offset + 4).get_string_from_ascii()
		var size: int = bytes.decode_u32(offset + 4)
		if id == "fmt ":
			var rate: int = bytes.decode_u32(offset + 12)
			var block: int = bytes.decode_u16(offset + 20)
			var slowed: int = roundi(rate * FIRE_RATE_SCALE)
			bytes.encode_u32(offset + 12, slowed)
			bytes.encode_u32(offset + 16, slowed * block)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to_path).get_base_dir())
			var file: FileAccess = FileAccess.open(to_path, FileAccess.WRITE)
			if file == null:
				return {}
			file.store_buffer(bytes)
			file.close()
			return {"file": to_path, "sha256": FileAccess.get_sha256(to_path),
				"method": "PCM samples of %s declared at %d Hz instead of %d Hz" % [from_path, slowed, rate],
				"source_sha256": FileAccess.get_sha256(from_path)}
		offset += 8 + size + (size % 2)
	push_error("sniper_placeholders: no format chunk in " + from_path)
	return {}


## A short bright ting with a quick rise: readable across a crater, original.
func _glint() -> Dictionary:
	var samples: int = roundi(GLINT_SECONDS * GLINT_RATE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GLINT).get_base_dir())
	var file: FileAccess = FileAccess.open(GLINT, FileAccess.WRITE)
	if file == null:
		return {}
	file.big_endian = false
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + samples * 2)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(GLINT_RATE)
	file.store_32(GLINT_RATE * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(samples * 2)
	var peak: float = 0.0
	for index: int in range(samples):
		var t: float = float(index) / GLINT_RATE
		var attack: float = minf(t / 0.004, 1.0)
		var decay: float = exp(-t * 9.0)
		var sweep: float = TAU * (2350.0 * t + 900.0 * t * t)
		var tone: float = 0.42 * sin(sweep) + 0.18 * sin(sweep * 1.5) + 0.08 * sin(sweep * 2.76)
		var sample: float = clampf(attack * decay * tone, -0.9, 0.9)
		var pcm: int = roundi(sample * 32767.0)
		peak = maxf(peak, absf(float(pcm) / 32767.0))
		file.store_16(pcm & 0xffff)
	file.close()
	return {"file": GLINT, "sha256": FileAccess.get_sha256(GLINT),
		"method": "deterministic procedural ting", "format": "pcm_s16le_mono_24000",
		"seconds": GLINT_SECONDS, "peak_linear": snappedf(peak, 0.0001)}
