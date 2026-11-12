class_name GravityBody
extends Node3D

@export var diameter: float = 1.0


func _ready() -> void:
	add_to_group("bodies")
	# Scale the children: Jolt ignores scale on a RigidBody3D.
	for child in get_children():
		if child is Node3D:
			var node := child as Node3D
			node.transform = node.transform.scaled(Vector3.ONE * diameter)
