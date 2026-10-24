extends AudioStreamPlayer
class_name HostVoice

## The Host's voiced calls on the Announcer bus. Each big moment has a
## name-free slot per variant, `res://assets/audio/host/<kind>_<variant>.mp3`,
## so recorded lines drop in without code: the caption carries the names, the
## clip never does. A missing clip is silence and the caption still shows.
## Text-only reactions never play. The server spaces big calls at least eight
## seconds apart; a new call still stops one that is speaking, so two voices
## never stack.

## A clip started; the radio ducks for this long.
signal spoke(seconds: float)

const SLOT_DIR: String = "res://assets/audio/host/"
const SLOT_EXTENSION: String = ".mp3"
const BUS_NAME: StringName = &"Announcer"
## Extra duck after the clip ends, so the radio does not swell under the tail.
const DUCK_TAIL: float = 0.5

## Tests inject a source: Callable(path: String) -> AudioStream or null.
var clip_source: Callable = Callable()


func _ready() -> void:
	bus = BUS_NAME if AudioServer.get_bus_index(BUS_NAME) >= 0 else &"Master"


## The name-free slot a recording fills for one kind and variant.
static func slot_path(kind: String, variant: int) -> String:
	return SLOT_DIR + kind + "_" + str(variant) + SLOT_EXTENSION


## Voice a `host_reaction` when the announcer setting allows it and the slot
## has a recording. Returns whether a clip started.
func speak(data: Dictionary, announcer: int) -> bool:
	if announcer == FragrSettings.ANNOUNCER_OFF or not MatchRules.reaction_big(data):
		return false
	var kind: String = MatchRules.reaction_kind(data)
	var variant: int = MatchRules.reaction_variant(data)
	if kind.is_empty() or variant < 0:
		return false
	var clip: AudioStream = _clip(slot_path(kind, variant))
	if clip == null:
		return false
	stop()
	stream = clip
	play()
	spoke.emit(clip.get_length() + DUCK_TAIL)
	return true


func _clip(path: String) -> AudioStream:
	if clip_source.is_valid():
		var injected: Variant = clip_source.call(path)
		return injected as AudioStream if injected is AudioStream else null
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream
