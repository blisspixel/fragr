extends SceneTree

## Auto settings logic with fake measurements: the tier and resolution
## search, the bottleneck rule, variance, pins, the floor path and the
## Compatibility offer; the in-match governor; the settings round trip; the
## Steam Deck profile; power and the stale-tune triggers; one headless run
## of BenchmarkRun driven by the tuner; and the first-launch card's Skip.
## Deterministic: no GPU, no timing.

var _failures: int = 0
var _dir: String = ""

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_dir = "user://test-auto-tune-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(_dir)
	set_meta("localexception_benchmark_dir", _dir.path_join("results"))
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_auto_tune: " + message)

static func m(low: float, gpu_ms: float = 0.0, share: float = 0.0, over_50: int = 0) -> Dictionary:
	return {"low_1_count_fps": low, "fps": low * 1.5, "gpu_ms_mean": gpu_ms, "gpu_slow_share": share, "over_50_count": over_50}

func tuner(seed: int, pixel_look: bool = false, fragile: bool = false, output_height: int = 1080) -> AutoTune:
	var tune: AutoTune = AutoTune.new()
	tune.target = 60
	tune.seed_tier = seed
	tune.pixel_look = pixel_look
	tune.pixel_choice = 1 if pixel_look else 0
	tune.fragile = fragile
	tune.output_height = output_height
	tune.configure()
	return tune

## Feed answers by candidate label until the search ends; returns the labels
## measured, in order.
func drive(tune: AutoTune, answers: Dictionary, fallback: Dictionary = {}) -> PackedStringArray:
	var seen: PackedStringArray = PackedStringArray()
	for _guard: int in range(40):
		var candidate: Dictionary = tune.next()
		if candidate.is_empty():
			break
		var name: String = AutoTune.label(candidate)
		seen.append(name)
		var answer: Variant = answers.get(name, fallback)
		if answer is Array:
			var queue: Array = answer
			tune.record(queue.pop_front() if queue.size() > 1 else queue[0])
		else:
			tune.record(answer)
	return seen

func _run() -> void:
	_search()
	_governor()
	_settings_round_trip()
	_deck_and_power()
	_records_and_triggers()
	await _headless_run()
	await _first_launch()
	_cleanup(ProjectSettings.globalize_path(_dir))
	if _failures == 0:
		print("test_auto_tune: PASS search, bottleneck, variance, pins, floor, governor, settings, Deck, triggers, run and Skip")
	quit(0 if _failures == 0 else 1)

func _search() -> void:
	# A strong machine: Medium passes with GPU to spare, so the search jumps two
	# tiers, holds Ultra, then supersamples while it still passes.
	var strong: AutoTune = tuner(RenderQuality.MEDIUM)
	var seen: PackedStringArray = drive(strong, {"Medium": m(200.0, 4.0, 0.8), "Ultra": m(120.0, 7.0, 0.8),
		"Ultra 125%": m(90.0, 10.0, 0.9), "Ultra 150%": m(70.0, 13.0, 0.9), "Ultra 150% confirm": m(71.0, 13.0, 0.9)})
	var result: Dictionary = strong.result()
	_check(seen == PackedStringArray(["Medium", "Ultra", "Ultra 125%", "Ultra 150%", "Ultra 150% confirm"]), "a strong machine skips up and supersamples: %s" % str(seen))
	_check(int(result["tier"]) == RenderQuality.ULTRA and int(result["render_scale"]) == 150 and result["limiter"] == "none" and bool(result["passed"]), "the strong machine keeps Ultra at 150%")
	var lines: PackedStringArray = AutoTune.describe(result, {"adapter": "Test GPU", "driver": "Forward+ vulkan", "size": [1920, 1080], "refresh": 144, "date": "2026-11-01", "cap_offer": 60})
	_check(lines[0] == "Auto settings: Ultra, 150% 3D resolution, native pixels, 60 fps target." and lines[1].begins_with("Measured 1% low 70 fps (Medium 200)"), "the card names the choice and the figures: " + "\n".join(lines))
	_check("\n".join(lines).contains("holds 60 at the highest settings") and "\n".join(lines).contains("frame cap of 60") and lines[lines.size() - 1].contains("Test GPU") and lines[lines.size() - 1].contains("144 Hz"), "the card says what limited it, offers a cap and names the machine")
	for line: String in lines:
		_check(not line.contains(char(0x2014)) and not line.contains(char(0x2013)), "no dashes in the card")

	# The graphics chip is the limit: High fails, Medium stays, no supersampling.
	var bound: AutoTune = tuner(RenderQuality.MEDIUM)
	seen = drive(bound, {"Medium": m(80.0, 10.0, 0.9), "High": m(55.0, 15.0, 0.95), "Medium confirm": m(79.0, 10.0, 0.9)})
	result = bound.result()
	_check(seen == PackedStringArray(["Medium", "High", "Medium confirm"]) and int(result["tier"]) == RenderQuality.MEDIUM and result["limiter"] == "gpu", "a GPU-bound machine stops below the tier that fails: %s" % str(seen))
	_check("\n".join(AutoTune.describe(result, {})).contains("Limited by the graphics chip. High would drop below 60"), "the card says the graphics chip limits it")
	_check((result["others"] as Array).size() == 1 and str(result["others"][0]["label"]) == "High", "the card lists the other tier measured")

	# Downward from the seed until a tier passes.
	var weak: AutoTune = tuner(RenderQuality.MEDIUM)
	seen = drive(weak, {"Medium": m(40.0, 20.0, 0.95), "Low": m(55.0, 15.0, 0.95), "Potato": m(72.0, 12.0, 0.95), "Potato confirm": m(73.0, 12.0, 0.95)})
	_check(seen == PackedStringArray(["Medium", "Low", "Potato", "Potato confirm"]) and int(weak.result()["tier"]) == RenderQuality.POTATO and bool(weak.result()["passed"]), "a weak machine steps down to Potato: %s" % str(seen))

	# Processor bound: lower graphics would not help, so the search stops.
	var cpu: AutoTune = tuner(RenderQuality.MEDIUM)
	seen = drive(cpu, {"Medium": m(45.0, 5.0, 0.3), "Medium confirm": m(46.0, 5.0, 0.3)})
	result = cpu.result()
	_check(seen == PackedStringArray(["Medium", "Medium confirm"]) and result["limiter"] == "cpu" and int(result["tier"]) == RenderQuality.MEDIUM and not bool(result["passed"]), "a CPU-bound fail keeps the tier and stops lowering")
	_check("\n".join(AutoTune.describe(result, {})).contains("Limited by the processor; lower graphics would not help") and not bool(result["offer_compatibility"]), "the card blames the processor and offers no renderer switch")
	_check(not cpu.cpu_bound(m(40.0)) and cpu.cpu_bound(m(40.0, 4.0, 0.5)) and not cpu.cpu_bound(m(40.0, 12.0, 0.9)), "unknown GPU time is never read as CPU bound")

	# Floor path, pixel look off: render scale down, then the renderer offer.
	var floor: AutoTune = tuner(RenderQuality.LOW)
	seen = drive(floor, {}, m(30.0, 30.0, 0.95))
	result = floor.result()
	_check(seen == PackedStringArray(["Low", "Potato", "Potato 83%", "Potato 67%", "Potato 50%", "Potato confirm"]), "the floor path tries lower render scales: %s" % str(seen))
	_check(not bool(result["passed"]) and bool(result["offer_compatibility"]) and "\n".join(AutoTune.describe(result, {})).contains("Compatibility renderer may run better"), "a failing floor offers Compatibility on Forward+")
	var tall: AutoTune = tuner(RenderQuality.POTATO, false, false, 2160)
	seen = drive(tall, {}, m(30.0, 30.0, 0.95))
	_check(seen.has("Potato 720p"), "a 4K output adds a 720-line render to the floor path: %s" % str(seen))
	var scaled: AutoTune = tuner(RenderQuality.POTATO)
	drive(scaled, {"Potato": m(50.0, 18.0, 0.95), "Potato 83%": m(62.0, 15.0, 0.95), "Potato 67%": m(75.0, 12.0, 0.95)}, m(75.0, 12.0, 0.95))
	_check(int(scaled.result()["render_scale"]) == 67 and bool(scaled.result()["passed"]), "the floor keeps the first render scale that passes")
	var compat: AutoTune = tuner(RenderQuality.LOW)
	compat.renderer = "gl_compatibility"
	compat.max_tier = RenderQuality.HIGH
	compat.configure()
	drive(compat, {}, m(30.0, 30.0, 0.95))
	_check(not bool(compat.result()["offer_compatibility"]), "Compatibility never offers itself")

	# Floor path, pixel look on: one coarser grid, measured and only suggested.
	var pixels: AutoTune = tuner(RenderQuality.POTATO, true)
	seen = drive(pixels, {"Potato": m(50.0, 18.0, 0.95), "Potato Medium pixels": m(70.0, 12.0, 0.95)}, m(50.0, 18.0, 0.95))
	result = pixels.result()
	_check(seen == PackedStringArray(["Potato", "Potato Medium pixels", "Potato confirm"]) and int(result["pixel_scale"]) == 1 and int(result["suggestion"]["pixel_scale"]) == 2,
		"the pixel look is never stepped fractionally or changed: %s" % str(seen))
	_check("\n".join(AutoTune.describe(result, {})).contains("Medium pixels measured 70 fps"), "the coarser grid is suggested in words")
	var grid: AutoTune = tuner(RenderQuality.HIGH, true)
	seen = drive(grid, {"Ultra": m(100.0, 8.0, 0.9)}, m(100.0, 8.0, 0.9))
	_check(not seen.has("Ultra 125%"), "no supersampling with the pixel look on")

	# Variance on a fragile machine drops one tier; a steady desktop keeps it.
	var fragile: AutoTune = tuner(RenderQuality.MEDIUM, false, true)
	seen = drive(fragile, {"Medium": m(80.0, 10.0, 0.9), "High": m(50.0, 15.0, 0.95), "Medium confirm": m(60.0, 10.0, 0.9), "Low confirm": m(95.0, 8.0, 0.9)})
	result = fragile.result()
	_check(bool(result["variable"]) and int(result["tier"]) == RenderQuality.LOW and seen.has("Low confirm"), "a fragile machine whose confirm falls short drops a tier: %s" % str(seen))
	_check("\n".join(AutoTune.describe(result, {})).contains("varied between runs"), "the card labels the variance")
	var steady: AutoTune = tuner(RenderQuality.MEDIUM)
	drive(steady, {"Medium": m(80.0, 10.0, 0.9), "High": m(50.0, 15.0, 0.95), "Medium confirm": m(64.0, 10.0, 0.9)})
	result = steady.result()
	_check(bool(result["variable"]) and int(result["tier"]) == RenderQuality.MEDIUM and is_equal_approx(float(result["low_1_count_fps"]), 64.0), "a desktop above its target keeps the tier and reports the lower figure")

	# A result near the line earns one more window and the mean decides.
	var near: AutoTune = tuner(RenderQuality.HIGH)
	seen = drive(near, {"High": [m(67.0, 10.0, 0.9), m(70.0, 10.0, 0.9)], "Ultra": m(40.0, 16.0, 0.95), "High confirm": m(69.0, 10.0, 0.9)})
	_check(seen.size() >= 2 and seen[0] == "High" and seen[1] == "High" and int(near.result()["tier"]) == RenderQuality.HIGH, "a figure near the line is measured twice: %s" % str(seen))
	_check(near.history[0]["outcome"] == "near the line, measured again", "the extra window is recorded")

	# A tier the player pinned is measured, never moved; only resolution moves.
	var pinned: AutoTune = tuner(RenderQuality.HIGH)
	pinned.tier_pinned = true
	pinned.configure()
	seen = drive(pinned, {"High": m(50.0, 15.0, 0.95), "High 83%": m(68.0, 12.0, 0.95)}, m(68.0, 12.0, 0.95))
	_check(seen[0] == "High" and seen[1] == "High 83%" and int(pinned.result()["tier"]) == RenderQuality.HIGH and int(pinned.result()["render_scale"]) == 83, "a pinned tier keeps its tier; resolution is tuned around it: %s" % str(seen))
	var both: AutoTune = tuner(RenderQuality.HIGH)
	both.tier_pinned = true
	both.scale_pinned = true
	both.configure()
	seen = drive(both, {}, m(50.0, 15.0, 0.95))
	_check(seen == PackedStringArray(["High", "High confirm"]), "with tier and scale pinned, only the confirm runs")

	# GPU figures: unknown is zero; the slowest frames' share is computed.
	var intervals: PackedFloat32Array = PackedFloat32Array()
	var gpu: PackedFloat32Array = PackedFloat32Array()
	for index: int in range(200):
		intervals.append(0.010 if index != 7 and index != 9 else 0.040)
		gpu.append(5.0 if index != 7 and index != 9 else 10.0)
	var figures: Dictionary = AutoTune.gpu_figures(intervals, gpu)
	_check(is_equal_approx(float(figures["gpu_slow_share"]), 0.25) and float(figures["gpu_ms_mean"]) > 5.0, "the slowest frames' GPU share: %s" % str(figures))
	_check(float(AutoTune.gpu_figures(intervals, PackedFloat32Array())["gpu_slow_share"]) == 0.0, "no GPU time reads as unknown")
	_check(AutoTune.cap_offer(60, 144, false) == 60 and AutoTune.cap_offer(60, 60, false) == 0 and AutoTune.cap_offer(60, 144, true) == 0 and AutoTune.cap_offer(144, 144, false, true) == 138, "the frame cap offer follows V-Sync and VRR")

func _governor() -> void:
	RenderQuality.reductions = PackedStringArray()
	var governor: FrameGovernor = FrameGovernor.new()
	governor.target = 60
	governor.quality = RenderQuality.HIGH
	governor.renderer = "forward_plus"
	for _second: int in range(3000):
		governor.push(0.0201)
	_check(not governor.armed and governor.windows == 2, "two short windows do not arm a step")
	_check(governor.safe_point().is_empty(), "nothing happens at a safe point while unarmed")
	for _second: int in range(1500):
		governor.push(0.0201)
	_check(governor.armed, "three failing windows in a row arm one step")
	var step: String = governor.safe_point()
	_check(step == "ssao" and RenderQuality.reductions == PackedStringArray(["ssao"]) and not governor.armed, "the first step at High is contact shading, taken at the safe point: " + step)
	_check(FrameGovernor.notice(step, 60) == "Graphics lowered: contact shading lowered to hold 60.", "the HUD line is one level sentence")
	governor.push(1.0)
	for _second: int in range(1000):
		governor.push(0.0201)
	governor.push(2.0)
	for _second: int in range(3000):
		governor.push(0.0101)
	_check(not governor.armed and governor.windows == 4, "a load gap restarts the window; a passing window breaks the streak")
	var ultra: FrameGovernor = FrameGovernor.new()
	ultra.quality = RenderQuality.ULTRA
	RenderQuality.reductions = PackedStringArray()
	_check(ultra.next_step() == "volumetric_fog", "Ultra loses volumetric fog first")
	var floor: FrameGovernor = FrameGovernor.new()
	floor.quality = RenderQuality.POTATO
	RenderQuality.reductions = PackedStringArray(["effects"])
	_check(floor.next_step().is_empty(), "nothing is left to lower at Potato once effects are halved")
	FrameGovernor.clear()
	_check(RenderQuality.reductions.is_empty(), "a re-tune or new session clears every step")
	var preferences: LocalExceptionSettings = LocalExceptionSettings.new(_dir.path_join("governor.cfg"))
	_check(FrameGovernor.allowed(preferences), "the valve is on by default")
	preferences.set_value("video", "pinned", ["quality"])
	_check(not FrameGovernor.allowed(preferences), "a pinned tier is never governed")
	preferences.set_value("video", "pinned", [])
	preferences.set_value("video", "governor", false)
	_check(not FrameGovernor.allowed(preferences), "the player can turn the valve off")
	var long: FrameGovernor = FrameGovernor.new()
	for _second: int in range(16 * 60 * 50):
		long.push(0.0201)
	_check(long.advise_retune(), "fifteen minutes of mostly failing play advises a re-tune")

func _settings_round_trip() -> void:
	var path: String = _dir.path_join("settings.cfg")
	var preferences: LocalExceptionSettings = LocalExceptionSettings.new(path)
	_check(preferences.get_value("video", "quality") == RenderQuality.MEDIUM and preferences.get_value("video", "auto") == true
		and preferences.get_value("video", "target_fps") == 60 and preferences.get_value("video", "render_scale") == 100
		and (preferences.get_value("video", "pinned") as Array).is_empty() and (preferences.get_value("video", "tune") as Dictionary).is_empty(), "defaults: Medium, auto on, 60 target, no pins, no tune")
	for target: Variant in [75, "60", -1, 60.5]:
		preferences.set_value("video", "target_fps", target)
		_check(preferences.get_value("video", "target_fps") == 60, "an unknown target falls back: %s" % str(target))
	preferences.set_value("video", "target_fps", 144)
	preferences.set_value("video", "pinned", ["vsync", "nonsense", "quality", "quality", 3])
	_check(preferences.get_value("video", "pinned") == ["quality", "vsync"], "pins keep known keys once, in order")
	preferences.set_value("video", "tune", {"version": 1, "source": "made up"})
	_check((preferences.get_value("video", "tune") as Dictionary).is_empty(), "an unknown record source is refused")
	var fingerprint: Dictionary = {"adapter": "Test GPU", "renderer": "forward_plus", "screen_size": [1920, 1080], "refresh": 144}
	var record: Dictionary = AutoTune.make_record({"tier": 3, "render_scale": 125, "target": 144, "low_1_count_fps": 150.0, "limiter": "gpu"}, fingerprint, PackedStringArray(["Auto settings: High."]), "measured", "ac", {})
	preferences.set_value("video", "tune", record)
	preferences.set_value("video", "quality", RenderQuality.HIGH)
	preferences.set_value("video", "render_scale", 125)
	_check(preferences.save_to_disk() == OK, "auto settings save")
	var loaded: LocalExceptionSettings = LocalExceptionSettings.new(path)
	loaded.load_from_disk()
	_check(not loaded.video_refused and loaded.get_value("video", "quality") == RenderQuality.HIGH and loaded.get_value("video", "render_scale") == 125
		and loaded.get_value("video", "target_fps") == 144 and loaded.pinned("quality") and loaded.get_value("video", "tune") == record, "tier, scale, target, pins and the tune record survive a restart")
	# A file from the three-preset build is refused, not migrated.
	var old: ConfigFile = ConfigFile.new()
	old.set_value("video", "quality", 1)
	old.set_value("video", "vertical_fov", 90.0)
	old.set_value("meta", "controls_layout", LocalExceptionSettings.CONTROLS_LAYOUT)
	old.save(path)
	loaded.load_from_disk()
	_check(loaded.video_refused and loaded.get_value("video", "quality") == RenderQuality.MEDIUM and is_equal_approx(float(loaded.get_value("video", "vertical_fov")), 90.0), "an old preset index is refused to auto; other video choices stay")
	# Pins come from hand changes; Reset to auto clears them and puts the tune back.
	var before: LocalExceptionSettings = LocalExceptionSettings.new(path)
	var draft: LocalExceptionSettings = before.draft()
	draft.set_value("video", "quality", RenderQuality.LOW)
	draft.set_value("video", "vertical_fov", 80.0)
	draft.pin_changes(before)
	_check(draft.get_value("video", "pinned") == ["quality"], "a hand-picked tier is pinned; other options are not")
	draft.set_value("video", "tune", record)
	draft.reset_to_auto()
	_check((draft.get_value("video", "pinned") as Array).is_empty() and draft.get_value("video", "quality") == RenderQuality.HIGH and draft.get_value("video", "render_scale") == 125, "Reset to auto clears pins and restores the tune's choice")
	draft.set_value("video", "pinned", ["quality"])
	draft.set_value("video", "quality", RenderQuality.LOW)
	AutoTune.apply_record(draft, record)
	_check(draft.get_value("video", "quality") == RenderQuality.LOW and draft.get_value("video", "render_scale") == 125, "a tune never moves a pinned option")

func _deck_and_power() -> void:
	var deck: Dictionary = {"os": "Linux", "adapter": "AMD Custom GPU 0405 (RADV VANGOGH)", "screen_size": [1280, 800], "refresh": 60, "renderer": "forward_plus"}
	_check(HardwareProfile.is_steam_deck(deck) and not HardwareProfile.DECK_FACTS_VERIFIED, "a spoofed Deck adapter on a 1280x800 Linux panel is a Deck (unverified on device)")
	_check(not HardwareProfile.is_steam_deck({"os": "Windows", "adapter": "AMD Custom GPU 0405", "screen_size": [1280, 800]}), "not on Windows")
	_check(not HardwareProfile.is_steam_deck({"os": "Linux", "adapter": "AMD Custom GPU 0405", "screen_size": [1920, 1080]}), "not on an external display")
	_check(HardwareProfile.is_steam_deck({"os": "Linux", "adapter": "AMD Radeon", "screen_size": [800, 1280], "steam_deck_env": "1"}), "the SteamDeck variable on a portrait panel counts")
	var profile: Dictionary = HardwareProfile.deck_profile(40, "battery", 70.0)
	_check(profile["target"] == 40 and profile["fps_cap"] == 40 and profile["vsync"] == true and str(profile["advice"]).is_empty(), "40 Hz on battery: steady 40, no advice")
	profile = HardwareProfile.deck_profile(60, "battery", 70.0)
	_check(profile["target"] == 40 and str(profile["advice"]).contains("40 Hz in the Quick Access menu"), "60 Hz on battery: 40 with the Quick Access advice")
	_check(HardwareProfile.deck_profile(60, "ac", 70.0)["target"] == 60 and HardwareProfile.deck_profile(60, "ac", 60.0)["target"] == 40, "60 on AC only when the 1% low is 66 or more")
	_check(HardwareProfile.deck_profile(40, "ac", 70.0)["target"] == 40, "a 40 Hz panel stays at 40 even on AC")
	_check(HardwareProfile.deck_profile(90, "battery", 50.0)["target"] == 45 and HardwareProfile.deck_profile(40, "battery", 30.0, 60)["target"] == 60, "OLED at 90 Hz is 45; the player's 60 wins")
	var preferences: LocalExceptionSettings = LocalExceptionSettings.new(_dir.path_join("deck.cfg"))
	var tune: AutoTune = AutoTune.for_settings(preferences, deck, Vector2i(1280, 800), "battery")
	_check(tune.max_tier == RenderQuality.HIGH and tune.target == 40 and is_equal_approx(tune.threshold, 44.0) and tune.seed_tier <= RenderQuality.LOW and tune.fragile, "the Deck tunes to 40 (44 with headroom), never Ultra, from Low")
	var record: Dictionary = AutoTune.make_record({"tier": 1, "target": 40}, deck, PackedStringArray(), "measured", "battery", profile)
	var applied: LocalExceptionSettings = preferences.draft()
	AutoTune.apply_record(applied, record)
	_check(applied.get_value("video", "fps_cap") == 40 and applied.get_value("video", "vsync") == true, "the Deck profile sets the cap and V-Sync")
	_check(HardwareProfile.seed({"adapter": "AMD Radeon 780M Graphics"})["tier"] == RenderQuality.MEDIUM and HardwareProfile.seed({"adapter": "llvmpipe"})["tier"] == RenderQuality.POTATO
		and HardwareProfile.seed({"adapter": "Unknown Device"})["tier"] == RenderQuality.MEDIUM and HardwareProfile.seed({"adapter": "NVIDIA GeForce RTX 4070", "renderer": "gl_compatibility"})["tier"] == RenderQuality.HIGH,
		"the seed table guesses; unknown is Medium; Compatibility never seeds Ultra")
	_check(HardwareProfile.integrated({"adapter": "Intel(R) Iris(R) Xe Graphics", "adapter_type": RenderingDevice.DEVICE_TYPE_OTHER}) and not HardwareProfile.integrated({"adapter": "x", "adapter_type": RenderingDevice.DEVICE_TYPE_DISCRETE_GPU}), "integrated graphics read from type, else name")
	_check(HardwareProfile.is_apple_silicon({"os": "macOS", "driver": "metal"}) and not HardwareProfile.is_apple_silicon({"os": "macOS", "driver": "vulkan"}), "Apple silicon is macOS on Metal")
	var supply: String = ProjectSettings.globalize_path(_dir.path_join("power"))
	DirAccess.make_dir_recursive_absolute(supply.path_join("AC"))
	DirAccess.make_dir_recursive_absolute(supply.path_join("BAT0"))
	_write(supply.path_join("AC/type"), "Mains\n")
	_write(supply.path_join("AC/online"), "0\n")
	_write(supply.path_join("BAT0/type"), "Battery\n")
	_write(supply.path_join("BAT0/status"), "Discharging\n")
	_check(HardwareProfile.power_state(supply) == "battery", "a discharging battery with mains offline is battery")
	_write(supply.path_join("AC/online"), "1\n")
	_check(HardwareProfile.power_state(supply) == "ac", "mains online is AC")
	_check(HardwareProfile.power_state(supply.path_join("missing")) == "unknown", "no power supply folder is unknown")

func _records_and_triggers() -> void:
	var fingerprint: Dictionary = {"adapter": "Test GPU", "driver_info": ["radv", "26.2"], "renderer": "forward_plus", "os": "Linux", "screen_size": [1920, 1080], "refresh": 120}
	var record: Dictionary = AutoTune.make_record({"tier": 3, "target": 60}, fingerprint, PackedStringArray(["x"]), "measured", "ac", {})
	_check(AutoTune.stale_reason(record, fingerprint).is_empty(), "a fresh tune is current")
	var driver: Dictionary = fingerprint.duplicate(true)
	driver["driver_info"] = ["radv", "26.3"]
	_check(AutoTune.stale_reason(record, driver).contains("driver"), "a driver update offers a re-tune")
	var display: Dictionary = fingerprint.duplicate(true)
	display["refresh"] = 60
	_check(AutoTune.stale_reason(record, display) == "Tuned for another display.", "another display is named")
	var revision: Dictionary = record.duplicate(true)
	revision["revision"] = RenderQuality.RENDER_COST_REVISION + 1
	_check(AutoTune.stale_reason(revision, fingerprint).contains("draws differently"), "a rendering-cost revision offers a re-tune")
	var advised: Dictionary = record.duplicate(true)
	advised["retune_advised"] = true
	_check(AutoTune.stale_reason(AutoTune.clean_record(advised), fingerprint).contains("fell short"), "long failing play offers a re-tune")
	var lookup: Dictionary = AutoTune.lookup_record({"adapter": "Intel(R) UHD Graphics 620"}, 60)
	_check(lookup["source"] == "lookup" and int(lookup["tier"]) == RenderQuality.POTATO and str(lookup["lines"][0]).contains("not measured"), "Skip's guess says it was not measured")
	_check(AutoTune.clean_record({"version": 1, "source": "measured", "tier": 9, "render_scale": 100, "resolution_height": 0, "target": 60, "revision": 1}).is_empty(), "a record naming no tier is refused")

func _headless_run() -> void:
	var path: String = _dir.path_join("run.cfg")
	var preferences: LocalExceptionSettings = LocalExceptionSettings.new(path)
	preferences.set_value("video", "pixel_scale", 0)
	var run: BenchmarkRun = BenchmarkRun.new()
	run.preferences = preferences
	run.tuner = tuner(RenderQuality.MEDIUM)
	root.add_child(run)
	var reports: Array = []
	run.finished.connect(func(report: Dictionary) -> void: reports.append(report))
	run.begin()
	run.set_process(false)
	# A shader compile in the first second keeps the warm-up going.
	run.advance(0.01, 3)
	run.advance(0.5, 0)
	_check(run.phase == "priming", "a compile resets the quiet clock")
	run.advance(0.6, 0)
	_check(run.phase == "scoring", "a second without compiles ends the warm-up")
	_check(str(run.progress()["headline"]) == "TRYING MEDIUM" and str(run.progress()["detail"]).contains("66 fps"), "the readout names the candidate and the line: " + str(run.progress()["headline"]))
	for _frame: int in range(20000):
		if not reports.is_empty():
			break
		if run.phase == "priming":
			run.advance(0.25, 0)
		else:
			run.advance(0.008, 0, 4.0)
	_check(reports.size() == 1 and reports[0].get("auto_tune") is Dictionary, "the run finishes with an auto-tune block")
	if reports.size() == 1:
		var report: Dictionary = reports[0]
		var tuned: Dictionary = report["auto_tune"]
		_check(int(tuned["result"]["tier"]) == RenderQuality.ULTRA and int(tuned["result"]["render_scale"]) == 150, "a fast fake machine ends at Ultra 150%%: %s" % str(tuned["result"]["tier"]))
		_check(preferences.get_value("video", "quality") == RenderQuality.ULTRA and preferences.get_value("video", "render_scale") == 150 and (preferences.get_value("video", "tune") as Dictionary).get("source") == "measured", "the choice reaches the settings with its record")
		_check(str(report["workload"]["id"]) == BenchmarkRun.TUNE_WORKLOAD_ID and str(report["workload"]["local_host"]) == "running", "the report names the host-running workload")
		_check((report["runs"] as Array).size() == (tuned["result"]["candidates"] as Array).size() and str(report["runs"][0]["preset"]) == "Medium", "every candidate is a row")
		_check(run.saved_basename.begins_with("autotune-"), "auto-tune results save apart from benchmark history")
		run.show_results(report)
		await process_frame
		var view: BenchmarkResults = run.find_child("BenchmarkScoreLayer", true, false) as BenchmarkResults
		_check(view != null and (view.find_child("Outcome", true, false) as Label).text == "AUTO SETTINGS CHOSEN", "the result card leads with the choice")
		_check(view != null and view.find_child("TuneCard", true, false) != null and view.find_child("JingleCaption", true, false) != null, "the plain-words card shows beside Crackpot's jingle")
	run.queue_free()
	await process_frame

func _first_launch() -> void:
	var path: String = _dir.path_join("first.cfg")
	set_meta("localexception_settings_path", path)
	set_meta(&"localexception_tune_offer_force", true)
	var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
	menu.set("_settings", LocalExceptionSettings.new(path))
	root.add_child(menu)
	await process_frame
	await process_frame
	var card: Node = menu.find_child("TuneOfferCard", true, false)
	_check(card != null and (menu.find_child("TuneOfferBody", true, false) as Label).text.contains("About"), "a first launch shows the auto settings card with its time")
	_check(menu.find_child("TuneOfferSkip", true, false) != null and menu.find_child("TuneOfferStart", true, false) != null, "the card offers Start and Skip")
	var skip: Button = menu.find_child("TuneOfferSkip", true, false) as Button
	if skip != null:
		skip.pressed.emit()
	await process_frame
	var saved: LocalExceptionSettings = LocalExceptionSettings.new(path)
	saved.load_from_disk()
	_check((saved.get_value("video", "tune") as Dictionary).get("source") == "lookup" and menu.find_child("TuneOfferCard", true, false) == null, "Skip applies the hardware guess and closes the card")
	_check(has_meta(&"localexception_tune_offered"), "the card shows once per session")
	remove_meta(&"localexception_tune_offer_force")
	menu.queue_free()
	await process_frame
	var again: Control = load("res://scenes/boot_menu.tscn").instantiate()
	again.set("_settings", LocalExceptionSettings.new(path))
	root.add_child(again)
	await process_frame
	_check(again.find_child("TuneOfferCard", true, false) == null, "a saved Skip never shows the card again")
	again.queue_free()
	await process_frame

func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _cleanup(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in DirAccess.get_directories_at(path):
		_cleanup(path.path_join(child))
	DirAccess.remove_absolute(path)
