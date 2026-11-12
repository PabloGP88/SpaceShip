class_name FuelComponent
extends Node

@export var starting_fuel: float = 200.0
## Raised to starting_fuel if lower.
@export var max_fuel: float = 0.0

@onready var fuel: float = starting_fuel


func _ready() -> void:
	max_fuel = maxf(max_fuel, starting_fuel)


func add_fuel(delta_fuel: float) -> void:
	fuel = clampf(fuel + delta_fuel, 0.0, max_fuel)


func get_fraction() -> float:
	return fuel / max_fuel if max_fuel > 0.0 else 0.0
