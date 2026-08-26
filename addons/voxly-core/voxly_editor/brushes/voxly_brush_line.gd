@tool
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/line.svg")

var _drag_origin: Vector3i = Vector3i.ZERO
var _dragging: bool = false
var _cached_drag_positions: Array[Vector3i] = []
var _width: int = 1
var _drag_end: Vector3i = Vector3i.ZERO

func _init() -> void:
	name = "line"
	display_name = "Line"
	requires_drag = true
	icon = ICON

func supports_continuous() -> bool:
	return false

## Width/thickness of the line in voxel units.
var width: int:
	set(v):
		_width = maxi(v, 1)

func get_options() -> Array[Dictionary]:
	return [
		{"label": "Width", "property": "width", "type": TYPE_INT, "default": 1, "min": 1, "max": 16, "step": 1}
	]

# Returns the voxel position at the given hit, with tool placement offset applied.
func _compute_offset_pos(editor, hit: Dictionary) -> Vector3i:
	var pos := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	return offset_for_tool(editor, pos, normal, hit.get("dda_hit", false))

func get_positions(editor, hit: Dictionary) -> Array[Vector3i]:
	# While actively dragging, return the cached preview positions.
	if _dragging:
		return _cached_drag_positions.duplicate()
	elif hit.is_empty():
		return []
	var pos := _compute_offset_pos(editor, hit)
	return [pos]

func on_drag_start(editor, hit: Dictionary) -> void:
	_dragging = true
	_cached_drag_positions.clear()
	# Compute the offset origin (with tool placement) for the first voxel.
	_drag_origin = _compute_offset_pos(editor, hit)
	# Cache the single origin position so click-without-drag still works
	_cached_drag_positions = [_drag_origin]

func on_drag_move(editor, hit: Dictionary) -> Array[Vector3i]:
	if not _dragging:
		return []
	
	# Compute the offset end position using the current hit's normal.
	var end := _compute_offset_pos(editor, hit)
	_drag_end = end
	# Draw the Bresenham line between the (already-offset) origin and the offset end.
	var spine := _bresenham_3d(_drag_origin, end)
	
	# Apply width: expand each spine voxel to a box of size `width`
	if _width > 1:
		var half := _width / 2
		var expanded: Array[Vector3i] = []
		for p in spine:
			for x in range(-half, _width - half):
				for y in range(-half, _width - half):
					for z in range(-half, _width - half):
						expanded.append(p + Vector3i(x, y, z))
		# Deduplicate
		var seen: Dictionary[Vector3i, bool] = {}
		var unique: Array[Vector3i] = []
		for p in expanded:
			if not seen.has(p):
				seen[p] = true
				unique.append(p)
		_cached_drag_positions = unique
		return unique
	
	_cached_drag_positions = spine
	return spine

func get_drag_info() -> String:
	if not _dragging:
		return ""
	
	var dx := absi(_drag_end.x - _drag_origin.x) + 1
	var dy := absi(_drag_end.y - _drag_origin.y) + 1
	var dz := absi(_drag_end.z - _drag_origin.z) + 1
	return "Line: %dx%dx%d" % [dx, dy, dz]

func on_drag_end() -> void:
	_dragging = false

## Bresenham 3D line algorithm - returns all voxel positions along a line.
func _bresenham_3d(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	var positions: Array[Vector3i] = []
	var current := from
	
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	var dz := absi(to.z - from.z)
	
	var sx := 1 if to.x > from.x else -1
	var sy := 1 if to.y > from.y else -1
	var sz := 1 if to.z > from.z else -1
	
	if dx >= dy and dx >= dz:
		var py := 2 * dy - dx
		var pz := 2 * dz - dx
		for i in range(dx + 1):
			positions.append(current)
			if py >= 0:
				current.y += sy
				py -= 2 * dx
			if pz >= 0:
				current.z += sz
				pz -= 2 * dx
			py += 2 * dy
			pz += 2 * dz
			current.x += sx
	elif dy >= dx and dy >= dz:
		var px := 2 * dx - dy
		var pz := 2 * dz - dy
		for i in range(dy + 1):
			positions.append(current)
			if px >= 0:
				current.x += sx
				px -= 2 * dy
			if pz >= 0:
				current.z += sz
				pz -= 2 * dy
			px += 2 * dx
			pz += 2 * dz
			current.y += sy
	else:
		var px := 2 * dx - dz
		var py := 2 * dy - dz
		for i in range(dz + 1):
			positions.append(current)
			if px >= 0:
				current.x += sx
				px -= 2 * dz
			if py >= 0:
				current.y += sy
				py -= 2 * dz
			px += 2 * dx
			py += 2 * dy
			current.z += sz
	
	return positions
