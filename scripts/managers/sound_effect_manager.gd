class_name SoundEffectManager
extends Node

const THRUST := 0
const ORBIT_BOOST := 1
const PLAYER_DESTROY := 2
const MISSION_DESTROY := 3

const GROUP := &"sound_effect_manager"

## 0 = thrust, 1 = orbit boost, 2 = player destroy, 3 = mission destroy
@export var sound_effects: Array[AudioStream] = [null, null, null, null]
## Audio bus every effect is sent to.
@export var bus: StringName = &"Master"
@export var pool_size := 16

var _players: Array[AudioStreamPlayer] = []

var _loops: Dictionary = {}


static func find(tree: SceneTree) -> SoundEffectManager:
	return tree.get_first_node_in_group(GROUP) as SoundEffectManager


func _ready() -> void:
	add_to_group(GROUP)
	for i in pool_size:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		p.finished.connect(_on_player_finished.bind(p))
		_players.append(p)


func play_sound_effect(index: int, pitch_variation := 0.0, volume_variation_db := 0.0,
		loop := false) -> AudioStreamPlayer:
	if index < 0 or index >= sound_effects.size() or sound_effects[index] == null:
		return null
	var p := _get_free_player()
	_loops.erase(p)
	if loop:
		_loops[p] = [pitch_variation, volume_variation_db]
	p.stream = sound_effects[index]
	_play_varied(p, pitch_variation, volume_variation_db)
	return p


func stop_sound_effect(p: AudioStreamPlayer) -> void:
	# If the loop entry is gone, the player was reused for another sound: leave it.
	if p == null or not _loops.has(p):
		return
	_loops.erase(p)
	p.stop()


func _play_varied(p: AudioStreamPlayer, pitch_variation: float, volume_variation_db: float) -> void:
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.volume_db = randf_range(-volume_variation_db, volume_variation_db)
	p.play()


func _on_player_finished(p: AudioStreamPlayer) -> void:
	if _loops.has(p):
		_play_varied(p, _loops[p][0], _loops[p][1])

func _get_free_player() -> AudioStreamPlayer:
	var oldest := _players[0]
	for p in _players:
		if not p.playing:
			return p
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	return oldest
