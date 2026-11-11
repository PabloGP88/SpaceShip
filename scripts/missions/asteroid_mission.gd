class_name AsteroidMission
extends Mission


@export var solid_body: StaticBody3D
@export var detect_area: Area3D


func _ready() -> void:
	if detect_area:
		detect_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _is_player_ship(body):
		complete()  # Spawns the completion effect.
		queue_free()
