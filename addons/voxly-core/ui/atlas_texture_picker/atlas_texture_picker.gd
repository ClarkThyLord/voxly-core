## Atlas texture cell picker.
##
## Displays a texture atlas as a grid and lets the user select one or more
## cells, with per-face reference highlights and a right-click context menu.
@tool
extends ScrollContainer

## Emitted when a texture cell is selected.
signal texture_cell_selected(texture_cell: Vector2i)

## Emitted when a texture cell is unselected.
signal texture_cell_unselected(texture_cell: Vector2i)

## When set (>= 0), the picker shows transparent reference highlights at the
## texture cells currently used by the voxel's faces. The user can still click
## to select any cell freely.
@export_range(-1, 100, 1, "or_greater")
var voxel_id: int = -1:
	set = _set_voxel_id

## The VoxelSet whose atlas to display.
@export var voxel_set: VoxelSet = null:
	set = _set_voxel_set

## Which faces to read reference textures from. When set, each face's texture
## is highlighted with a transparent fill for reference.
## Example: [Vector3i.ZERO, Vector3i.UP] will highlight base and top face textures.
@export var reference_faces: Array[Vector3i] = []:
	set = _set_reference_faces

## Currently selected texture cells.
@export var selected_texture_cell: Array[Vector2i] = []:
	set = _set_selected_texture_cell,
	get = _get_selected_texture_cell

## Maximum textures that can be selected (-1 = unlimited, 0 = no selection).
@export_range(-1, 10, 1, "or_greater")
var selection_max: int = -1:
	set = _set_selection_max

## Transparent fill for reference highlights (shows current voxel face textures).
@export var reference_color: Color = Color(1, 0.84, 0, 0.6)

## Border color for the hovered cell.
@export var hovered_color: Color = Color(1, 1, 1, 0.6)

## Border color for selected cells.
@export var selected_color: Color = Color.WHITE

## Border color for invalid cells (outside atlas bounds).
@export var invalid_color: Color = Color.RED

## TextureRect displaying the atlas.
@onready var _atlas_texture: TextureRect = %AtlasTexture

## Cell under the mouse, or (-1, -1) when not hovering.
var _last_hovered_cell: Vector2i = -Vector2i.ONE
## Currently selected atlas cells.
var _selected_texture_cell: Array[Vector2i] = []

# Maps texture cell Ã¢â€ â€™ array of face names that reference it.
## Atlas cells referenced by the voxel faces.
var _reference_cells: Dictionary[Vector2i, Array] = {}

## Right-click context menu.
var _context_menu: PopupMenu = null
## True while a refresh is queued for the ready state.
var _pending_refresh := false

## Actions available in the picker right-click context menu.
enum ContextAction {
	SELECT,
	UNSELECT,
	UNSELECT_ALL,
}

## Returns whether the given cell is selected.
func has_selected(texture_cell: Vector2i) -> bool:
	return texture_cell in _selected_texture_cell

## Returns the selected cells.
func get_selected_texture_cell() -> Array[Vector2i]:
	return _selected_texture_cell.duplicate()

## Selects the given cell.
func select_texture_cell(texture_cell: Vector2i) -> void:
	if _is_valid_texture_cell(texture_cell):
		_select(texture_cell)
		queue_redraw()

## Unselects the given cell.
func unselect_texture_cell(texture_cell: Vector2i) -> void:
	_unselect(texture_cell)
	queue_redraw()

## Clears all cell selections.
func clear_selections() -> void:
	while not _selected_texture_cell.is_empty():
		_unselect(_selected_texture_cell.back())
	queue_redraw()

## Connects input and refresh signals.
func _ready() -> void:
	mouse_exited.connect(_on_mouse_exited)
	
	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_action)
	add_child(_context_menu)
	
	if _pending_refresh:
		_refresh()
	_sync_references()

## Draws the atlas grid and selection highlights.
func _draw() -> void:
	if not voxel_set or not voxel_set.is_texture_ready():
		return
	
	var cell_size := voxel_set.texture_atlas_cell_size
	var scroll_offset := Vector2i(scroll_horizontal, scroll_vertical)
	
	# Draw reference highlights (border only for voxel face textures).
	for texture_cell in _reference_cells:
		var rect := Rect2(Vector2i(texture_cell * cell_size) - scroll_offset, cell_size)
		draw_rect(rect, reference_color, false, 3.0)
	
	# Draw currently selected textures (full border).
	for texture_cell in _selected_texture_cell:
		var rect := Rect2(Vector2i(texture_cell * cell_size) - scroll_offset, cell_size)
		draw_rect(rect, selected_color, false, 3.0)
	
	# Draw the hovered cell border.
	if _last_hovered_cell != -Vector2i.ONE:
		var rect := Rect2(Vector2i(_last_hovered_cell * cell_size) - scroll_offset, cell_size)
		var color := hovered_color if _is_valid_texture_cell(_last_hovered_cell) else invalid_color
		draw_rect(rect, color, false, 3.0)

## Clamps and applies the maximum selection count.
func _set_selection_max(value: int) -> void:
	selection_max = clampi(value, -1, 256)
	_shrink_selection()
	queue_redraw()

## Updates the voxel set and schedules a refresh.
func _set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if voxel_set == new_voxel_set:
		return
	if voxel_set and voxel_set.texture_atlas_changed.is_connected(_on_atlas_changed):
		voxel_set.texture_atlas_changed.disconnect(_on_atlas_changed)
	voxel_set = new_voxel_set
	if voxel_set and not voxel_set.texture_atlas_changed.is_connected(_on_atlas_changed):
		voxel_set.texture_atlas_changed.connect(_on_atlas_changed)
	if is_inside_tree():
		_refresh()
	else:
		_pending_refresh = true

## Updates the voxel ID and schedules a refresh.
func _set_voxel_id(new_voxel_id: int) -> void:
	if new_voxel_id == voxel_id:
		return
	voxel_id = new_voxel_id
	_sync_references()
	if is_inside_tree():
		queue_redraw()

## Updates the referenced face list.
func _set_reference_faces(new_faces: Array[Vector3i]) -> void:
	reference_faces = new_faces.duplicate()
	_sync_references()
	if is_inside_tree():
		queue_redraw()

## Updates the selected cells list.
func _set_selected_texture_cell(new_cells: Array[Vector2i]) -> void:
	_selected_texture_cell = new_cells.duplicate()
	queue_redraw()

## Internal getter for the selected cells.
func _get_selected_texture_cell() -> Array[Vector2i]:
	return _selected_texture_cell.duplicate()

## Shows the context menu for the given texture cell.
func _show_context_menu(texture_cell: Vector2i, at_position: Vector2) -> void:
	_context_menu.clear()
	
	if texture_cell in _selected_texture_cell:
		_context_menu.add_item("Unselect", ContextAction.UNSELECT)
	else:
		_context_menu.add_item("Select", ContextAction.SELECT)
	
	if not _selected_texture_cell.is_empty():
		_context_menu.add_item("Unselect All", ContextAction.UNSELECT_ALL)
	
	_context_menu.set_meta("context_cell", texture_cell)
	_context_menu.popup(Rect2i(at_position, Vector2i.ZERO))

## Handles context menu actions for cells.
func _on_context_action(action_id: int) -> void:
	var texture_cell: Vector2i = _context_menu.get_meta("context_cell", -Vector2i.ONE)
	if texture_cell == -Vector2i.ONE:
		return
	
	match action_id:
		ContextAction.SELECT:
			if texture_cell not in _selected_texture_cell:
				_select(texture_cell)
				queue_redraw()
		ContextAction.UNSELECT:
			if texture_cell in _selected_texture_cell:
				_unselect(texture_cell)
				queue_redraw()
		ContextAction.UNSELECT_ALL:
			clear_selections()

## Reads the voxel's face textures and builds the reference cell map.
func _sync_references() -> void:
	_reference_cells.clear()
	
	if voxel_id < 0 or not voxel_set or not voxel_set.voxel_id_exists(voxel_id):
		return
	
	var voxel := voxel_set.get_voxel(voxel_id)
	if not voxel:
		return
	
	# Vector3i.ZERO references the base texture cell.
	var show_base: bool = false
	for face in reference_faces:
		if face == Vector3i.ZERO:
			show_base = true
		else:
			var texture_cell := voxel.get_face_texture_cell(face)
			if texture_cell >= Vector2i.ZERO:
				if not _reference_cells.has(texture_cell):
					_reference_cells[texture_cell] = []
				_reference_cells[texture_cell].append(Voxel.FACE_NAMES[face])
	
	if show_base:
		var base_texture_cell := voxel.base_texture_cell
		if base_texture_cell >= Vector2i.ZERO:
			if not _reference_cells.has(base_texture_cell):
				_reference_cells[base_texture_cell] = []
			_reference_cells[base_texture_cell].append("base")

## Refreshes when the atlas changes.
func _on_atlas_changed() -> void:
	_refresh()

## Rebuilds the display and selection state.
func _refresh() -> void:
	if not _atlas_texture:
		_pending_refresh = true
		return
	_pending_refresh = false
	
	if voxel_set and voxel_set.is_texture_ready():
		_atlas_texture.texture = voxel_set.texture_atlas
		var texture_size := voxel_set.texture_atlas.get_size()
		_atlas_texture.custom_minimum_size = texture_size
		_atlas_texture.size = texture_size
	else:
		_atlas_texture.texture = null
		_atlas_texture.custom_minimum_size = Vector2.ZERO
	
	queue_redraw()

## Handles mouse input for hover, selection, and the context menu.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_last_hovered_cell = _position_to_cell(event.position)
		queue_redraw()
		_update_tooltip()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if selection_max == 0:
			return
		var texture_cell := _position_to_cell(event.position)
		if _is_valid_texture_cell(texture_cell):
			_show_context_menu(texture_cell, get_screen_position() + event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if selection_max == 0:
			return
		var texture_cell := _position_to_cell(event.position)
		if not _is_valid_texture_cell(texture_cell):
			return
		if texture_cell in _selected_texture_cell:
			_unselect(texture_cell)
		else:
			_select(texture_cell)
		queue_redraw()

## Clears the hover state.
func _on_mouse_exited() -> void:
	_last_hovered_cell = -Vector2i.ONE
	queue_redraw()

## Converts a local position to an atlas cell.
func _position_to_cell(position: Vector2) -> Vector2i:
	if not voxel_set or not voxel_set.is_texture_ready():
		return -Vector2i.ONE
	var scroll_offset := Vector2(scroll_horizontal, scroll_vertical)
	var atlas_position := position + scroll_offset
	return Vector2i(
		floori(atlas_position.x / voxel_set.texture_atlas_cell_size.x),
		floori(atlas_position.y / voxel_set.texture_atlas_cell_size.y)
	)

## Returns whether the cell is inside the atlas grid.
func _is_valid_texture_cell(texture_cell: Vector2i) -> bool:
	return voxel_set and voxel_set.is_texture_cell_valid(texture_cell)

## Updates the tooltip for the hovered cell.
func _update_tooltip() -> void:
	if _last_hovered_cell == -Vector2i.ONE:
		tooltip_text = ""
	else:
		var text := str(_last_hovered_cell)
		var face_names := _reference_cells.get(_last_hovered_cell)
		if face_names and not face_names.is_empty():
			text += " Ã¢â‚¬â€ %s" % ", ".join(face_names)
		tooltip_text = text

## Selects a cell, enforcing the selection limit.
func _select(texture_cell: Vector2i) -> void:
	if selection_max == 0:
		return
	if selection_max > 0 and _selected_texture_cell.size() >= selection_max:
		_shrink_selection(selection_max - 1)
	_selected_texture_cell.append(texture_cell)
	texture_cell_selected.emit(texture_cell)
	notify_property_list_changed()

## Unselects a cell.
func _unselect(texture_cell: Vector2i) -> void:
	_selected_texture_cell.erase(texture_cell)
	texture_cell_unselected.emit(texture_cell)
	notify_property_list_changed()

## Trims the selection to the given limit.
func _shrink_selection(limit: int = selection_max) -> void:
	if limit >= 0:
		while _selected_texture_cell.size() > limit:
			_unselect(_selected_texture_cell.back())
