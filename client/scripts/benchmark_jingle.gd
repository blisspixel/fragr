extends AudioStreamPlayer
class_name BenchmarkJingle

## Crackpot's certificate: a few seconds of over-produced, hard-tuned pop that
## plays once when a benchmark run completes. Crackpot is the league regular
## who is compliance-flavoured and has decided to enjoy the joke, so he sings
## your graphics card through the Office's own paperwork: the Schedule,
## Article Seven, the Custodian of Record.
##
## It lives on the Announcer bus, so Settings > Audio covers it twice: the
## Announcer volume sets its level and Announcer Off silences it. Only the
## results screen of a completed benchmark creates one, so it never plays in
## a match.
##
## Six takes ship (three lyrics, two takes each) until Nick picks one by ear on
## the results screen. The pick is saved as `[audio] benchmark_jingle`; then
## `fragr-audiogen jingle-prune --apply` deletes the other five and the picker
## goes with them, with no code change.

## A clip started; carries the take and its length.
signal sang(take: String, seconds: float)

const ROOT: String = "res://assets/audio/jingle/benchmark/"
const EXTENSION: String = ".mp3"
const BUS_NAME: StringName = &"Announcer"
const SETTINGS_SECTION: String = "audio"
const SETTINGS_KEY: String = "benchmark_jingle"
const TAKES: Array[String] = ["1a", "1b", "2a", "2b", "3a", "3b"]
const DEFAULT_TAKE: String = "1a"
const SPEAKER: String = "CRACKPOT"

## What each lyric sings, word for word, for the caption.
const LYRICS: Dictionary = {
	"1": "Certified! Your graphics card is Level Zero, a Fixture! Nobody argues with a door!",
	"2": "You are not in trouble, you are in compliance! Every frame metered by intent: Article Seven!",
	"3": "Custodian of Record: you! Envelope: sixty frames! License the card, license the mind, it's the same form!",
}

## Integrated loudness of each shipped take (ffmpeg ebur128, 2026-10-31). The
## player lifts or trims each to TARGET_LUFS so a pick by ear compares
## performances, not mastering levels, and sits near the Host's calls.
const MEASURED_LUFS: Dictionary = {
	"1a": -10.8, "1b": -12.2, "2a": -15.5, "2b": -20.0, "3a": -11.1, "3b": -10.9,
}
const TARGET_LUFS: float = -18.0

## Tests inject a source: Callable(path: String) -> AudioStream or null.
var clip_source: Callable = Callable()
var take: String = ""


func _ready() -> void:
	bus = BUS_NAME if AudioServer.get_bus_index(BUS_NAME) >= 0 else &"Master"


## A saved value the game accepts: one of TAKES, else the default.
static func clean_take(value: Variant) -> String:
	if value is String and (value as String) in TAKES:
		return value
	return DEFAULT_TAKE


## The takes still in the build, in TAKES order. After `jingle-prune` only
## the pick remains, and the results screen drops its picker.
static func shipped_takes() -> Array[String]:
	var out: Array[String] = []
	for candidate: String in TAKES:
		if ResourceLoader.exists(ROOT + candidate + EXTENSION):
			out.append(candidate)
	return out


## The saved pick when it still ships, else the first take that does.
static func chosen_take(settings: FragrSettings) -> String:
	var saved: String = DEFAULT_TAKE if settings == null else clean_take(settings.get_value(SETTINGS_SECTION, SETTINGS_KEY))
	var shipped: Array[String] = shipped_takes()
	if saved in shipped or shipped.is_empty():
		return saved
	return shipped[0]


static func take_path(chosen: String) -> String:
	return ROOT + clean_take(chosen) + EXTENSION


static func lyric(chosen: String) -> String:
	return str(LYRICS.get(clean_take(chosen).left(1), ""))


## "1A" for the picker.
static func label(chosen: String) -> String:
	return clean_take(chosen).to_upper()


static func gain_db(chosen: String) -> float:
	return TARGET_LUFS - float(MEASURED_LUFS.get(clean_take(chosen), TARGET_LUFS))


## Whether the certificate is sung: only for a completed run, never when the
## Announcer setting is Off. The bus volume handles everything in between.
static func allowed(report: Dictionary, announcer: int) -> bool:
	return announcer != FragrSettings.ANNOUNCER_OFF and str(report.get("state", "")) == "complete" \
		and report.get("runs") is Array and not (report["runs"] as Array).is_empty()


## Sing one take, cutting off any take already playing. Returns whether a clip
## started; a missing clip is silence.
func sing(chosen: String, announcer: int) -> bool:
	if announcer == FragrSettings.ANNOUNCER_OFF:
		return false
	var clip: AudioStream = _clip(take_path(chosen))
	if clip == null:
		return false
	stop()
	take = clean_take(chosen)
	stream = clip
	volume_db = gain_db(take)
	play()
	sang.emit(take, clip.get_length())
	return true


func _clip(path: String) -> AudioStream:
	if clip_source.is_valid():
		var injected: Variant = clip_source.call(path)
		return injected as AudioStream if injected is AudioStream else null
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream
