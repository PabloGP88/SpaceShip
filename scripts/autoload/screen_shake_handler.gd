extends Node
## Global screen shake. Offsets the active camera's h/v_offset; rotation is
## read by the camera through get_rotation_basis().

class Shake:
	var strength: float
	var duration: float
	var frequency: float
	var rotation: float
	var falloff: float
	var elapsed := 0.0
	var seed: float

@export var enabled := true
@export_range(0.0, 2.0) var global_multiplier := 1.0
@export var max_offset := 2.0
@export var max_rotation_degrees := 10.0

var _shakes: Array[Shake] = []
var _noise := FastNoiseLite.new()
var _offset := Vector2.ZERO
var _rotation := Vector3.ZERO
var _applied_offset := Vector2.ZERO
var _camera: Camera3D


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()


func shake(
	strength := 0.3,
	duration := 0.4,
	frequency := 20.0,
	rotation_deg := 0.5,
	falloff := 2.0,
) -> void:
	if not enabled or duration <= 0.0 or (strength <= 0.0 and rotation_deg <= 0.0):
		return
	var s := Shake.new()
	s.strength = strength
	s.duration = duration
	s.frequency = frequency
	s.rotation = deg_to_rad(rotation_deg)
	s.falloff = falloff
	s.seed = randf() * 10000.0
	_shakes.append(s)


## Like shake(), weakened by the camera's distance to source.
func shake_at(
	source: Vector3,
	radius: float,
	strength := 0.3,
	duration := 0.4,
	frequency := 20.0,
	rotation_deg := 0.5,
	falloff := 2.0,
) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or radius <= 0.0:
		return
	var dist := cam.global_position.distance_to(source)
	if dist >= radius:
		return
	var attenuation := pow(1.0 - dist / radius, 2.0)
	shake(strength * attenuation, duration, frequency, rotation_deg * attenuation, falloff)


func get_rotation_basis() -> Basis:
	return Basis.from_euler(_rotation)


func _process(delta: float) -> void:
	_offset = Vector2.ZERO
	_rotation = Vector3.ZERO

	for i in range(_shakes.size() - 1, -1, -1):
		var s := _shakes[i]
		s.elapsed += delta
		if s.elapsed >= s.duration:
			_shakes.remove_at(i)
			continue
		var t := s.elapsed * s.frequency
		var amount := pow(1.0 - s.elapsed / s.duration, s.falloff)
		_offset += Vector2(_sample(s.seed, t), _sample(s.seed + 100.0, t)) * s.strength * amount
		_rotation += Vector3(
			_sample(s.seed + 200.0, t),
			_sample(s.seed + 300.0, t),
			_sample(s.seed + 400.0, t),
		) * s.rotation * amount

	var mult := global_multiplier if enabled else 0.0
	_offset = _offset.limit_length(max_offset) * mult
	var max_rot := deg_to_rad(max_rotation_degrees)
	_rotation = _rotation.clamp(Vector3.ONE * -max_rot, Vector3.ONE * max_rot) * mult
	_apply_offset()


func _sample(row: float, t: float) -> float:
	return _noise.get_noise_2d(t, row)


func _apply_offset() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != _camera:
		if is_instance_valid(_camera):
			_camera.h_offset -= _applied_offset.x
			_camera.v_offset -= _applied_offset.y
		_applied_offset = Vector2.ZERO
		_camera = cam
	if _camera == null:
		return
	_camera.h_offset += _offset.x - _applied_offset.x
	_camera.v_offset += _offset.y - _applied_offset.y
	_applied_offset = _offset
