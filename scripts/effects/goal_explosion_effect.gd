class_name GoalExplosionEffect
extends Node3D
## One-shot burst spawned when a mission is completed.

@export var shake_strength := 1.4
@export var shake_duration := 1.4
@export var shake_frequency := 14.0
@export var shake_rotation_deg := 4.0
## Multiplied by the effect's scale.
@export var shake_falloff_distance := 120.0
## Object radius the effect is authored for at scale 1.
@export var reference_radius := 20.0
@export var min_scale := 0.25
@export var max_scale := 50.0


func fit_to_radius(radius: float) -> void:
	if radius <= 0.0 or reference_radius <= 0.0:
		return
	scale = Vector3.ONE * clampf(radius / reference_radius, min_scale, max_scale)


func _ready() -> void:
	var longest := 0.0
	for child in get_children():
		if child is GPUParticles3D:
			child.local_coords = true
			child.restart()
			longest = maxf(longest, child.lifetime)
	# Deferred so the spawner can set global_position first.
	_shake.call_deferred()
	get_tree().create_timer(longest + 0.5).timeout.connect(queue_free)


func _shake() -> void:
	var size_factor := global_basis.get_scale().x
	ScreenShakeHandler.shake_at(
		global_position,
		shake_falloff_distance * size_factor,
		shake_strength,
		shake_duration,
		shake_frequency,
		shake_rotation_deg,
	)
