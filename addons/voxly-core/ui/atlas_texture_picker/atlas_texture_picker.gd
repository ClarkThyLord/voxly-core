@tool
extends ScrollContainer

## Emitted when a texture coordinate is selected.
signal texture_xy_selected(uv: Vector2i)

## Emitted when a texture coordinate is unselected.
signal texture_xy_unselected(uv: Vector2i)

## When set (>= 0), the picker shows transparent reference highlights at the
## texture coordinates currently used by the voxel's faces. User can still
## click to select any cell freely.
@export_range(-1, 100, 1, "or_greater")
var voxel_id: int = -1:
	set = _set_voxel_id

## The VoxelSet whose atlas to display.
@export
var voxel_set: VoxelSet = null:
	set = _set_voxel_set

## Which faces to read reference textures from. When set, each face's texture
## is highlighted with a transparent fill for reference.
## Example: [Vector3i.ZERO, Vector3i.UP] will highlight base and top faces textures.
@export
var reference_faces: Array[Vector3i] = []:
	set = _set_reference_faces

## Currently selected texture coordinates.
@export
var selected_texture_xy: Array[Vector2i] = []:
	set = _set_selected_texture_xy,
	get = _get_selected_texture_xy

## Maximum textures that can be selected (-1 = unlimited, 0 = no selection).
@export_range(-1, 10, 1, "or_greater")
var selection_max: int = -1:
	set = _set_selection_max

## Transparent fill for reference highlights (shows current voxel face textures).
@export
var reference_color: Color = Color(1, 0.84, 0, 0.6)

## Border color for the hovered cell.
@export
var hovered_color: Color = Color(1, 1, 1, 0.6)

## Border color for selected cells.
@export
var selected_color: Color = Color.WHITE

## Border color for invalid cells (outside atlas bounds).
@export
var invalid_color: Color = Color.RED

@onready
var _atlas_texture: TextureRect = %AtlasTexture

var _last_uv_hovered: Vector2i = - Vector2i.ONE
var _selected_texture_xy: Array[Vector2i] = []

# Maps UV coordinate → array of face names that reference it.
# Built by _sync_from_voxel() for the reference highlight tooltip.
var _reference_uvs: Dictionary[Vector2i, Array] = {}

var _context_menu: PopupMenu = null
var _pending_refresh := false

enum ContextAction {
	SELECT,
	UNSELECT,
	UNSELECT_ALL,
}

func has_selected(uv: Vector2i) -> bool:
	return uv in _selected_texture_xy

func get_selected_texture_xy() -> Array[Vector2i]:
	return _selected_texture_xy.duplicate()

func select_texture_xy(uv: Vector2i) -> void:
	if _is_valid_texture_xy(uv):
		_select(uv)
		queue_redraw()

func unselect_texture_xy(uv: Vector2i) -> void:
	_unselect(uv)
	queue_redraw()

func clear_selections() -> void:
	while not _selected_texture_xy.is_empty():
		_unselect(_selected_texture_xy.back())
	queue_redraw()

func _ready() -> void:
	mouse_exited.connect(_on_mouse_exited)
	
	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_action)
	add_child(_context_menu)

	if _pending_refresh:
		_refresh()
	_sync_references()

func _draw() -> void:
	if not voxel_set or not voxel_set.is_texture_ready():
		return
	
	var cell_size := voxel_set.texture_atlas_cell_size
	var scroll_offset := Vector2i(scroll_horizontal, scroll_vertical)
	
	# Draw reference highlights (border only for voxel face textures)
	for uv in _reference_uvs:
		var rect := Rect2(Vector2i(uv * cell_size) - scroll_offset, cell_size)
		draw_rect(rect, reference_color, false, 3.0)
	
	# Draw currently selected textures (full border)
	for uv in _selected_texture_xy:
		var rect := Rect2(Vector2i(uv * cell_size) - scroll_offset, cell_size)
		draw_rect(rect, selected_color, false, 3.0)
	
	# Draw hovered cell border
	if _last_uv_hovered != -Vector2i.ONE:
		var rect := Rect2(Vector2i(_last_uv_hovered * cell_size) - scroll_offset, cell_size)
		var color := hovered_color if _is_valid_texture_xy(_last_uv_hovered) else invalid_color
		draw_rect(rect, color, false, 3.0)

func _set_selection_max(value: int) -> void:
	selection_max = clampi(value, -1, 256)
	_shrink_selection()
	queue_redraw()

func _set_voxel_set(new_set: VoxelSet) -> void:
	if voxel_set == new_set:
		return
	if voxel_set and voxel_set.texture_atlas_changed.is_connected(_on_atlas_changed):
		voxel_set.texture_atlas_changed.disconnect(_on_atlas_changed)
	voxel_set = new_set
	if voxel_set and not voxel_set.texture_atlas_changed.is_connected(_on_atlas_changed):
		voxel_set.texture_atlas_changed.connect(_on_atlas_changed)
	if is_inside_tree():
		_refresh()
	else:
		_pending_refresh = true

func _set_voxel_id(new_id: int) -> void:
	if new_id == voxel_id:
		return
	voxel_id = new_id
	_sync_references()
	if is_inside_tree():
		queue_redraw()

func _set_reference_faces(new_faces: Array[Vector3i]) -> void:
	reference_faces = new_faces.duplicate()
	_sync_references()
	if is_inside_tree():
		queue_redraw()

func _set_selected_texture_xy(new_uvs: Array[Vector2i]) -> void:
	_selected_texture_xy = new_uvs.duplicate()
	queue_redraw()

func _get_selected_texture_xy() -> Array[Vector2i]:
	return _selected_texture_xy.duplicate()

## Reads textures from the voxel's faces and builds _reference_uvs.
## This is purely visual — does not affect selection.
func _show_context_menu(uv: Vector2i, at_position: Vector2) -> void:
	_context_menu.clear()
	
	if uv in _selected_texture_xy:
		_context_menu.add_item("Unselect", ContextAction.UNSELECT)
	else:
		_context_menu.add_item("Select", ContextAction.SELECT)
	
	if not _selected_texture_xy.is_empty():
		_context_menu.add_item("Unselect All", ContextAction.UNSELECT_ALL)
	
	_context_menu.set_meta("context_uv", uv)
	_context_menu.popup(Rect2i(at_position, Vector2i.ZERO))

func _on_context_action(action_id: int) -> void:
	var uv: Vector2i = _context_menu.get_meta("context_uv", -Vector2i.ONE)
	if uv == -Vector2i.ONE:
		return
	
	match action_id:
		ContextAction.SELECT:
			if uv not in _selected_texture_xy:
				_select(uv)
				queue_redraw()
		ContextAction.UNSELECT:
			if uv in _selected_texture_xy:
				_unselect(uv)
				queue_redraw()
		ContextAction.UNSELECT_ALL:
			clear_selections()

func _sync_references() -> void:
	_reference_uvs.clear()
	
	if voxel_id < 0 or not voxel_set or not voxel_set.voxel_id_exists(voxel_id):
		return
	
	var voxel := voxel_set.get_voxel(voxel_id)
	if not voxel:
		return
	
	# Vector3i.ZERO, reference base texture xy
	var show_base: bool = false
	for face in reference_faces:
		if face == Vector3i.ZERO:
			show_base = true
		else:
			var tex := voxel.get_face_texture_xy(face)
			if tex >= Vector2i.ZERO:
				if not _reference_uvs.has(tex):
					_reference_uvs[tex] = []
				_reference_uvs[tex].append(Voxel.FACE_NAMES[face])

	if show_base:
		var base_tex := voxel.base_texture_xy
		if base_tex >= Vector2i.ZERO:
			if not _reference_uvs.has(base_tex):
				_reference_uvs[base_tex] = []
			_reference_uvs[base_tex].append("base")

func _on_atlas_changed() -> void:
	_refresh()

func _refresh() -> void:
	if not _atlas_texture:
		_pending_refresh = true
		return
	_pending_refresh = false

	if voxel_set and voxel_set.is_texture_ready():
		_atlas_texture.texture = voxel_set.texture_atlas
		var tex_size := voxel_set.texture_atlas.get_size()
		_atlas_texture.custom_minimum_size = tex_size
		_atlas_texture.size = tex_size
	else:
		_atlas_texture.texture = null
		_atlas_texture.custom_minimum_size = Vector2.ZERO

	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_last_uv_hovered = _pos_to_texture(event.position)
		queue_redraw()
		_update_tooltip()

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if selection_max == 0:
			return
		var uv := _pos_to_texture(event.position)
		if _is_valid_texture_xy(uv):
			_show_context_menu(uv, get_screen_position() + event.position)

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if selection_max == 0:
			return
		var uv := _pos_to_texture(event.position)
		if not _is_valid_texture_xy(uv):
			return
		if uv in _selected_texture_xy:
			_unselect(uv)
		else:
			_select(uv)
		queue_redraw()

func _on_mouse_exited() -> void:
	_last_uv_hovered = - Vector2i.ONE
	queue_redraw()

func _pos_to_texture(pos: Vector2) -> Vector2i:
	if not voxel_set or not voxel_set.is_texture_ready():
		return -Vector2i.ONE
	var scroll_offset := Vector2(scroll_horizontal, scroll_vertical)
	var atlas_pos := pos + scroll_offset
	return Vector2i(
		floori(atlas_pos.x / voxel_set.texture_atlas_cell_size.x),
		floori(atlas_pos.y / voxel_set.texture_atlas_cell_size.y)
	)

func _is_valid_texture_xy(uv: Vector2i) -> bool:
	return voxel_set and voxel_set.is_texture_atlas_position(uv)

func _update_tooltip() -> void:
	if _last_uv_hovered == -Vector2i.ONE:
		tooltip_text = ""
	else:
		var text := str(_last_uv_hovered)
		var faces := _reference_uvs.get(_last_uv_hovered)
		if faces and not faces.is_empty():
			text += " — %s" % ", ".join(faces)
		tooltip_text = text

func _select(uv: Vector2i) -> void:
	if selection_max == 0:
		return
	if selection_max > 0 and _selected_texture_xy.size() >= selection_max:
		_shrink_selection(selection_max - 1)
	_selected_texture_xy.append(uv)
	texture_xy_selected.emit(uv)
	notify_property_list_changed()

func _unselect(uv: Vector2i) -> void:
	_selected_texture_xy.erase(uv)
	texture_xy_unselected.emit(uv)
	notify_property_list_changed()

func _shrink_selection(limit: int = selection_max) -> void:
	if limit >= 0:
		while _selected_texture_xy.size() > limit:
			_unselect(_selected_texture_xy.back())
