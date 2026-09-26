extends SceneTree

## Scene manifests: committed files validate, captions resolve, bad data is refused.

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_story_scene: " + message)

func _good() -> Dictionary:
	return {
		"format": 1.0,
		"id": "sample",
		"title_key": "STORY_L02_TITLE",
		"music": {"path": "res://assets/story/music/bed.mp3", "volume_db": -10.0},
		"shots": [
			{"id": "ONE", "caption_key": "STORY_L01_L02_LEDGER", "image": "res://assets/story/stills/a.png",
				"motion": {"kind": "zoom_in", "amount": 0.05}, "narration": "res://assets/story/voice/{locale}/a.mp3",
				"timing": "narration", "hold": 1.0},
			{"id": "TWO", "caption_key": "STORY_L01_L02_WARD"},
		],
	}

func _rejects(patch: Callable, message: String) -> void:
	var data: Dictionary = _good()
	patch.call(data)
	_expect(not StoryScene.validation_error(data).is_empty(), "rejects " + message)

func _too_many_shots(data: Dictionary) -> void:
	var many: Array = []
	for index: int in StoryScene.MAX_SHOTS + 1:
		many.append({"id": "S%d" % index, "caption_key": "STORY_L01_L02_WARD"})
	data["shots"] = many

func _run() -> void:
	_expect(StoryScene.validation_error(_good()).is_empty(), "a complete manifest validates: " + StoryScene.validation_error(_good()))
	_expect(StoryScene.validation_error(JSON.parse_string(JSON.stringify(_good()))).is_empty(), "a manifest survives a JSON round trip")
	_expect(not StoryScene.validation_error([]).is_empty(), "rejects a list")
	_expect(not StoryScene.validation_error(null).is_empty(), "rejects null")
	_rejects(func(d: Dictionary) -> void: d["extra"] = true, "an unknown scene field")
	_rejects(func(d: Dictionary) -> void: d["format"] = 2.0, "a future format")
	_rejects(func(d: Dictionary) -> void: d.erase("format"), "a missing format")
	_rejects(func(d: Dictionary) -> void: d["id"] = "Bad Id", "an id with spaces and capitals")
	_rejects(func(d: Dictionary) -> void: d["id"] = "", "an empty id")
	_rejects(func(d: Dictionary) -> void: d["title_key"] = "lower_key", "a lowercase title key")
	_rejects(func(d: Dictionary) -> void: d["skip_key"] = 7.0, "a numeric skip key")
	_rejects(func(d: Dictionary) -> void: d["shots"] = [], "an empty shot list")
	_rejects(func(d: Dictionary) -> void: d["shots"] = {}, "shots as an object")
	_rejects(_too_many_shots, "too many shots")
	_rejects(func(d: Dictionary) -> void: d["shots"][1]["id"] = "ONE", "duplicate shot ids")
	_rejects(func(d: Dictionary) -> void: d["shots"][1]["id"] = "two", "a lowercase shot id")
	_rejects(func(d: Dictionary) -> void: d["shots"][1].erase("caption_key"), "a shot without a caption")
	_rejects(func(d: Dictionary) -> void: d["shots"][1]["caption"] = "Inline English", "inline caption text")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["image"] = "res://scripts/boot_menu.gd", "an image outside the assets")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["image"] = "res://assets/../scripts/x.png", "a parent path")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["image"] = "user://still.png", "a user path")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["image"] = "res://assets/story/stills/a.jpg", "a non-png still")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["image"] = "C:\\stills\\a.png", "an absolute file path")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["narration"] = "res://assets/story/voice/a.mp4", "a video as narration")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["timing"] = "auto", "an unknown timing rule")
	_rejects(func(d: Dictionary) -> void: d["shots"][0].erase("narration"), "narration timing without a clip")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["hold"] = 9.0, "a long hold")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["hold"] = -1.0, "a negative hold")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["motion"] = {"kind": "spin"}, "an unknown motion")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["motion"] = {"kind": "zoom_in", "amount": 0.5}, "an unsubtle zoom")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["motion"] = {"kind": "zoom_in", "speed": 2.0}, "an unknown motion field")
	_rejects(func(d: Dictionary) -> void: d["shots"][0]["motion"] = "zoom_in", "motion as a string")
	_rejects(func(d: Dictionary) -> void: d["music"] = {"path": "res://assets/story/music/bed.mp3", "volume_db": 6.0}, "a boosted bed")
	_rejects(func(d: Dictionary) -> void: d["ambience"] = {"path": "res://assets/story/a.png"}, "an image as ambience")
	_rejects(func(d: Dictionary) -> void: d["ambience"] = {"path": "res://assets/story/a.ogg", "loop": true}, "an unknown bed field")

	# Every committed manifest loads, its keys resolve, and its file name is its id.
	var directory: PackedStringArray = DirAccess.get_files_at(StoryScene.DIRECTORY)
	var loaded: int = 0
	for file: String in directory:
		if file.get_extension() != "json":
			continue
		var scene_id: String = file.get_basename()
		var scene: Dictionary = StoryScene.load_scene(scene_id)
		_expect(not scene.is_empty(), "committed manifest loads: " + file)
		loaded += 1
		for key: String in StoryScene.catalog_keys(scene):
			var text: String = TranslationServer.translate(key)
			_expect(text != key and not text.is_empty(), "%s caption key resolves: %s" % [scene_id, key])
	_expect(loaded >= 2, "the opening and the first interlude are committed")
	for mission: String in StoryScene.AFTER_MISSION:
		_expect(StoryScene.exists(StoryScene.AFTER_MISSION[mission]), "departure scene exists for " + mission)

	# The migrated opening keeps its five keyed beats in order.
	var opening: Dictionary = StoryScene.load_scene(CampaignOpening.SCENE_ID)
	var beats: Array[String] = []
	for shot: Dictionary in opening.get("shots", []):
		beats.append(shot["id"])
		_expect(shot["caption_key"] == "STORY_M01_" + shot["id"] + "_BODY", "opening body key is unchanged for " + shot["id"])
		_expect(shot.get("title_key") == "STORY_M01_" + shot["id"] + "_TITLE", "opening title key is unchanged for " + shot["id"])
	_expect(beats == CampaignOpening.BEATS, "opening manifest matches the five beats")
	# The committed opening stills load; ADDRESS and RECALL stay text until theirs exist.
	for shot: Dictionary in opening.get("shots", []):
		if shot["id"] in ["HOME", "CHOICE", "PURSUIT"]:
			_expect(ResourceLoader.exists(shot.get("image", "")), "opening still loads for " + shot["id"])
	_expect(StoryScene.validation_error(CampaignOpening.fallback()).is_empty(), "the opening fallback is itself a valid scene")

	# File loading refuses names that are not identifiers and ids that disagree.
	_expect(not StoryScene.exists("../opening"), "a path is not a scene id")
	_expect(not StoryScene.exists("missing_scene"), "an absent scene does not exist")

	# Narration falls back from the locale to English, then to silence.
	_expect(StoryScene.narration_path({"narration": "res://assets/audio/fire.wav"}) == "res://assets/audio/fire.wav", "a present clip is used")
	_expect(StoryScene.narration_path({"narration": "res://assets/story/voice/{locale}/none.mp3"}, "de_DE").is_empty(), "missing clips in every locale fall back to text")
	_expect(StoryScene.narration_path({}).is_empty(), "no narration means reader paced")

	if failures == 0:
		print("test_story_scene: PASS strict manifests, committed scenes, caption keys and narration fallback")
	quit(0 if failures == 0 else 1)
