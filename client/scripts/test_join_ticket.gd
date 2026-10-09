extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("test_join_ticket: " + message)
	quit(1)

func _run() -> void:
	var previous_server: String = OS.get_environment("FRAGR_SERVER")
	OS.set_environment("FRAGR_SERVER", "wss://example.test:6767")
	var tls_network: Node = load("res://scripts/net_client.gd").new()
	OS.set_environment("FRAGR_SERVER", previous_server)
	if str(tls_network.get("server_url")) != "wss://example.test:6767":
		_fail("FRAGR_SERVER TLS address was " + str(tls_network.get("server_url")))
		return
	tls_network.free()
	var network: Node = load("res://scripts/net_client.gd").new()
	var expected := "v1.1700000060.human.5b6e18c7aef8a218ef64786317c23e472eb2b432bfa681e1c76e340b48d232ba"
	var ticket: String = str(network.call("join_ticket", "human", "0123456789abcdef", 1700000060))
	if ticket != expected:
		_fail("human ticket was " + ticket)
		return
	var agent: String = str(network.call("join_ticket", "agent", "0123456789abcdef", 1700000060))
	if not agent.begins_with("v1.1700000060.agent.") or agent == ticket:
		_fail("agent ticket was " + agent)
		return
	if str(network.call("join_ticket", "spectator", "0123456789abcdef", 1700000060)) != "":
		_fail("spectators are not ticketed")
		return
	if str(network.call("join_ticket", "human", "short", 1700000060)) != "":
		_fail("a short secret minted a ticket")
		return
	if str(network.call("join_ticket", "human", "  0123456789abcdef  ", 1700000060)) != expected:
		_fail("surrounding space changed the secret")
		return
	var v2_expected := "v2.1700000060.human.00112233445566778899aabbccddeeff.d3NzOi8vcGxheS5leGFtcGxlOjY3Njc.0ec6964cd92cc8c6b91dea2c4491f9454ebc20e7aadce35b355e4d675df4b6d8"
	var v2_ticket: String = str(network.call("join_ticket_v2", "human", "0123456789abcdef", 1700000060, "00112233445566778899aabbccddeeff", "wss://play.example:6767"))
	if v2_ticket != v2_expected:
		_fail("v2 ticket was " + v2_ticket)
		return
	var public_ws: String = str(network.call("presented_ticket", "ws://203.0.113.8:6767", "0123456789abcdef", 1700000060, "00112233445566778899aabbccddeeff"))
	if public_ws != "":
		_fail("a public cleartext host received a ticket")
		return
	var local_ticket: String = str(network.call("presented_ticket", "ws://127.0.0.1:6767", "0123456789abcdef", 1700000060, "00112233445566778899aabbccddeeff"))
	if not local_ticket.begins_with("v2.1700000060.human."):
		_fail("loopback did not present a v2 ticket")
		return
	var seen: Array[String] = []
	network.connect("server_error", func(message: String) -> void: seen.append(message))
	if not bool(network.call("_admission_error", "join_rejected")) or seen != ["This server refused the join."]:
		_fail("refusal was " + str(seen))
		return
	network.free()
	print("test_join_ticket: PASS")
	quit(0)
