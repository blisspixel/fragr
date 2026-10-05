class_name ServerEndpoint
extends RefCounted

## One accepted origin supplies both the game URL and its status probe.
## Paths, credentials and query strings are deliberately not host addresses.
static func parse(value: Variant) -> Dictionary:
	if not value is String:
		return {}
	for index: int in (value as String).length():
		var code: int = (value as String).unicode_at(index)
		if code < 32 or code == 127:
			return {}
	var text: String = (value as String).strip_edges()
	if text.is_empty() or text.length() > 2048:
		return {}
	for index: int in text.length():
		var code: int = text.unicode_at(index)
		if code <= 32 or code == 127:
			return {}
	var scheme: String = "ws"
	var explicit_scheme: bool = text.contains("://")
	if explicit_scheme:
		var marker: int = text.find("://")
		scheme = text.left(marker).to_lower()
		if scheme not in ["ws", "wss"]:
			return {}
		text = text.substr(marker + 3)
	if text.ends_with("/"):
		text = text.left(-1)
	if text.is_empty() or text.contains("/") or text.contains("\\") \
		or text.contains("@") or text.contains("?") or text.contains("#"):
		return {}
	var host: String = ""
	var port_text: String = ""
	var authority: String = ""
	if text.begins_with("["):
		var closing: int = text.find("]")
		if closing <= 1:
			return {}
		host = text.substr(1, closing - 1)
		if not host.contains(":") or not host.is_valid_ip_address():
			return {}
		var rest: String = text.substr(closing + 1)
		if not rest.is_empty():
			if not rest.begins_with(":"):
				return {}
			port_text = rest.substr(1)
			if port_text.is_empty():
				return {}
		authority = "[" + host.to_lower() + "]"
	else:
		var parts: PackedStringArray = text.split(":", true)
		if parts.size() > 2:
			return {}
		host = parts[0].to_lower()
		if parts.size() == 2:
			port_text = parts[1]
			if port_text.is_empty():
				return {}
		if not _valid_host(host):
			return {}
		authority = host
	var port: int = (443 if scheme == "wss" else 80) if explicit_scheme else 6767
	if not port_text.is_empty():
		if port_text.length() > 5 or not port_text.is_valid_int() \
			or str(port_text.to_int()) != port_text:
			return {}
		port = port_text.to_int()
	if port < 1 or port > 65535:
		return {}
	authority += ":" + str(port)
	return {"game_url": scheme + "://" + authority,
		"status_url": ("https" if scheme == "wss" else "http") + "://" + authority + "/status",
		"host": host, "port": port, "secure": scheme == "wss"}

static func _valid_host(host: String) -> bool:
	if host.is_empty() or host.length() > 253:
		return false
	var numeric: bool = true
	for index: int in host.length():
		var code: int = host.unicode_at(index)
		if not (code >= 48 and code <= 57 or code == 46):
			numeric = false
	if numeric:
		return host.is_valid_ip_address() and not host.contains(":")
	for label: String in host.split(".", true):
		if label.is_empty() or label.length() > 63 or label.begins_with("-") or label.ends_with("-"):
			return false
		for index: int in label.length():
			var code: int = label.unicode_at(index)
			if not (code >= 97 and code <= 122 or code >= 48 and code <= 57 or code == 45):
				return false
	return true
