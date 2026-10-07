class_name ReleaseInstall
extends RefCounted

## Pure checks for the join-page offer. Join itself does not download anything.
## The player asks, then this client fetches the latest published desktop archive,
## matches it to SHA256SUMS.txt, and rejoins that host. The latest tag is not
## treated as proof that it speaks the server's gameplay version.

const API_URL: String = "https://api.github.com/repos/blisspixel/fragr/releases/latest"
const PAGE_URL: String = "https://github.com/blisspixel/fragr/releases/latest"
const SUMS_NAME: String = "SHA256SUMS.txt"
const PLATFORMS: PackedStringArray = ["windows-x86_64", "linux-x86_64", "macos-universal"]
const MANIFEST_LIMIT: int = 262144
const SUMS_LIMIT: int = 65536
const ARCHIVE_LIMIT: int = 1024 * 1024 * 1024
const UNPACK_LIMIT: int = ARCHIVE_LIMIT * 2
const MAX_ENTRIES: int = 512

const OFFER_NOTE: String = "Checks SHA256SUMS.txt, then rejoins this host. The latest published build may still be older than this server."
const CHECKING: String = "Checking the latest release."
const DOWNLOADING_SUMS: String = "Downloading the checksum."
const DOWNLOADING: String = "Downloading the latest client."
const MISMATCH: String = "The archive did not match SHA256SUMS.txt."
const NO_BUILD: String = "The latest release has no desktop build for this computer."
const UNREADABLE: String = "The latest release could not be read."
const UNREACHABLE: String = "Could not reach the releases page."
const NO_GAME: String = "The archive did not contain the game."
const BAD_ARCHIVE: String = "The archive was not a desktop package."
const TOO_LARGE: String = "The archive was larger than this client will install."
const REPLACING: String = "The checked build will replace this copy and rejoin this host."
const STARTED_BESIDE: String = "The checked build is opening and will rejoin this host."
const CHECK_AGAIN: String = "Check this host again before installing."
const OUTSIDE: String = "Could not choose a folder outside this checkout."
const PREPARE_FAILED: String = "Could not prepare the download."
const START_FAILED: String = "Could not start the checked build."

static func platform_id() -> String:
	if OS.has_feature("windows") and OS.has_feature("x86_64"):
		return "windows-x86_64"
	if OS.has_feature("linux") and OS.has_feature("x86_64"):
		return "linux-x86_64"
	if OS.has_feature("macos"):
		return "macos-universal"
	return ""

static func valid_tag(tag: String) -> bool:
	if not tag.begins_with("v") or tag.length() > 32:
		return false
	var parts: PackedStringArray = tag.substr(1).split(".", false)
	if parts.size() != 3:
		return false
	for part: String in parts:
		if part.is_empty() or part.length() > 4 or not part.is_valid_int() or str(int(part)) != part:
			return false
	return true

static func archive_name(tag: String, platform: String) -> String:
	if not valid_tag(tag) or platform not in PLATFORMS:
		return ""
	return "fragr-%s-%s.zip" % [tag, platform]

static func game_relative(platform: String) -> String:
	match platform:
		"windows-x86_64":
			return "fragr.exe"
		"linux-x86_64":
			return "fragr.x86_64"
		"macos-universal":
			return "fragr.app/Contents/MacOS/fragr"
		_:
			return ""

## Only the three published archives and SHA256SUMS.txt, on the releases host.
static func download_url(tag: String, filename: String) -> String:
	if not valid_tag(tag) or filename.contains("/") or filename.contains("\\") or filename.contains(".."):
		return ""
	var allowed: bool = filename == SUMS_NAME
	if not allowed:
		for platform: String in PLATFORMS:
			if filename == archive_name(tag, platform):
				allowed = true
	if not allowed:
		return ""
	return "https://github.com/blisspixel/fragr/releases/download/%s/%s" % [tag, filename]

static func api_headers() -> PackedStringArray:
	return PackedStringArray(["User-Agent: fragr", "Accept: application/vnd.github+json"])

static func file_headers() -> PackedStringArray:
	return PackedStringArray(["User-Agent: fragr"])

## Empty error means the manifest names a desktop archive for this platform.
## Download URLs are built here. A URL inside the JSON is ignored.
static func parse_release(body: String, platform: String) -> Dictionary:
	if platform not in PLATFORMS:
		return {"error": NO_BUILD}
	if body.length() > MANIFEST_LIMIT:
		return {"error": UNREADABLE}
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": UNREADABLE}
	var data: Dictionary = parsed
	var tag: String = str(data.get("tag_name", ""))
	if not valid_tag(tag):
		return {"error": UNREADABLE}
	var archive: String = archive_name(tag, platform)
	if archive.is_empty():
		return {"error": NO_BUILD}
	var assets: Variant = data.get("assets", null)
	if typeof(assets) != TYPE_ARRAY:
		return {"error": UNREADABLE}
	var have_archive: bool = false
	var have_sums: bool = false
	for item: Variant in assets:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var name: String = str((item as Dictionary).get("name", ""))
		if name == archive:
			have_archive = true
		elif name == SUMS_NAME:
			have_sums = true
	if not have_archive:
		return {"error": NO_BUILD}
	if not have_sums:
		return {"error": UNREADABLE}
	var archive_url: String = download_url(tag, archive)
	var sums_url: String = download_url(tag, SUMS_NAME)
	if archive_url.is_empty() or sums_url.is_empty():
		return {"error": UNREADABLE}
	return {
		"tag": tag,
		"archive": archive,
		"package": archive.trim_suffix(".zip"),
		"platform": platform,
		"archive_url": archive_url,
		"sums_url": sums_url,
	}

## The hash for `filename`, or empty when the line is missing or disagrees with itself.
static func checksum_for(sums_text: String, filename: String) -> String:
	if filename.is_empty() or filename.contains("/") or filename.contains("\\") or filename.contains("..") or filename.contains(" "):
		return ""
	var found: String = ""
	for raw: String in sums_text.split("\n", false):
		var line: String = raw.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.length() < 66:
			continue
		var hash: String = line.substr(0, 64).to_lower()
		if not _hex64(hash):
			continue
		var rest: String = line.substr(64)
		if not rest.begins_with(" ") and not rest.begins_with("\t"):
			continue
		if rest.strip_edges() != filename:
			continue
		if not found.is_empty() and found != hash:
			return ""
		found = hash
	return found

static func hashes_equal(actual: String, expected: String) -> bool:
	var left: String = actual.strip_edges().to_lower()
	var right: String = expected.strip_edges().to_lower()
	return _hex64(left) and left == right

static func file_matches(path: String, expected: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return hashes_equal(FileAccess.get_sha256(path), expected)

## Empty when the zip bytes match the named line. A mismatch does not unpack.
static func accept_archive(zip_path: String, sums_text: String, filename: String) -> String:
	var expected: String = checksum_for(sums_text, filename)
	if expected.is_empty() or not file_matches(zip_path, expected):
		return MISMATCH
	return ""

static func checked_extract(zip_path: String, sums_text: String, filename: String, dest_root: String, package_name: String, platform: String) -> String:
	var accepted: String = accept_archive(zip_path, sums_text, filename)
	if not accepted.is_empty():
		return accepted
	return extract(zip_path, dest_root, package_name, platform)

## Empty when every entry stayed inside the package folder and the game file is there.
static func extract(zip_path: String, dest_root: String, package_name: String, platform: String) -> String:
	var relative_game: String = package_name + "/" + game_relative(platform)
	if game_relative(platform).is_empty() or safe_relative(relative_game, package_name).is_empty():
		return BAD_ARCHIVE
	var reader: ZIPReader = ZIPReader.new()
	if reader.open(zip_path) != OK:
		return BAD_ARCHIVE
	var entries: PackedStringArray = reader.get_files()
	if entries.is_empty() or entries.size() > MAX_ENTRIES:
		reader.close()
		return BAD_ARCHIVE
	var saw_game: bool = false
	for entry: String in entries:
		var relative: String = safe_relative(entry, package_name)
		if relative.is_empty():
			reader.close()
			return BAD_ARCHIVE
		if relative == relative_game:
			saw_game = true
	if not saw_game:
		reader.close()
		return NO_GAME
	var root: String = dest_root.replace("\\", "/").simplify_path()
	if DirAccess.make_dir_recursive_absolute(root) != OK and not DirAccess.dir_exists_absolute(root):
		reader.close()
		return PREPARE_FAILED
	var unpacked: int = 0
	for entry: String in entries:
		var text: String = entry.replace("\\", "/")
		var relative: String = safe_relative(text, package_name)
		var target: String = root.path_join(relative).simplify_path()
		if not path_is_inside(target, root):
			reader.close()
			return BAD_ARCHIVE
		if text.ends_with("/"):
			if DirAccess.make_dir_recursive_absolute(target) != OK and not DirAccess.dir_exists_absolute(target):
				reader.close()
				return PREPARE_FAILED
			continue
		var parent: String = target.get_base_dir()
		if DirAccess.make_dir_recursive_absolute(parent) != OK and not DirAccess.dir_exists_absolute(parent):
			reader.close()
			return PREPARE_FAILED
		var bytes: PackedByteArray = reader.read_file(entry)
		unpacked += bytes.size()
		if unpacked > UNPACK_LIMIT or bytes.is_empty() and relative == relative_game:
			reader.close()
			return TOO_LARGE if unpacked > UNPACK_LIMIT else NO_GAME
		var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			reader.close()
			return PREPARE_FAILED
		file.store_buffer(bytes)
		file.close()
	reader.close()
	var game: String = root.path_join(relative_game).simplify_path()
	if not FileAccess.file_exists(game):
		return NO_GAME
	return ""

## Empty when `entry` is not a file or directory inside `package_name`.
static func safe_relative(entry: String, package_name: String) -> String:
	if package_name.is_empty() or package_name.contains("/") or package_name.contains("\\") or package_name.contains(".."):
		return ""
	var text: String = entry.replace("\\", "/").strip_edges()
	if text.ends_with("/"):
		text = text.trim_suffix("/")
	if text.is_empty() or text.begins_with("/") or text.contains(":"):
		return ""
	var parts: PackedStringArray = text.split("/", false)
	if parts.is_empty() or parts[0] != package_name:
		return ""
	for part: String in parts:
		if part.is_empty() or part == "." or part == ".." or part.contains(":") or part.contains("\\"):
			return ""
	return "/".join(parts)

## Repo root when the client directory sits in a source checkout. Otherwise empty.
static func blocked_root(client_dir: String, parent_has_cargo: bool, parent_has_git: bool) -> String:
	if not parent_has_cargo and not parent_has_git:
		return ""
	return client_dir.replace("\\", "/").simplify_path().trim_suffix("/").get_base_dir()

static func path_is_inside(path: String, root: String) -> bool:
	var left: String = _norm(path)
	var right: String = _norm(root)
	if left.is_empty() or right.is_empty():
		return false
	return left == right or left.begins_with(right + "/")

## Where an exported game may be replaced. Empty for the editor, Godot, or a checkout.
static func replace_directory(executable_path: String, editor: bool, blocked_roots: PackedStringArray) -> String:
	if editor:
		return ""
	var exe: String = executable_path.replace("\\", "/").simplify_path()
	var file: String = exe.get_file().to_lower()
	if file.contains("godot"):
		return ""
	var root: String = ""
	if file == "fragr.exe" or file == "fragr.x86_64":
		root = exe.get_base_dir()
	elif file == "fragr" and exe.get_base_dir().trim_suffix("/").ends_with("fragr.app/Contents/MacOS"):
		root = exe.get_base_dir().get_base_dir().get_base_dir().get_base_dir()
	else:
		return ""
	root = root.replace("\\", "/").simplify_path()
	if root.is_empty():
		return ""
	for blocked: String in blocked_roots:
		if path_is_inside(root, blocked):
			return ""
	return root

static func files_hold_editor(names: PackedStringArray) -> bool:
	for name: String in names:
		if str(name).get_file().to_lower().begins_with("godot"):
			return true
	return false

## Join boot for a fresh process. Empty unless `--rejoin` names a host.
static func rejoin_boot(user_args: PackedStringArray, player_name: String) -> Dictionary:
	var index: int = user_args.find("--rejoin")
	if index < 0 or index + 1 >= user_args.size():
		return {}
	var endpoint: Dictionary = ServerEndpoint.parse(user_args[index + 1])
	if endpoint.is_empty():
		return {}
	var name: String = player_name.strip_edges()
	if name.is_empty():
		name = "Player"
	return {
		"role": "human",
		"name": name,
		"host": str(endpoint["game_url"]),
		"hud_mode": "PLAYING",
		"mode": "join",
	}

## `beside` launches the unpacked copy. `replace` waits for this process to exit,
## then copies onto an exported install. The editor and a checkout stay beside.
static func handoff(executable_path: String, editor: bool, blocked_roots: PackedStringArray, install_files: PackedStringArray, pid: int, package_dir: String, host: String, platform: String) -> Dictionary:
	var relative: String = game_relative(platform)
	if relative.is_empty() or pid <= 0:
		return {"error": START_FAILED}
	var package: String = package_dir.replace("\\", "/").simplify_path()
	var beside: String = package.path_join(relative).simplify_path()
	var arguments: PackedStringArray = PackedStringArray(["--", "--rejoin", host])
	if not shell_safe(beside) or not shell_safe(host):
		return {"error": START_FAILED}
	var replace: String = replace_directory(executable_path, editor, blocked_roots)
	if not replace.is_empty() and files_hold_editor(install_files):
		replace = ""
	if replace.is_empty():
		return {"mode": "beside", "game": beside, "arguments": arguments, "script": "", "quit_after": not editor}
	var game: String = replace.path_join(relative).simplify_path()
	var script: String = replacement_script(platform, pid, package, replace, game, host)
	if script.is_empty():
		return {"mode": "beside", "game": beside, "arguments": arguments, "script": "", "quit_after": not editor}
	return {"mode": "replace", "game": game, "arguments": arguments, "script": script, "quit_after": true}

static func replacement_script(platform: String, pid: int, source: String, dest: String, game: String, host: String) -> String:
	if pid <= 0 or not shell_safe(source) or not shell_safe(dest) or not shell_safe(game) or not shell_safe(host):
		return ""
	if platform == "windows-x86_64":
		var win_source: String = source.replace("/", "\\")
		var win_dest: String = dest.replace("/", "\\")
		var win_game: String = game.replace("/", "\\")
		return "\r\n".join(PackedStringArray([
			"@echo off",
			"setlocal",
			":wait",
			"tasklist /FI \"PID eq %d\" /FO CSV /NH 2>nul | findstr /C:\"%d\" >nul" % [pid, pid],
			"if not errorlevel 1 (",
			"  ping -n 2 127.0.0.1 >nul",
			"  goto wait",
			")",
			"robocopy \"%s\" \"%s\" /E /R:10 /W:1 /NFL /NDL /NJH /NJS /nc /ns /np" % [win_source, win_dest],
			"if errorlevel 8 exit /b 1",
			"start \"\" \"%s\" -- --rejoin \"%s\"" % [win_game, host],
		])) + "\r\n"
	if platform != "linux-x86_64" and platform != "macos-universal":
		return ""
	var server: String = dest.path_join("fragr-server")
	if platform == "macos-universal":
		server = dest.path_join("fragr.app/Contents/MacOS/fragr-server")
	if not shell_safe(server):
		return ""
	var lines: PackedStringArray = PackedStringArray([
		"#!/bin/sh",
		"if [ -z \"$FRAGR_HANDOFF\" ]; then",
		"  FRAGR_HANDOFF=1",
		"  export FRAGR_HANDOFF",
		"  (trap '' HUP; exec \"$0\") </dev/null >/dev/null 2>&1 &",
		"  exit 0",
		"fi",
		"while kill -0 %d 2>/dev/null; do" % pid,
		"  sleep 1",
		"done",
		"cp -a \"%s/.\" \"%s/\"" % [source, dest],
		"chmod +x \"%s\" \"%s\"" % [game, server],
	])
	if platform == "macos-universal":
		var app: String = dest.path_join("fragr.app")
		if not shell_safe(app):
			return ""
		# A copied download can keep the quarantine flag. Clearing it is not required to succeed.
		lines.append("xattr -dr com.apple.quarantine \"%s\" || true" % app)
	lines.append("exec \"%s\" -- --rejoin \"%s\"" % [game, host])
	lines.append("")
	return "\n".join(lines)

static func shell_safe(text: String) -> bool:
	if text.is_empty() or text.length() > 512:
		return false
	# A trailing separator becomes a backslash before the closing quote, and
	# cmd treats that backslash as escaping the quote. A bare drive letter
	# is the current directory on that drive, not the install folder.
	if text.ends_with("/") or text.ends_with("\\"):
		return false
	if text.length() == 2 and text.unicode_at(1) == 58:
		var drive: int = text.unicode_at(0)
		if (drive >= 65 and drive <= 90) or (drive >= 97 and drive <= 122):
			return false
	for index: int in text.length():
		var code: int = text.unicode_at(index)
		if code < 32 or code == 127:
			return false
		if code == 34 or code == 37 or code == 38 or code == 39 or code == 36 or code == 33 \
			or code == 60 or code == 62 or code == 94 or code == 96 or code == 124:
			return false
	return true

static func _hex64(hash: String) -> bool:
	if hash.length() != 64:
		return false
	for index: int in hash.length():
		var code: int = hash.unicode_at(index)
		var digit: bool = (code >= 48 and code <= 57) or (code >= 97 and code <= 102)
		if not digit:
			return false
	return true

static func _norm(path: String) -> String:
	var text: String = path.replace("\\", "/").simplify_path().trim_suffix("/")
	if OS.has_feature("windows") or OS.has_feature("macos"):
		text = text.to_lower()
	return text
