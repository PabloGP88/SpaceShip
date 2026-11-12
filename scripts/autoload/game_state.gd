extends Node
## Autoloaded so a restart (scene reload) skips the main menu.

signal game_started

var in_menu := true
var _starting := false


func is_starting() -> bool:
	return _starting


func request_play() -> void:
	if not in_menu or _starting:
		return
	_starting = true


func finish_start() -> void:
	if not in_menu:
		return
	_starting = false
	in_menu = false
	game_started.emit()
