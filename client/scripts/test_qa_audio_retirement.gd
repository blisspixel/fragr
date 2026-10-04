extends SceneTree

const TOUR = preload("res://scripts/qa_tour.gd")
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_qa_audio_retirement: " + message)

func _run() -> void:
	var voice: AudioStreamPlayer = AudioStreamPlayer.new()
	voice.stream = load(L07Assets.CURFEW_CHIME_SOUND) as AudioStreamWAV
	root.add_child(voice)
	voice.play()
	await process_frame
	_check(voice.has_stream_playback(), "real committed chime creates a playback")
	if not voice.has_stream_playback():
		voice.free()
		quit(1)
		return
	var original: WeakRef = weakref(voice.get_stream_playback())
	_check(not TOUR.audio_reference_retired(original), "live playback remains owned")
	# Replace a live playback, then remove its owner, as a repeated chime and a
	# map handoff do. Both retiring playback references must actually release.
	voice.stop()
	voice.play()
	await process_frame
	var replacement: WeakRef = weakref(voice.get_stream_playback())
	_check(not TOUR.audio_reference_retired(replacement), "replacement playback remains owned")
	voice.stop()
	voice.stream = null
	voice.queue_free()
	await process_frame
	var deadline: int = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline and (not TOUR.audio_reference_retired(original)
			or not TOUR.audio_reference_retired(replacement)):
		await create_timer(0.01).timeout
	_check(TOUR.audio_reference_retired(original) and TOUR.audio_reference_retired(replacement),
		"both actual stopped playbacks release within the unchanged two-second bound")
	if _failures == 0:
		print("test_qa_audio_retirement: PASS real repeated playback, stopped owner, synchronous weak-reference checks and bounded release")
	quit(0 if _failures == 0 else 1)
