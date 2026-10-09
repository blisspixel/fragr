class_name RecordsPanel
extends VBoxContainer

var records: PlayerRecords
var preferences: FragrSettings
var _kind: String = "mission"
var _summary: Label
var _selection: OptionButton
var _details: Label
var _quip: Label
var _notice: Label
var _filtered: Array[Dictionary] = []
var _first_tab: Button
var _tabs: Dictionary[String, Button] = {}

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_label(24).text = tr("RECORD_TITLE")
	var appearance: Array[String] = []
	for kind: String in ["title", "emblem"]:
		if records.customization[kind] != "none":
			appearance.append(PlayerRewards.label(records.customization[kind]))
	if not appearance.is_empty():
		_label(16).text = " | ".join(appearance)
	var tabs: HBoxContainer = HBoxContainer.new()
	var group: ButtonGroup = ButtonGroup.new()
	for kind: String in ["mission", "arena", "practice"]:
		var button: Button = Button.new()
		button.toggle_mode = true
		button.button_group = group
		_tabs[kind] = button
		if _first_tab == null:
			_first_tab = button
		button.text = tr("RECORD_TAB_" + kind.to_upper())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _select_kind(kind))
		tabs.add_child(button)
	add_child(tabs)
	_summary = _label(20)
	_selection = OptionButton.new()
	_selection.fit_to_longest_item = false
	_selection.clip_text = true
	_selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection.item_selected.connect(_show_record)
	add_child(_selection)
	_details = _label(18)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size.y = 180.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_details.reparent(scroll)
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quip = _label(18)
	_quip.add_theme_color_override("font_color", MenuTheme.EMBER)
	var commentary: CheckButton = CheckButton.new()
	commentary.text = tr("RECORD_COMMENTARY")
	commentary.button_pressed = preferences.get_value("gameplay", "stat_commentary")
	commentary.toggled.connect(func(enabled: bool) -> void:
		var candidate: FragrSettings = preferences.draft()
		candidate.set_value("gameplay", "stat_commentary", enabled)
		if preferences.commit(candidate) != OK:
			commentary.set_pressed_no_signal(not enabled)
			_notice.text = tr("RECORD_SAVE_ERROR")
		_show_record(_selection.selected)
	)
	var options: HBoxContainer = HBoxContainer.new()
	options.add_child(commentary)
	commentary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var export_button: Button = Button.new()
	export_button.text = tr("RECORD_EXPORT")
	export_button.pressed.connect(_export)
	options.add_child(export_button)
	add_child(options)
	_notice = _label(16)
	_select_kind(_kind)

func focus_first() -> void:
	_first_tab.grab_focus()

func _label(size: int) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 628.0
	add_child(label)
	return label

func _export() -> void:
	var path: String = "user://record-export-%s.json" % Crypto.new().generate_random_bytes(6).hex_encode()
	_notice.text = tr("RECORD_EXPORTED").format({"path": ProjectSettings.globalize_path(path)}) if records.export_json(path) == OK else tr("RECORD_SAVE_ERROR")

func _select_kind(kind: String) -> void:
	_kind = kind
	for tab: String in _tabs:
		_tabs[tab].set_pressed_no_signal(tab == kind)
	_filtered.clear()
	_selection.clear()
	for entry: Dictionary in records.entries:
		if entry["record"]["scope"]["kind"] == kind:
			_filtered.append(entry)
	for entry: Dictionary in _filtered:
		var record: Dictionary = entry["record"]
		_selection.add_item(record["map_name"])
		_selection.set_item_tooltip(_selection.item_count - 1, record["map_name"])
	_selection.disabled = _filtered.is_empty()
	var counts: Dictionary = records.totals(kind)
	_summary.text = tr("RECORD_TOTALS").format({
		"records": _filtered.size(), "kills": PlayerRecord.sum_combat(counts, "kills"),
		"deaths": int(counts["deaths"]), "time": _time(int(counts["alive_ticks"])),
	})
	_notice.text = tr("RECORD_RETENTION").format({"count": PlayerRecords.LIMIT}) if records.error == OK else tr("RECORD_SAVE_ERROR")
	_show_record(0)

func _show_record(index: int) -> void:
	_details.text = ""
	_quip.text = ""
	if index < 0 or index >= _filtered.size():
		_details.text = tr("RECORD_EMPTY")
		return
	var entry: Dictionary = _filtered[index]
	var record: Dictionary = entry["record"]
	var scope: Dictionary = record["scope"]
	var total: Dictionary = record["total"]
	var lines: Array[String] = [_status(record) + " | " + tr("RECORD_ORIGIN_" + String(entry["origin"]).to_upper())]
	if scope["kind"] == "arena" and int(record["entered_at"]) > int(record["round_started_at"]):
		lines.append(tr("RECORD_LATE_JOIN"))
	if scope["kind"] == "mission":
		lines.append(tr("RECORD_MISSION").format({"difficulty": tr("DIFFICULTY_" + String(scope["rules"]["difficulty"]).to_upper()), "attempt": int(scope["attempt"])}))
		if record.has("mission_elapsed_ticks"):
			lines.append(tr("RESULT_TIME") + ": " + CampaignResult.precise_time(int(record["mission_elapsed_ticks"])))
		var comparison: Dictionary = records.mission_comparison(record, str(entry.get("server_sha256", "")))
		if not comparison.is_empty():
			lines.append(tr("RECORD_MISSION_BEST").format({"time": CampaignResult.precise_time(int(comparison["best_ticks"])), "count": comparison["count"]}))
			lines.append(tr("RESULT_BEST_SCOPE"))
	var kills: int = PlayerRecord.sum_combat(total, "kills")
	var deaths: int = int(total["deaths"])
	var alive: int = int(total["alive_ticks"])
	lines.append(tr("RECORD_COMBAT").format({"kills": kills, "deaths": deaths, "time": _time(alive)}))
	var dealt_all: int = PlayerRecord.sum_combat(total, "hp_damage") + PlayerRecord.sum_combat(total, "armor_damage")
	var frag_rate: String = PlayerRecord.format_tenths(PlayerRecord.per_minute_tenths(kills, alive))
	var dealt_rate: String = PlayerRecord.format_tenths(PlayerRecord.per_minute_tenths(dealt_all, alive))
	if frag_rate != "" and dealt_rate != "":
		lines.append(tr("RECORD_PACE").format({"frags": frag_rate, "dealt": dealt_rate, "time": _time(alive)}))
	if deaths > 0:
		lines.append(tr("RECORD_KD").format({"ratio": PlayerRecord.unit_label(kills, deaths), "kills": kills, "deaths": deaths}))
	# Shots per kill stay on guns and fists. A grenade kill is not a shot.
	var shots: int = PlayerRecord.sum_weapon(total, "attacks")
	var shot_kills: int = PlayerRecord.sum_weapon(total, "kills")
	if shot_kills > 0 and shots > 0:
		lines.append(tr("RECORD_SPK").format({"ratio": PlayerRecord.unit_label(shots, shot_kills), "attacks": shots, "kills": shot_kills}))
	lines.append(tr("RECORD_DAMAGE").format({"hp": PlayerRecord.sum_combat(total, "hp_damage"), "armor": PlayerRecord.sum_combat(total, "armor_damage"), "lost": int(total["hp_lost"])}))
	for weapon: int in range(total["weapons"].size()):
		var counts: Dictionary = total["weapons"][weapon]
		if int(counts.get("attacks", 0)) == 0:
			continue
		lines.append_array(weapon_lines(EquipmentState.display_name(String(EquipmentState.WEAPONS[weapon])).to_upper(), counts, true))
	if PlayerRecord.grenade_count(total, "attacks") > 0:
		lines.append_array(weapon_lines(tr("RECORD_GRENADES"), _explosive_counts(total, "grenades"), false))
	if PlayerRecord.mine_count(total, "attacks") > 0:
		lines.append_array(weapon_lines(tr("RECORD_MINES"), _explosive_counts(total, "mines"), false))
	if PlayerRecord.remote_mine_count(total, "attacks") > 0:
		lines.append_array(weapon_lines(tr("RECORD_REMOTE_MINES"), _explosive_counts(total, "remote_mines"), false))
	if PlayerRecord.sum_combat(total, "attacks") == 0:
		lines.append(tr("RECORD_NO_ATTACKS"))
	if PlayerRecord.secrets(total) > 0:
		lines.append(tr("RECORD_SECRETS").format({"count": PlayerRecord.secrets(total)}))
	if scope["kind"] == "mission" and int(scope["attempt"]) > 1:
		lines.append(tr("RECORD_ATTEMPT").format({"kills": PlayerRecord.sum_combat(record["attempt"], "kills"), "time": _time(int(record["attempt"]["alive_ticks"]))}))
	_details.text = "\n".join(lines)
	if preferences.get_value("gameplay", "stat_commentary"):
		var quip: String = commentary_key(record)
		_quip.text = tr(quip) if not quip.is_empty() else ""

static func weapon_lines(weapon_name: String, counts: Dictionary, geometry: bool) -> Array[String]:
	var written: Array[String] = []
	var attacks: int = int(counts.get("attacks", 0))
	if attacks <= 0:
		return written
	var hurts: int = int(counts.get("damaging_attacks", 0))
	var hp: int = int(counts.get("hp_damage", 0))
	var armor: int = int(counts.get("armor_damage", 0))
	var dealt: int = hp + armor
	var connects: int = int(counts.get("connects", 0))
	var heads: int = int(counts.get("heads", 0))
	# A damaging column with neither key predates connect accounting. Zero hurt
	# with neither key is a measured miss, which is a real zero.
	var tracked: bool = geometry and (counts.has("connects") or counts.has("heads") or hurts == 0)
	var clauses: PackedStringArray = PackedStringArray()
	clauses.append(_rate_clause("RECORD_PER_SHOT" if geometry else "RECORD_PER_USE", dealt, attacks))
	if tracked and connects > 0 and connects != attacks:
		clauses.append(_rate_clause("RECORD_PER_BODY", dealt, connects))
	if hurts > 0 and hurts != attacks and (not tracked or hurts != connects):
		clauses.append(_rate_clause("RECORD_PER_HURT", dealt, hurts))
	written.append(TranslationServer.translate("RECORD_WEAPON").format({
		"weapon": weapon_name, "attacks": attacks, "noun": TranslationServer.translate("RECORD_NOUN_SHOTS" if geometry else "RECORD_NOUN_USES"),
		"dealt": dealt, "hp": hp, "armor": armor, "rates": ", ".join(clauses),
	}))
	written.append(TranslationServer.translate("RECORD_HURT").format({
		"hurts": hurts, "attacks": attacks, "percent": PlayerRecord.percent_label(hurts, attacks),
	}))
	var rate_hits: int = hurts
	var rate_name: String = TranslationServer.translate("RECORD_RATE_HURT")
	if tracked:
		written.append(TranslationServer.translate("RECORD_CONNECT").format({
			"connects": connects, "attacks": attacks, "percent": PlayerRecord.percent_label(connects, attacks),
		}))
		if connects > 0:
			written.append(TranslationServer.translate("RECORD_HEAD").format({
				"heads": heads, "connects": connects, "percent": PlayerRecord.percent_label(heads, connects),
			}))
		rate_hits = connects
		rate_name = TranslationServer.translate("RECORD_RATE_BODY")
	_append_wilson(written, rate_name, rate_hits, attacks)
	if tracked and connects > 0:
		_append_wilson(written, TranslationServer.translate("RECORD_RATE_HEAD"), heads, connects)
	return written

static func _rate_clause(key: String, numerator: int, denominator: int) -> String:
	return TranslationServer.translate(key).format({"rate": PlayerRecord.unit_label(numerator, denominator)})

static func _append_wilson(written: Array[String], rate_name: String, hits: int, trials: int) -> void:
	var interval: Vector2i = PlayerRecord.wilson_thousandths(hits, trials)
	if interval.x < 0:
		return
	written.append(TranslationServer.translate("RECORD_WILSON").format({
		"rate": rate_name, "low": PlayerRecord.format_tenths(interval.x), "high": PlayerRecord.format_tenths(interval.y),
		"hits": hits, "trials": trials,
	}))

static func _explosive_counts(total: Dictionary, column: String) -> Dictionary:
	var counts: Dictionary = {}
	for field: String in PlayerRecord.WEAPON_COUNTS:
		counts[field] = PlayerRecord.column_count(total, column, field)
	return counts

static func commentary_key(record: Dictionary) -> String:
	var counts: Dictionary = record["total"]
	if int(counts["dry_triggers"]) > 0:
		return "RECORD_QUIP_DRY"
	var attempt: Dictionary = record["attempt"]
	if record["status"] == "complete" and PlayerRecord.sum_combat(attempt, "kills") > 0 \
		and PlayerRecord.sum_combat(attempt, "attacks") == int(attempt["weapons"][0]["attacks"]) + PlayerRecord.weapon_count(attempt, 5, "attacks"):
		return "RECORD_QUIP_MELEE"
	return ""

static func _status(record: Dictionary) -> String:
	if not PlayerRecord.terminal(record):
		return TranslationServer.translate("RECORD_INCOMPLETE")
	return TranslationServer.translate("RECORD_STATUS_" + String(record["status"]).to_upper())

static func _time(ticks: int) -> String:
	var seconds: int = ticks / 20
	return "%d:%02d" % [seconds / 60, seconds % 60]
