## First-person character controller for the forest example.
##
## WASD + mouse-look movement with jump, gravity, coyote time, jump buffering,
## and a head-bob camera effect. Esc captures/releases the mouse.
extends CharacterBody3D

## Movement speed in meters/second.
@export var walk_speed := 5.0

## Ground acceleration.
@export var ground_accel := 30.0

## Air acceleration.
@export var air_accel := 12.0

## Ground friction applied when no movement input is held.
@export var friction := 20.0

## Maximum fall speed so long drops feel stable.
@export var terminal_fall_speed := 25.0

## Jump velocity applied when the player jumps.
@export var jump_velocity := 6.0

## Gravity applied each physics tick.
@export var gravity := 14.0

## How long after walking off a ledge the player can still jump.
@export var coyote_time := 0.1

## How long a jump press stays buffered before landing.
@export var jump_buffer_time := 0.15

## Mouse look sensitivity.
@export var mouse_sensitivity := 0.002

## Maximum camera pitch in radians (looking up/down).
@export var pitch_limit := 1.45

@export_group("Head Bob")
## Whether the head-bob camera effect is enabled.
@export var head_bob_enabled := true
## Head-bob oscillation frequency in radians per second.
@export var head_bob_frequency := 9.0
## Head-bob vertical amplitude in meters.
@export var head_bob_amplitude := 0.05

## The player camera that mouse-look and head-bob drive.
@onready var camera: Camera3D = %CharacterCamera3D

## True while the mouse is captured for look input.
var _mouse_captured := false
## Remaining time the player can still jump after leaving the ground.
var _coyote_timer := 0.0
## Remaining time a jump press is remembered before landing.
var _jump_buffer_timer := 0.0
## Accumulated head-bob phase in seconds.
var _head_bob_time := 0.0
## Camera Y offset used as the head-bob rest position.
var _head_bob_base_y := 0.5


## Configures the camera and captures the mouse on play.
func _ready() -> void:
	camera.current = true
	# Render continuously between physics ticks instead of snapping per tick.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	_head_bob_base_y = camera.position.y
	_capture_mouse()


## Handles mouse look and escape-to-release input.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		# Yaw follows the character body, pitch is clamped on the camera.
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, -pitch_limit, pitch_limit)
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			_capture_mouse()


## Moves the character each physics tick.
func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	
	# Coyote time: refresh while grounded, drain while airborne.
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	
	# Remember a jump press so it fires on landing.
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	
	# Jump if a buffered press is active and we're grounded.
	if _jump_buffer_timer > 0.0 and (_coyote_timer > 0.0 or is_on_floor()):
		velocity.y = jump_velocity
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0
	
	# Gravity with a terminal fall speed so long falls feel stable.
	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -terminal_fall_speed)
	
	# Horizontal movement: accelerate toward the target velocity on the
	# ground, apply friction when idle, and use gentler acceleration in the
	# air so mid-air direction changes keep some momentum.
	var target := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var h_vel := Vector3(velocity.x, 0, velocity.z)
	if is_on_floor() and input_dir == Vector2.ZERO:
		h_vel = h_vel.move_toward(Vector3.ZERO, friction * walk_speed * delta)
	else:
		var accel := ground_accel if is_on_floor() else air_accel
		h_vel = h_vel.move_toward(target * walk_speed, accel * delta)
	velocity.x = h_vel.x
	velocity.z = h_vel.z
	
	move_and_slide()
	
	_update_head_bob(delta, h_vel.length())


## Applies the head-bob camera offset based on horizontal speed.
func _update_head_bob(delta: float, horizontal_speed: float) -> void:
	if not head_bob_enabled or not is_instance_valid(camera):
		return
	
	# Ease back to the base position when airborne or standing still.
	if not is_on_floor() or horizontal_speed < 0.5:
		_head_bob_time = 0.0
		camera.position = camera.position.lerp(
			Vector3(0, _head_bob_base_y, 0),
			1.0 - pow(0.01, delta)
		)
		return
	
	_head_bob_time += horizontal_speed * delta
	var amplitude := head_bob_amplitude * minf(horizontal_speed / walk_speed, 1.0)
	var bob_y := sin(_head_bob_time * head_bob_frequency) * amplitude
	var bob_x := cos(_head_bob_time * head_bob_frequency * 0.5) * amplitude * 0.5
	camera.position = Vector3(bob_x, _head_bob_base_y + bob_y, 0)


## Captures the mouse for look input.
func _capture_mouse() -> void:
	_mouse_captured = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
