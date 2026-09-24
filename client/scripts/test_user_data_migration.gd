extends SceneTree

var failures: int = 0

func _initialize() -> void:
	var root_dir: String = ProjectSettings.globalize_path("user://migration-test-%d" % OS.get_process_id())
	var old_dir: String = root_dir.path_join(UserDataMigration.PREVIOUS_NAME)
	var new_dir: String = root_dir.path_join("fragr")
	_expect(UserDataMigration.previous_dir(new_dir) == old_dir, "the previous directory is the sibling named fragr Client")
	_expect(UserDataMigration.carry_forward(old_dir, new_dir).is_empty(), "no previous directory copies nothing")
	DirAccess.make_dir_recursive_absolute(old_dir)
	_write(old_dir.path_join("settings.cfg"), "[audio]\nmaster=0.5\n")
	_write(old_dir.path_join("service-record.0.json"), "{}")
	_write(old_dir.path_join("unrelated.txt"), "leave me")
	_expect(UserDataMigration.carry_forward(old_dir, old_dir).is_empty(), "a directory never copies onto itself")
	var copied: PackedStringArray = UserDataMigration.carry_forward(old_dir, new_dir)
	_expect(copied == PackedStringArray(["settings.cfg", "service-record.0.json"]), "settings and the record slot are copied: %s" % [copied])
	_expect(FileAccess.get_file_as_string(new_dir.path_join("settings.cfg")) == "[audio]\nmaster=0.5\n", "settings arrive byte for byte")
	_expect(not FileAccess.file_exists(new_dir.path_join("unrelated.txt")), "other files stay behind")
	_expect(FileAccess.file_exists(old_dir.path_join("settings.cfg")), "the old files stay in place")
	_write(old_dir.path_join("settings.cfg"), "[audio]\nmaster=0.1\n")
	_expect(UserDataMigration.carry_forward(old_dir, new_dir).is_empty(), "a second launch copies nothing")
	_expect(FileAccess.get_file_as_string(new_dir.path_join("settings.cfg")) == "[audio]\nmaster=0.5\n", "newer settings are never overwritten")
	for dir: String in [old_dir, new_dir]:
		for name: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(name))
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(root_dir)
	if failures == 0:
		print("test_user_data_migration: PASS")
	quit(0 if failures == 0 else 1)

func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_user_data_migration: " + message)
