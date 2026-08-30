## Interactive forest example controller.
##
## Provides a Minecraft-style block interaction on top of a VoxelModel3D:
##   - Left click  : destroy the voxel currently being looked at
##   - Right click : place the currently selected voxel against the targeted face
##   - Middle click: pick the targeted voxel and select it as the active block
##   - Scroll      : cycle through the voxel set's available block types
extends Node3D

## How far the target raycast reaches in world units.
@export var reach_distance := 6.0

## Scale applied to the hand block preview.
@export var hand_preview_scale := 0.6

## How far the hand block preview sits in front of the camera along -Z.
@export var hand_preview_distance := 1.2

## How far the hand block preview sits to the right of the camera center.
@export var hand_preview_lateral := 0.6

## How far the hand block preview sits below the camera center.
@export var hand_preview_height := -0.5

const BOX_OUTLINE_SHADER := preload("res://addons/voxly-core/shaders/box_outline.gdshader")

## The voxel model world being interacted with.
@onready var world: VoxelModel3D = %World
## The player camera used for targeting.
@onready var camera: Camera3D = %CharacterCamera3D
## The mesh preview showing the currently selected block.
@onready var hand_preview: MeshInstance3D = %CharacterBlockPreview
## Plays the hand swing animations.
@onready var animation_player: AnimationPlayer = %CharacterAnimationPlayer

## Selectable voxel IDs, cycled with the scroll wheel.
var _voxel_ids: Array[int] = []

## Currently selected voxel ID for placement.
var _selected_voxel_id := 0

## Index into _voxel_ids for the current selection.
var _selection_index := 0

## Outline overlay showing the targeted voxel.
var _outline: MeshInstance3D = null

## Cached result of the last DDA raycast.
var _current_raycast := {}

## Countdown for the current hand swing before returning to the rest pose.
var _action_timer := 0.0

## Builds the target outline and seeds the selectable block list.
func _ready() -> void:
	_build_outline()
	
	# Seed the selectable block list from the voxel set.
	_voxel_ids.assign(world.voxel_set.get_voxel_ids())
	if _voxel_ids.is_empty():
		push_warning("VoxelSet has no voxels to select from")
	_selection_index = 0
	if _voxel_ids.size() > 0:
		_update_selection(_voxel_ids[0])

## Updates the target outline and hand preview each frame.
func _process(delta: float) -> void:
	var hit := _raycast_target()
	_current_raycast = hit
	
	if hit.has("hit"):
		var world_pos := world.voxel_to_world_position(hit.hit_position)
		var half := world.voxel_size / 2.0
		_outline.global_position = world_pos + half
		_outline.visible = true
	else:
		_outline.visible = false
	
	# Follow the camera position but leave rotation to the animation player
	# so placed/removed block swings play correctly.
	var held_offset := Vector3(hand_preview_lateral, hand_preview_height, -hand_preview_distance)
	hand_preview.global_position = camera.global_transform * held_offset
	
	# Once a swing completes, return the hand to its rest pose.
	if _action_timer > 0.0:
		_action_timer -= delta
		if _action_timer <= 0.0 and animation_player and animation_player.current_animation == "action":
			animation_player.play("RESET")

## Handles mouse button actions and scroll-wheel selection cycling.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if captured:
					_destroy_target()
			MOUSE_BUTTON_RIGHT:
				if captured:
					_place_selected()
			MOUSE_BUTTON_MIDDLE:
				if captured:
					_pick_target()
			MOUSE_BUTTON_WHEEL_UP:
				_cycle_selection(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_cycle_selection(1)

## Returns the DDA hit dictionary from the camera's center ray, or {} on miss.
func _raycast_target() -> Dictionary:
	if not world or not camera:
		return {}
	
	var direction := -camera.global_transform.basis.z
	return world.voxel_raycast(camera.global_position, direction, reach_distance)

## Destroys the targeted voxel if it exists and is within the model.
func _destroy_target() -> void:
	if not _current_raycast.has("hit"):
		return
	
	var position: Vector3i = _current_raycast.hit_position
	if not world.is_voxel_position_valid(position):
		return
	if world.get_voxel(position) == null:
		return
	
	world.remove_voxel(position)
	world.update()
	_play_action_animation()

## Places the selected voxel against the targeted face if the slot is empty.
func _place_selected() -> void:
	if not _current_raycast.has("hit"):
		return
	
	var target_position: Vector3i = _current_raycast.hit_position
	var position: Vector3i = target_position + _current_raycast.hit_normal
	if not world.is_voxel_position_valid(position):
		return
	if world.get_voxel(position) != null:
		return
	
	world.set_voxel(position, _selected_voxel_id)
	world.update()
	_play_action_animation()

## Selects the targeted voxel as the active placement block.
func _pick_target() -> void:
	if not _current_raycast.has("hit"):
		return
	var voxel_id: Variant = world.get_voxel(_current_raycast.hit_position)
	if typeof(voxel_id) != TYPE_INT:
		return
	if not world.voxel_set.voxel_id_exists(int(voxel_id)):
		return
	var index := _voxel_ids.find(int(voxel_id))
	if index == -1:
		return
	
	_selection_index = index
	_update_selection(int(voxel_id))

## Cycles the active selection by `direction` (positive = next, negative = previous).
func _cycle_selection(direction: int) -> void:
	if _voxel_ids.is_empty():
		return
	
	_selection_index = wrapi(_selection_index + direction, 0, _voxel_ids.size())
	_update_selection(_voxel_ids[_selection_index])

## Plays the hand block "action" swing animation once, then returns to rest.
func _play_action_animation() -> void:
	if not animation_player:
		return
	var anim := animation_player.get_animation("action")
	if not anim:
		return
	
	animation_player.play("action")
	_action_timer = anim.length / maxf(animation_player.speed_scale, 0.001)

## Regenerates the hand block preview mesh for the given voxel ID.
func _update_selection(voxel_id: int) -> void:
	_selected_voxel_id = voxel_id
	# Generate the block at hand_preview_scale so the mesh is already sized.
	var mesh := VoxelPreview.generate(voxel_id, world.voxel_set, hand_preview_scale)
	if mesh:
		hand_preview.mesh = mesh
		hand_preview.visible = true
	else:
		hand_preview.visible = false

## Builds the outline overlay cage that highlights the targeted voxel.
func _build_outline() -> void:
	_outline = MeshInstance3D.new()
	_outline.name = "TargetOutline"
	var box := BoxMesh.new()
	# Slightly smaller than a full voxel so the cage reads as an outline.
	box.size = world.voxel_size * 0.98
	var material := ShaderMaterial.new()
	material.shader = BOX_OUTLINE_SHADER
	material.set_shader_parameter("outline_color", Color(0.2, 1.0, 0.8, 0.95))
	box.material = material
	_outline.mesh = box
	_outline.visible = false
	add_child(_outline)
