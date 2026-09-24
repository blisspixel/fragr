extends SceneTree
## The install check must reach the real fragr-server through LocalMatch, and
## LocalMatch must attach even when requested while the root is adding children.

class MissingServer extends LocalMatch:
	func executable_path() -> String:
		return ""

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_install_check: " + message)

func _run() -> void:
	var first: LocalMatch = LocalMatch.for_tree(self)
	_expect(LocalMatch.for_tree(self) == first, "a second request before attachment reuses the pending owner")
	await process_frame
	_expect(first.is_inside_tree() and root.get_node_or_null("LocalMatch") == first, "the owner attaches on the next frame")

	var results: Array[bool] = []
	var absent: MissingServer = MissingServer.new()
	var missing: InstallCheck = InstallCheck.new(absent)
	missing.quit_when_done = false
	missing.finished.connect(func(passed: bool) -> void: results.append(passed))
	root.add_child(missing)
	_expect(results == [false], "a missing server fails the check at once")
	missing.queue_free()
	absent.free()

	var run_dir: String = ProjectSettings.globalize_path("user://install-check-runs")
	DirAccess.make_dir_recursive_absolute(run_dir)
	OS.set_environment("FRAGR_RUN_DIR", run_dir)
	var check: InstallCheck = InstallCheck.new(first)
	check.quit_when_done = false
	check.finished.connect(func(passed: bool) -> void: results.append(passed))
	root.add_child(check)
	var deadline: int = Time.get_ticks_msec() + InstallCheck.TIMEOUT_MS + 2000
	while results.size() < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	OS.unset_environment("FRAGR_RUN_DIR")
	DirAccess.remove_absolute(run_dir)
	_expect(results == [false, true], "the built server answers a run preview")
	first.stop()
	check.queue_free()
	await process_frame
	if failures == 0:
		print("test_install_check: PASS")
	quit(0 if failures == 0 else 1)
