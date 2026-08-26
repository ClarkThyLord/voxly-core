@tool
class_name Capture
extends Node

@export_tool_button("Capture", "Camera")
var capture_button = capture

@export var save_to : String = "res://capture.png"

@export var reference_camera : Camera3D

@export var transparent_background : bool = false

@export_group("Capture on Ready")
@export var capture_on_ready : bool = false

## How many seconds to wait before taking the shot (0 for instant)
@export var capture_on_ready_delay_seconds: float = 0.0

@export_group("Quality")
@export
var use_taa : bool = true

@export
var msaa_3d : Viewport.MSAA = Viewport.MSAA.MSAA_4X

@export
var screen_space_aa : Viewport.ScreenSpaceAA = Viewport.ScreenSpaceAA.SCREEN_SPACE_AA_SMAA

func _ready() -> void:
	# Optional delay to let the main scene load or animations settle.
	if capture_on_ready_delay_seconds > 0:
		await get_tree().create_timer(capture_on_ready_delay_seconds).timeout
	
	if capture_on_ready:
		capture()

func capture() -> void:
	# Find the active camera in your main scene.
	var main_cam: Camera3D = get_viewport().get_camera_3d()
	if is_instance_valid(reference_camera):
		main_cam = reference_camera
	
	if not is_instance_valid(main_cam):
		push_error("Camera3D not found in the scene!")
		return
	
	# Setup a hidden SubViewport for the transparent render.
	var sub_viewport = SubViewport.new()
	sub_viewport.size = get_viewport().get_window().size
	if transparent_background:
		sub_viewport.transparent_bg = true
	
	# Set TAA.
	sub_viewport.use_taa = use_taa
	
	# Set MSAA quality.
	sub_viewport.msaa_3d = msaa_3d
	
	# Set screen space AA.
	sub_viewport.screen_space_aa = screen_space_aa
	
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	add_child(sub_viewport)

	# Create a duplicate camera and match it to the main camera.
	var duplicate_cam = main_cam.duplicate()
	sub_viewport.add_child(duplicate_cam)
	
	# Sync position, rotation, and field of view fields.
	duplicate_cam.global_transform = main_cam.global_transform
	duplicate_cam.fov = main_cam.fov
	duplicate_cam.near = main_cam.near
	duplicate_cam.far = main_cam.far
	duplicate_cam.keep_aspect = main_cam.keep_aspect
	
	# Wait for the engine to render the new SubViewport frame.
	await RenderingServer.frame_post_draw
	
	# Extract and format the transparent image.
	var image: Image = sub_viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	
	# Save to the user folder.
	var error = image.save_png(save_to)
	
	if error == OK:
		print("Success! Render saved to: ", ProjectSettings.globalize_path(save_to))
	else:
		print("Failed to save render. Error:\n", error)
	
	# Clean up the temporary nodes.
	sub_viewport.queue_free()
