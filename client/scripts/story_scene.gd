class_name StoryScene
extends RefCounted

## Scene manifests: ordered shots of a still, a caption key and optional sound.
## A manifest is strict data. Missing picture or sound files are not errors;
## the player falls back to text so a scene is never blocked by an asset.

const FORMAT: int = 1
const DIRECTORY: String = "res://assets/story/scenes/"
const ASSET_ROOT: String = "res://assets/"
const MAX_SHOTS: int = 24
const MAX_HOLD_SECONDS: float = 5.0
const MAX_MOTION: float = 0.15
const MOTIONS: Array[String] = ["none", "zoom_in", "zoom_out", "pan_left", "pan_right", "pan_up", "pan_down"]
const TIMINGS: Array[String] = ["reader", "narration"]
const IMAGE_EXTENSIONS: Array[String] = ["png"]
const AUDIO_EXTENSIONS: Array[String] = ["ogg", "mp3", "wav"]
const SCENE_KEYS: Array[String] = ["format", "id", "title_key", "skip_key", "music", "ambience", "shots"]
const SHOT_KEYS: Array[String] = ["id", "title_key", "caption_key", "speaker_key", "image", "motion", "narration", "timing", "hold"]
const BED_KEYS: Array[String] = ["path", "volume_db"]
const MOTION_KEYS: Array[String] = ["kind", "amount"]

## The scene a campaign plays after a mission departs, by mission id. Presentation
## only: the server already owns the departure, and a missing entry plays nothing.
const AFTER_MISSION: Dictionary[String, String] = {
	"recall_notice": "l01_l02",
}

static func path_for(scene_id: String) -> String:
	return DIRECTORY + scene_id + ".json"

static func exists(scene_id: String) -> bool:
	return _identifier(scene_id) and FileAccess.file_exists(path_for(scene_id))

## A validated manifest, or an empty dictionary with the reason pushed as an error.
static func load_scene(scene_id: String) -> Dictionary:
	if not _identifier(scene_id):
		push_error("story_scene: invalid scene id " + scene_id)
		return {}
	var path: String = path_for(scene_id)
	if not FileAccess.file_exists(path):
		push_error("story_scene: missing manifest " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var reason: String = validation_error(parsed)
	if reason.is_empty() and (parsed as Dictionary)["id"] != scene_id:
		reason = "id does not match its file name"
	if not reason.is_empty():
		push_error("story_scene: %s: %s" % [path, reason])
		return {}
	return parsed as Dictionary

## Empty when the manifest is usable. Unknown fields, wrong types, unsafe paths
## and out-of-range timing are all rejected rather than guessed at.
static func validation_error(data: Variant) -> String:
	if not data is Dictionary:
		return "manifest is not an object"
	var scene: Dictionary = data
	var unknown: String = _unknown_key(scene, SCENE_KEYS)
	if not unknown.is_empty():
		return "unknown field " + unknown
	if not scene.get("format") is float or float(scene["format"]) != float(FORMAT):
		return "format must be %d" % FORMAT
	if not scene.get("id") is String or not _identifier(scene["id"]):
		return "id must be lowercase letters, digits and underscores"
	for key: String in ["title_key", "skip_key"]:
		if not _key_ok(scene, key, true):
			return key + " must be an uppercase catalog key"
	for bed: String in ["music", "ambience"]:
		if scene.has(bed):
			var bed_error: String = _bed_error(scene[bed])
			if not bed_error.is_empty():
				return bed + ": " + bed_error
	if not scene.get("shots") is Array:
		return "shots must be a list"
	var shots: Array = scene["shots"]
	if shots.is_empty() or shots.size() > MAX_SHOTS:
		return "a scene has 1 to %d shots" % MAX_SHOTS
	var seen: Dictionary[String, bool] = {}
	for index: int in shots.size():
		var shot_error: String = _shot_error(shots[index])
		if not shot_error.is_empty():
			return "shot %d: %s" % [index + 1, shot_error]
		var shot_id: String = (shots[index] as Dictionary)["id"]
		if seen.has(shot_id):
			return "shot %d: duplicate id %s" % [index + 1, shot_id]
		seen[shot_id] = true
	return ""

static func _shot_error(value: Variant) -> String:
	if not value is Dictionary:
		return "not an object"
	var shot: Dictionary = value
	var unknown: String = _unknown_key(shot, SHOT_KEYS)
	if not unknown.is_empty():
		return "unknown field " + unknown
	if not shot.get("id") is String or not (shot["id"] as String).to_upper() == shot["id"] or not _identifier((shot["id"] as String).to_lower()):
		return "id must be an uppercase identifier"
	if not _key_ok(shot, "caption_key", false):
		return "caption_key is required and must be an uppercase catalog key"
	for key: String in ["title_key", "speaker_key"]:
		if not _key_ok(shot, key, true):
			return key + " must be an uppercase catalog key"
	if shot.has("image") and not _asset_path_ok(shot["image"], IMAGE_EXTENSIONS):
		return "image must be a png under " + ASSET_ROOT
	if shot.has("narration") and not _asset_path_ok(shot["narration"], AUDIO_EXTENSIONS):
		return "narration must be ogg, mp3 or wav under " + ASSET_ROOT
	if shot.has("timing") and (not shot["timing"] is String or not shot["timing"] in TIMINGS):
		return "timing must be reader or narration"
	if shot.get("timing") == "narration" and not shot.has("narration"):
		return "narration timing needs a narration clip"
	if shot.has("hold") and (not shot["hold"] is float or float(shot["hold"]) < 0.0 or float(shot["hold"]) > MAX_HOLD_SECONDS):
		return "hold must be 0 to %d seconds" % int(MAX_HOLD_SECONDS)
	if shot.has("motion"):
		if not shot["motion"] is Dictionary:
			return "motion must be an object"
		var motion: Dictionary = shot["motion"]
		unknown = _unknown_key(motion, MOTION_KEYS)
		if not unknown.is_empty():
			return "motion has unknown field " + unknown
		if not motion.get("kind") is String or not motion["kind"] in MOTIONS:
			return "motion kind is not supported"
		if motion.has("amount") and (not motion["amount"] is float or float(motion["amount"]) < 0.0 or float(motion["amount"]) > MAX_MOTION):
			return "motion amount must be 0 to %.2f" % MAX_MOTION
	return ""

static func _bed_error(value: Variant) -> String:
	if not value is Dictionary:
		return "not an object"
	var bed: Dictionary = value
	var unknown: String = _unknown_key(bed, BED_KEYS)
	if not unknown.is_empty():
		return "unknown field " + unknown
	if not _asset_path_ok(bed.get("path"), AUDIO_EXTENSIONS):
		return "path must be ogg, mp3 or wav under " + ASSET_ROOT
	if bed.has("volume_db") and (not bed["volume_db"] is float or float(bed["volume_db"]) < -40.0 or float(bed["volume_db"]) > 0.0):
		return "volume_db must be -40 to 0"
	return ""

static func _unknown_key(object: Dictionary, allowed: Array[String]) -> String:
	for key: Variant in object:
		if not key is String or not key in allowed:
			return str(key)
	return ""

static func _identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 48:
		return false
	for character: String in value:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") and character != "_":
			return false
	return true

static func _key_ok(object: Dictionary, key: String, optional: bool) -> bool:
	if not object.has(key):
		return optional
	var value: Variant = object[key]
	return value is String and (value as String).to_upper() == value and _identifier((value as String).to_lower())

## Paths stay inside the packaged assets. A locale placeholder lets a later voice
## pass add per-language narration beside the English files.
static func _asset_path_ok(value: Variant, extensions: Array[String]) -> bool:
	if not value is String:
		return false
	var path: String = value
	if not path.begins_with(ASSET_ROOT) or ".." in path or "\\" in path or "//" in path.trim_prefix("res://"):
		return false
	return path.get_extension() in extensions

## The narration clip for the current locale, then English, then nothing.
static func narration_path(shot: Dictionary, locale: String = TranslationServer.get_locale()) -> String:
	var template: String = str(shot.get("narration", ""))
	if template.is_empty():
		return ""
	for candidate: String in [locale, locale.get_slice("_", 0), "en"]:
		var path: String = template.replace("{locale}", candidate)
		if ResourceLoader.exists(path):
			return path
	return ""

## Every catalog key a manifest uses, for harnesses that prove captions resolve.
static func catalog_keys(scene: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: String in ["title_key", "skip_key"]:
		if scene.has(key):
			keys.append(scene[key])
	for shot: Dictionary in scene.get("shots", []):
		for key: String in ["title_key", "caption_key", "speaker_key"]:
			if shot.has(key):
				keys.append(shot[key])
	return keys
