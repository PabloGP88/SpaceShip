extends Node3D

@onready var _music: AudioStreamPlayer2D = $Music
@onready var _default_music_volume_db: float = _music.volume_db

var _music_muted := false


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"restart"):
		get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_M:
		_music_muted = not _music_muted
		_music.volume_db = -80.0 if _music_muted else _default_music_volume_db
