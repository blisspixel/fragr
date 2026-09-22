extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("test_join_ticket: " + message)
	quit(1)

func _run() -> void:
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
	var seen: Array[String] = []
	network.connect("server_error", func(message: String) -> void: seen.append(message))
	if not bool(network.call("_admission_error", "join_rejected")) or seen != ["This server refused the join."]:
		_fail("refusal was " + str(seen))
		return
	network.free()
	print("test_join_ticket: PASS")
	quit(0)
