extends SceneTree

## Fixture checks for the install offer. No network and no process launch.

const NetworkScript = preload("res://scripts/net_client.gd")

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_release_install: " + message)

func _run() -> void:
	_check_contract()
	_check_manifest()
	_check_checksum_and_extract()
	_check_handoff()
	_check_rejoin()
	if failures == 0:
		print("test_release_install: PASS")
	quit(0 if failures == 0 else 1)

func _check_contract() -> void:
	_check(ReleaseInstall.PAGE_URL == NetworkScript.RELEASES_URL, "the offer and the refusal sentence name the same page")
	_check(ReleaseInstall.platform_id() != "", "this computer has a published desktop package")
	_check(ReleaseInstall.archive_name("v0.78.0", "windows-x86_64") == "localexception-v0.78.0-windows-x86_64.zip", "windows archive name")
	_check(ReleaseInstall.archive_name("v0.78.0", "linux-x86_64") == "localexception-v0.78.0-linux-x86_64.zip", "linux archive name")
	_check(ReleaseInstall.archive_name("v0.78.0", "macos-universal") == "localexception-v0.78.0-macos-universal.zip", "macOS archive name")
	_check(ReleaseInstall.archive_name("v0.78", "windows-x86_64").is_empty(), "a short tag is not an archive name")
	_check(ReleaseInstall.archive_name("../v0.1.0", "windows-x86_64").is_empty(), "a tag cannot climb out of the download path")
	_check(ReleaseInstall.download_url("v0.78.0", "localexception-v0.78.0-windows-x86_64.zip") == "https://github.com/blisspixel/fragr/releases/download/v0.78.0/localexception-v0.78.0-windows-x86_64.zip", "archive URL is the published object")
	_check(ReleaseInstall.download_url("v0.78.0", "SHA256SUMS.txt").begins_with("https://github.com/blisspixel/fragr/releases/download/v0.78.0/"), "checksum URL stays on the release")
	_check(ReleaseInstall.download_url("v0.78.0", "https://evil.example/steal.zip").is_empty(), "a foreign name is not a download")
	_check(ReleaseInstall.safe_relative("localexception-v0.0.1-windows-x86_64/localexception.exe", "localexception-v0.0.1-windows-x86_64") == "localexception-v0.0.1-windows-x86_64/localexception.exe", "a package file stays relative")
	_check(ReleaseInstall.safe_relative("localexception-v0.0.1-windows-x86_64/../../outside.txt", "localexception-v0.0.1-windows-x86_64").is_empty(), "a parent segment is rejected")
	_check(ReleaseInstall.safe_relative("/tmp/outside.txt", "localexception-v0.0.1-windows-x86_64").is_empty(), "an absolute entry is rejected")
	_check(ReleaseInstall.safe_relative("C:/Windows/system32/x", "localexception-v0.0.1-windows-x86_64").is_empty(), "a drive entry is rejected")
	_check(ReleaseInstall.blocked_root("C:/GitHub/localexception/client", true, true) == "C:/GitHub/localexception", "a client directory blocks its checkout")
	_check(ReleaseInstall.blocked_root("C:/Games/localexception", false, false).is_empty(), "an install directory is not a checkout")
	_check(ReleaseInstall.replace_directory("C:/Users/Nick Seal/Tools/Godot_v4.7.2/Godot_v4.7.2-stable_win64.exe", false, PackedStringArray(["C:/GitHub/localexception"])).is_empty(), "the editor binary is not an install")
	_check(ReleaseInstall.replace_directory("C:/GitHub/localexception/build/localexception.exe", false, PackedStringArray(["C:/GitHub/localexception"])).is_empty(), "a checkout copy is not replaced")
	_check(ReleaseInstall.replace_directory("C:/Games/localexception/localexception.exe", true, PackedStringArray()).is_empty(), "editor play does not replace a folder")
	_check(ReleaseInstall.replace_directory("C:/Games/localexception/localexception.exe", false, PackedStringArray(["C:/GitHub/localexception"])) == "C:/Games/localexception", "an exported Windows folder can be replaced")
	_check(ReleaseInstall.replace_directory("/opt/localexception/localexception.x86_64", false, PackedStringArray(["/src/localexception"])) == "/opt/localexception", "an exported Linux folder can be replaced")
	_check(ReleaseInstall.replace_directory("/Applications/LocalException/Local Exception.app/Contents/MacOS/Local Exception", false, PackedStringArray()).replace("\\", "/") == "/Applications/LocalException", "an exported macOS folder is the app's parent")
	_check(ReleaseInstall.files_hold_editor(PackedStringArray(["localexception.exe", "localexception-server.exe"])) == false, "a package directory is not the editor")
	_check(ReleaseInstall.files_hold_editor(PackedStringArray(["Godot_v4.7.2-stable_win64.exe"])), "a Godot executable blocks replacement")
	_check(not ServerBook.client_is_behind({"schema_version": 2}), "a missing version is not behind")
	_check(ServerBook.client_is_behind({"gameplay_version": 99}), "a higher gameplay version is behind")
	_check(not ServerBook.client_is_behind({"gameplay_version": 1}), "an older server is not this client's update")

func _check_manifest() -> void:
	var body: String = JSON.stringify({
		"tag_name": "v0.78.0",
		"assets": [
			{"name": "localexception-v0.78.0-windows-x86_64.zip", "browser_download_url": "https://evil.example/steal.zip"},
			{"name": "SHA256SUMS.txt", "browser_download_url": "https://evil.example/sums"},
		],
	})
	var parsed: Dictionary = ReleaseInstall.parse_release(body, "windows-x86_64")
	_check(parsed.get("archive_url", "") == "https://github.com/blisspixel/fragr/releases/download/v0.78.0/localexception-v0.78.0-windows-x86_64.zip", "the manifest URL is not taken from the JSON")
	_check(not str(parsed.get("archive_url", "")).contains("evil.example") and not str(parsed.get("sums_url", "")).contains("evil.example"), "a foreign asset URL is ignored")
	_check(ReleaseInstall.parse_release(body, "linux-x86_64").get("error", "") == ReleaseInstall.NO_BUILD, "a platform missing from the release is refused")
	var bad_tag: String = JSON.stringify({"tag_name": "v0.78.0/../../etc", "assets": []})
	_check(ReleaseInstall.parse_release(bad_tag, "windows-x86_64").get("error", "") == ReleaseInstall.UNREADABLE, "a tag with a slash is not a release")

func _check_checksum_and_extract() -> void:
	var root: String = ProjectSettings.globalize_path("user://release-install-test-%d" % OS.get_process_id())
	_remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	var package: String = "localexception-v0.0.1-windows-x86_64"
	var zip_path: String = root.path_join(package + ".zip")
	var packer: ZIPPacker = ZIPPacker.new()
	var opened: Error = packer.open(zip_path)
	_check(opened == OK, "fixture archive opens")
	if opened != OK:
		_remove_tree(root)
		return
	packer.start_file(package + "/localexception.exe")
	packer.write_file("game-bytes".to_utf8_buffer())
	packer.close_file()
	packer.start_file(package + "/localexception-server.exe")
	packer.write_file("server-bytes".to_utf8_buffer())
	packer.close_file()
	packer.start_file(package + "/licenses/localexception-LICENSE.txt")
	packer.write_file("license".to_utf8_buffer())
	packer.close_file()
	packer.close()
	var digest: String = FileAccess.get_sha256(zip_path)
	var sums: String = "%s  %s\n%s  other.zip\n" % [digest, package + ".zip", "b".repeat(64)]
	_check(ReleaseInstall.checksum_for(sums, package + ".zip") == digest, "two-space checksum line matches the archive")
	_check(ReleaseInstall.checksum_for("%s %s\n" % [digest, package + ".zip"], package + ".zip") == digest, "one-space checksum line matches the archive")
	_check(ReleaseInstall.checksum_for(sums, "../" + package + ".zip").is_empty(), "a checksum name cannot climb")
	var conflict: String = "%s  %s\n%s  %s\n" % [digest, package + ".zip", "c".repeat(64), package + ".zip"]
	_check(ReleaseInstall.checksum_for(conflict, package + ".zip").is_empty(), "two hashes for one archive are refused")
	var bad_dest: String = root.path_join("bad")
	_check(ReleaseInstall.checked_extract(zip_path, "%s  %s\n" % ["d".repeat(64), package + ".zip"], package + ".zip", bad_dest, package, "windows-x86_64") == ReleaseInstall.MISMATCH, "a wrong hash is a mismatch")
	_check(not DirAccess.dir_exists_absolute(bad_dest), "a mismatch does not unpack")
	var good_dest: String = root.path_join("good")
	_check(ReleaseInstall.checked_extract(zip_path, sums, package + ".zip", good_dest, package, "windows-x86_64").is_empty(), "a matching archive unpacks")
	var game: String = good_dest.path_join(package).path_join("localexception.exe")
	_check(FileAccess.file_exists(game) and FileAccess.get_file_as_string(game) == "game-bytes", "the game file is the archived bytes")
	_check(not FileAccess.file_exists(root.path_join("outside.txt")), "unpack does not write beside the destination")
	var slipped: String = root.path_join("slipped.zip")
	var slip: ZIPPacker = ZIPPacker.new()
	if slip.open(slipped) == OK:
		var parent_entry: Error = slip.start_file(package + "/../../outside.txt")
		if parent_entry == OK:
			slip.write_file("nope".to_utf8_buffer())
			slip.close_file()
		slip.start_file(package + "/localexception.exe")
		slip.write_file("game-bytes".to_utf8_buffer())
		slip.close_file()
		slip.close()
		if parent_entry == OK:
			var slip_digest: String = FileAccess.get_sha256(slipped)
			var slip_sums: String = "%s  slipped.zip\n" % slip_digest
			var slip_dest: String = root.path_join("slip-dest")
			var slip_error: String = ReleaseInstall.checked_extract(slipped, slip_sums, "slipped.zip", slip_dest, package, "windows-x86_64")
			_check(slip_error == ReleaseInstall.BAD_ARCHIVE, "a parent entry is not installed")
			_check(not FileAccess.file_exists(root.path_join("outside.txt")) and not FileAccess.file_exists(root.get_base_dir().path_join("outside.txt")), "a parent entry is not written")
	_remove_tree(root)

func _check_handoff() -> void:
	var blocked: PackedStringArray = PackedStringArray(["C:/GitHub/localexception"])
	var files: PackedStringArray = PackedStringArray(["localexception.exe", "localexception-server.exe"])
	var host: String = "ws://192.168.44.46:6767"
	var package: String = "C:/Users/Nick Seal/AppData/localexception/releases/offer-1/localexception-v0.78.0-windows-x86_64"
	var plan: Dictionary = ReleaseInstall.handoff("C:/Games/localexception/localexception.exe", false, blocked, files, 4242, package, host, "windows-x86_64")
	var script: String = str(plan.get("script", ""))
	_check(plan.get("mode", "") == "replace" and plan.get("quit_after", false) == true, "an exported game is replaced after it exits")
	_check(script.find("tasklist") >= 0 and script.find("tasklist") < script.find("robocopy") and script.find("robocopy") < script.find("--rejoin"), "replacement waits, then copies, then rejoins")
	_check(script.contains("4242") and script.contains(host) and script.contains("--rejoin"), "the handoff names this process and this host")
	_check(not script.contains("C:/GitHub/localexception") and not script.to_lower().contains("godot"), "the handoff does not copy onto the checkout or the editor")
	_check(plan.get("arguments", PackedStringArray()) == PackedStringArray(["--", "--rejoin", host]), "rejoin is a user argument")
	var editor_plan: Dictionary = ReleaseInstall.handoff("C:/Games/localexception/localexception.exe", true, blocked, files, 4242, package, host, "windows-x86_64")
	_check(editor_plan.get("mode", "") == "beside" and str(editor_plan.get("script", "")).is_empty() and editor_plan.get("quit_after", true) == false, "the editor stays up and is not replaced")
	var godot_plan: Dictionary = ReleaseInstall.handoff("C:/Users/Nick Seal/Tools/Godot_v4.7.2/Godot_v4.7.2-stable_win64.exe", false, blocked, PackedStringArray(), 7, package, host, "windows-x86_64")
	_check(godot_plan.get("mode", "") == "beside" and str(godot_plan.get("game", "")).ends_with("localexception.exe") and not str(godot_plan.get("game", "")).to_lower().contains("godot"), "a Godot run launches the unpacked game")
	var checkout: Dictionary = ReleaseInstall.handoff("C:/GitHub/localexception/build/localexception.exe", false, blocked, files, 8, package, host, "windows-x86_64")
	_check(checkout.get("mode", "") == "beside" and str(checkout.get("script", "")).is_empty(), "a source build is not overwritten")
	var tools: Dictionary = ReleaseInstall.handoff("C:/Tools/localexception.exe", false, PackedStringArray(), PackedStringArray(["localexception.exe", "Godot_v4.7.2-stable_win64.exe"]), 9, package, host, "windows-x86_64")
	_check(tools.get("mode", "") == "beside" and str(tools.get("script", "")).is_empty(), "a folder that holds Godot is not replaced")
	var drive_root: Dictionary = ReleaseInstall.handoff("C:/localexception.exe", false, PackedStringArray(), PackedStringArray(["localexception.exe"]), 11, package, host, "windows-x86_64")
	_check(drive_root.get("mode", "") == "beside" and str(drive_root.get("script", "")).is_empty(), "a drive-root install is not written by cmd")
	var linux: Dictionary = ReleaseInstall.handoff("/opt/localexception/localexception.x86_64", false, PackedStringArray(["/src/localexception"]), PackedStringArray(["localexception.x86_64", "localexception-server"]), 99, "/tmp/localexception-releases/offer-1/localexception-v0.78.0-linux-x86_64", "ws://127.0.0.1:6767", "linux-x86_64")
	var linux_script: String = str(linux.get("script", ""))
	_check(linux.get("mode", "") == "replace" and linux_script.find("kill -0 99") >= 0 and linux_script.find("kill -0") < linux_script.find("cp -a") and linux_script.find("cp -a") < linux_script.find("--rejoin"), "a Linux replacement waits before it copies")

func _check_rejoin() -> void:
	var boot: Dictionary = ReleaseInstall.rejoin_boot(PackedStringArray(["--rejoin", "192.168.44.46:6767"]), "Meat Proxy")
	_check(boot.get("mode", "") == "join" and boot.get("role", "") == "human" and boot.get("hud_mode", "") == "PLAYING", "rejoin enters as the player")
	_check(boot.get("host", "") == "ws://192.168.44.46:6767" and boot.get("name", "") == "Meat Proxy", "rejoin keeps the host and the callsign")
	_check(ReleaseInstall.rejoin_boot(PackedStringArray(["--check-install"]), "Meat Proxy").is_empty(), "install check is not a rejoin")
	_check(ReleaseInstall.rejoin_boot(PackedStringArray(["--rejoin", "not a host"]), "Meat Proxy").is_empty(), "an unreadable rejoin host is ignored")

func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub: String in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
