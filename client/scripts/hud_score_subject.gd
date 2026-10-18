class_name HudScoreSubject
extends RefCounted

## Snapshot rosters omit temporarily inactive bodies. Retain only the selected
## participant's last accepted score, never infer a full-match leader from them.
var subject_id: String = ""
var name: String = ""
var score: int = 0
var known: bool = false
var _visible: Dictionary = {}

func clear() -> void:
	subject_id = ""
	name = ""
	score = 0
	known = false
	_visible.clear()

func select(id: String) -> void:
	if subject_id != id:
		subject_id = id
		name = ""
		known = false
	_accept()

func observe(players: Array) -> void:
	_visible.clear()
	for value: Variant in players:
		if value is Dictionary and value.get("id") is String:
			_visible[value.id] = value
	_accept()

func _accept() -> void:
	if subject_id.is_empty() or not _visible.has(subject_id):
		return
	var player: Dictionary = _visible[subject_id]
	name = str(player.get("name", ""))
	score = int(player.get("score", 0))
	known = true

func text() -> String:
	return name + ": " + str(score) if known else ""
