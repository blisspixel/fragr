extends SceneTree

## Brief native-window check. Run explicitly on a desktop, never in the headless
## suite. The normal visual tour does not capture the pointer at all.
var _failures: int = 0

func _initialize() -> void:
	auto_accept_quit = false
	call_deferred("_run")

func _finalize() -> void:
	MouseCapture.release()

func _check(expected: Input.MouseMode, label: String) -> void:
	if Input.mouse_mode != expected:
		_failures += 1
		push_error("qa_pointer: " + label)
	print("qa_pointer: %s mode=%d" % [label, Input.mouse_mode])

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(480, 320)
	root.title = "fragr input check"
	await process_frame
	var capture: MouseCapture = MouseCapture.new()
	root.add_child(capture)
	root.grab_focus()
	await create_timer(0.15).timeout
	capture.set_gameplay(true)
	await create_timer(0.15).timeout
	_check(Input.MOUSE_MODE_CAPTURED, "focused game captures")
	root.focus_exited.emit()
	_check(Input.MOUSE_MODE_VISIBLE, "focus loss releases")
	root.focus_entered.emit()
	_check(Input.MOUSE_MODE_CAPTURED, "focused game resumes")
	capture.set_gameplay(false)
	_check(Input.MOUSE_MODE_VISIBLE, "overlay releases")
	capture.set_gameplay(true)
	root.close_requested.emit()
	capture.set_gameplay(true)
	root.focus_entered.emit()
	_check(Input.MOUSE_MODE_VISIBLE, "close prevents recapture")
	capture.queue_free()
	await process_frame
	var replacement: MouseCapture = MouseCapture.new()
	root.add_child(replacement)
	replacement.set_gameplay(true)
	_check(Input.MOUSE_MODE_CAPTURED, "replacement match captures")
	replacement.queue_free()
	await process_frame
	_check(Input.MOUSE_MODE_VISIBLE, "scene exit releases")
	await RenderingServer.frame_post_draw
	if _failures == 0:
		print("qa_pointer: PASS native pointer lifecycle")
	quit(0 if _failures == 0 else 1)
