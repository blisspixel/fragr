extends RefCounted
class_name HardwareProfile

## What this computer is, as far as Godot can say, for auto settings
## (AutoTune). The fingerprint decides when a saved tune is stale; the seed
## table gives the tuner its first guess, never its answer; the Steam Deck
## check picks the handheld profile. Local only: nothing here leaves the
## machine.

## Hardware fields: a change offers a re-tune on the boot menu.
const HARDWARE_FIELDS: Array[String] = ["adapter", "vendor", "driver_info", "api", "renderer", "driver", "os", "display_server", "cpu", "cpu_count", "memory_gb"]
## Display fields: a change says "Tuned for another display".
const DISPLAY_FIELDS: Array[String] = ["screen_size", "refresh"]

## Starting guesses by adapter name, lowercase substrings, first match wins.
## A guess only seeds the measured search. Unknown hardware starts at Medium.
const SEEDS: Array[Dictionary] = [
	{"match": "llvmpipe", "tier": RenderQuality.POTATO, "note": "software renderer"},
	{"match": "lavapipe", "tier": RenderQuality.POTATO, "note": "software renderer"},
	{"match": "swiftshader", "tier": RenderQuality.POTATO, "note": "software renderer"},
	{"match": "custom gpu 0405", "tier": RenderQuality.LOW, "note": "Steam Deck"},
	{"match": "custom gpu 0932", "tier": RenderQuality.LOW, "note": "Steam Deck OLED"},
	{"match": "hd graphics", "tier": RenderQuality.POTATO, "note": "older Intel integrated"},
	{"match": "uhd graphics", "tier": RenderQuality.POTATO, "note": "Intel UHD integrated"},
	{"match": "iris", "tier": RenderQuality.LOW, "note": "Intel Iris integrated"},
	{"match": "arc(tm) graphics", "tier": RenderQuality.MEDIUM, "note": "Intel Arc integrated"},
	{"match": "arc", "tier": RenderQuality.HIGH, "note": "Intel Arc"},
	{"match": "890m", "tier": RenderQuality.MEDIUM, "note": "Radeon integrated"},
	{"match": "880m", "tier": RenderQuality.MEDIUM, "note": "Radeon integrated"},
	{"match": "780m", "tier": RenderQuality.MEDIUM, "note": "Radeon integrated"},
	{"match": "760m", "tier": RenderQuality.MEDIUM, "note": "Radeon integrated"},
	{"match": "680m", "tier": RenderQuality.LOW, "note": "Radeon integrated"},
	{"match": "vega", "tier": RenderQuality.LOW, "note": "Radeon Vega integrated"},
	{"match": "radeon(tm) graphics", "tier": RenderQuality.LOW, "note": "Radeon integrated"},
	{"match": "radeon graphics", "tier": RenderQuality.LOW, "note": "Radeon integrated"},
	{"match": "apple m1", "tier": RenderQuality.MEDIUM, "note": "Apple M1"},
	{"match": "apple m2", "tier": RenderQuality.MEDIUM, "note": "Apple M2"},
	{"match": "apple m", "tier": RenderQuality.HIGH, "note": "Apple silicon"},
	{"match": "rtx", "tier": RenderQuality.HIGH, "note": "GeForce RTX"},
	{"match": "gtx 16", "tier": RenderQuality.MEDIUM, "note": "GeForce GTX 16"},
	{"match": "gtx 10", "tier": RenderQuality.MEDIUM, "note": "GeForce GTX 10"},
	{"match": "gtx", "tier": RenderQuality.LOW, "note": "older GeForce GTX"},
	{"match": "rx 9", "tier": RenderQuality.HIGH, "note": "Radeon RX 9000"},
	{"match": "rx 7", "tier": RenderQuality.HIGH, "note": "Radeon RX 7000"},
	{"match": "rx 6", "tier": RenderQuality.HIGH, "note": "Radeon RX 6000"},
	{"match": "rx 5", "tier": RenderQuality.MEDIUM, "note": "Radeon RX 5000"},
]

## NOT VERIFIED on a real Deck (docs/plans/graphics-autotune.md, Steam Deck):
## the adapter strings and the SteamDeck environment variable are commonly
## cited, not confirmed. Confirm on the device before trusting the detector.
const DECK_ADAPTERS: Array[String] = ["custom gpu 0405", "custom gpu 0932"]
const DECK_ENV: String = "SteamDeck"
const DECK_PANEL: Vector2i = Vector2i(1280, 800)
const DECK_FACTS_VERIFIED: bool = false

static func read() -> Dictionary:
	var headless: bool = DisplayServer.get_name() == "headless"
	var screen: int = DisplayServer.window_get_current_screen() if not headless else 0
	var size: Vector2i = DisplayServer.screen_get_size(screen) if not headless else Vector2i.ZERO
	var refresh: float = DisplayServer.screen_get_refresh_rate(screen) if not headless else -1.0
	var memory: Dictionary = OS.get_memory_info()
	var info: Array = []
	for part: String in OS.get_video_adapter_driver_info():
		info.append(part)
	return {
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"adapter_type": int(RenderingServer.get_video_adapter_type()),
		"driver_info": info,
		"api": RenderingServer.get_video_adapter_api_version(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"os": OS.get_name(),
		"display_server": DisplayServer.get_name(),
		"cpu": OS.get_processor_name(),
		"cpu_count": OS.get_processor_count(),
		"memory_gb": roundi(float(memory.get("physical", 0)) / 1073741824.0),
		"screen_size": [size.x, size.y],
		"refresh": roundi(refresh) if refresh > 0.0 else -1,
		"steam_deck_env": OS.get_environment(DECK_ENV),
	}

static func _key(fingerprint: Dictionary, fields: Array[String]) -> String:
	var picked: Dictionary = {}
	for field: String in fields:
		picked[field] = fingerprint.get(field)
	return JSON.stringify(JSON.parse_string(JSON.stringify(picked)), "", true).sha256_text().left(16)

static func hardware_key(fingerprint: Dictionary) -> String:
	return _key(fingerprint, HARDWARE_FIELDS)

static func display_key(fingerprint: Dictionary) -> String:
	return _key(fingerprint, DISPLAY_FIELDS)

## The seed tier and why, from the adapter name. A Compatibility renderer never
## seeds above High, and a CPU or software adapter starts at the floor.
static func seed(fingerprint: Dictionary) -> Dictionary:
	var name: String = str(fingerprint.get("adapter", "")).to_lower()
	var type: int = int(fingerprint.get("adapter_type", RenderingDevice.DEVICE_TYPE_OTHER))
	var found: Dictionary = {"tier": RenderQuality.MEDIUM, "note": "not in the hardware list"}
	if type == RenderingDevice.DEVICE_TYPE_CPU:
		found = {"tier": RenderQuality.POTATO, "note": "software renderer"}
	else:
		for entry: Dictionary in SEEDS:
			if name.contains(str(entry["match"])):
				found = {"tier": int(entry["tier"]), "note": str(entry["note"])}
				break
	found["tier"] = RenderQuality.effective_tier(int(found["tier"]), str(fingerprint.get("renderer", "forward_plus")))
	if is_steam_deck(fingerprint):
		found["tier"] = mini(int(found["tier"]), RenderQuality.LOW)
	return found

## Integrated graphics share memory and power with the processor; the tuner
## treats them, like a battery, as likely to slow under heat.
static func integrated(fingerprint: Dictionary) -> bool:
	var type: int = int(fingerprint.get("adapter_type", RenderingDevice.DEVICE_TYPE_OTHER))
	if type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return true
	if type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return false
	# OpenGL reports OTHER; read the name.
	var name: String = str(fingerprint.get("adapter", "")).to_lower()
	for hint: String in ["hd graphics", "uhd graphics", "iris", "radeon graphics", "radeon(tm) graphics", "vega", "780m", "760m", "680m", "880m", "890m", "custom gpu", "apple m"]:
		if name.contains(hint):
			return true
	return false

## Linux, a 1280x800 panel (either way up), and a Deck adapter name or the
## SteamDeck variable. See DECK_FACTS_VERIFIED.
static func is_steam_deck(fingerprint: Dictionary) -> bool:
	if str(fingerprint.get("os", "")) != "Linux":
		return false
	var size: Variant = fingerprint.get("screen_size", [])
	var panel: bool = size is Array and (size as Array).size() == 2 \
		and ((int(size[0]) == DECK_PANEL.x and int(size[1]) == DECK_PANEL.y) or (int(size[0]) == DECK_PANEL.y and int(size[1]) == DECK_PANEL.x))
	if not panel:
		return false
	var name: String = str(fingerprint.get("adapter", "")).to_lower()
	for adapter: String in DECK_ADAPTERS:
		if name.contains(adapter):
			return true
	return str(fingerprint.get("steam_deck_env", "")) == "1"

static func is_apple_silicon(fingerprint: Dictionary) -> bool:
	return str(fingerprint.get("os", "")) == "macOS" and str(fingerprint.get("driver", "")) == "metal"

## "ac", "battery" or "unknown". Linux only (Godot 4 has no power API): any
## online mains supply is AC; otherwise a discharging battery is battery.
## Windows and macOS report unknown.
static func power_state(root: String = "/sys/class/power_supply") -> String:
	if not DirAccess.dir_exists_absolute(root):
		return "unknown"
	var battery: bool = false
	var mains_seen: bool = false
	for supply: String in DirAccess.get_directories_at(root):
		var path: String = root.path_join(supply)
		var kind: String = _read_line(path.path_join("type"))
		if kind == "Mains" or kind == "USB":
			if _read_line(path.path_join("online")) == "1":
				return "ac"
			mains_seen = true
		elif kind == "Battery":
			if _read_line(path.path_join("status")) == "Discharging":
				battery = true
	if battery:
		return "battery"
	return "ac" if mains_seen else "unknown"

static func _read_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).strip_edges().left(32)

## The Deck's frame target and pacing. 40 fps at 40 Hz (45 at 90 Hz on OLED)
## is the default: every frame is new and battery life stays near 30 fps.
## 60 is chosen when the player picks it, or on AC power when the measured
## uncapped 1% low at the Deck settings is 66 or more on a 60 Hz or faster
## panel. A 60 Hz panel that cannot hold 60 is capped at 40 with advice to
## set 40 Hz in Quick Access, because 40 fps on 60 Hz judders. NOT VERIFIED
## on a Deck: whether the engine reads the 40 Hz mode as 40, and how the
## Quick Access limiter and gamescope interact with this cap.
static func deck_profile(refresh: int, power: String, uncapped_low_1: float, player_target: int = 0) -> Dictionary:
	var base: int = 45 if refresh == 90 else 40
	var target: int = base
	var reason: String = "40 fps at 40 Hz: steady, every frame new, and gentle on the battery." if base == 40 else "45 fps at 90 Hz: an even half of the panel's refresh."
	if player_target == 60:
		target = 60
		reason = "60 fps, as you chose."
	elif power == "ac" and uncapped_low_1 >= 66.0 and refresh >= 60:
		target = 60
		reason = "60 fps on AC power: the Deck held a 1%% low of %d here." % roundi(uncapped_low_1)
	var advice: String = ""
	if target == 40 and refresh != 40:
		advice = "Set Refresh Rate to 40 Hz in the Quick Access menu for steady motion."
	return {"target": target, "fps_cap": target, "vsync": true, "reason": reason, "advice": advice}
