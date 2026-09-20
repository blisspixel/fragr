extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_mouse_capture: " + message)

func _run() -> void:
	# State transitions are testable without confining the tester's desktop.
	var capture: MouseCapture = MouseCapture.new()
	capture.set_gameplay(true)
	_check(capture.desired_mode() == Input.MOUSE_MODE_VISIBLE, "unfocused startup stays released")
	capture._automated = true
	capture._focus_entered()
	_check(capture.desired_mode() == Input.MOUSE_MODE_VISIBLE and capture.gameplay_input_allowed(), "automation plays without desktop capture")
	if DisplayServer.get_name() == "headless":
		capture._automated = false
		_check(capture.desired_mode() == Input.MOUSE_MODE_CAPTURED, "focused gameplay requests capture")
		capture.set_gameplay(false)
		_check(capture.desired_mode() == Input.MOUSE_MODE_VISIBLE, "menus release the pointer")
		capture.set_gameplay(true)
		capture._focus_exited()
		_check(capture.desired_mode() == Input.MOUSE_MODE_VISIBLE and not capture.gameplay_input_allowed(), "focus loss releases and stops gameplay input")
		capture._focus_entered()
		_check(capture.desired_mode() == Input.MOUSE_MODE_CAPTURED, "focus recovery respects gameplay request")
	capture._close_requested()
	capture.set_gameplay(true)
	capture._focus_entered()
	_check(capture.desired_mode() == Input.MOUSE_MODE_VISIBLE and not capture.gameplay_input_allowed(), "closing cannot recapture on a late frame or focus event")
	capture.free()
	set_meta("fragr_automated", true)
	var scene_capture: MouseCapture = MouseCapture.new()
	root.add_child(scene_capture)
	scene_capture.set_gameplay(true)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "automated scene leaves the desktop pointer free")
	scene_capture.queue_free()
	await process_frame
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "scene teardown releases the pointer")
	remove_meta("fragr_automated")
	if _failures == 0:
		print("test_mouse_capture: PASS startup, menus, focus, automation, close and teardown")
	quit(0 if _failures == 0 else 1)
