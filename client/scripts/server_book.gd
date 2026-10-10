class_name ServerBook
extends RefCounted

## Hosts this computer remembers. Favorites are kept on purpose. Recent hosts
## are the ones whose match line came back. Nothing here is an account, and
## the file never stores a ticket, a callsign, or a status body.

const PATH: String = "user://servers.cfg"
const MAX_FAVORITES: int = 12
const MAX_RECENT: int = 8
## Godot does not report a prefix, so a scan stays inside each adapter's /24.
const MAX_SCAN_TARGETS: int = 1024
const NetworkScript = preload("res://scripts/net_client.gd")

## Empty when the host omitted its versions or they match this client.
## A mismatch is a warning. It does not by itself refuse the row.
static func version_note(data: Dictionary) -> String:
	if client_is_behind(data):
		return "Update this client. " + NetworkScript.release_check()
	if _advertised_differs(data, "gameplay_version", int(NetworkScript.GAMEPLAY_VERSION)) \
		or _advertised_differs(data, "geometry_version", MapGeometry.VERSION):
		return "This server speaks an older version."
	return ""

## True when the host advertises a gameplay or geometry version above this client.
static func client_is_behind(data: Dictionary) -> bool:
	return _client_is_behind(data, "gameplay_version", int(NetworkScript.GAMEPLAY_VERSION)) \
		or _client_is_behind(data, "geometry_version", MapGeometry.VERSION)

static func _client_is_behind(data: Dictionary, key: String, expected: int) -> bool:
	if not data.has(key) or not EquipmentState.integer(data.get(key), 4294967295):
		return false
	return int(data[key]) > expected

static func _advertised_differs(data: Dictionary, key: String, expected: int) -> bool:
	if not data.has(key) or not EquipmentState.integer(data.get(key), 4294967295):
		return false
	return int(data[key]) != expected

var storage_path: String
var favorites: Array[String] = []
var recent: Array[String] = []

static func for_tree(tree: SceneTree, settings_path: String = "") -> ServerBook:
	var path: String = str(tree.get_meta("fragr_server_book_path", ""))
	if path.is_empty() and not settings_path.is_empty() and settings_path != FragrSettings.PATH:
		path = settings_path + ".servers"
	if path.is_empty():
		path = PATH
	return ServerBook.new(path)

func _init(path: String = PATH) -> void:
	storage_path = path
	load_from_disk()

## Full game URL, including scheme. An old host:port line loads as cleartext ws.
static func canonical(value: String) -> String:
	var endpoint: Dictionary = ServerEndpoint.parse(value)
	if endpoint.is_empty():
		return ""
	return str(endpoint["game_url"])

## Game port inside a LAN presence packet, or 0 when the packet is not one.
static func beacon_port(packet: PackedByteArray) -> int:
	var text: String = packet.get_string_from_utf8()
	var prefix: String = "FRAGR/1 "
	if not text.begins_with(prefix) or text.count("\n") != 1 or not text.ends_with("\n"):
		return 0
	var port_text: String = text.substr(prefix.length(), text.length() - prefix.length() - 1)
	if port_text.is_empty() or port_text.length() > 5 or not port_text.is_valid_int():
		return 0
	if str(port_text.to_int()) != port_text or port_text.to_int() < 1 or port_text.to_int() > 65535:
		return 0
	return port_text.to_int()

## Short row text for a schema 2 match line. Empty when Watch and Join must stay shut.
static func detail(parsed: Variant, ping_ms: int = -1) -> String:
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var data: Dictionary = parsed
	if not EquipmentState.integer(data.get("schema_version"), 2) or data["schema_version"] != 2:
		return ""
	if not data.get("kind") is String or not data.get("map") is String:
		return ""
	if not EquipmentState.integer(data.get("fighters"), 4294967295):
		return ""
	if not EquipmentState.integer(data.get("connections"), 4294967295):
		return ""
	var kind: String = str(data["kind"])
	var map_name: String = str(data["map"])
	var fighters: int = int(data["fighters"])
	var connections: int = int(data["connections"])
	if (kind != "arena" and kind != "campaign") or map_name.is_empty() or fighters < 0 or connections < 0:
		return ""
	var line: String = "%s. %d fighters." % [map_name, fighters]
	if kind == "campaign":
		line = "%s. Mission. %d fighters." % [map_name, fighters]
	if kind == "arena" and data.has("mode"):
		var rules: Dictionary = MatchRules.parse({"mode": data.get("mode", "ffa"), "mutators": data.get("mutators", [])})
		if rules.is_empty():
			return ""
		line += " " + MatchRules.chip_text(rules)
	var note: String = version_note(data)
	if not note.is_empty():
		line += " " + note
	if ping_ms >= 0:
		line += " %d ms." % ping_ms
	return line

## Empty unless this reply is a server row. A timeout is not a row.
static func probe_row(result: int, code: int, parsed: Variant, ping_ms: int) -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		return ""
	if code == 503:
		return TranslationServer.translate("JOIN_BUSY")
	if code != 200:
		return ""
	return detail(parsed, ping_ms)

## Private, link-local, or the shared 100.64/10 overlay. Not a public address,
## and not the cloud metadata host.
static func lan_ipv4(ip: String) -> bool:
	var octets: PackedInt32Array = _ipv4_octets(ip)
	if octets.size() != 4:
		return false
	if octets[0] == 10:
		return true
	if octets[0] == 192 and octets[1] == 168:
		return true
	if octets[0] == 172 and octets[1] >= 16 and octets[1] <= 31:
		return true
	if octets[0] == 100 and octets[1] >= 64 and octets[1] <= 127:
		return true
	if octets[0] == 169 and octets[1] == 254:
		return not (octets[2] == 169 and octets[3] == 254)
	return false

## A beacon source worth probing. Public and metadata addresses are not.
static func lan_beacon(address: String) -> bool:
	var endpoint: Dictionary = ServerEndpoint.parse(address)
	if endpoint.is_empty():
		return false
	return lan_ipv4(str(endpoint["host"]))

## The busy body this server sends. Any other 503 is not a match.
static func busy_body(parsed: Variant) -> bool:
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	return data.get("schema_version") == 2 and data.get("busy") == true

## Loopback, this computer's private IPv4 addresses, then the rest of each /24.
## Wider networks are not guessed. The list stops at MAX_SCAN_TARGETS.
static func scan_targets(interfaces: Array, port: int) -> Array[String]:
	var game_port: int = port if port >= 1 and port <= 65535 else 6767
	var seen: Dictionary = {}
	var ordered: Array[String] = []
	var extras: Array[String] = []
	_append_target(ordered, seen, "127.0.0.1", game_port)
	for iface: Variant in interfaces:
		if not iface is Dictionary:
			continue
		var addresses: Variant = iface.get("addresses", [])
		if addresses is PackedStringArray:
			for raw: String in addresses:
				_consider_scan_address(ordered, extras, seen, raw, game_port)
		elif addresses is Array:
			for raw: Variant in addresses:
				_consider_scan_address(ordered, extras, seen, str(raw), game_port)
	for neighbor: String in extras:
		_append_target(ordered, seen, neighbor, game_port)
	return ordered

static func _consider_scan_address(ordered: Array[String], extras: Array[String], seen: Dictionary, raw: String, port: int) -> void:
	var octets: PackedInt32Array = _ipv4_octets(raw)
	if not lan_ipv4(raw):
		return
	_append_target(ordered, seen, raw, port)
	for host: int in range(1, 255):
		var neighbor: String = "%d.%d.%d.%d" % [octets[0], octets[1], octets[2], host]
		# The metadata host can sit in the same link-local /24 as this computer.
		if not lan_ipv4(neighbor):
			continue
		if not seen.has(neighbor) and neighbor not in extras:
			extras.append(neighbor)

static func _append_target(ordered: Array[String], seen: Dictionary, ip: String, port: int) -> void:
	if seen.has(ip) or ordered.size() >= MAX_SCAN_TARGETS:
		return
	seen[ip] = true
	ordered.append("%s:%d" % [ip, port])

static func _ipv4_octets(text: String) -> PackedInt32Array:
	var parts: PackedStringArray = text.split(".", false)
	if parts.size() != 4:
		return PackedInt32Array()
	var octets: PackedInt32Array = PackedInt32Array()
	for part: String in parts:
		if part.is_empty() or not part.is_valid_int() or str(part.to_int()) != part:
			return PackedInt32Array()
		var number: int = part.to_int()
		if number < 0 or number > 255:
			return PackedInt32Array()
		octets.append(number)
	return octets

## True when this address was not already saved. Order of an existing row can wait.
func remember(value: String) -> bool:
	var address: String = canonical(value)
	if address.is_empty():
		return false
	if address in favorites or address in recent:
		recent.erase(address)
		recent.push_front(address)
		while recent.size() > MAX_RECENT:
			recent.pop_back()
		save_to_disk()
		return false
	recent.push_front(address)
	while recent.size() > MAX_RECENT:
		recent.pop_back()
	save_to_disk()
	return true

func keep(value: String) -> bool:
	var address: String = canonical(value)
	if address.is_empty():
		return false
	favorites.erase(address)
	favorites.push_front(address)
	while favorites.size() > MAX_FAVORITES:
		favorites.pop_back()
	remember(value)
	save_to_disk()
	return true

func drop_address(value: String) -> void:
	var address: String = canonical(value)
	if address.is_empty():
		return
	favorites.erase(address)
	recent.erase(address)
	save_to_disk()

## Favorites first, then recent hosts that are not already kept.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for address: String in favorites:
		out.append({"address": address, "kept": true, "secure": address.begins_with("wss://")})
	for address: String in recent:
		if address not in favorites:
			out.append({"address": address, "kept": false, "secure": address.begins_with("wss://")})
	return out

func load_from_disk() -> void:
	favorites.clear()
	recent.clear()
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(storage_path) != OK:
		return
	favorites = _clean(str(cfg.get_value("book", "favorites", "")), MAX_FAVORITES)
	recent = _clean(str(cfg.get_value("book", "recent", "")), MAX_RECENT)

func save_to_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("book", "favorites", "\n".join(favorites))
	cfg.set_value("book", "recent", "\n".join(recent))
	# Write beside the destination so a failed write cannot truncate the last book.
	var temporary: String = storage_path + ".%d.tmp" % OS.get_process_id()
	if cfg.save(temporary) != OK:
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(temporary)
		return
	var replaced: Error = DirAccess.rename_absolute(temporary, storage_path)
	if replaced != OK:
		# Windows refuses to rename onto a file that is already there.
		DirAccess.remove_absolute(storage_path)
		replaced = DirAccess.rename_absolute(temporary, storage_path)
	if replaced != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)

func _clean(text: String, limit: int) -> Array[String]:
	var out: Array[String] = []
	for line: String in text.split("\n", false):
		var raw: String = line.strip_edges()
		var address: String = canonical(raw)
		var legacy: String = address.substr(5) if address.begins_with("ws://") else ""
		if address.is_empty() or address in out or (raw != address and raw != legacy):
			continue
		out.append(address)
		if out.size() == limit:
			break
	return out
