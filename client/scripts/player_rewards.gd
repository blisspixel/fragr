class_name PlayerRewards
extends RefCounted

## Local profile awards consume private authoritative records, never presentation.
const IDS: Array[String] = ["recall_notice_complete", "authored_secret_found"]
const MIN_RULES_REVISION: int = 3
const DEFAULTS: Dictionary = {"title": "none", "emblem": "none", "finish": "standard"}
const CHOICES: Dictionary = {
	"title": ["none", "on_file", "margin_reader"],
	"emblem": ["none", "transfer_stamp"],
	"finish": ["standard", "oxide", "margin_teal"],
}
const REQUIRED: Dictionary = {
	"on_file": "recall_notice_complete", "transfer_stamp": "recall_notice_complete",
	"margin_reader": "authored_secret_found", "margin_teal": "authored_secret_found",
}
const FINISH_SHADER: Shader = preload("res://scripts/weapon_finish.gdshader")
const FINISH_TINTS: Dictionary = {
	"standard": Vector3.ONE, "oxide": Vector3(1.2, 0.96, 0.82),
	"margin_teal": Vector3(0.8, 1.04, 1.08),
}

static func eligible(record: Dictionary, origin: String, server_hash: String) -> Array[String]:
	var awards: Array[String] = []
	if origin != "local" or not PlayerRecords._valid_server_hash(server_hash) \
		or not PlayerRecord.validation_error(record, record.get("player_id")).is_empty() \
		or record["role"] != "human" or record["scope"]["kind"] != "mission":
		return awards
	var scope: Dictionary = record["scope"]
	if not scope["run"] is Dictionary or int(scope["rules"]["revision"]) < MIN_RULES_REVISION:
		return awards
	if scope["mission"] == MissionState.ID and int(record["map_id"]) == 1001 \
		and record["status"] == "complete" and scope["run"]["status"] == "complete":
		awards.append("recall_notice_complete")
	if PlayerRecord.secrets(record["total"]) > 0:
		awards.append("authored_secret_found")
	return awards

static func valid_unlocks(value: Variant) -> bool:
	if not value is Array or value.size() > IDS.size():
		return false
	var seen: Dictionary = {}
	for proof: Variant in value:
		if not proof is Dictionary or proof.size() != 3 or proof.get("id") not in IDS \
			or seen.has(proof["id"]) or not proof.get("record") is Dictionary:
			return false
		if proof["id"] not in eligible(proof["record"], "local", str(proof.get("server_sha256", ""))):
			return false
		seen[proof["id"]] = true
	return true

static func owns(unlocks: Array[Dictionary], award: String) -> bool:
	for proof: Dictionary in unlocks:
		if proof["id"] == award:
			return true
	return false

static func available(kind: String, choice: String, unlocks: Array[Dictionary]) -> bool:
	return CHOICES.has(kind) and choice in CHOICES[kind] \
		and (not REQUIRED.has(choice) or owns(unlocks, REQUIRED[choice]))

static func valid_selection(value: Variant, unlocks: Array[Dictionary]) -> bool:
	if not value is Dictionary or value.size() != DEFAULTS.size():
		return false
	for kind: String in DEFAULTS:
		if not value.get(kind) is String or not available(kind, value[kind], unlocks):
			return false
	return true

static func label(choice: String) -> String:
	return TranslationServer.translate("REWARD_CHOICE_" + choice.to_upper())

static func material(finish: String) -> ShaderMaterial:
	if finish == "standard" or not FINISH_TINTS.has(finish):
		return null
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = FINISH_SHADER
	result.set_shader_parameter("paint_tint", FINISH_TINTS[finish])
	return result

static func gun_can_finish(weapon: String) -> bool:
	return weapon in ["Tack", "Flechette", "Scatter", "Rail", "Sniper", "Arc"]
