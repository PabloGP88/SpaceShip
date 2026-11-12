class_name Player
extends Node3D

@export_group("Movement")
@export var roll_impulse := 2.0
@export var pitch_impulse := 2.0
@export var yaw_impulse := 2.0
@export var thrust_force := 20.0
@export var rotation_correction_speed := 1.0
@export var rotation_correction_multiplier := 1.0
@export var rotation_correction_exponent := 0.01

@export_group("Orbit lock")

@export var min_lock_altitude := 10.0
@export var max_lock_altitude := 700.0
@export var orbit_speed_multiplier := 2.0
@export var orbit_boost_response := 3.0
@export var orbit_align_speed := 4.0
@export var orbit_charge_time := 2.0
@export var orbit_charge_slow_scale := 0.4
@export var orbit_charge_peak_weak := 0.6
@export var orbit_charge_peak_strong := 1.0
@export var orbit_boost_shake_strength := 0.4
@export var orbit_boost_shake_duration := 0.5
@export var orbit_boost_shake_frequency := 25.0
@export var orbit_boost_shake_rotation_deg := 1.0

@export_group("Fuel")
@export var fuel_drain_rate := 20.0

@export_group("Components")
@export var fuel_component: FuelComponent
@export var gravity_effect: GravityEffect
@export var ship: RigidBody3D

@export_group("Effects")
@export var thrust_effect: GPUParticles3D
@export var thrust_in_orbit_effect: GPUParticles3D
@export var thrust_pitch_variation := 0.08
@export var thrust_volume_variation_db := 2.0
@export var explosion: PackedScene = preload("res://scenes/effects/explosion_ship.tscn")
@export var explosion_offset := 2.0
@export var death_shake_strength := 1.0
@export var death_shake_duration := 1.0
@export var death_shake_frequency := 18.0
@export var death_shake_rotation_deg := 3.0
@export var mission_rumble_weak := 0.5
@export var mission_rumble_strong := 0.35
@export var mission_rumble_duration := 0.25
@export var mission_shake_strength := 0.25
@export var mission_shake_duration := 0.35
@export var mission_shake_frequency := 16.0
@export var mission_shake_rotation_deg := 0.6

var _locked_orbit: Orbit
var _locked_source: Node3D
var _lock_time := 0.0
var _orbit_time_scale := 1.0
var _orbit_charge := 0.0
var _is_dead := false
var _was_thrusting := false
var _impact_rumble_left := 0.0
var _thrust_sound: AudioStreamPlayer


func _ready() -> void:
	add_to_group("player")
	_set_thrust_emitting(false)

	ship.contact_monitor = true
	ship.max_contacts_reported = maxi(ship.max_contacts_reported, 4)
	ship.body_entered.connect(_on_ship_body_entered)

	if GameState.in_menu:
		_enter_menu_mode()
		GameState.game_started.connect(_exit_menu_mode, CONNECT_ONE_SHOT)


func _enter_menu_mode() -> void:
	gravity_effect.enabled = false
	ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	ship.freeze = true
	_set_thrust_emitting(true)


func _exit_menu_mode() -> void:
	ship.freeze = false
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	gravity_effect.enabled = true
	_set_thrust_emitting(false)


func _on_ship_body_entered(body: Node) -> void:
	if GameState.in_menu:
		return
	if body.is_in_group(&"deadly"):
		var hit := _get_contact_point(body)
		var away := ship.global_position - hit
		if away.is_zero_approx() and body is Node3D:
			away = ship.global_position - body.global_position
		on_dead(hit + away.normalized() * explosion_offset)


func _get_contact_point(body: Node) -> Vector3:
	var state := PhysicsServer3D.body_get_direct_state(ship.get_rid())
	if state:
		for i in state.get_contact_count():
			if state.get_contact_collider_object(i) == body:
				# Despite the name, this is in global space.
				return state.get_contact_local_position(i)
	return ship.global_position


func is_dead() -> bool:
	return _is_dead


func on_dead(hit_point: Vector3 = ship.global_position) -> void:
	if _is_dead:
		return
	_is_dead = true
	# Stop thrust first so it can't cut off the death sound.
	_set_thrust_emitting(false)
	Input.start_joy_vibration(0, 1.0, 1.0, 3.0)
	_spawn_explosion(hit_point)
	var sfx := SoundEffectManager.find(get_tree())
	if sfx:
		sfx.play_sound_effect(SoundEffectManager.PLAYER_DESTROY)
	ScreenShakeHandler.shake(
		death_shake_strength,
		death_shake_duration,
		death_shake_frequency,
		death_shake_rotation_deg,
	)

	ship.hide()
	ship.set_deferred(&"freeze", true)


func play_mission_impact() -> void:
	if _is_dead:
		return
	_impact_rumble_left = mission_rumble_duration
	Input.start_joy_vibration(
		0, mission_rumble_weak, mission_rumble_strong, mission_rumble_duration)
	ScreenShakeHandler.shake(
		mission_shake_strength,
		mission_shake_duration,
		mission_shake_frequency,
		mission_shake_rotation_deg,
	)


func _spawn_explosion(at: Vector3) -> void:
	if explosion == null:
		return
	var fx := explosion.instantiate() as Node3D
	get_tree().current_scene.add_child(fx)
	fx.global_position = at

	var longest := 0.0
	for child in fx.get_children():
		if child is GPUParticles3D:
			longest = maxf(longest, child.lifetime)
	get_tree().create_timer(longest + 0.5).timeout.connect(fx.queue_free)


func _physics_process(delta: float) -> void:
	_impact_rumble_left = maxf(_impact_rumble_left - delta, 0.0)
	if _is_dead or GameState.in_menu:
		return
	if _locked_orbit:
		_apply_orbit_boost(delta)
		_follow_locked_orbit(delta)
		return
	_apply_rotation_correction()
	_apply_rotation(delta)
	_apply_thrust(delta)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.in_menu:
		return
	if event.is_action_pressed(&"toggle_orbit_lock") and not event.is_echo():
		if _locked_orbit:
			unlock_orbit()
		else:
			lock_orbit()


func get_orbit_source() -> Node3D:
	return gravity_effect.strongest_source(ship.global_position)


func get_current_orbit() -> Orbit:
	if _locked_orbit:
		return _locked_orbit
	var source := get_orbit_source()
	return gravity_effect.orbit_around(source)


func get_orbit_velocity() -> Vector3:
	if _locked_orbit:
		return _locked_orbit.velocity_at(_lock_time)
	return ship.linear_velocity


func can_lock_orbit() -> bool:
	var source := get_orbit_source()
	if source == null:
		return false
	var orbit := gravity_effect.orbit_around(source)
	var radius := GravityEffect.source_radius(source)
	return orbit.is_stable(radius + min_lock_altitude) \
			and orbit.apoapsis <= radius + max_lock_altitude


func get_locked_source() -> Node3D:
	return _locked_source


func is_orbit_boosting() -> bool:
	return _locked_orbit != null and _is_thrust_pressed() \
			and fuel_component.fuel > 0.0 and _orbit_charge >= orbit_charge_time


func is_orbit_locked() -> bool:
	return _locked_orbit != null


## Rides the current orbit on rails so it never decays.
func lock_orbit() -> bool:
	if _locked_orbit or not can_lock_orbit():
		return false
	_locked_source = get_orbit_source()
	_locked_orbit = gravity_effect.orbit_around(_locked_source)
	_lock_time = 0.0
	_orbit_time_scale = 1.0
	_orbit_charge = 0.0
	gravity_effect.enabled = false

	ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	ship.freeze = true
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	return true


func unlock_orbit() -> void:
	if not _locked_orbit:
		return
	ship.freeze = false
	ship.linear_velocity = _locked_orbit.velocity_at(_lock_time)
	ship.angular_velocity = Vector3.ZERO
	_orbit_time_scale = 1.0
	_orbit_charge = 0.0
	if _was_thrusting and not _is_dead and _impact_rumble_left <= 0.0:
		Input.stop_joy_vibration(0)
	_was_thrusting = false
	_locked_orbit = null
	_locked_source = null
	gravity_effect.enabled = true


func _follow_locked_orbit(delta: float) -> void:
	if not is_instance_valid(_locked_source):
		unlock_orbit()
		return
	_lock_time += delta * _orbit_time_scale
	var rel_position := _locked_orbit.position_at(_lock_time)
	ship.global_position = _locked_source.global_position + rel_position
	_align_to_orbit(rel_position, _locked_orbit.velocity_at(_lock_time), delta)


func _align_to_orbit(rel_position: Vector3, velocity: Vector3, delta: float) -> void:
	var up := rel_position.normalized()
	var forward := velocity.normalized()
	if up.is_zero_approx() or forward.is_zero_approx() \
			or forward.cross(up).is_zero_approx():
		return
	var target := Basis.looking_at(forward, up).get_rotation_quaternion()
	var current := ship.global_basis.orthonormalized().get_rotation_quaternion()
	var weight := 1.0 - exp(-orbit_align_speed * delta)
	ship.global_basis = Basis(current.slerp(target, weight))


func _apply_orbit_boost(delta: float) -> void:
	var held := _is_thrust_pressed() and fuel_component.fuel > 0.0
	var was_charged := _orbit_charge >= orbit_charge_time
	if held:
		_orbit_charge = minf(_orbit_charge + delta, orbit_charge_time)
	else:
		_orbit_charge = 0.0
	var charged := held and _orbit_charge >= orbit_charge_time
	_set_thrust_emitting(charged)
	if charged and not was_charged:
		var sfx := SoundEffectManager.find(get_tree())
		if sfx:
			sfx.play_sound_effect(SoundEffectManager.ORBIT_BOOST)
		ScreenShakeHandler.shake(
			orbit_boost_shake_strength,
			orbit_boost_shake_duration,
			orbit_boost_shake_frequency,
			orbit_boost_shake_rotation_deg,
		)

	var target_scale := 1.0
	if charged:
		target_scale = orbit_speed_multiplier
	elif held:
		target_scale = orbit_charge_slow_scale

	_orbit_time_scale = move_toward(
		_orbit_time_scale,
		target_scale,
		orbit_boost_response * maxf(orbit_speed_multiplier - 1.0, 1.0) * delta,
	)
	if charged:
		fuel_component.add_fuel(-fuel_drain_rate * delta)

	if _impact_rumble_left > 0.0:
		pass
	elif held:
		var t := _orbit_charge / orbit_charge_time if orbit_charge_time > 0.0 else 1.0
		Input.start_joy_vibration(
			0, orbit_charge_peak_weak * t, orbit_charge_peak_strong * t, 0.2)
	elif _was_thrusting:
		Input.stop_joy_vibration(0)
	_was_thrusting = held


func _set_thrust_emitting(on: bool) -> void:
	var in_orbit := is_orbit_locked()
	thrust_effect.emitting = on and not in_orbit
	thrust_in_orbit_effect.emitting = on and in_orbit
	_set_thrust_sound(on and not GameState.in_menu)


func _set_thrust_sound(on: bool) -> void:
	if on == (_thrust_sound != null):
		return
	if on:
		var sfx := SoundEffectManager.find(get_tree())
		if sfx:
			_thrust_sound = sfx.play_sound_effect(SoundEffectManager.THRUST,
					thrust_pitch_variation, thrust_volume_variation_db, true)
	else:
		var sfx := SoundEffectManager.find(get_tree())
		if sfx:
			sfx.stop_sound_effect(_thrust_sound)
		else:
			_thrust_sound.stop()
		_thrust_sound = null


func _apply_rotation(delta: float) -> void:
	var roll := clampf(
		int(Input.is_physical_key_pressed(KEY_A)) - int(Input.is_physical_key_pressed(KEY_D))
		+ Input.get_axis(&"ship_roll_right", &"ship_roll_left"),
		-1.0, 1.0,
	)
	var pitch := clampf(
		int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
		+ Input.get_axis(&"ship_pitch_down", &"ship_pitch_up"),
		-1.0, 1.0,
	)
	var yaw := clampf(
		int(Input.is_physical_key_pressed(KEY_Q)) - int(Input.is_physical_key_pressed(KEY_E))
		+ Input.get_axis(&"ship_yaw_right", &"ship_yaw_left"),
		-1.0, 1.0,
	)

	var torque := ship.global_basis.z * roll * roll_impulse \
			+ ship.global_basis.x * pitch * pitch_impulse \
			+ ship.global_basis.y * yaw * yaw_impulse

	if torque != Vector3.ZERO:
		ship.apply_torque_impulse(torque * delta)


func _apply_thrust(delta: float) -> void:
	var thrusting := _is_thrust_pressed() and fuel_component.fuel > 0.0
	_set_thrust_emitting(thrusting)

	if thrusting:
		ship.apply_central_force(-ship.global_basis.z * thrust_force)
		fuel_component.add_fuel(-fuel_drain_rate * delta)

	if _is_dead:
		return
	if _impact_rumble_left > 0.0:
		pass
	elif thrusting:
		Input.start_joy_vibration(0, 0.1, 0.2, 0.5)
	elif _was_thrusting:
		Input.stop_joy_vibration(0)
	_was_thrusting = thrusting


func _is_thrust_pressed() -> bool:
	return Input.is_physical_key_pressed(KEY_SPACE) or Input.is_action_pressed(&"ship_thrust")


func _apply_rotation_correction() -> void:
	var closest_gravity_body: GravityBody
	var closest_gravity_body_distance: float = INF
	for node in get_tree().get_nodes_in_group(&"gravity"):
		var gravity_body := node as GravityBody
		if not gravity_body:
			continue
		var gravity_body_distance: float = (
			gravity_body.global_position - ship.global_position
		).length()

		if gravity_body_distance < closest_gravity_body_distance:
			closest_gravity_body = gravity_body
			closest_gravity_body_distance = gravity_body_distance

	if not closest_gravity_body:
		return

	var closest_gravity_body_radius: float = closest_gravity_body.diameter / 2.0
	# Clamped: a negative base to a fractional power is NaN.
	var altitude := maxf(closest_gravity_body_distance - closest_gravity_body_radius, 0.0)
	var rotation_correction_coefficient: float = rotation_correction_multiplier / (
		(altitude + 1.0) ** rotation_correction_exponent
	)
	var rotation_correction: float = rotation_correction_coefficient * rotation_correction_speed

	if rotation_correction < 0.01:
		return

	var up: Vector3 = ship.global_position - closest_gravity_body.global_position

	if up.is_zero_approx():
		return
	up = up.normalized()

	var nose: Vector3 = -ship.global_basis.z
	var forward = nose - up * nose.dot(up)
	if forward.is_zero_approx():
		var ship_up: Vector3 = ship.global_basis.y
		forward = ship_up - up * ship_up.dot(up)
		if forward.is_zero_approx():
			return

	var target_basis := Basis.looking_at(forward, up)
	var current_basis: Basis = ship.global_basis.orthonormalized()

	var error: Quaternion = target_basis.get_rotation_quaternion() \
			* current_basis.get_rotation_quaternion().inverse()
	if error.w < 0.0:
		error = -error
	var angle := error.get_angle()
	if angle < 0.0001:
		return # get_axis() is NaN for an identity rotation

	ship.angular_velocity += error.get_axis() * angle * rotation_correction
