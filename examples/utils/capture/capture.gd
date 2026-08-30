## Dev utility for capturing the current viewport to a PNG render.
##
## Renders the active camera's view into a hidden SubViewport (optionally with
## a transparent background and configurable anti-aliasing quality), then saves
## the image. Use the "Capture" tool button in the inspector or set
## `capture_on_ready` to shoot automatically after a delay.
@tool
class_name Capture
extends Node

## Inspector tool button that triggers a capture.
@export_tool_button("Capture", "Camera")
var capture_button = capture

## Where the rendered image is saved (a res:// or user:// path).
@export var save_to: String = "res://capture.png"

## Optional camera override; when set, this camera is rendered instead of the
## active viewport camera.
@export var reference_camera: Camera3D

## When true, the captured background is transparent instead of opaque.
@export var transparent_background: bool = false

@export_group("Capture on Ready")
## Whether a capture runs automatically when the node is ready.
@export var capture_on_ready: bool = false

## How many seconds to wait before taking the shot (0 for instant).
@export var capture_on_ready_delay_seconds: float = 0.0

@export_group("Quality")
## Whether temporal anti-aliasing is enabled in the capture viewport.
@export var use_taa: bool = true

## MSAA level used in the capture viewport.
@export var msaa_3d: Viewport.MSAA = Viewport.MSAA.MSAA_4X

## Screen-space anti-aliasing used in the capture viewport.
@export var screen_space_aa: Viewport.ScreenSpaceAA = Viewport.ScreenSpaceAA.SCREEN_SPACE_AA_SMAA

## Captures automatically after the configured delay when capture_on_ready is enabled.
func _ready() -> void:
	# Optional delay to let the main scene load or animations settle.
	if capture_on_ready_delay_seconds > 0:
		await get_tree().create_timer(capture_on_ready_delay_seconds).timeout
	
	if capture_on_ready:
		capture()

## Captures the current viewport to `save_to` via a hidden SubViewport.
func capture() -> void:
	# Find the active camera in the main scene.
	var active_camera: Camera3D = get_viewport().get_camera_3d()
	if is_instance_valid(reference_camera):
		active_camera = reference_camera
	
	if not is_instance_valid(active_camera):
		push_error("Camera3D not found in the scene!")
		return
	
	# Setup a hidden SubViewport for the render.
	var sub_viewport := SubViewport.new()
	sub_viewport.size = get_viewport().get_window().size
	if transparent_background:
		sub_viewport.transparent_bg = true
	
	# Set anti-aliasing quality.
	sub_viewport.use_taa = use_taa
	sub_viewport.msaa_3d = msaa_3d
	sub_viewport.screen_space_aa = screen_space_aa
	
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	add_child(sub_viewport)
	
	# Create a duplicate camera and match it to the main camera.
	var duplicate_camera: Camera3D = active_camera.duplicate()
	sub_viewport.add_child(duplicate_camera)
	
	# Sync position, rotation, and field of view fields.
	duplicate_camera.global_transform = active_camera.global_transform
	duplicate_camera.fov = active_camera.fov
	duplicate_camera.near = active_camera.near
	duplicate_camera.far = active_camera.far
	duplicate_camera.keep_aspect = active_camera.keep_aspect
	
	# Wait for the engine to render the new SubViewport frame.
	await RenderingServer.frame_post_draw
	
	# Extract and format the image.
	var image: Image = sub_viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	
	# Save to the configured path.
	var error: Error = image.save_png(save_to)
	
	if error == OK:
		print("Success! Render saved to: ", ProjectSettings.globalize_path(save_to))
	else:
		print("Failed to save render. Error:\n", error)
	
	# Clean up the temporary nodes.
	sub_viewport.queue_free()
