@tool
extends Node3D

## Auto-rotation speed in degrees per second.
@export
var camera_speed := 20.0

## Whether the camera auto-rotates around the pivot when idle.
@export
var auto_rotate := true

## When true, the camera and pivot transforms authored in the scene
## are respected on play, and double-click reset restores them exactly.
## When false, the orbit camera overrides the scene.
@export
var respect_scene_camera := true

## Minimum distance from camera to pivot in meters.
@export
var zoom_min := 2.0

## Maximum distance from camera to pivot in meters.
@export
var zoom_max := 30.0

## Distance change per scroll tick.
@export
var zoom_step := 1.0

## Mouse drag sensitivity for orbit.
@export
var orbit_sensitivity := 0.005

var _auto_rotate := true
var _is_dragging := false
var _camera: Camera3D = null
var _camera_distance: float = 5.0
var _orbit_horizontal := 0.0
var _orbit_vertical := -0.35
var _last_click_time: float = 0.0

# Exact scene-authored transforms used by double-click reset when respecting
# the scene camera.
var _initial_pivot_transform: Transform3D
var _initial_camera_transform: Transform3D

# Snapshot of initial state for double-click reset.
var _initial_pivot_rotation: float = 0.0
var _initial_camera_distance: float = 5.0
var _initial_orbit_vertical: float = -0.35

@onready
var camera_pivot : Node3D = %CameraPivot


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	_auto_rotate = auto_rotate
	
	if not camera_pivot:
		return
	
	for child in camera_pivot.get_children():
		if child is Camera3D:
			_camera = child
			break
	
	# Derive orbit trackers from the existing camera so interactions hand off
	# smoothly without snapping to the script's default framing.
	_sync_orbit_from_camera()
	
	# Snapshot the exact scene state for reset.
	_initial_pivot_transform = camera_pivot.transform
	if _camera:
		_initial_camera_transform = _camera.transform
	
	_initial_pivot_rotation = camera_pivot.rotation.y
	_initial_camera_distance = _camera_distance
	_initial_orbit_vertical = _orbit_vertical
	_orbit_horizontal = camera_pivot.rotation.y
	
	# Only rebuild the camera transform when the scene camera is not respected.
	if not respect_scene_camera:
		_update_camera_position()


func _process(delta : float) -> void:
	if Engine.is_editor_hint():
		return
	elif not camera_pivot:
		return
	
	if _auto_rotate and not _is_dragging:
		camera_pivot.rotate_y(deg_to_rad(camera_speed * delta))


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	elif not _camera or not camera_pivot:
		return
	
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Double-click detection (within 0.3s)
				var now := Time.get_ticks_msec() / 1000.0
				var time_since_last := now - _last_click_time
				_last_click_time = now
				if time_since_last < 0.3:
					_reset_camera()
					return
				
				# Sync orbit tracker with current pivot rotation to prevent snap.
				_is_dragging = true
				_auto_rotate = false
				_orbit_horizontal = camera_pivot.rotation.y
			else:
				_is_dragging = false
				_auto_rotate = auto_rotate
			get_viewport().set_input_as_handled()
		
		MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = clamp(_camera_distance - zoom_step, zoom_min, zoom_max)
			_update_camera_position()
			get_viewport().set_input_as_handled()
		
		MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = clamp(_camera_distance + zoom_step, zoom_min, zoom_max)
			_update_camera_position()
			get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _is_dragging:
		return
	
	var delta := event.relative * orbit_sensitivity
	
	# Horizontal drag orbits the pivot around Y.
	_orbit_horizontal -= delta.x
	camera_pivot.rotation.y = _orbit_horizontal
	
	# Vertical drag tilts the camera up/down.
	_orbit_vertical = clamp(_orbit_vertical - delta.y, -1.55, 1.55)
	
	_update_camera_position()
	
	get_viewport().set_input_as_handled()


## Re-positions the camera from orbital angles and distance.
func _update_camera_position() -> void:
	if not _camera:
		return
	
	var pos := Vector3(
		0.0,
		sin(_orbit_vertical) * _camera_distance,
		-cos(_orbit_vertical) * _camera_distance
	)
	_camera.position = pos
	_camera.look_at(Vector3.ZERO, Vector3.UP)


## Re-syncs the orbit trackers from the camera's current scene position so
## that drag/zoom interactions continue from the authored framing.
func _sync_orbit_from_camera() -> void:
	if not _camera:
		return
	
	var pos := _camera.position
	_camera_distance = clamp(pos.length(), zoom_min, zoom_max)
	if _camera_distance > 0.001:
		_orbit_vertical = asin(clamp(pos.y / _camera_distance, -1.0, 1.0))


## Resets the camera to its initial scene setup.
func _reset_camera() -> void:
	if not _camera or not camera_pivot:
		return
	
	_is_dragging = false
	_auto_rotate = auto_rotate
	
	if respect_scene_camera:
		# Restore the exact scene-authored transforms and re-sync the orbit
		# trackers so subsequent interaction continues from that state.
		camera_pivot.transform = _initial_pivot_transform
		_camera.transform = _initial_camera_transform
		_sync_orbit_from_camera()
		_orbit_horizontal = camera_pivot.rotation.y
	else:
		_orbit_horizontal = _initial_pivot_rotation
		_orbit_vertical = _initial_orbit_vertical
		_camera_distance = _initial_camera_distance
		camera_pivot.rotation.y = _initial_pivot_rotation
		_update_camera_position()
