extends Node
class_name CityAmbienceAudio

@export_range(-60.0, 6.0, 0.1) var crowd_volume_db := -20.0
@export_range(-60.0, 6.0, 0.1) var traffic_volume_db := -22.0
@export_range(0.1, 5.0, 0.1) var fade_in_s := 2.0
@export_range(0.1, 5.0, 0.1) var crossfade_s := 1.5

@onready var _crowd: Array[AudioStreamPlayer] = [$CrowdA, $CrowdB]
@onready var _traffic: Array[AudioStreamPlayer] = [$TrafficA, $TrafficB]

var _crowd_active := 0
var _traffic_active := 0
var _elapsed := 0.0


func _ready() -> void:
	for sound in _crowd + _traffic:
		if sound.stream is AudioStreamMP3:
			(sound.stream as AudioStreamMP3).loop = false
		sound.volume_db = -80.0
	_crowd[0].play()
	_traffic[0].play()


func _process(delta: float) -> void:
	_elapsed += delta
	var fade := clampf(_elapsed / fade_in_s, 0.0, 1.0)
	_crowd_active = _update_layer(_crowd, _crowd_active, crowd_volume_db, fade)
	_traffic_active = _update_layer(_traffic, _traffic_active, traffic_volume_db, fade)


func _update_layer(
	players: Array[AudioStreamPlayer], active: int, level_db: float, fade: float
) -> int:
	var current := players[active]
	var next := players[1 - active]
	var length := current.stream.get_length()
	var overlap := minf(crossfade_s, length * 0.25)
	if not next.playing and current.get_playback_position() >= length - overlap:
		next.volume_db = -80.0
		next.play()
	var blend := 0.0
	if next.playing:
		blend = clampf(next.get_playback_position() / overlap, 0.0, 1.0)
	current.volume_db = _gain_db(level_db, fade * (1.0 - blend))
	if next.playing:
		next.volume_db = _gain_db(level_db, fade * blend)
		if blend >= 0.999 or not current.playing:
			current.stop()
			current.volume_db = -80.0
			return 1 - active
	return active


func _gain_db(level_db: float, gain: float) -> float:
	return level_db + linear_to_db(maxf(gain, 0.001))
