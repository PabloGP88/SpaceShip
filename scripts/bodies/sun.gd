@tool
class_name Sun
extends Node3D
## Follows the camera at a fixed distance and drives the sunlight.

@export var direction := Vector3(0.433, 0.5, 0.75):
	set(v):
		direction = v.normalized() if v.length() > 0.0 else Vector3.UP
		_update()
@export var distance := 3200.0:
	set(v):
		distance = v
		_update()
@export var radius := 650.0:
	set(v):
		radius = v
		_update()
@export var corona_scale := 3.0:
	set(v):
		corona_scale = v
		_update()

@export_range(0.0, 20.0, 0.1, "or_greater") var light_intensity := 3.0:
	set(v):
		light_intensity = v
		_update()
@export_range(0.0, 50.0, 0.1, "or_greater") var glow_intensity := 12.0:
	set(v):
		glow_intensity = v
		_update()

@export_range(0.0, 1.0, 0.01) var shadow_strength := 0.85:
	set(v):
		shadow_strength = v
		_update()

@export_group("Fill Light")
@export_range(0.0, 10.0, 0.05, "or_greater") var fill_intensity := 0.6:
	set(v):
		fill_intensity = v
		_update()
@export var fill_color := Color(0.55, 0.65, 1.0):
	set(v):
		fill_color = v
		_update()
## 0 = opposite the sun, 1 = from the side.
@export_range(0.0, 1.0, 0.01) var fill_side_offset := 0.35:
	set(v):
		fill_side_offset = v
		_update()
@export_group("")

@onready var _fill: DirectionalLight3D = $FillLight
@onready var _body: MeshInstance3D = $Body
@onready var _corona: MeshInstance3D = $Corona
@onready var _light: DirectionalLight3D = $DirectionalLight3D


func _ready() -> void:
	# Run after the camera has moved this frame to avoid jitter.
	process_priority = 1000
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if not is_node_ready():
		return

	var origin := Vector3.ZERO
	var dist := distance
	if not Engine.is_editor_hint():
		var cam := get_viewport().get_camera_3d()
		if cam:
			origin = cam.global_position
			dist = minf(distance, cam.far * 0.9 - radius * corona_scale * 0.5)

	global_position = origin + direction * dist
	_body.scale = Vector3.ONE * radius
	_corona.scale = Vector3.ONE * radius * corona_scale

	_light.light_energy = light_intensity
	_light.shadow_opacity = shadow_strength

	var side := direction.cross(Vector3.UP)
	if side.length() < 0.01:
		side = direction.cross(Vector3.RIGHT)
	var fill_dir := (-direction).slerp(side.normalized(), fill_side_offset * 0.999).normalized()
	var fill_up := Vector3.UP if absf(fill_dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	_fill.global_basis = Basis.looking_at(-fill_dir, fill_up)
	_fill.light_energy = fill_intensity
	_fill.light_color = fill_color
	_fill.visible = fill_intensity > 0.0

	var surf := (_body.mesh as SphereMesh).material as ShaderMaterial
	surf.set_shader_parameter("energy", glow_intensity)
	var cor := (_corona.mesh as QuadMesh).material as ShaderMaterial
	cor.set_shader_parameter("intensity", glow_intensity * 0.25)

	# Directional lights shine along -Z: point -Z away from the sun.
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	_light.global_basis = Basis.looking_at(-direction, up)
