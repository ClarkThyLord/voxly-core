@tool
extends Control

## Emitted when the user edits the voxel (color, texture, etc).
signal changed

signal face_edited(voxel_id: int, face: Vector3i)

enum ViewMode {
	VIEW_3D,
	VIEW_2D,
}
enum EditorMode {
	EDITABLE,
	VIEW_ONLY,
}
enum ContextAction {
	COLOR_FACE,
	TEXTURE_FACE,
	RESET_FACE_COLOR,
	RESET_FACE_TEXTURE_XY,
	COLOR_BASE,
	TEXTURE_BASE,
	RESET_BASE_COLOR,
	RESET_BASE_TEXTURE,
	COLOR_SELECTED,
	TEXTURE_SELECTED,
	RESET_SELECTED_COLOR,
	RESET_SELECTED_TEXTURE,
	SELECT_FACE,
	UNSELECT_FACE,
	SELECT_ALL_FACES,
	UNSELECT_ALL_FACES,
	CHANGE_ENVIRONMENT,
	RESET_ENVIRONMENT,
}

# Face button references
@onready var _mode_2d: Control = %Mode2D
@onready var _front_face = %FrontFace
@onready var _left_face = %LeftFace
@onready var _back_face = %BackFace
@onready var _top_face = %TopFace
@onready var _bottom_face = %BottomFace
@onready var _right_face = %RightFace
var _face_buttons: Dictionary[Vector3i, Button] = {}

# 3D references
@onready var _mode_3d: SubViewportContainer = %Mode3D
@onready var _viewport: SubViewport = %SubViewport
@onready var _voxel_preview: MeshInstance3D = %VoxelPreview
@onready var _voxel_highlight: MeshInstance3D = %VoxelHighlight
@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _camera: Camera3D = %Camera

# UI
@onready var _context_label: Label = %ContextLabel
@onready var _mode_dropdown: OptionButton = %ModeOptionButton
@onready var _edit_menu: MenuButton = %EditMenuButton
@onready var _settings_menu: MenuButton = %SettingsMenuButton

@onready
var _atlas_texture_picker_window: Window = %AtlasTexturePickerWindow

@onready
var _atlas_texture_picker = %AtlasTexturePicker

@onready
var _atlas_texture_picker_window_ok_button: Button = %AtlasTexturePickerWindowOkButton

@onready
var _atlas_texture_picker_window_cancel_button: Button = %AtlasTexturePickerWindowCancelButton

# Exports
@export var voxel_id: int = 0:
	set = _set_voxel_id

@export var voxel_set: VoxelSet = null:
	set = _set_voxel_set

## Default view mode (2D or 3D) applied on startup.
@export var default_view: ViewMode = ViewMode.VIEW_3D:
	set = _set_default_view

## Whether the editor is in editable or view-only mode.
@export var edit_mode: EditorMode = EditorMode.EDITABLE:
	set = _set_edit_mode

## Default environment to load at startup.
## Can be a .tres or .env file. Leave empty for transparent background.
@export var default_env: Environment = null:
	set = _set_default_env

## Minimum faces that must remain selected.
@export var selection_min: int = 0

## Maximum faces that can be selected (-1 = unlimited).
@export var selection_max: int = -1

@export
var camera_sensitivity: float = 1.0

var selected_faces: Array[Vector3i] = []
var _voxel: Voxel = null
var _pending_update := false
var _is_dragging := false
var _last_hovered_face: Vector3i = Vector3i.ZERO
var _context_menu_face: Vector3i = Vector3i.ZERO
var _env_path: String = ""
var _config_path: String = "user://voxel_editor_env.cfg"

@onready
var _color_picker_window := %ColorPickerWindow

var _context_menu: PopupMenu = null
var _color_faces: Array[Vector3i]
var _color_callback: Callable
var _atlas_target_faces: Array[Vector3i] = []
var _atlas_warning_dialog: AcceptDialog = null
var _highlight_material: StandardMaterial3D = null
var _undo_redo: UndoRedo = null
var _undo_redo_manager: EditorUndoRedoManager = null
var _env_file_dialog: FileDialog = null

# Color picker state
var _color_originals: Dictionary = {}
 # true if editing base_color, false if editing face overrides
var _is_color_base_mode: bool = false

# Atlas texture picker state
var _atlas_originals: Dictionary = {}
# true if editing base_texture_xy, false if editing face overrides
var _is_atlas_base_mode: bool = false

func set_undo_redo(undo_redo: UndoRedo) -> void:
	_undo_redo = undo_redo

func set_undo_redo_manager(manager: EditorUndoRedoManager) -> void:
	_undo_redo_manager = manager

func _set_voxel_set(new_set: VoxelSet) -> void:
	if new_set == voxel_set:
		return
	if _voxel and _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.disconnect(_on_voxel_changed)
	voxel_set = new_set
	_voxel = voxel_set.get_voxel(voxel_id) if voxel_set and voxel_id >= 0 else null
	if _voxel and not _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.connect(_on_voxel_changed)
	if not is_inside_tree():
		_pending_update = true
	else:
		_update_view()


func _set_voxel_id(new_id: int) -> void:
	if new_id == voxel_id:
		return
	if _voxel and _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.disconnect(_on_voxel_changed)
	voxel_id = new_id
	selected_faces.clear()
	_voxel = voxel_set.get_voxel(voxel_id) if voxel_set and voxel_id >= 0 else null
	if _voxel and not _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.connect(_on_voxel_changed)
	if not is_inside_tree():
		_pending_update = true
	else:
		_update_view()


func _set_edit_mode(value: EditorMode) -> void:
	if value == edit_mode:
		return
	edit_mode = value
	var editable := edit_mode == EditorMode.EDITABLE
	
	# Face buttons: toggle mode controls whether clicking selects
	for btn in _face_buttons.values():
		if is_instance_valid(btn):
			btn.toggle_mode = editable
	
	# Clear selection when switching to view-only
	if not editable and not selected_faces.is_empty():
		_clear_face_selection()

func _set_default_view(value: ViewMode) -> void:
	if value == default_view:
		return
	default_view = value
	_apply_default_view()

func _set_default_env(new_env: Environment) -> void:
	if default_env == new_env:
		return
	default_env = new_env
	if is_inside_tree():
		if default_env:
			_set_environment(default_env)
		else:
			_reset_environment()

func _apply_default_view() -> void:
	if not _mode_dropdown:
		return
	var idx := 0 if default_view == ViewMode.VIEW_3D else 1
	_mode_dropdown.selected = idx
	_on_mode_changed(idx)

func _ready() -> void:
	# Face buttons
	_face_buttons = {
		Vector3i.FORWARD: _front_face,
		Vector3i.LEFT: _left_face,
		Vector3i.BACK: _back_face,
		Vector3i.UP: _top_face,
		Vector3i.DOWN: _bottom_face,
		Vector3i.RIGHT: _right_face,
	}
	for face in _face_buttons:
		var btn = _face_buttons[face]
		btn.display_face = face
		btn.toggle_mode = true
		btn.mouse_entered.connect(_on_face_btn_mouse_entered.bind(face))
		btn.mouse_exited.connect(_on_face_btn_mouse_exited.bind(face))
		btn.voxel_selected.connect(_on_face_btn_selected.bind(face))
		btn.voxel_unselected.connect(_on_face_btn_unselected.bind(face))
		btn.voxel_right_clicked.connect(_on_face_right_clicked.bind(face))
	
	# 2D empty-area right-click
	_mode_2d.gui_input.connect(_on_2d_gui_input)
	
	# Mode dropdown
	_mode_dropdown.item_selected.connect(_on_mode_changed)
	
	# Edit menu — rebuilt on open with current context
	_edit_menu.get_popup().about_to_popup.connect(_populate_edit_menu)
	_edit_menu.get_popup().id_pressed.connect(_on_context_menu_action)
	
	# Settings menu
	_settings_menu.get_popup().id_pressed.connect(_on_settings_action)
	_settings_menu.get_popup().clear(true)
	_settings_menu.get_popup().add_item("Change Environment", ContextAction.CHANGE_ENVIRONMENT)
	_settings_menu.get_popup().add_item("Reset Environment", ContextAction.RESET_ENVIRONMENT)
	
	# 3D input
	_mode_3d.gui_input.connect(_on_3d_gui_input)
	_mode_3d.mouse_exited.connect(_on_3d_mouse_exited)
	
	# Environment
	if default_env:
		_set_environment(default_env)
	else:
		_load_env_config()
	
	# Context menu
	_context_menu = PopupMenu.new()
	_context_menu.name = "ContextMenu"
	_context_menu.id_pressed.connect(_on_context_menu_action)
	add_child(_context_menu)
	
	# Env file dialog
	_env_file_dialog = FileDialog.new()
	_env_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_env_file_dialog.add_filter("*.tres,*.env", "Godot Environment")
	_env_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_env_file_dialog.file_selected.connect(_on_env_file_selected)
	add_child(_env_file_dialog)
	
	# Atlas warning dialog
	_atlas_warning_dialog = AcceptDialog.new()
	_atlas_warning_dialog.title = "Texture Atlas Not Ready"
	_atlas_warning_dialog.ok_button_text = "Ok"
	add_child(_atlas_warning_dialog)
	
	# Atlas picker window
	_atlas_texture_picker_window_ok_button.pressed.connect(_on_atlas_ok)
	_atlas_texture_picker_window_cancel_button.pressed.connect(_on_atlas_cancel)
	
	# Apply default view mode
	_apply_default_view()
	
	# Apply edit mode
	if edit_mode != EditorMode.EDITABLE:
		_set_edit_mode(edit_mode)
	
	# Initial update
	if _pending_update:
		_update_view()

func _on_voxel_changed() -> void:
	_update_view()

func _update_view() -> void:
	if not _voxel_preview:
		_pending_update = true
		return
	_pending_update = false
	
	# Update 3D preview mesh
	if voxel_set and voxel_id >= 0 and voxel_set.voxel_id_exists(voxel_id):
		var mesh = VoxelPreview.generate(voxel_id, voxel_set)
		_voxel_preview.mesh = mesh
	else:
		_voxel_preview.mesh = null
	
	# Update face buttons
	var vs: VoxelSet = voxel_set
	var vid: int = voxel_id
	for face in _face_buttons:
		var btn = _face_buttons[face]
		btn.voxel_set = vs
		btn.voxel_id = vid
	
	# Update selection overlay
	_update_selection_overlay()
	_update_context_label()

func _on_face_btn_mouse_entered(face: Vector3i) -> void:
	_last_hovered_face = face
	_update_context_label()

func _on_face_btn_mouse_exited(face: Vector3i) -> void:
	_last_hovered_face = Vector3i.ZERO
	_update_context_label()

func _on_face_btn_selected(_id: int, face: Vector3i) -> void:
	_toggle_face_selection(face)

func _on_face_btn_unselected(_id: int, face: Vector3i) -> void:
	_unselect_face_selection(face)

func _toggle_face_selection(face: Vector3i) -> void:
	if face in selected_faces:
		_unselect_face_selection(face)
	else:
		if selection_max >= 0 and selected_faces.size() >= selection_max:
			return
		selected_faces.append(face)
		_update_selection_overlay()
		_update_context_label()

func _select_face_selection(face: Vector3i) -> void:
	if face in selected_faces:
		return
	if selection_max >= 0 and selected_faces.size() >= selection_max:
		return
	selected_faces.append(face)
	_update_selection_overlay()
	_update_context_label()

func _unselect_face_selection(face: Vector3i) -> void:
	if face not in selected_faces:
		return
	if selected_faces.size() <= selection_min:
		return
	selected_faces.erase(face)
	_update_selection_overlay()
	_update_context_label()

func _clear_face_selection() -> void:
	selected_faces.clear()
	for f in _face_buttons:
		_face_buttons[f].button_pressed = false
	_update_selection_overlay()
	_update_context_label()

func _get_highlight_material() -> StandardMaterial3D:
	if not _highlight_material:
		_highlight_material = StandardMaterial3D.new()
		_highlight_material.albedo_color = Color(0, 0, 1, 0.35)
		_highlight_material.vertex_color_use_as_albedo = false
		_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _highlight_material

func _update_selection_overlay() -> void:
	if not _voxel_highlight or not voxel_set or not voxel_set.voxel_id_exists(voxel_id):
		return
	
	if selected_faces.is_empty():
		_voxel_highlight.mesh = null
		return
	
	var mesher := VoxelMesher.create()
	mesher.begin(Vector3.ONE, voxel_set, true, false)
	for face in selected_faces:
		mesher.add_face(Vector3i.ZERO, voxel_id, face)
	var mesh := mesher.commit()
	_voxel_highlight.mesh = mesh
	
	if mesh and mesh.get_surface_count() > 0:
		_voxel_highlight.set_surface_override_material(0, _get_highlight_material())


func _update_context_label() -> void:
	var context = ""
	if _last_hovered_face != Vector3i.ZERO:
		context += "Hovering: " + Voxel.FACE_NAMES[_last_hovered_face]
	if not selected_faces.is_empty():
		if not context.is_empty():
			context += " | "
		context += "Selected: "
		var selected_faces_context = ""
		for selected_face in selected_faces:
			if not selected_faces_context.is_empty():
				selected_faces_context += ", "
			selected_faces_context += Voxel.FACE_NAMES[selected_face]
		context += selected_faces_context
	_context_label.text = context

var _motion := Vector2.ZERO

func _on_3d_gui_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_raycast_face(event.position)
	
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_is_dragging = true
					_update_cursor()
				else:
					_is_dragging = false
					_update_cursor()
				if event.double_click:
					_pick_face()
			elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
				_show_context_menu_at(get_screen_position() + event.position, _last_hovered_face)
		elif event is InputEventMouseMotion:
			if _is_dragging:
				_motion = event.relative
			_update_cursor()


func _process(delta: float) -> void:
	if _motion != Vector2.ZERO:
		var motion := _motion * camera_sensitivity * delta
		_camera_pivot.rotation.x = clampf(_camera_pivot.rotation.x - motion.y, -1.4, 1.4)
		_camera_pivot.rotation.y -= motion.x
	_motion = Vector2.ZERO


func _raycast_face(screen_pos: Vector2) -> void:
	var space := _viewport.find_world_3d().direct_space_state
	if not space:
		return
	
	var cam := _viewport.get_camera_3d()
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 10.0
	
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	var result := space.intersect_ray(query)
	var face = Vector3i.ZERO
	if not result.is_empty():
		var normal: Vector3 = result.get("normal", Vector3.ZERO).round()
		face = Vector3i(normal)
	
	_last_hovered_face = face
	_update_context_label()


func _update_cursor() -> void:
	## Uses Input.set_default_cursor_shape() because SubViewportContainer's
	## mouse_default_cursor_shape is often overridden by the embedded viewport.
	if _is_dragging:
		Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	elif _last_hovered_face != Vector3i.ZERO:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _on_3d_mouse_exited() -> void:
	_last_hovered_face = Vector3i.ZERO
	_update_cursor()


func _pick_face() -> void:
	if _last_hovered_face == Vector3i.ZERO:
		return
	_toggle_face_selection(_last_hovered_face)
	_update_context_label()


func _on_2d_gui_input(event: InputEvent) -> void:
	"""Handle right-click on empty area in 2D view."""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_show_context_menu_at(get_screen_position() + event.position, Vector3i.ZERO)

func _on_mode_changed(index: int) -> void:
	var mode := index as ViewMode
	_mode_2d.visible = mode == ViewMode.VIEW_2D
	_mode_3d.visible = mode == ViewMode.VIEW_3D

func _on_face_right_clicked(_id: int, at_position: Vector2, face: Vector3i) -> void:
	_show_context_menu_at(at_position, face)

func _show_context_menu_at(position: Vector2, face_hint: Vector3i = Vector3i.ZERO) -> void:
	var face := face_hint if face_hint != Vector3i.ZERO else _last_hovered_face

	_last_hovered_face = Vector3i.ZERO
	_context_menu_face = face
	_update_context_label()
	
	_context_menu.clear()
	
	if face != Vector3i.ZERO:
		if face in selected_faces:
			_context_menu.add_item("Unselect", ContextAction.UNSELECT_FACE)
		else:
			_context_menu.add_item("Select", ContextAction.SELECT_FACE)
	if selected_faces.size() < 6:
		_context_menu.add_item("Select All (%d)" % (6 - selected_faces.size()), ContextAction.SELECT_ALL_FACES)
	if not selected_faces.is_empty():
		_context_menu.add_item("Unselect All (%d)" % selected_faces.size(), ContextAction.UNSELECT_ALL_FACES)
	_context_menu.add_separator()
	
	if face != Vector3i.ZERO:
		var face_str := Voxel.FACE_NAMES[face]
		_context_menu.add_item("Color %s" % face_str, ContextAction.COLOR_FACE)
		_context_menu.add_item("Texture %s" % face_str, ContextAction.TEXTURE_FACE)
		if _voxel.has_face_color(face, false):
			_context_menu.add_item("Reset %s Color" % face_str, ContextAction.RESET_FACE_COLOR)
		if _voxel.has_face_texture_xy(face, false):
			_context_menu.add_item("Reset %s Texture" % face_str, ContextAction.RESET_FACE_TEXTURE_XY)
		_context_menu.add_separator()
	
	if not selected_faces.is_empty():
		_context_menu.add_item("Color Selected (%d)" % selected_faces.size(), ContextAction.COLOR_SELECTED)
		_context_menu.add_item("Texture Selected (%d)" % selected_faces.size(), ContextAction.TEXTURE_SELECTED)
		_context_menu.add_item("Reset Selected (%d) Color" % selected_faces.size(), ContextAction.RESET_SELECTED_COLOR)
		_context_menu.add_item("Reset Selected (%d) Texture" % selected_faces.size(), ContextAction.RESET_SELECTED_TEXTURE)
		_context_menu.add_separator()
	
	_context_menu.add_item("Color Voxel", ContextAction.COLOR_BASE)
	_context_menu.add_item("Texture Voxel", ContextAction.TEXTURE_BASE)
	if _voxel.has_base_color():
		_context_menu.add_item("Reset Base Color", ContextAction.RESET_BASE_COLOR)
	if _voxel.has_base_texture_xy():
		_context_menu.add_item("Reset Base Texture", ContextAction.RESET_BASE_TEXTURE)
	
	_context_menu.popup(Rect2i(position, Vector2i.ZERO))


func _populate_edit_menu() -> void:
	var popup := _edit_menu.get_popup()
	popup.clear()
	
	if not _voxel:
		return
	
	# Selection-level actions
	if selected_faces.size() < 6:
		popup.add_item("Select All (%d)" % (6 - selected_faces.size()), ContextAction.SELECT_ALL_FACES)
	if not selected_faces.is_empty():
		popup.add_item("Unselect All (%d)" % selected_faces.size(), ContextAction.UNSELECT_ALL_FACES)
		popup.add_separator()
		popup.add_item("Color Selected (%d)" % selected_faces.size(), ContextAction.COLOR_SELECTED)
		popup.add_item("Texture Selected (%d)" % selected_faces.size(), ContextAction.TEXTURE_SELECTED)
		popup.add_item("Reset Selected (%d) Color" % selected_faces.size(), ContextAction.RESET_SELECTED_COLOR)
		popup.add_item("Reset Selected (%d) Texture" % selected_faces.size(), ContextAction.RESET_SELECTED_TEXTURE)
	
	# Voxel-level actions
	popup.add_separator()
	popup.add_item("Color Voxel", ContextAction.COLOR_BASE)
	popup.add_item("Texture Voxel", ContextAction.TEXTURE_BASE)
	if _voxel.has_base_color():
		popup.add_item("Reset Base Color", ContextAction.RESET_BASE_COLOR)
	if _voxel.has_base_texture_xy():
		popup.add_item("Reset Base Texture", ContextAction.RESET_BASE_TEXTURE)


func _on_context_menu_action(id: int) -> void:
	if not _voxel:
		return
	
	match id:
		ContextAction.SELECT_FACE:
			_select_face_selection(_context_menu_face)
		
		ContextAction.UNSELECT_FACE:
			_unselect_face_selection(_context_menu_face)
		
		ContextAction.SELECT_ALL_FACES:
			_clear_face_selection()
			for f in Voxel.FACES:
				selected_faces.append(f)
				var btn = _face_buttons.get(f)
				if btn: btn.button_pressed = true
			_update_selection_overlay()
			_update_context_label()
		
		ContextAction.UNSELECT_ALL_FACES:
			_clear_face_selection()
		
		ContextAction.COLOR_FACE:
			if _context_menu_face != Vector3i.ZERO:
				var current := _voxel.get_face_color(_context_menu_face)
				_is_color_base_mode = false
				_open_color_picker("Change %s Color" % Voxel.FACE_NAMES[_context_menu_face], current, [_context_menu_face])
			
		ContextAction.TEXTURE_FACE:
			_is_atlas_base_mode = false
			_open_atlas_picker([_context_menu_face], "Change %s Color" % Voxel.FACE_NAMES[_context_menu_face])
		
		ContextAction.RESET_FACE_COLOR:
			if _context_menu_face != Vector3i.ZERO:
				var face := _context_menu_face
				var old_color := _voxel.get_face_color(face)
				if _create_undo_action("Reset %s Voxel Face Color" % Voxel.FACE_NAMES[face], voxel_set):
					if _undo_redo_manager:
						_undo_redo_manager.add_do_method(_voxel, "set_face_color", face, Voxel.UNSET_COLOR)
						_undo_redo_manager.add_undo_method(_voxel, "set_face_color", face, old_color)
					else:
						_undo_redo.add_do_method(_voxel.set_face_color.bind(face, Voxel.UNSET_COLOR))
						_undo_redo.add_undo_method(_voxel.set_face_color.bind(face, old_color))
					_commit_undo_action()
				else:
					_voxel.set_face_color(face, Voxel.UNSET_COLOR)
				changed.emit()
				_update_view()
				_notify_voxel_set_changed()
			
		ContextAction.RESET_FACE_TEXTURE_XY:
			if _context_menu_face != Vector3i.ZERO:
				var face := _context_menu_face
				var old_tex := _voxel.get_face_texture_xy(face)
				if _create_undo_action("Reset %s Voxel Face Texture" % Voxel.FACE_NAMES[face], voxel_set):
					if _undo_redo_manager:
						_undo_redo_manager.add_do_method(_voxel, "set_face_texture_xy", face, Voxel.UNSET_TEXTURE_XY)
						_undo_redo_manager.add_undo_method(_voxel, "set_face_texture_xy", face, old_tex)
					else:
						_undo_redo.add_do_method(_voxel.set_face_texture_xy.bind(face, Voxel.UNSET_TEXTURE_XY))
						_undo_redo.add_undo_method(_voxel.set_face_texture_xy.bind(face, old_tex))
					_commit_undo_action()
				else:
					_voxel.set_face_texture_xy(face, Voxel.UNSET_TEXTURE_XY)
				changed.emit()
				_update_view()
				_notify_voxel_set_changed()
			
		ContextAction.COLOR_SELECTED:
			if not selected_faces.is_empty():
				var current := _voxel.get_face_color(selected_faces[0])
				_is_color_base_mode = false
				_open_color_picker("Color Selected", current, selected_faces)
			
		ContextAction.TEXTURE_SELECTED:
			_is_atlas_base_mode = false
			_open_atlas_picker(selected_faces, "Texture Selected")
		
		ContextAction.RESET_SELECTED_COLOR:
			if not selected_faces.is_empty():
				if _create_undo_action("Reset %d Voxel Faces Color" % selected_faces.size(), voxel_set):
					for f in selected_faces:
						var old_c := _voxel.get_face_color(f)
						if _undo_redo_manager:
							_undo_redo_manager.add_do_method(_voxel, "set_face_color", f, Voxel.UNSET_COLOR)
							_undo_redo_manager.add_undo_method(_voxel, "set_face_color", f, old_c)
						else:
							_undo_redo.add_do_method(_voxel.set_face_color.bind(f, Voxel.UNSET_COLOR))
							_undo_redo.add_undo_method(_voxel.set_face_color.bind(f, old_c))
					_commit_undo_action()
				else:
					for selected_face in selected_faces:
						_voxel.set_face_color(selected_face, Voxel.UNSET_COLOR)
				changed.emit()
				_update_view()
				_notify_voxel_set_changed()
			
		ContextAction.RESET_SELECTED_TEXTURE:
			if not selected_faces.is_empty():
				if _create_undo_action("Reset %d Voxel Faces Texture" % selected_faces.size(), voxel_set):
					for f in selected_faces:
						var old_t := _voxel.get_face_texture_xy(f)
						if _undo_redo_manager:
							_undo_redo_manager.add_do_method(_voxel, "set_face_texture_xy", f, Voxel.UNSET_TEXTURE_XY)
							_undo_redo_manager.add_undo_method(_voxel, "set_face_texture_xy", f, old_t)
						else:
							_undo_redo.add_do_method(_voxel.set_face_texture_xy.bind(f, Voxel.UNSET_TEXTURE_XY))
							_undo_redo.add_undo_method(_voxel.set_face_texture_xy.bind(f, old_t))
					_commit_undo_action()
				else:
					for selected_face in selected_faces:
						_voxel.set_face_texture_xy(selected_face, Voxel.UNSET_TEXTURE_XY)
				changed.emit()
				_update_view()
				_notify_voxel_set_changed()
			
		ContextAction.COLOR_BASE:
			_is_color_base_mode = true
			_open_color_picker("Change Base Color", _voxel.base_color, [])
		
		ContextAction.TEXTURE_BASE:
			_is_atlas_base_mode = true
			_open_atlas_picker([], "Change Base Texture")
		
		ContextAction.RESET_BASE_COLOR:
			if _create_undo_action("Reset Voxel Base Color", voxel_set):
				var old_base_color := _voxel.base_color
				if _undo_redo_manager:
					_undo_redo_manager.add_do_property(_voxel, "base_color", Voxel.UNSET_COLOR)
					_undo_redo_manager.add_undo_property(_voxel, "base_color", old_base_color)
				else:
					_undo_redo.add_do_property(_voxel, "base_color", Voxel.UNSET_COLOR)
					_undo_redo.add_undo_property(_voxel, "base_color", old_base_color)
				_commit_undo_action()
			else:
				_voxel.base_color = Voxel.UNSET_COLOR
			changed.emit()
			_update_view()
			_notify_voxel_set_changed()
		
		ContextAction.RESET_BASE_TEXTURE:
			if _create_undo_action("Reset Voxel Base Texture", voxel_set):
				var old_base_tex := _voxel.base_texture_xy
				if _undo_redo_manager:
					_undo_redo_manager.add_do_property(_voxel, "base_texture_xy", Voxel.UNSET_TEXTURE_XY)
					_undo_redo_manager.add_undo_property(_voxel, "base_texture_xy", old_base_tex)
				else:
					_undo_redo.add_do_property(_voxel, "base_texture_xy", Voxel.UNSET_TEXTURE_XY)
					_undo_redo.add_undo_property(_voxel, "base_texture_xy", old_base_tex)
				_commit_undo_action()
			else:
				_voxel.base_texture_xy = Voxel.UNSET_TEXTURE_XY
			changed.emit()
			_update_view()
			_notify_voxel_set_changed()
		
		ContextAction.CHANGE_ENVIRONMENT:
			_env_file_dialog.popup_centered_clamped(Vector2i(300, 250))
		
		ContextAction.RESET_ENVIRONMENT:
			_reset_environment()

func _open_color_picker(title: String, current: Color, color_faces: Array[Vector3i]) -> void:
	if not _voxel:
		return
	
	# Snapshot original values for revert on cancel
	_color_originals.clear()
	_color_faces = color_faces
	if _is_color_base_mode:
		_color_originals["base"] = _voxel.base_color
	else:
		for face in color_faces:
			_color_originals[face] = _voxel.get_face_color(face)
	
	_color_picker_window.title = title
	if current.a == 0:
		current.a = 1
	_color_picker_window.color = current
	
	# Connect live preview — disconnect any previous first to avoid duplicates
	var picker: ColorPicker = _color_picker_window.get_color_picker()
	if picker.color_changed.is_connected(_on_color_preview):
		picker.color_changed.disconnect(_on_color_preview)
	picker.color_changed.connect(_on_color_preview)
	
	_color_picker_window.popup_centered_clamped()

func _on_color_preview(new_color: Color) -> void:
	if not _voxel:
		return
	if _is_color_base_mode:
		_voxel.base_color = new_color
	else:
		for face in _color_faces:
			_voxel.set_face_color(face, new_color)
	_update_view()

func _apply_color_picker(color: Color) -> void:
	var picker: ColorPicker = _color_picker_window.get_color_picker()
	if picker.color_changed.is_connected(_on_color_preview):
		picker.color_changed.disconnect(_on_color_preview)
	
	if _is_color_base_mode:
		_apply_base_color(color)
	else:
		_apply_faces_color(_color_faces, color)
	_close_color_picker()

func _close_color_picker() -> void:
	if _color_picker_window:
		# Disconnect live preview
		var picker: ColorPicker = _color_picker_window.get_color_picker()
		if picker.color_changed.is_connected(_on_color_preview):
			picker.color_changed.disconnect(_on_color_preview)
		_color_picker_window.hide()

func _cancel_color_picker() -> void:
	if not _voxel:
		return
	# Disconnect live preview
	var picker: ColorPicker = _color_picker_window.get_color_picker()
	if picker.color_changed.is_connected(_on_color_preview):
		picker.color_changed.disconnect(_on_color_preview)
	# Restore original values
	if _is_color_base_mode and _color_originals.has("base"):
		_voxel.base_color = _color_originals["base"]
	else:
		for face in _color_originals:
			if face is Vector3i:
				_voxel.set_face_color(face, _color_originals[face])
	_update_view()
	_close_color_picker()

func _create_undo_action(action_name: String, context: Object = null) -> bool:
	if _undo_redo_manager:
		_undo_redo_manager.create_action(action_name, UndoRedo.MERGE_DISABLE, context)
		return true
	if _undo_redo:
		_undo_redo.create_action(action_name)
		return true
	return false

func _commit_undo_action(execute: bool = true) -> void:
	if _undo_redo_manager:
		_undo_redo_manager.commit_action(execute)
	elif _undo_redo:
		_undo_redo.commit_action(execute)

func _notify_voxel_set_changed() -> void:
	if voxel_set:
		voxel_set.changed.emit()

func _apply_base_color(new_color: Color) -> void:
	if not _voxel:
		return
	if _create_undo_action("Color Voxel Base", voxel_set):
		var old_color := _color_originals.get("base", _voxel.base_color)
		if _undo_redo_manager:
			_undo_redo_manager.add_do_property(_voxel, "base_color", new_color)
			_undo_redo_manager.add_undo_property(_voxel, "base_color", old_color)
		else:
			_undo_redo.add_do_property(_voxel, "base_color", new_color)
			_undo_redo.add_undo_property(_voxel, "base_color", old_color)
		_commit_undo_action()
	else:
		_voxel.base_color = new_color
	changed.emit()
	_update_view()
	_notify_voxel_set_changed()

func _apply_faces_color(faces: Array[Vector3i], new_color: Color) -> void:
	if not _voxel:
		return
	if _create_undo_action("Color %d Voxel Faces" % faces.size(), voxel_set):
		for face in faces:
			var old_color := _color_originals.get(face, _voxel.get_face_color(face))
			if _undo_redo_manager:
				_undo_redo_manager.add_do_method(_voxel, "set_face_color", face, new_color)
				_undo_redo_manager.add_undo_method(_voxel, "set_face_color", face, old_color)
			else:
				_undo_redo.add_do_method(_voxel.set_face_color.bind(face, new_color))
				_undo_redo.add_undo_method(_voxel.set_face_color.bind(face, old_color))
		_commit_undo_action()
	else:
		for face in faces:
			_voxel.set_face_color(face, new_color)
	changed.emit()
	_update_view()
	for face in faces:
		face_edited.emit(voxel_id, face)
	_notify_voxel_set_changed()

func _show_texture_warning() -> void:
	if not _atlas_warning_dialog or not voxel_set:
		return
	
	var missing: PackedStringArray = []
	if not voxel_set.texture_atlas:
		missing.append("- A texture atlas image")
	if voxel_set.texture_atlas_cell_size.x <= 0 or voxel_set.texture_atlas_cell_size.y <= 0:
		missing.append("- A cell size (width x height > 0)")
	
	var msg: String = "Texture atlas is not ready.\n\nThe VoxelSet needs:\n" + "\n".join(missing)
	_atlas_warning_dialog.dialog_text = msg
	_atlas_warning_dialog.popup_centered_clamped()


func _open_atlas_picker(target_faces: Array[Vector3i], context_name: String) -> void:
	if not voxel_set:
		return
	
	if not voxel_set.is_texture_ready():
		_show_texture_warning()
		return
	
	_atlas_target_faces = target_faces
	
	# Snapshot original textures for revert on cancel
	_atlas_originals.clear()
	if _is_atlas_base_mode:
		if _voxel:
			_atlas_originals["base"] = _voxel.base_texture_xy
	elif _voxel:
		for face in target_faces:
			_atlas_originals[face] = _voxel.get_face_texture_xy(face)
	
	_atlas_texture_picker.voxel_id = voxel_id
	_atlas_texture_picker.voxel_set = voxel_set
	_atlas_texture_picker.reference_faces = target_faces
	_atlas_texture_picker.selected_texture_xy = [] as Array[Vector2i]
	
	# Connect live preview
	if _atlas_texture_picker.texture_xy_selected.is_connected(_on_atlas_preview):
		_atlas_texture_picker.texture_xy_selected.disconnect(_on_atlas_preview)
	if _atlas_texture_picker.texture_xy_unselected.is_connected(_on_atlas_preview):
		_atlas_texture_picker.texture_xy_unselected.disconnect(_on_atlas_preview)
	_atlas_texture_picker.texture_xy_selected.connect(_on_atlas_preview)
	_atlas_texture_picker.texture_xy_unselected.connect(_on_atlas_preview)
	
	_atlas_texture_picker_window.title = context_name
	if _is_atlas_base_mode:
		_atlas_texture_picker_window_ok_button.text = "Set Base Texture"
	elif target_faces.size() == 1:
		_atlas_texture_picker_window_ok_button.text = "Set %s Texture" % Voxel.FACE_NAMES[target_faces[0]]
	else:
		_atlas_texture_picker_window_ok_button.text = "Set Texture (%d faces)" % target_faces.size()
	_atlas_texture_picker_window_cancel_button.text = "Cancel"
	
	_atlas_texture_picker_window.popup_centered_clamped()


func _on_atlas_preview(_uv: Vector2i) -> void:
	if not _voxel:
		return
	var uvs = _atlas_texture_picker.get_selected_texture_xy()
	if uvs.is_empty():
		return
	var uv = uvs[0]
	if _is_atlas_base_mode:
		_voxel.base_texture_xy = uv
	else:
		for face in _atlas_target_faces:
			_voxel.set_face_texture_xy(face, uv)
	_update_view()


func _on_atlas_ok() -> void:
	if not _voxel:
		return
	# Disconnect live preview
	if _atlas_texture_picker.texture_xy_selected.is_connected(_on_atlas_preview):
		_atlas_texture_picker.texture_xy_selected.disconnect(_on_atlas_preview)
	if _atlas_texture_picker.texture_xy_unselected.is_connected(_on_atlas_preview):
		_atlas_texture_picker.texture_xy_unselected.disconnect(_on_atlas_preview)
	
	var uvs = _atlas_texture_picker.get_selected_texture_xy()
	if uvs.is_empty():
		return
	var uv = uvs[0]
	
	if _is_atlas_base_mode:
		if _create_undo_action("Texture Voxel Base", voxel_set):
			var old_tex := _atlas_originals.get("base", _voxel.base_texture_xy)
			if _undo_redo_manager:
				_undo_redo_manager.add_do_property(_voxel, "base_texture_xy", uv)
				_undo_redo_manager.add_undo_property(_voxel, "base_texture_xy", old_tex)
			else:
				_undo_redo.add_do_property(_voxel, "base_texture_xy", uv)
				_undo_redo.add_undo_property(_voxel, "base_texture_xy", old_tex)
			_commit_undo_action()
		else:
			_voxel.base_texture_xy = uv
	else:
		if _create_undo_action("Texture %d Voxel Faces" % _atlas_target_faces.size(), voxel_set):
			for face in _atlas_target_faces:
				var old_tex := _atlas_originals.get(face, _voxel.get_face_texture_xy(face))
				if _undo_redo_manager:
					_undo_redo_manager.add_do_method(_voxel, "set_face_texture_xy", face, uv)
					_undo_redo_manager.add_undo_method(_voxel, "set_face_texture_xy", face, old_tex)
				else:
					_undo_redo.add_do_method(_voxel.set_face_texture_xy.bind(face, uv))
					_undo_redo.add_undo_method(_voxel.set_face_texture_xy.bind(face, old_tex))
			_commit_undo_action()
		else:
			for face in _atlas_target_faces:
				_voxel.set_face_texture_xy(face, uv)
	
	_atlas_texture_picker_window.hide()
	changed.emit()
	_update_view()
	for face in _atlas_target_faces:
		face_edited.emit(voxel_id, face)
	_notify_voxel_set_changed()


func _on_atlas_cancel() -> void:
	# Disconnect live preview
	if _atlas_texture_picker.texture_xy_selected.is_connected(_on_atlas_preview):
		_atlas_texture_picker.texture_xy_selected.disconnect(_on_atlas_preview)
	if _atlas_texture_picker.texture_xy_unselected.is_connected(_on_atlas_preview):
		_atlas_texture_picker.texture_xy_unselected.disconnect(_on_atlas_preview)
	
	# Restore original textures
	if _voxel:
		if _is_atlas_base_mode and _atlas_originals.has("base"):
			_voxel.base_texture_xy = _atlas_originals["base"]
		else:
			for face in _atlas_originals:
				if face is Vector3i:
					_voxel.set_face_texture_xy(face, _atlas_originals[face])
		_update_view()
	_atlas_texture_picker_window.hide()

func _on_settings_action(id: int) -> void:
	match id:
		ContextAction.CHANGE_ENVIRONMENT:
			_env_file_dialog.popup_centered()
		ContextAction.RESET_ENVIRONMENT:
			_reset_environment()

func _on_env_file_selected(path: String) -> void:
	_env_path = path
	_save_env_config()
	_set_environment(load(path))

func _set_environment(env: Environment) -> void:
	var world_root: Node3D = _viewport.get_node("Node3D")
	var env_node: WorldEnvironment = null
	for child in world_root.get_children():
		if child is WorldEnvironment:
			env_node = child
			break
	if not env_node:
		env_node = WorldEnvironment.new()
		world_root.add_child(env_node)
	env_node.environment = env
	# Disable transparent background so the loaded environment is visible
	_viewport.transparent_bg = false

func _reset_environment() -> void:
	_env_path = ""
	_save_env_config()
	# Re-enable transparent background for the default clean look
	_viewport.transparent_bg = true
	_setup_3d_default_environment()

func _setup_3d_default_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_color = Color(0.25, 0.25, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_set_environment(env)

func _load_env_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_config_path) == OK:
		_env_path = cfg.get_value("env", "path", "")
		if not _env_path.is_empty():
			var env := load(_env_path)
			if env is Environment:
				_set_environment(env)
				return
	_setup_3d_default_environment()

func _save_env_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("env", "path", _env_path)
	cfg.save(_config_path)

func _on_color_picker_window_color_canceled():
	_cancel_color_picker()

func _on_color_picker_window_color_confirmed(color):
	_apply_color_picker(color)

func _on_color_picker_window_close_requested():
	_cancel_color_picker()
