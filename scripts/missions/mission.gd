class_name Mission
extends PointOfInterest

signal completed

@export var completion_effect: PackedScene = preload("res://scenes/effects/goal_explosion_effect.tscn")

var is_completed := false


func complete() -> void:
	if is_completed:
		return
	is_completed = true
	remove_from_group(GROUP)
	_spawn_completion_effect()
	var sfx := SoundEffectManager.find(get_tree())
	if sfx:
		sfx.play_sound_effect(SoundEffectManager.MISSION_DESTROY)
	for player in get_tree().get_nodes_in_group(&"player"):
		if player is Player:
			(player as Player).play_mission_impact()
	completed.emit()


func _spawn_completion_effect() -> void:
	if completion_effect == null:
		return
	var fx := completion_effect.instantiate() as Node3D
	if fx.has_method(&"fit_to_radius"):
		fx.call(&"fit_to_radius", get_world_radius())
	# Parent to the scene so it outlives the mission.
	get_tree().current_scene.add_child(fx)
	fx.global_position = global_position


func get_world_radius() -> float:
	var bounds := AABB()
	var found := false
	for node in find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		if not vi.is_visible_in_tree() or vi.is_in_group(&"exclude_from_bounds"):
			continue
		var box := vi.global_transform * vi.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	if not found:
		return 0.0
	var size := bounds.size
	return maxf(size.x, maxf(size.y, size.z)) * 0.5


func _is_player_ship(body: Node) -> bool:
	for player in get_tree().get_nodes_in_group(&"player"):
		if player is Player and (player as Player).ship == body:
			return true
	return false
