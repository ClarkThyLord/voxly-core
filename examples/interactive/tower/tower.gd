extends Node3D
## Interactive tower example controller.
##
## A top-down "world overview" where the user clicks to stack random tower
## blocks from the towers voxel set. The overview camera glides up as the
## tower grows so the newest block always stays framed.
##
##   - Left click  : stack a random block on top of the tower
##   - Right click : pop the top block back off (down to the foundation)

## The tower column sits in the center of the Towers model
const CENTER_X := 1
const CENTER_Z := 1

## How quickly the camera eases toward the current tower top (higher = snappier).
@export var camera_follow_speed := 6.0

## Voxel ID used for the foundation block.
@export var foundation_voxel_id := 0

@onready var towers: VoxelModel3D = %Towers
@onready var camera_pivot: Node3D = %CameraPivot

## Buildable voxel IDs, drawn from randomly when stacking.
var _voxel_ids: Array[int] = []

## Number of blocks currently in the tower.
var _height := 1

## HUD label showing the controls and current tower height.
@onready
var _hud: Label = %HUD


func _ready() -> void:
	# Seed the buildable block list from the tower voxel set.
	_voxel_ids.assign(towers.voxel_set.get_voxel_ids())
	if _voxel_ids.is_empty():
		push_warning("Towers VoxelSet has no voxels to stack")
	
	# Re-seed the tower with a single centered foundation so the stack is
	# guaranteed to be dead-center regardless of the baked scene data.
	towers.clear_voxels()
	towers.set_voxel(Vector3i(CENTER_X, 0, CENTER_Z), foundation_voxel_id)
	towers.update()
	_height = 1

	# Start the camera level with the foundation top.
	camera_pivot.position.y = _get_tower_top_world_y()
	_update_hud()


func _process(delta: float) -> void:
	if not towers or not camera_pivot:
		return
	
	# Ease the overview camera up/down to frame the current tower top.
	var target_y := _get_tower_top_world_y()
	camera_pivot.position.y = lerpf(
		camera_pivot.position.y,
		target_y,
		1.0 - exp(-delta * camera_follow_speed)
	)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_add_block()
			MOUSE_BUTTON_RIGHT:
				_remove_block()


## Stacks a random block from the voxel set onto the tower's top.
func _add_block() -> void:
	if _height >= towers.shape.y:
		return
	elif _voxel_ids.is_empty():
		return
	
	var voxel_id: int = _voxel_ids.pick_random()
	towers.set_voxel(Vector3i(CENTER_X, _height, CENTER_Z), voxel_id)
	towers.update()
	_height += 1
	_update_hud()


## Pops the top block off, leaving the foundation in place.
func _remove_block() -> void:
	if _height <= 1:
		return
	_height -= 1
	towers.remove_voxel(Vector3i(CENTER_X, _height, CENTER_Z))
	towers.update()
	_update_hud()


## World-space Y of the center of the currently highest block, used as the
## camera follow target so the tower top stays framed in the overview.
func _get_tower_top_world_y() -> float:
	if not towers:
		return 0.0
	
	var top_local: Vector3 = towers.voxel_to_world_position(
		Vector3i(CENTER_X, _height - 1, CENTER_Z)
	)
	var top_world: Vector3 = towers.to_global(top_local)
	return top_world.y + towers.voxel_size.y * 0.5


func _update_hud() -> void:
	if _hud:
		_hud.text = "   Left Click: Stack Block   |   Right Click: Pop Block   |   Height: %d" % _height
