extends SceneTree

const ScreenFlashScript = preload("res://scripts/screen_flash.gd")

var _failures: int = 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_screen_flash: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var flash = ScreenFlashScript.new()
	root.add_child(flash)

	# 1. Defaults
	_check(flash.flash_mode == FragrSettings.FLASHES_REDUCED, "defaults to Reduced mode")
	_check(flash.active == false and flash.visible == false, "initially inactive and invisible")

	# 2. Time-injected rate limit in Reduced mode
	var mock_clock: Array[float] = [10.0]
	flash.time_source = func() -> float: return mock_clock[0]

	# Clear any previous tree history for isolated test
	root.remove_meta("fragr_flash_history")
	flash._history.clear()

	_check(flash.trigger("damage", MenuTheme.DANGER), "impulse 1 admitted at t=10.0")
	_check(flash.active and flash.visible, "flash is active and visible after admission")
	mock_clock[0] = 10.2
	_check(flash.trigger("damage", MenuTheme.DANGER), "impulse 2 admitted at t=10.2")
	mock_clock[0] = 10.4
	_check(flash.trigger("damage", MenuTheme.DANGER), "impulse 3 admitted at t=10.4")
	mock_clock[0] = 10.6
	_check(not flash.trigger("damage", MenuTheme.DANGER), "impulse 4 rejected: rolling budget exhausted")
	mock_clock[0] = 10.8
	_check(not flash.trigger("spawn", MenuTheme.EMBER), "impulse 5 rejected across different producer")

	# Advance time past the 1.0s window of impulse 1 (10.0 + 1.0 = 11.0)
	mock_clock[0] = 11.05
	var admitted: bool = flash.trigger("damage", MenuTheme.DANGER)
	_check(admitted, "impulse 6 admitted after window slides")
	_check(not flash.trigger("damage", MenuTheme.DANGER), "impulse 7 rejected: budget full again (10.2, 10.4, 11.05)")

	# 3. Off mode clears and suppresses
	flash.set_flash_mode(FragrSettings.FLASHES_OFF)
	_check(not flash.active and not flash.visible, "switching to Off clears active flash")
	mock_clock[0] = 15.0
	_check(not flash.trigger("damage", MenuTheme.DANGER), "Off mode suppresses all impulses")

	# 4. Full mode
	flash.set_flash_mode(FragrSettings.FLASHES_FULL)
	mock_clock[0] = 20.0
	_check(flash.trigger("damage", MenuTheme.DANGER), "Full mode admits impulse")

	# 5. Magenta prevention
	var magenta: Color = Color(0.6, 0.15, 0.55)
	flash.trigger("fail", magenta)
	_check(flash.current_color != magenta and flash.current_color == MenuTheme.DANGER, "magenta is replaced with danger red")

	# 6. Shared tree ledger survives replacement
	mock_clock[0] = 30.0
	flash.set_flash_mode(FragrSettings.FLASHES_REDUCED)
	flash._history.clear()
	root.remove_meta("fragr_flash_history")
	flash.trigger("damage", MenuTheme.DANGER)
	mock_clock[0] = 30.1
	flash.trigger("damage", MenuTheme.DANGER)
	mock_clock[0] = 30.2
	flash.trigger("damage", MenuTheme.DANGER)
	flash.free()

	var flash2 = ScreenFlashScript.new()
	flash2.time_source = func() -> float: return mock_clock[0]
	root.add_child(flash2)
	mock_clock[0] = 30.3
	_check(not flash2.trigger("damage", MenuTheme.DANGER), "new ScreenFlash inherits tree history and enforces rate limit")
	flash2.free()

	root.remove_meta("fragr_flash_history")

	if _failures == 0:
		print("test_screen_flash: PASS rate limit, rolling window, off suppression, magenta prevention, and ledger sharing")
		quit(0)
	else:
		push_error("test_screen_flash: FAIL")
		quit(1)
