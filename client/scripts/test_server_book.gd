extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_server_book: " + message)

func _run() -> void:
	var path: String = "user://test-server-book-%d.cfg" % OS.get_process_id()
	var book: ServerBook = ServerBook.new(path)
	_check(book.canonical("192.0.2.10") == "192.0.2.10:6767", "a bare host uses the game port")
	_check(book.canonical("ws://192.0.2.10:6767") == "192.0.2.10:6767", "a game URL stores as host and port")
	_check(book.canonical("http://192.0.2.10:6767").is_empty(), "an http URL is not a saved host")
	_check(book.keep("192.0.2.10"), "save accepts a host")
	_check(book.favorites == ["192.0.2.10:6767"], "save stores the canonical address once")
	_check(book.remember("192.0.2.11:6767"), "a new answered host is recent")
	_check(not book.remember("192.0.2.10:6767"), "a favorite checked again is not a new row")
	var rows: Array[Dictionary] = book.rows()
	_check(rows.size() == 2 and rows[0]["address"] == "192.0.2.10:6767" and rows[0]["kept"] \
		and rows[1]["address"] == "192.0.2.11:6767" and not rows[1]["kept"],
		"kept hosts lead, then recent ones")
	book.drop_address("192.0.2.10:6767")
	_check(book.rows().size() == 1 and book.rows()[0]["address"] == "192.0.2.11:6767", "drop removes that host only")
	var again: ServerBook = ServerBook.new(path)
	_check(again.recent == ["192.0.2.11:6767"] and again.favorites.is_empty(), "the book reloads from this computer")
	var junk: ServerBook = ServerBook.new(path + ".junk")
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("book", "favorites", "not a host\n192.0.2.12:6767\n192.0.2.12:6767")
	cfg.set_value("book", "recent", "192.0.2.13:1\n\nhttp://nope")
	_check(cfg.save(path + ".junk") == OK, "fixture book writes")
	junk.load_from_disk()
	_check(junk.favorites == ["192.0.2.12:6767"] and junk.recent == ["192.0.2.13:1"], "junk lines are dropped")
	var live: Dictionary = {"schema_version": 2, "kind": "arena", "map": "Arena Duel", "fighters": 4, "connections": 2, "mode": "tdm", "callsign": "VenueFox"}
	var detail: String = ServerBook.detail(live, 18)
	_check(detail.contains("Arena Duel") and detail.contains("4 fighters") and detail.ends_with("18 ms.") \
		and detail.contains(tr("MODE_TDM")) and not detail.contains("VenueFox") \
		and not detail.contains("different version"),
		"a row names the map, the count, the mode and the check time, and not a callsign")
	var matched: Dictionary = live.duplicate()
	matched["gameplay_version"] = 37
	matched["geometry_version"] = 2
	_check(not ServerBook.detail(matched, 18).contains("different version"), "a matching version stays quiet")
	var older: Dictionary = live.duplicate()
	older["gameplay_version"] = 1
	var older_detail: String = ServerBook.detail(older, 18)
	_check(older_detail.contains("This server speaks an older version.") and older_detail.ends_with("18 ms.") \
		and not older_detail.contains("SHA256SUMS.txt") and not older_detail.is_empty(),
		"an older server warns and still leaves a row")
	var ahead: Dictionary = live.duplicate()
	ahead["gameplay_version"] = 99
	var ahead_detail: String = ServerBook.detail(ahead, 18)
	_check(ahead_detail.contains("Update this client.") and ahead_detail.contains("https://github.com/blisspixel/fragr/releases/latest") \
		and ahead_detail.contains("SHA256SUMS.txt") and ahead_detail.ends_with("18 ms."),
		"a newer server names the release and its checksum")
	_check(ServerBook.detail({"schema_version": 1, "kind": "arena", "map": "Arena Duel", "fighters": 1, "connections": 1}).is_empty(),
		"schema 1 is not a row")
	live["mode"] = "unknown-future-mode"
	_check(ServerBook.detail(live).is_empty(), "an unreadable mode is not a row")
	var capped: ServerBook = ServerBook.new(path + ".cap")
	for n: int in 20:
		_check(capped.keep("203.0.113.%d" % (n + 1)), "save accepts host %d" % (n + 1))
	_check(capped.favorites.size() == ServerBook.MAX_FAVORITES and capped.favorites[0] == "203.0.113.20:6767",
		"favorites keep the twelve newest")
	var recent_book: ServerBook = ServerBook.new(path + ".recent")
	for n: int in 20:
		_check(recent_book.remember("198.51.100.%d" % (n + 1)), "a new host is recent")
	_check(recent_book.recent.size() == ServerBook.MAX_RECENT and recent_book.recent[0] == "198.51.100.20:6767",
		"recent keeps the eight newest")
	_check(ServerBook.beacon_port("FRAGR/1 6767\n".to_utf8_buffer()) == 6767, "beacon names 6767")
	_check(ServerBook.beacon_port("FRAGR/1 1\n".to_utf8_buffer()) == 1, "beacon names port 1")
	_check(ServerBook.beacon_port("FRAGR/1 65535\n".to_utf8_buffer()) == 65535, "beacon names the last port")
	var neighborhood: Array[String] = ServerBook.scan_targets([{"addresses": ["192.168.44.10", "::1", "127.0.0.1", "0.0.0.0", "224.0.0.1", "192.168.44.010", "192.0.2.10", "8.8.8.8", "169.254.169.254"]}], 6767)
	_check(neighborhood[0] == "127.0.0.1:6767" and neighborhood.size() == 255 \
		and "192.168.44.10:6767" in neighborhood and "192.168.44.1:6767" in neighborhood \
		and not "192.168.44.0:6767" in neighborhood and not "192.168.44.255:6767" in neighborhood \
		and neighborhood.find("192.168.44.10:6767") < neighborhood.find("192.168.44.1:6767") \
		and not "192.0.2.10:6767" in neighborhood and not "8.8.8.8:6767" in neighborhood \
		and not "169.254.169.254:6767" in neighborhood,
		"a scan checks this computer before the rest of its private /24")
	var apipa: Array[String] = ServerBook.scan_targets([{"addresses": ["169.254.169.10"]}], 6767)
	_check("169.254.169.10:6767" in apipa and not "169.254.169.254:6767" in apipa,
		"a link-local /24 does not probe the metadata host")
	_check(ServerBook.lan_beacon("192.168.44.46:6767") and ServerBook.lan_beacon("10.1.2.3:6767") \
		and not ServerBook.lan_beacon("192.0.2.10:6767") and not ServerBook.lan_beacon("169.254.169.254:80") \
		and not ServerBook.lan_beacon("8.8.8.8:6767"),
		"a beacon host is a private machine")
	_check(ServerBook.busy_body({"schema_version": 2, "busy": true}) \
		and not ServerBook.busy_body({"schema_version": 2}) and not ServerBook.busy_body({}),
		"only a fragr busy body counts")
	_check(ServerBook.scan_targets([], 0) == ["127.0.0.1:6767"], "an empty adapter list still checks loopback on the game port")
	_check(ServerBook.scan_targets([{"addresses": ["192.0.2.10"]}], 7777)[0] == "127.0.0.1:7777", "a typed port is the port that is scanned")
	var wide: Array = []
	for block: int in 5:
		wide.append({"addresses": ["10.%d.0.1" % block]})
	var capped_scan: Array[String] = ServerBook.scan_targets(wide, 6767)
	_check(capped_scan.size() == ServerBook.MAX_SCAN_TARGETS and "10.0.0.1:6767" in capped_scan,
		"a scan stops at the address cap")
	var answered: Dictionary = {"schema_version": 2, "kind": "arena", "map": "Arena Duel", "fighters": 4, "connections": 2, "mode": "tdm"}
	_check(ServerBook.probe_row(HTTPRequest.RESULT_SUCCESS, 200, answered, 12).contains("Arena Duel"), "a match line is a scan row")
	_check(ServerBook.probe_row(HTTPRequest.RESULT_SUCCESS, 503, {}, 0) == TranslationServer.translate("JOIN_BUSY"), "a busy host is a scan row")
	_check(ServerBook.probe_row(HTTPRequest.RESULT_CANT_CONNECT, 0, null, 0).is_empty(), "a closed port is not a scan row")
	for bad: String in ["FRAGR/1 6767", "FRAGR/1 6767\nextra", "FRAGR/1 0\n", "FRAGR/1 06767\n", "fragr/1 6767\n", "GET /status\n", "FRAGR/1 65536\n", ""]:
		_check(ServerBook.beacon_port(bad.to_utf8_buffer()) == 0, "reject beacon " + bad)
	for extra: String in [path, path + ".junk", path + ".cap", path + ".recent"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(extra))
	await _closed_port()
	if failures == 0:
		print("test_server_book: PASS")
	quit(0 if failures == 0 else 1)

func _closed_port() -> void:
	var scan: LanScan = LanScan.new()
	root.add_child(scan)
	var hits: Array[String] = []
	var state: Dictionary = {"done": false}
	scan.found.connect(func(address: String, _summary: String) -> void: hits.append(address))
	scan.finished.connect(func() -> void: state["done"] = true)
	scan.start(["127.0.0.1:1"])
	var started: int = Time.get_ticks_msec()
	while not state["done"] and Time.get_ticks_msec() - started < 3000:
		await process_frame
	_check(state["done"], "a closed port scan finishes")
	_check(hits.is_empty(), "a closed port is not a row: " + ", ".join(hits))
	scan.free()
