extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_server_endpoint: " + message)

func _run() -> void:
	var cases: Array[Dictionary] = [
		{"input": "127.0.0.1:6767", "game": "ws://127.0.0.1:6767", "status": "http://127.0.0.1:6767/status"},
		{"input": " localhost ", "game": "ws://localhost:6767", "status": "http://localhost:6767/status"},
		{"input": "ws://192.168.1.12:32123", "game": "ws://192.168.1.12:32123", "status": "http://192.168.1.12:32123/status"},
		{"input": "WSS://LOCALEXCEPTION.EXAMPLE/", "game": "wss://localexception.example:443", "status": "https://localexception.example:443/status"},
		{"input": "ws://localhost", "game": "ws://localhost:80", "status": "http://localhost:80/status"},
		{"input": "[::1]:6767", "game": "ws://[::1]:6767", "status": "http://[::1]:6767/status"},
	]
	for item: Dictionary in cases:
		var parsed: Dictionary = ServerEndpoint.parse(item["input"])
		_check(parsed.get("game_url") == item["game"] and parsed.get("status_url") == item["status"],
			"game and probe share accepted endpoint: " + str(item["input"]))
		_check(ServerEndpoint.parse(parsed.get("game_url")) == parsed, "canonical endpoint roundtrip")
	var bad: Array[Variant] = [null, 42, {}, "", "\n", "http://localhost:6767", "ws://user:password@localhost:6767",
		"ws://localhost:6767?token=private", "localhost:0", "localhost:65536", "localhost:-1", "localhost:+12",
		"localhost:0012", "localhost:", "ws://localhost/a", "localhost//", "local host:6767", "127.0.0.999:6767",
		"ws://localhost:6767#fragment", "::1:6767", "[not-an-ip]:6767", "[::1]extra", "bad..host:6767",
		"-host:6767", "host-:6767", "host_foo:6767", "ws://localhost\r:6767", "\nlocalhost:6767"]
	for value: Variant in bad:
		_check(ServerEndpoint.parse(value).is_empty(), "reject malformed endpoint")
	var network: Node = load("res://scripts/net_client.gd").new()
	var clear_private: Array[String] = [
		"ws://127.0.0.1:6767", "ws://localhost:6767", "ws://api.localhost:6767",
		"ws://10.1.2.3:6767", "ws://192.168.1.9:6767", "ws://172.16.5.5:6767",
		"ws://169.254.1.1:6767", "ws://172.31.0.1:6767", "ws://LOCALHOST:6767",
		"ws://[::1]:6767", "ws://[fc00::1]:6767", "ws://[fd00::1]:6767",
		"ws://[fe80::1]:6767", "ws://[FE80::1]:6767", "ws://[febf::1]:6767",
	]
	for url: String in clear_private:
		_check(network.ticket_transport_allowed(url), "cleartext ticket stays on a private host: " + url)
	var clear_public: Array[String] = [
		"ws://fc.example.com:6767", "ws://fd.example.com:6767", "ws://federal.example:6767",
		"ws://fe80.example.com:6767", "ws://example.com:6767", "ws://8.8.8.8:6767",
		"ws://172.15.0.1:6767", "ws://172.32.0.1:6767", "ws://11.0.0.1:6767",
		"ws://[fec0::1]:6767", "ws://[::ffff:127.0.0.1]:6767",
	]
	for url: String in clear_public:
		_check(not network.ticket_transport_allowed(url), "cleartext ticket stays off a public host: " + url)
	_check(network.ticket_transport_allowed("wss://example.com:6767"), "tls may carry a ticket")
	network.free()
	if failures == 0:
		print("test_server_endpoint: PASS")
	quit(0 if failures == 0 else 1)
