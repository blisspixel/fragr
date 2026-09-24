class_name UserDataMigration
extends RefCounted
## Until the 2026-09 desktop packages the project was named "fragr Client", and
## Godot keys the user:// directory to that name. The first launch under the
## new name copies settings and the service record from the old directory, once,
## and only when the new directory has neither. The old files stay in place.

const PREVIOUS_NAME: String = "fragr Client"
const FILES: Array[String] = ["settings.cfg", "service-record.0.json", "service-record.1.json"]

static func previous_dir(current: String) -> String:
	return current.get_base_dir().path_join(PREVIOUS_NAME)

static func carry_forward(from_dir: String, to_dir: String) -> PackedStringArray:
	var copied: PackedStringArray = PackedStringArray()
	if from_dir.simplify_path() == to_dir.simplify_path() or not DirAccess.dir_exists_absolute(from_dir):
		return copied
	for name: String in FILES:
		if FileAccess.file_exists(to_dir.path_join(name)):
			return copied
	if DirAccess.make_dir_recursive_absolute(to_dir) != OK:
		return copied
	for name: String in FILES:
		var source: String = from_dir.path_join(name)
		if FileAccess.file_exists(source) and DirAccess.copy_absolute(source, to_dir.path_join(name)) == OK:
			copied.append(name)
	return copied

static func run_for(tree: SceneTree) -> void:
	# Harnesses isolate settings and records; they must never touch a player's files.
	if tree.get_meta("fragr_automated", false) or tree.has_meta("fragr_settings_path") or tree.has_meta("fragr_records_path"):
		return
	var current: String = OS.get_user_data_dir()
	var copied: PackedStringArray = carry_forward(previous_dir(current), current)
	if not copied.is_empty():
		print("fragr: carried %s forward from %s" % [", ".join(copied), previous_dir(current)])
