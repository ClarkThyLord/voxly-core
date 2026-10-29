## Example utility for smoothly moving light around radius.
extends OmniLight3D

## How fast the light moves.
@export var speed: float = 2.0

## How far it can drift from its starting point.
@export var radius: float = 0.5

## Controls the organic "jerkiness" of the movement.
@export var noise_scale: float = 5.0

## Track the starting anchor position.
var _start_position: Vector3

## Noise generator for movement.
var _noise: FastNoiseLite

## Track the starting time.
var _time_passed: float = 0.0

func _ready() -> void:
	# Save the original position so it moves "in place"
	_start_position = position
	
	# Set up the _noise generator for organic movement
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.frequency = 0.5

func _process(delta: float) -> void:
	_time_passed += delta * speed
	
	# Calculate smooth, pseudo-random offsets using _noise + offset.
	var offset_x = _noise.get_noise_1d(_time_passed * noise_scale)
	var offset_y = _noise.get_noise_1d(_time_passed * noise_scale + 100.0)
	var offset_z = _noise.get_noise_1d(_time_passed * noise_scale + 200.0)
	
	# Combine offsets and apply the radius modifier
	var offset = Vector3(offset_x, offset_y, offset_z) * radius
	
	# Apply smoothly to the position
	position = _start_position + offset
