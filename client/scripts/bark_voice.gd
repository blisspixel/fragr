class_name BarkVoice
extends Node3D

## Voices campaign chatter at the speaker's position. Latch plays dry on the
## Voice bus. Union lines play on a `UnionRadio` bus, created here when
## missing, that band-limits and lightly drives the dry recording into
## compliance radio before it reaches Voice; the colour lives in Godot and
## the stored recordings stay dry. A missing slot is silence (the caption
## still shows). A new line stops the one speaking, so voices never stack.

const VOICE_BUS: StringName = &"Voice"
const RADIO_BUS: StringName = &"UnionRadio"
const RADIO_CENTRE_HZ: float = 1600.0
const RADIO_RESONANCE: float = 0.6
const RADIO_DRIVE: float = 0.18
const UNIT_SIZE: float = 6.0
const MAX_DISTANCE: float = 40.0

## Tests inject a source: Callable(path: String) -> AudioStream or null.
var clip_source: Callable = Callable()
var union_player: AudioStreamPlayer3D
var latch_player: AudioStreamPlayer3D


func _ready() -> void:
	name = "BarkVoice"
	ensure_radio_bus()
	union_player = _player("UnionBark", RADIO_BUS)
	latch_player = _player("LatchBark", VOICE_BUS)


func _player(player_name: String, bus_name: StringName) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.bus = bus_name if AudioServer.get_bus_index(bus_name) >= 0 else &"Master"
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	add_child(player)
	return player


## The Union radio bus, sending to Voice so the voice volume setting still
## governs it. Returns its index.
static func ensure_radio_bus() -> int:
	var index: int = AudioServer.get_bus_index(RADIO_BUS)
	if index >= 0:
		return index
	AudioServer.add_bus()
	index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, RADIO_BUS)
	var send: StringName = VOICE_BUS if AudioServer.get_bus_index(VOICE_BUS) >= 0 else &"Master"
	AudioServer.set_bus_send(index, send)
	var band := AudioEffectBandPassFilter.new()
	band.cutoff_hz = RADIO_CENTRE_HZ
	band.resonance = RADIO_RESONANCE
	AudioServer.add_bus_effect(index, band)
	var drive := AudioEffectDistortion.new()
	drive.mode = AudioEffectDistortion.MODE_OVERDRIVE
	drive.drive = RADIO_DRIVE
	drive.pre_gain = 0.0
	drive.post_gain = -2.0
	AudioServer.add_bus_effect(index, drive)
	return index


## Voice one validated bark. Returns whether a clip started.
func speak(data: Dictionary) -> bool:
	var path: String = CampaignBarks.slot_path(data)
	var where: Vector3 = CampaignBarks.position(data)
	if path.is_empty() or not where.is_finite():
		return false
	var clip: AudioStream = _clip(path)
	if clip == null:
		return false
	stop_all()
	var player: AudioStreamPlayer3D = union_player if CampaignBarks.is_union(data) else latch_player
	player.stream = clip
	player.global_position = where
	player.play()
	return true


func stop_all() -> void:
	for player: AudioStreamPlayer3D in [union_player, latch_player]:
		if player != null:
			player.stop()


func _clip(path: String) -> AudioStream:
	if clip_source.is_valid():
		var injected: Variant = clip_source.call(path)
		return injected as AudioStream if injected is AudioStream else null
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream
