extends SceneTree

## The humour pass's copy: every loading tip and menu motto is a translated
## catalog line, the graphics tiers each say what they draw before the joke,
## and no shipped catalog line uses an em or en dash. Canon review is a human
## job; this harness keeps the mechanical rules from drifting.
var failures: int = 0

const CATALOGS: Array[String] = ["res://i18n/world.en.po", "res://i18n/story.en.po", "res://i18n/controls.en.po",
	"res://i18n/match.en.po", "res://i18n/tips.en.po"]

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_humour_copy: " + message)

func _run() -> void:
	var registered: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	for path: String in CATALOGS:
		_check(path in registered, "%s is a registered catalog" % path)
		var text: String = FileAccess.get_file_as_string(path)
		_check(not text.is_empty(), "%s reads" % path)
		_check(text.find("—") < 0 and text.find("–") < 0, "%s has no em or en dash" % path)

	# Tips: catalog lines, unique, short enough for the card, and never the
	# Inheritance, which a tip could put in front of a late-campaign player.
	_check(Tips.count() >= 60, "the card has a real pool of tips: %d" % Tips.count())
	var seen: Dictionary = {}
	for key: String in Tips.TIPS:
		var line: String = TranslationServer.translate(key)
		_check(line != key and not line.is_empty(), "%s is translated" % key)
		_check(not seen.has(line), "%s is not a duplicate" % key)
		seen[line] = true
		_check(line.length() <= 200, "%s fits the card in two short sentences: %d" % [key, line.length()])
		_check(line.findn("inheritance") < 0, "%s leaves the Inheritance alone" % key)
	_check(Tips.pick(7) == Tips.pick(7) and Tips.pick(7) == TranslationServer.translate(Tips.pick_key(7)), "a seed draws the same translated tip")
	_check(not Tips.random_tip().begins_with("TIP_"), "the loading card shows words, not a key")

	# Graphics tiers: one line each, the tier's name and what it draws first.
	for tier: int in range(RenderQuality.TIER_NAMES.size()):
		var note: String = SettingsPanel.tier_note(tier)
		_check(note.begins_with(RenderQuality.TIER_NAMES[tier] + ": "), "tier %d leads with its name: %s" % [tier, note])
		_check(note.length() <= 140, "tier %d fits the Graphics note: %d" % [tier, note.length()])
	_check(SettingsPanel.tier_note(RenderQuality.MEDIUM).contains("shadows"), "Medium says what it draws before the joke")
	_check(SettingsPanel.tier_note(-3) == SettingsPanel.tier_note(RenderQuality.POTATO), "a bad tier reads as Potato")

	# Menu mottos: every one has words, and one is chosen per launch.
	var menu: GDScript = load("res://scripts/boot_menu.gd")
	var mottos: Array = menu.get("MOTTOS")
	_check(mottos.size() >= 4, "the menu has a few mottos")
	for key: Variant in mottos:
		_check(TranslationServer.translate(str(key)) != str(key), "%s is translated" % key)
		# One level line under the navigation help on the narrowest page.
		_check(TranslationServer.translate(str(key)).length() <= 44, "%s fits one line" % key)
	var first: String = menu.call("motto_key")
	_check(first in mottos and first == menu.call("motto_key"), "the motto holds for the launch")

	# The marks still carry the book, so the joke never hides the score.
	var nemesis: String = TranslationServer.translate("HUD_BOARD_NEMESIS")
	_check(nemesis.contains("{won}") and nemesis.contains("{lost}"), "the nemesis mark keeps the book: " + nemesis)
	_check(TranslationServer.translate("HUD_BOARD_MVP").begins_with("MVP"), "the MVP mark still says MVP")
	var tally: String = TranslationServer.translate("HUD_FUN_METRICS")
	# The feed shows three lines of about 29 characters at 1280 wide.
	_check(tally.contains("67 DAYS") and tally.length() <= 84, "the fun tally notice keeps its shredder and fits the feed: %d" % tally.length())
	_check(TranslationServer.translate("BENCH_TUNE_BODY").contains("{seconds}") and TranslationServer.translate("BENCH_TUNE_BODY").contains("{fps}"),
		"the tune card keeps its time and target")

	if failures == 0:
		print("test_humour_copy: PASS tips, tiers, mottos, marks and dashes")
	quit(1 if failures > 0 else 0)
