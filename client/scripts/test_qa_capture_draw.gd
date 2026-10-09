extends "res://scripts/qa_tour.gd"

func _run() -> void:
	# Headless validation must never synthesize renderer work. The minimized
	# image and paused HUD controls require the separate rendered evidence.
	if DisplayServer.get_name() != "headless":
		push_error("test_qa_capture_draw: run with --headless")
		quit(1)
		return
	for _index: int in 8:
		super._process(0.5)
		await process_frame
	if _capture_forced_draws != 0:
		push_error("test_qa_capture_draw: headless capture requested a draw")
		quit(1)
		return
	print("test_qa_capture_draw: PASS (actual headless capture callback requests zero draws)")
	quit(0)
