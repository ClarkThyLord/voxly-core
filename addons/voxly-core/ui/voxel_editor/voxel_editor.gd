## Face-level voxel editor widget.
##
## Edits a single [Voxel]'s base and per-face color, texture cell, and material
## overrides through a 2D/3D preview, face selection buttons, and context
## menus, with undo/redo support and configurable environment settings.
@tool
extends VBoxContainer

const MaterialEditorWindowScript := preload("res://addons/voxly-core/ui/material_editor_window/material_editor_window.gd")

## Emitted when the user edits the voxel (color, texture, etc).
signal changed

## Emitted when a voxel face is edited.
signal face_edited(voxel_id: int, face: Vector3i)

## Which view the voxel editor displays (3D or 2D).
enum ViewMode {
	VIEW_3D,
	VIEW_2D,
}

## Whether the voxel editor is editable or view-only.
enum EditorMode {
	EDITABLE,
	VIEW_ONLY,
}

## Actions available in the voxel editor context menu.
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
	MATERIAL_FACE,
	RESET_MATERIAL_FACE,
	MATERIAL_SELECTED,
	RESET_SELECTED_MATERIAL,
	MATERIAL_BASE,
	RESET_MATERIAL_BASE,
}

# Face button references
## 2D viewport mode.
@onready var _mode_2d: Control = %Mode2D

## Front face button.
@onready var _front_face = %FrontFace

## Left face button.
@onready var _left_face = %LeftFace

## Back face button.
@onready var _back_face = %BackFace

## Top face button.
@onready var _top_face = %TopFace

## Bottom face button.
@onready var _bottom_face = %BottomFace

## Right face button.
@onready var _right_face = %RightFace

## Face buttons keyed by their face normal.
var _face_buttons: Dictionary[Vector3i, Button] = {}

# 3D references
## 3D viewport container.
@onready var _mode_3d: SubViewportContainer = %Mode3D

## Embedded 3D viewport.
@onready var _viewport: SubViewport = %SubViewport

## Mesh preview of the voxel.
@onready var _voxel_preview: MeshInstance3D = %VoxelPreview

## Highlight overlay mesh.
@onready var _voxel_highlight: MeshInstance3D = %VoxelHighlight

## Pivot the orbit camera rotates around.
@onready var _camera_pivot: Node3D = %CameraPivot

## The 3D viewport camera.
@onready var _camera: Camera3D = %Camera

# UI
## Label showing hover and selection context.
@onready var _context_label: Label = %ContextLabel

## 2D/3D mode selector.
@onready var _mode_dropdown: OptionButton = %ModeOptionButton

## Select actions menu.
@onready var _select_menu: MenuButton = %SelectMenuButton

## Edit actions menu.
@onready var _edit_menu: MenuButton = %EditMenuButton

## Settings menu.
@onready var _settings_menu: MenuButton = %SettingsMenuButton

## Window for picking atlas cells.
@onready var _atlas_texture_picker_window: Window = %AtlasTexturePickerWindow

# Exports
## The voxel ID being edited.
@export var voxel_id: int = 0:
	set = _set_voxel_id

## The voxel set the edited voxel belongs to.
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

## Whether face selection is enabled. When false, the Select menu is hidden.
@export var selection_enabled: bool = true:
	set = _set_selection_enabled

## Minimum faces that must remain selected.
@export var selection_min: int = 0

## Maximum faces that can be selected (-1 = unlimited).
@export var selection_max: int = -1

## Orbit camera drag sensitivity.
@export var camera_sensitivity: float = 1.0

## Currently selected faces.
var selected_faces: Array[Vector3i] = []

## The voxel being edited.
var _voxel: Voxel = null

## True while an update is queued for the ready state.
var _pending_update := false

## True while orbiting with the mouse.
var _is_dragging := false

## Face currently under the mouse.
var _last_hovered_face: Vector3i = Vector3i.ZERO

## Face the context menu was opened for.
var _context_menu_face: Vector3i = Vector3i.ZERO

## Path of the environment resource.
var _env_path: String = ""

const DEFAULT_ENV_PATH := "res://addons/voxly-core/ui/voxel_editor/default_env.tres"

## Color picker window.
@onready var _color_picker_window := %ColorPickerWindow

## Material editor window.
@onready var _material_editor_window := %MaterialEditorWindow

## Right-click context menu.
@onready var _context_menu: PopupMenu = %ContextMenu

## Faces targeted by the color picker.
var _color_faces: Array[Vector3i]

## Callback invoked when the color picker confirms.
var _color_callback: Callable

## Faces targeted by the atlas picker.
var _atlas_target_faces: Array[Vector3i] = []

## Dialog for warnings.
@onready var _accept_dialog: AcceptDialog = %AcceptDialog

## Material used for the selection highlight.
var _highlight_material: StandardMaterial3D = null

## Plain UndoRedo stack used when not in the editor.
var _undo_redo: UndoRedo = null

## Editor undo/redo manager used inside the editor.
var _undo_redo_manager: EditorUndoRedoManager = null

## File dialog for environment selection.
@onready var _file_dialog: FileDialog = %FileDialog

# Color picker state
## Original colors for canceling the color picker.
var _color_originals: Dictionary = {}
	
	# true if editing base_color, false if editing face overrides
## True when the color picker edits the base color.
var _is_color_base_mode: bool = false

# Atlas texture picker state
## Original cells for canceling the atlas picker.
var _atlas_originals: Dictionary = {}

# true if editing base_texture_cell, false if editing face overrides
## True when the atlas picker edits the base cell.
var _is_atlas_base_mode: bool = false

# Material editor state
## Original material IDs for canceling the material editor.
var _material_originals: Dictionary = {}

## Faces targeted by the material editor.
var _material_target_faces: Array[Vector3i] = []

## True when the material editor edits the base material.
var _is_material_base_mode: bool = false

## Sets the plain undo/redo stack.
func set_undo_redo(undo_redo: UndoRedo) -> void:
	_undo_redo = undo_redo
	
	if _material_editor_window:
		_material_editor_window.set_undo_redo(undo_redo)

## Sets the editor undo/redo manager.
func set_undo_redo_manager(manager: EditorUndoRedoManager) -> void:
	_undo_redo_manager = manager
	
	if _material_editor_window:
		_material_editor_window.set_undo_redo_manager(manager)

## Updates the voxel set and reloads the voxel.
func _set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if new_voxel_set == voxel_set:
		return
	if _voxel and _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.disconnect(_on_voxel_changed)
	
	voxel_set = new_voxel_set
	_material_target_faces.clear()
	_material_originals.clear()
	_voxel = voxel_set.get_voxel(voxel_id) if voxel_set and voxel_id >= 0 else null
	
	if _voxel and not _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.connect(_on_voxel_changed)
	
	if _material_editor_window:
		_material_editor_window.voxel_set = new_voxel_set
	
	if not is_inside_tree():
		_pending_update = true
	else:
		_update_view()


## Updates the edited voxel ID.
func _set_voxel_id(new_voxel_id: int) -> void:
	if new_voxel_id == voxel_id:
		return
	
	if _voxel and _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.disconnect(_on_voxel_changed)
	
	voxel_id = new_voxel_id
	selected_faces.clear()
	_material_target_faces.clear()
	_material_originals.clear()
	_voxel = voxel_set.get_voxel(voxel_id) if voxel_set and voxel_id >= 0 else null
	
	if _voxel and not _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.connect(_on_voxel_changed)
	if not is_inside_tree():
		_pending_update = true
	else:
		_update_view()


## Toggles face selection.
func _set_selection_enabled(value: bool) -> void:
	if value == selection_enabled:
		return
	
	selection_enabled = value
	_update_toolbar_visibility()


## Applies the edit/view-only mode.
func _set_edit_mode(value: EditorMode) -> void:
	if value == edit_mode:
		return
	
	edit_mode = value
	var editable := edit_mode == EditorMode.EDITABLE
	
	# Face buttons: toggle mode controls whether clicking selects
	for button in _face_buttons.values():
		if is_instance_valid(button):
			button.toggle_mode = editable
	
	# Clear selection when switching to view-only
	if not editable and not selected_faces.is_empty():
		_clear_face_selection()
	
	if _material_editor_window:
		_material_editor_window.edit_mode = MaterialEditorWindowScript.EditMode.EDITABLE if editable else MaterialEditorWindowScript.EditMode.VIEW_ONLY
	
	_update_toolbar_visibility()

## Applies the default 2D/3D view mode.
func _set_default_view(value: ViewMode) -> void:
	if value == default_view:
		return
	
	default_view = value
	_apply_default_view()

## Sets the default environment.
func _set_default_env(new_env: Environment) -> void:
	if default_env == new_env:
		return
	
	default_env = new_env
	if is_inside_tree():
		if default_env:
			_set_environment(default_env)
		else:
			_reset_environment()

## Applies the default view to the mode dropdown.
func _apply_default_view() -> void:
	if not _mode_dropdown:
		return
	
	var index := 0 if default_view == ViewMode.VIEW_3D else 1
	_mode_dropdown.selected = index
	_on_mode_changed(index)

## Connects all widget signals and initializes the view.
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
		var button = _face_buttons[face]
		# Map Vector3i face to DisplayFace enum
		if face == Vector3i.FORWARD:
			button.display_face = button.DisplayFace.FRONT
		elif face == Vector3i.BACK:
			button.display_face = button.DisplayFace.BACK
		elif face == Vector3i.LEFT:
			button.display_face = button.DisplayFace.LEFT
		elif face == Vector3i.RIGHT:
			button.display_face = button.DisplayFace.RIGHT
		elif face == Vector3i.UP:
			button.display_face = button.DisplayFace.TOP
		elif face == Vector3i.DOWN:
			button.display_face = button.DisplayFace.BOTTOM
		button.toggle_mode = true
		button.mouse_entered.connect(_on_face_btn_mouse_entered.bind(face))
		button.mouse_exited.connect(_on_face_btn_mouse_exited.bind(face))
		button.voxel_selected.connect(_on_face_btn_selected.bind(face))
		button.voxel_unselected.connect(_on_face_btn_unselected.bind(face))
		button.voxel_right_clicked.connect(_on_face_right_clicked.bind(face))
	
	# 2D empty-area right-click
	_mode_2d.gui_input.connect(_on_2d_gui_input)
	
	# Mode dropdown
	_mode_dropdown.item_selected.connect(_on_mode_changed)
	
	# Select menu
	_select_menu.get_popup().about_to_popup.connect(_populate_select_menu)
	_select_menu.get_popup().id_pressed.connect(_on_context_menu_action)
	
	# Edit menu
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
	_context_menu.id_pressed.connect(_on_context_menu_action)
	
	## Env file dialog
	_file_dialog.file_selected.connect(_on_env_file_selected)
	
	# Atlas picker window
	_atlas_texture_picker_window.confirmed.connect(_on_atlas_ok)
	_atlas_texture_picker_window.canceled.connect(_on_atlas_cancel)
	
	# Material editor window
	_material_editor_window.setup("Material Editor", voxel_set, "", MaterialEditorWindowScript.EditMode.EDITABLE)
	_material_editor_window.changed.connect(_on_material_editor_window_changed)
	_material_editor_window.material_id_changed.connect(_on_material_editor_material_id_changed)
	_material_editor_window.confirmed.connect(_on_material_editor_session_finished)
	_material_editor_window.canceled.connect(_on_material_editor_session_finished)
	if _undo_redo:
		_material_editor_window.set_undo_redo(_undo_redo)
	if _undo_redo_manager:
		_material_editor_window.set_undo_redo_manager(_undo_redo_manager)
	
	# Apply toolbar visibility
	_update_toolbar_visibility()
	
	# Apply default view mode
	_apply_default_view()
	
	# Apply edit mode
	if edit_mode != EditorMode.EDITABLE:
		_set_edit_mode(edit_mode)
	
	# Initial update
	if _pending_update:
		_update_view()

## Refreshes the view when the voxel changes.
func _on_voxel_changed() -> void:
	_update_view()

## Rebuilds the voxel preview mesh.
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
	var current_voxel_set: VoxelSet = voxel_set
	var voxel_id: int = voxel_id
	for face in _face_buttons:
		var button = _face_buttons[face]
		button.voxel_set = current_voxel_set
		button.voxel_id = voxel_id
	
	# Update selection overlay
	_update_selection_overlay()
	_update_context_label()

## Updates the hover context for a face button.
func _on_face_btn_mouse_entered(face: Vector3i) -> void:
	_last_hovered_face = face
	_update_context_label()

## Clears the hover context.
func _on_face_btn_mouse_exited(face: Vector3i) -> void:
	_last_hovered_face = Vector3i.ZERO
	_update_context_label()

## Adds a face to the selection.
func _on_face_btn_selected(_id: int, face: Vector3i) -> void:
	_toggle_face_selection(face)

## Removes a face from the selection.
func _on_face_btn_unselected(_id: int, face: Vector3i) -> void:
	_unselect_face_selection(face)

## Toggles a face in the selection.
func _toggle_face_selection(face: Vector3i) -> void:
	if face in selected_faces:
		_unselect_face_selection(face)
	else:
		if selection_max >= 0 and selected_faces.size() >= selection_max:
			return
		selected_faces.append(face)
		_update_selection_overlay()
		_update_context_label()

## Adds a face to the selection and updates the overlay.
func _select_face_selection(face: Vector3i) -> void:
	if face in selected_faces:
		return
	if selection_max >= 0 and selected_faces.size() >= selection_max:
		return
	selected_faces.append(face)
	_update_selection_overlay()
	_update_context_label()

## Removes a face from the selection and updates the overlay.
func _unselect_face_selection(face: Vector3i) -> void:
	if face not in selected_faces:
		return
	if selected_faces.size() <= selection_min:
		return
	selected_faces.erase(face)
	_update_selection_overlay()
	_update_context_label()

## Clears all selected faces.
func _clear_face_selection() -> void:
	selected_faces.clear()
	for face in _face_buttons:
		_face_buttons[face].button_pressed = false
	_update_selection_overlay()
	_update_context_label()

## Returns the shared highlight material.
func _get_highlight_material() -> StandardMaterial3D:
	if not _highlight_material:
		_highlight_material = StandardMaterial3D.new()
		_highlight_material.albedo_color = Color(0, 0, 1, 0.35)
		_highlight_material.vertex_color_use_as_albedo = false
		_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _highlight_material

## Updates the highlight overlay for the selection.
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
	# Center the mesher-built mesh (grid-corner 0..1 layout) so it sits
	# centered at the voxel origin like VoxelPreview.generate() now returns.
	if mesh:
		VoxelPreview.translate_mesh(mesh, Vector3(-0.5, -0.5, -0.5))
	_voxel_highlight.mesh = mesh
	
	if mesh and mesh.get_surface_count() > 0:
		_voxel_highlight.set_surface_override_material(0, _get_highlight_material())


## Updates the hover and selection context label.
func _update_context_label() -> void:
	var context = ""
	if _last_hovered_face != Vector3i.ZERO:
		context += "Hovering: " + Voxel.FACE_NAMES[_last_hovered_face]
	if not selected_faces.is_empty():
		if not context.is_empty():
			context += "\n"
		context += "Selected: "
		var selected_faces_context = ""
		for selected_face in selected_faces:
			if not selected_faces_context.is_empty():
				selected_faces_context += ", "
			selected_faces_context += Voxel.FACE_NAMES[selected_face]
		context += selected_faces_context
	_context_label.text = context

## Accumulated orbit drag motion.
var _motion := Vector2.ZERO

## Handles mouse input in the 3D viewport.
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


## Applies orbit drag rotation.
func _process(delta: float) -> void:
	if _motion != Vector2.ZERO:
		var motion := _motion * camera_sensitivity * delta
		_camera_pivot.rotation.x = clampf(_camera_pivot.rotation.x - motion.y, -1.4, 1.4)
		_camera_pivot.rotation.y -= motion.x
	_motion = Vector2.ZERO


## Raycasts the 3D viewport to find the hovered face.
func _raycast_face(screen_position: Vector2) -> void:
	var space_state := _viewport.find_world_3d().direct_space_state
	if not space_state:
		return
	
	var camera := _viewport.get_camera_3d()
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * 10.0
	
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = from
	ray_query.to = to
	var result := space_state.intersect_ray(ray_query)
	var face = Vector3i.ZERO
	if not result.is_empty():
		var normal: Vector3 = result.get("normal", Vector3.ZERO).round()
		face = Vector3i(normal)
	
	_last_hovered_face = face
	_update_context_label()


## Updates the default cursor shape.
func _update_cursor() -> void:
	## Uses Input.set_default_cursor_shape() because SubViewportContainer's
	## mouse_default_cursor_shape is often overridden by the embedded viewport.
	if _is_dragging:
		Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	elif _last_hovered_face != Vector3i.ZERO:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


## Clears the hovered face when the mouse leaves.
func _on_3d_mouse_exited() -> void:
	_last_hovered_face = Vector3i.ZERO
	_update_cursor()


## Toggles the hovered face selection on double-click.
func _pick_face() -> void:
	if _last_hovered_face == Vector3i.ZERO:
		return
	_toggle_face_selection(_last_hovered_face)
	_update_context_label()


## Opens the context menu on 2D right-click.
func _on_2d_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_show_context_menu_at(get_screen_position() + event.position, Vector3i.ZERO)

## Switches between the 2D and 3D views.
func _on_mode_changed(index: int) -> void:
	var mode := index as ViewMode
	_mode_2d.visible = mode == ViewMode.VIEW_2D
	_mode_3d.visible = mode == ViewMode.VIEW_3D

## Opens the context menu for a face.
func _on_face_right_clicked(_id: int, at_position: Vector2, face: Vector3i) -> void:
	_show_context_menu_at(at_position, face)

## Builds and shows the context menu.
func _show_context_menu_at(position: Vector2, face_hint: Vector3i = Vector3i.ZERO) -> void:
	var face := face_hint if face_hint != Vector3i.ZERO else _last_hovered_face
	
	_last_hovered_face = Vector3i.ZERO
	_context_menu_face = face
	_update_context_label()
	
	_context_menu.clear()
	var is_editable := edit_mode == EditorMode.EDITABLE
	
	if face != Vector3i.ZERO:
		if face in selected_faces:
			_context_menu.add_item("Unselect", ContextAction.UNSELECT_FACE)
		else:
			_context_menu.add_item("Select", ContextAction.SELECT_FACE)
	if selected_faces.size() < 6:
		_context_menu.add_item("Select All (%d)" % (6 - selected_faces.size()), ContextAction.SELECT_ALL_FACES)
	if not selected_faces.is_empty():
		_context_menu.add_item("Unselect All (%d)" % selected_faces.size(), ContextAction.UNSELECT_ALL_FACES)
	
	# Only show edit options when in EDITABLE mode
	if is_editable:
		_context_menu.add_separator()
		
		if face != Vector3i.ZERO:
			var face_name := Voxel.FACE_NAMES[face]
			_context_menu.add_item("Color %s" % face_name, ContextAction.COLOR_FACE)
			_context_menu.add_item("Texture %s" % face_name, ContextAction.TEXTURE_FACE)
			_context_menu.add_item("Material %s" % face_name, ContextAction.MATERIAL_FACE)
			if _voxel.has_face_color(face, false):
				_context_menu.add_item("Reset %s Color" % face_name, ContextAction.RESET_FACE_COLOR)
			if _voxel.has_face_texture_cell(face, false):
				_context_menu.add_item("Reset %s Texture" % face_name, ContextAction.RESET_FACE_TEXTURE_XY)
			if _voxel.has_face_material_id(face, false):
				_context_menu.add_item("Reset %s Material" % face_name, ContextAction.RESET_MATERIAL_FACE)
			_context_menu.add_separator()
		
		if not selected_faces.is_empty():
			_context_menu.add_item("Color Selected (%d)" % selected_faces.size(), ContextAction.COLOR_SELECTED)
			_context_menu.add_item("Texture Selected (%d)" % selected_faces.size(), ContextAction.TEXTURE_SELECTED)
			_context_menu.add_item("Material Selected (%d)" % selected_faces.size(), ContextAction.MATERIAL_SELECTED)
			var has_face_color_override := false
			var has_face_tex_override := false
			var has_face_mat_override := false
			for selected_face in selected_faces:
				if _voxel.has_face_color(selected_face, false):
					has_face_color_override = true
				if _voxel.has_face_texture_cell(selected_face, false):
					has_face_tex_override = true
				if _voxel.has_face_material_id(selected_face, false):
					has_face_mat_override = true
			if has_face_color_override:
				_context_menu.add_item("Reset Selected (%d) Color" % selected_faces.size(), ContextAction.RESET_SELECTED_COLOR)
			if has_face_tex_override:
				_context_menu.add_item("Reset Selected (%d) Texture" % selected_faces.size(), ContextAction.RESET_SELECTED_TEXTURE)
			if has_face_mat_override:
				_context_menu.add_item("Reset Selected (%d) Material" % selected_faces.size(), ContextAction.RESET_SELECTED_MATERIAL)
			_context_menu.add_separator()
		
		_context_menu.add_item("Color Base Voxel", ContextAction.COLOR_BASE)
		_context_menu.add_item("Texture Base Voxel", ContextAction.TEXTURE_BASE)
		_context_menu.add_item("Material Base Voxel", ContextAction.MATERIAL_BASE)
		if _voxel.has_base_color():
			_context_menu.add_item("Reset Base Color", ContextAction.RESET_BASE_COLOR)
		if _voxel.has_base_texture_cell():
			_context_menu.add_item("Reset Base Texture", ContextAction.RESET_BASE_TEXTURE)
		if _voxel.has_base_material_id():
			_context_menu.add_item("Reset Base Material", ContextAction.RESET_MATERIAL_BASE)
	
	_context_menu.popup(Rect2i(position, Vector2i.ZERO))


## Builds the select menu.
func _populate_select_menu() -> void:
	## Populates the Select menu with selection-related actions.
	var popup := _select_menu.get_popup()
	popup.clear()
	
	if not _voxel:
		return
	
	var can_select_more := selected_faces.size() < 6
	var has_selection := not selected_faces.is_empty()
	
	if can_select_more:
		popup.add_item("Select All (%d)" % (6 - selected_faces.size()), ContextAction.SELECT_ALL_FACES)
	if has_selection:
		popup.add_item("Unselect All (%d)" % selected_faces.size(), ContextAction.UNSELECT_ALL_FACES)


## Shows or hides toolbar menus by state.
func _update_toolbar_visibility() -> void:
	## Shows/hides the Select and Edit menu buttons based on current settings.
	var can_select := selection_enabled and (selection_max == -1 or selection_max > 0)
	if _select_menu:
		_select_menu.visible = can_select
	
	var is_editable := edit_mode == EditorMode.EDITABLE
	if _edit_menu:
		_edit_menu.visible = is_editable


## Builds the edit menu.
func _populate_edit_menu() -> void:
	var popup := _edit_menu.get_popup()
	popup.clear()
	
	if not _voxel:
		return
	
	# Selected-faces actions
	if not selected_faces.is_empty():
		popup.add_item("Color Selected (%d)" % selected_faces.size(), ContextAction.COLOR_SELECTED)
		popup.add_item("Texture Selected (%d)" % selected_faces.size(), ContextAction.TEXTURE_SELECTED)
		popup.add_item("Material Selected (%d)" % selected_faces.size(), ContextAction.MATERIAL_SELECTED)
		var has_face_color_override := false
		var has_face_tex_override := false
		var has_face_mat_override := false
		for selected_face in selected_faces:
			if _voxel.has_face_color(selected_face, false):
				has_face_color_override = true
			if _voxel.has_face_texture_cell(selected_face, false):
				has_face_tex_override = true
			if _voxel.has_face_material_id(selected_face, false):
				has_face_mat_override = true
		if has_face_color_override:
			popup.add_item("Reset Selected (%d) Color" % selected_faces.size(), ContextAction.RESET_SELECTED_COLOR)
		if has_face_tex_override:
			popup.add_item("Reset Selected (%d) Texture" % selected_faces.size(), ContextAction.RESET_SELECTED_TEXTURE)
		if has_face_mat_override:
			popup.add_item("Reset Selected (%d) Material" % selected_faces.size(), ContextAction.RESET_SELECTED_MATERIAL)
		if has_face_color_override or has_face_tex_override or has_face_mat_override:
			popup.add_separator()
	
	# Voxel-level actions
	popup.add_item("Color Base Voxel", ContextAction.COLOR_BASE)
	popup.add_item("Texture Base Voxel", ContextAction.TEXTURE_BASE)
	popup.add_item("Material Base Voxel", ContextAction.MATERIAL_BASE)
	if _voxel.has_base_color():
		popup.add_item("Reset Base Color", ContextAction.RESET_BASE_COLOR)
	if _voxel.has_base_texture_cell():
		popup.add_item("Reset Base Texture", ContextAction.RESET_BASE_TEXTURE)
	if _voxel.has_base_material_id():
		popup.add_item("Reset Base Material", ContextAction.RESET_MATERIAL_BASE)
	
	# Face-level editing (for the first hovered/context face)
	if _context_menu_face != Vector3i.ZERO:
		popup.add_separator()
		var face_name := Voxel.FACE_NAMES[_context_menu_face]
		popup.add_item("Color %s" % face_name, ContextAction.COLOR_FACE)
		popup.add_item("Texture %s" % face_name, ContextAction.TEXTURE_FACE)
		popup.add_item("Material %s" % face_name, ContextAction.MATERIAL_FACE)
		if _voxel.has_face_color(_context_menu_face, false):
			popup.add_item("Reset %s Color" % face_name, ContextAction.RESET_FACE_COLOR)
		if _voxel.has_face_texture_cell(_context_menu_face, false):
			popup.add_item("Reset %s Texture" % face_name, ContextAction.RESET_FACE_TEXTURE_XY)
		if _voxel.has_face_material_id(_context_menu_face, false):
			popup.add_item("Reset %s Material" % face_name, ContextAction.RESET_MATERIAL_FACE)


## Handles context menu actions.
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
			for face in Voxel.FACES:
				selected_faces.append(face)
				var button = _face_buttons.get(face)
				if button: button.button_pressed = true
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
				var previous_color := _voxel.get_face_color(face, false)
				if _create_undo_action("Reset %s Voxel Face Color" % Voxel.FACE_NAMES[face], voxel_set):
					if _undo_redo_manager:
						_undo_redo_manager.add_do_method(_voxel, "set_face_color", face, Voxel.UNSET_COLOR)
						_undo_redo_manager.add_undo_method(_voxel, "set_face_color", face, previous_color)
					else:
						_undo_redo.add_do_method(_voxel.set_face_color.bind(face, Voxel.UNSET_COLOR))
						_undo_redo.add_undo_method(_voxel.set_face_color.bind(face, previous_color))
					_commit_undo_action()
				else:
					_voxel.set_face_color(face, Voxel.UNSET_COLOR)
				changed.emit()
				_update_view()
				_notify_voxel_set_changed()
		
		ContextAction.RESET_FACE_TEXTURE_XY:
			if _context_menu_face != Vector3i.ZERO:
				var face := _context_menu_face
				var previous_texture := _voxel.get_face_texture_cell(face)
				if _create_undo_action("Reset %s Voxel Face Texture" % Voxel.FACE_NAMES[face], voxel_set):
					if _undo_redo_manager:
						_undo_redo_manager.add_do_method(_voxel, "set_face_texture_cell", face, Voxel.UNSET_TEXTURE_XY)
						_undo_redo_manager.add_undo_method(_voxel, "set_face_texture_cell", face, previous_texture)
					else:
						_undo_redo.add_do_method(_voxel.set_face_texture_cell.bind(face, Voxel.UNSET_TEXTURE_XY))
						_undo_redo.add_undo_method(_voxel.set_face_texture_cell.bind(face, previous_texture))
					_commit_undo_action()
				else:
					_voxel.set_face_texture_cell(face, Voxel.UNSET_TEXTURE_XY)
				changed.emit()
				_update_view()
				_notify_voxel_set_changed()
		
		ContextAction.COLOR_SELECTED:
			if not selected_faces.is_empty():
				var current := _voxel.get_face_color(selected_faces[0], false)
				_is_color_base_mode = false
				_open_color_picker("Color Selected", current, selected_faces)
		
		ContextAction.TEXTURE_SELECTED:
			_is_atlas_base_mode = false
			_open_atlas_picker(selected_faces, "Texture Selected")
		
		ContextAction.RESET_SELECTED_COLOR:
			if not selected_faces.is_empty():
				if _create_undo_action("Reset %d Voxel Faces Color" % selected_faces.size(), voxel_set):
					for face in selected_faces:
						var previous_color := _voxel.get_face_color(face, false)
						if _undo_redo_manager:
							_undo_redo_manager.add_do_method(_voxel, "set_face_color", face, Voxel.UNSET_COLOR)
							_undo_redo_manager.add_undo_method(_voxel, "set_face_color", face, previous_color)
						else:
							_undo_redo.add_do_method(_voxel.set_face_color.bind(face, Voxel.UNSET_COLOR))
							_undo_redo.add_undo_method(_voxel.set_face_color.bind(face, previous_color))
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
					for face in selected_faces:
						var previous_texture := _voxel.get_face_texture_cell(face)
						if _undo_redo_manager:
							_undo_redo_manager.add_do_method(_voxel, "set_face_texture_cell", face, Voxel.UNSET_TEXTURE_XY)
							_undo_redo_manager.add_undo_method(_voxel, "set_face_texture_cell", face, previous_texture)
						else:
							_undo_redo.add_do_method(_voxel.set_face_texture_cell.bind(face, Voxel.UNSET_TEXTURE_XY))
							_undo_redo.add_undo_method(_voxel.set_face_texture_cell.bind(face, previous_texture))
					_commit_undo_action()
				else:
					for selected_face in selected_faces:
						_voxel.set_face_texture_cell(selected_face, Voxel.UNSET_TEXTURE_XY)
				changed.emit()
				_update_view()
				_notify_voxel_set_changed()
		
		ContextAction.COLOR_BASE:
			_is_color_base_mode = true
			_open_color_picker("Change Base Color", _voxel.base_color, [])
		
		ContextAction.TEXTURE_BASE:
			_is_atlas_base_mode = true
			_open_atlas_picker([Vector3i.ZERO], "Change Base Texture")
		
		ContextAction.RESET_BASE_COLOR:
			if _create_undo_action("Reset Voxel Base Color", voxel_set):
				var previous_base_color := _voxel.base_color
				if _undo_redo_manager:
					_undo_redo_manager.add_do_property(_voxel, "base_color", Voxel.UNSET_COLOR)
					_undo_redo_manager.add_undo_property(_voxel, "base_color", previous_base_color)
				else:
					_undo_redo.add_do_property(_voxel, "base_color", Voxel.UNSET_COLOR)
					_undo_redo.add_undo_property(_voxel, "base_color", previous_base_color)
				_commit_undo_action()
			else:
				_voxel.base_color = Voxel.UNSET_COLOR
			changed.emit()
			_update_view()
			_notify_voxel_set_changed()
		
		ContextAction.RESET_BASE_TEXTURE:
			if _create_undo_action("Reset Voxel Base Texture", voxel_set):
				var previous_base_texture := _voxel.base_texture_cell
				if _undo_redo_manager:
					_undo_redo_manager.add_do_property(_voxel, "base_texture_cell", Voxel.UNSET_TEXTURE_XY)
					_undo_redo_manager.add_undo_property(_voxel, "base_texture_cell", previous_base_texture)
				else:
					_undo_redo.add_do_property(_voxel, "base_texture_cell", Voxel.UNSET_TEXTURE_XY)
					_undo_redo.add_undo_property(_voxel, "base_texture_cell", previous_base_texture)
				_commit_undo_action()
			else:
				_voxel.base_texture_cell = Voxel.UNSET_TEXTURE_XY
			changed.emit()
			_update_view()
			_notify_voxel_set_changed()
		
		ContextAction.MATERIAL_FACE:
			if _context_menu_face != Vector3i.ZERO:
				_is_material_base_mode = false
				_open_material_editor([_context_menu_face])
		
		ContextAction.MATERIAL_SELECTED:
			_is_material_base_mode = false
			_open_material_editor(selected_faces)
		
		ContextAction.MATERIAL_BASE:
			_is_material_base_mode = true
			_open_material_editor([])
		
		ContextAction.RESET_MATERIAL_FACE:
			if _context_menu_face != Vector3i.ZERO:
				var face := _context_menu_face
				var previous_material := _voxel.get_face_material_id(face, false)
				if _create_undo_action("Reset %s Voxel Face Material" % Voxel.FACE_NAMES[face], voxel_set):
					if _undo_redo_manager:
						_undo_redo_manager.add_do_method(_voxel, "set_face_material_id", face, Voxel.UNSET_MATERIAL_ID)
						_undo_redo_manager.add_undo_method(_voxel, "set_face_material_id", face, previous_material)
					else:
						_undo_redo.add_do_method(_voxel.set_face_material_id.bind(face, Voxel.UNSET_MATERIAL_ID))
						_undo_redo.add_undo_method(_voxel.set_face_material_id.bind(face, previous_material))
					_commit_undo_action()
				else:
					_voxel.set_face_material_id(face, Voxel.UNSET_MATERIAL_ID)
				changed.emit()
				_update_view()
				_notify_voxel_set_changed()
		
		ContextAction.RESET_SELECTED_MATERIAL:
			if not selected_faces.is_empty():
				if _create_undo_action("Reset %d Voxel Faces Material" % selected_faces.size(), voxel_set):
					for face in selected_faces:
						var previous_material := _voxel.get_face_material_id(face, false)
						if _undo_redo_manager:
							_undo_redo_manager.add_do_method(_voxel, "set_face_material_id", face, Voxel.UNSET_MATERIAL_ID)
							_undo_redo_manager.add_undo_method(_voxel, "set_face_material_id", face, previous_material)
						else:
							_undo_redo.add_do_method(_voxel.set_face_material_id.bind(face, Voxel.UNSET_MATERIAL_ID))
							_undo_redo.add_undo_method(_voxel.set_face_material_id.bind(face, previous_material))
					_commit_undo_action()
				else:
					for selected_face in selected_faces:
						_voxel.set_face_material_id(selected_face, Voxel.UNSET_MATERIAL_ID)
				changed.emit()
				_update_view()
				_notify_voxel_set_changed()
		
		ContextAction.RESET_MATERIAL_BASE:
			if _create_undo_action("Reset Voxel Base Material", voxel_set):
				var previous_base_material := _voxel.base_material_id
				if _undo_redo_manager:
					_undo_redo_manager.add_do_property(_voxel, "base_material_id", Voxel.UNSET_MATERIAL_ID)
					_undo_redo_manager.add_undo_property(_voxel, "base_material_id", previous_base_material)
				else:
					_undo_redo.add_do_property(_voxel, "base_material_id", Voxel.UNSET_MATERIAL_ID)
					_undo_redo.add_undo_property(_voxel, "base_material_id", previous_base_material)
				_commit_undo_action()
			else:
				_voxel.base_material_id = Voxel.UNSET_MATERIAL_ID
			changed.emit()
			_update_view()
			_notify_voxel_set_changed()
		
		ContextAction.CHANGE_ENVIRONMENT:
			_file_dialog.popup_centered_clamped(Vector2i(300, 250))
		
		ContextAction.RESET_ENVIRONMENT:
			_reset_environment()

## Opens the color picker for the given faces.
func _open_color_picker(title: String, current: Color, color_faces: Array[Vector3i]) -> void:
	if not _voxel:
		return
	
	# Snapshot original_material_id values for revert on cancel
	_color_originals.clear()
	_color_faces = color_faces
	if _is_color_base_mode:
		_color_originals["base"] = _voxel.base_color
	else:
		for face in color_faces:
			_color_originals[face] = _voxel.get_face_color(face, false)
	
	_color_picker_window.title = title
	if current.a == 0:
		current.a = 1
	_color_picker_window.color = current
	
	# Connect live preview, disconnect any previous first to avoid duplicates
	var picker: ColorPicker = _color_picker_window.get_color_picker()
	if picker.color_changed.is_connected(_on_color_preview):
		picker.color_changed.disconnect(_on_color_preview)
	picker.color_changed.connect(_on_color_preview)
	
	_color_picker_window.popup_centered_clamped()

## Applies the color live while previewing.
func _on_color_preview(new_color: Color) -> void:
	if not _voxel:
		return
	if _is_color_base_mode:
		_voxel.base_color = new_color
	else:
		for face in _color_faces:
			_voxel.set_face_color(face, new_color)
	_update_view()

## Applies the confirmed color.
func _apply_color_picker(color: Color) -> void:
	var picker: ColorPicker = _color_picker_window.get_color_picker()
	if picker.color_changed.is_connected(_on_color_preview):
		picker.color_changed.disconnect(_on_color_preview)
	
	if _is_color_base_mode:
		_apply_base_color(color)
	else:
		_apply_faces_color(_color_faces, color)
	_close_color_picker()

## Hides the color picker window.
func _close_color_picker() -> void:
	if _color_picker_window:
		# Disconnect live preview
		var picker: ColorPicker = _color_picker_window.get_color_picker()
		if picker.color_changed.is_connected(_on_color_preview):
			picker.color_changed.disconnect(_on_color_preview)
		_color_picker_window.hide()

## Restores the original colors and closes the picker.
func _cancel_color_picker() -> void:
	if not _voxel:
		return
	# Disconnect live preview
	var picker: ColorPicker = _color_picker_window.get_color_picker()
	if picker.color_changed.is_connected(_on_color_preview):
		picker.color_changed.disconnect(_on_color_preview)
	# Restore original_material_id values
	if _is_color_base_mode and _color_originals.has("base"):
		_voxel.base_color = _color_originals["base"]
	else:
		for face in _color_originals:
			if face is Vector3i:
				_voxel.set_face_color(face, _color_originals[face])
	_update_view()
	_close_color_picker()

## Begins an undo action on the active stack.
func _create_undo_action(action_name: String, context: Object = null) -> bool:
	if _undo_redo_manager:
		_undo_redo_manager.create_action(action_name, UndoRedo.MERGE_DISABLE, context)
		return true
	if _undo_redo:
		_undo_redo.create_action(action_name)
		return true
	return false

## Commits the active undo action.
func _commit_undo_action(execute: bool = true) -> void:
	if _undo_redo_manager:
		_undo_redo_manager.commit_action(execute)
	elif _undo_redo:
		_undo_redo.commit_action(execute)

## Emits the voxel set changed signal.
func _notify_voxel_set_changed() -> void:
	if voxel_set:
		voxel_set.changed.emit()

## Applies a new base color through undo/redo.
func _apply_base_color(new_color: Color) -> void:
	if not _voxel:
		return
	if _create_undo_action("Color Voxel Base", voxel_set):
		var previous_color := _color_originals.get("base", _voxel.base_color)
		if _undo_redo_manager:
			_undo_redo_manager.add_do_property(_voxel, "base_color", new_color)
			_undo_redo_manager.add_undo_property(_voxel, "base_color", previous_color)
		else:
			_undo_redo.add_do_property(_voxel, "base_color", new_color)
			_undo_redo.add_undo_property(_voxel, "base_color", previous_color)
		_commit_undo_action()
	else:
		_voxel.base_color = new_color
	changed.emit()
	_update_view()
	_notify_voxel_set_changed()

## Applies a new color to the given faces.
func _apply_faces_color(faces: Array[Vector3i], new_color: Color) -> void:
	if not _voxel:
		return
	if _create_undo_action("Color %d Voxel Faces" % faces.size(), voxel_set):
		for face in faces:
			var previous_color := _color_originals.get(face, _voxel.get_face_color(face, false))
			if _undo_redo_manager:
				_undo_redo_manager.add_do_method(_voxel, "set_face_color", face, new_color)
				_undo_redo_manager.add_undo_method(_voxel, "set_face_color", face, previous_color)
			else:
				_undo_redo.add_do_method(_voxel.set_face_color.bind(face, new_color))
				_undo_redo.add_undo_method(_voxel.set_face_color.bind(face, previous_color))
		_commit_undo_action()
	else:
		for face in faces:
			_voxel.set_face_color(face, new_color)
	changed.emit()
	_update_view()
	for face in faces:
		face_edited.emit(voxel_id, face)
	_notify_voxel_set_changed()

## Shows a warning when the atlas is missing.
func _show_texture_warning() -> void:
	if not _accept_dialog or not voxel_set:
		return
	
	var missing: PackedStringArray = []
	if not voxel_set.texture_atlas:
		missing.append("- A texture atlas image")
	if voxel_set.texture_atlas_cell_size.x <= 0 or voxel_set.texture_atlas_cell_size.y <= 0:
		missing.append("- A cell size (width x height > 0)")
	
	var message: String = "Texture atlas is not ready.\n\nThe VoxelSet needs:\n" + "\n".join(missing)
	_accept_dialog.title = "Texture Atlas Not Ready"
	_accept_dialog.dialog_text = message
	_accept_dialog.popup_centered_clamped()


## Opens the atlas picker for the given faces.
func _open_atlas_picker(target_faces: Array[Vector3i], context_name: String) -> void:
	if not voxel_set:
		return
	
	if not voxel_set.is_texture_ready():
		_show_texture_warning()
		return
	
	_atlas_target_faces = target_faces
	
	# Snapshot original_material_id textures for revert on cancel
	_atlas_originals.clear()
	if _is_atlas_base_mode:
		if _voxel:
			_atlas_originals["base"] = _voxel.base_texture_cell
	elif _voxel:
		for face in target_faces:
			_atlas_originals[face] = _voxel.get_face_texture_cell(face)
	
	var picker = _atlas_texture_picker_window.get_atlas_texture_picker()
	picker.voxel_id = voxel_id
	picker.voxel_set = voxel_set
	picker.reference_faces = target_faces
	picker.selected_texture_cell = [] as Array[Vector2i]
	
	# Connect live preview
	if picker.texture_cell_selected.is_connected(_on_atlas_preview):
		picker.texture_cell_selected.disconnect(_on_atlas_preview)
	if picker.texture_cell_unselected.is_connected(_on_atlas_preview):
		picker.texture_cell_unselected.disconnect(_on_atlas_preview)
	picker.texture_cell_selected.connect(_on_atlas_preview)
	picker.texture_cell_unselected.connect(_on_atlas_preview)
	
	var ok_text := "Set Base Texture" if _is_atlas_base_mode else ("Set %s Texture" % Voxel.FACE_NAMES[target_faces[0]] if target_faces.size() == 1 else "Set Texture (%d faces)" % target_faces.size())
	_atlas_texture_picker_window.setup(context_name, ok_text, "Cancel")
	
	_atlas_texture_picker_window.popup_centered_clamped()


## Applies the atlas selection live while previewing.
func _on_atlas_preview(_uv: Vector2i) -> void:
	if not _voxel:
		return
	var texture_cells = _atlas_texture_picker_window.get_atlas_texture_picker().get_selected_texture_cell()
	if texture_cells.is_empty():
		return
	var texture_cell = texture_cells[0]
	if _is_atlas_base_mode:
		_voxel.base_texture_cell = texture_cell
	else:
		for face in _atlas_target_faces:
			_voxel.set_face_texture_cell(face, texture_cell)
	_update_view()


## Applies the confirmed atlas selection.
func _on_atlas_ok() -> void:
	if not _voxel:
		return
	var picker = _atlas_texture_picker_window.get_atlas_texture_picker()
	# Disconnect live preview
	if picker.texture_cell_selected.is_connected(_on_atlas_preview):
		picker.texture_cell_selected.disconnect(_on_atlas_preview)
	if picker.texture_cell_unselected.is_connected(_on_atlas_preview):
		picker.texture_cell_unselected.disconnect(_on_atlas_preview)
	
	var texture_cells = picker.get_selected_texture_cell()
	if texture_cells.is_empty():
		return
	var texture_cell = texture_cells[0]
	
	if _is_atlas_base_mode:
		if _create_undo_action("Texture Voxel Base", voxel_set):
			var previous_texture := _atlas_originals.get("base", _voxel.base_texture_cell)
			if _undo_redo_manager:
				_undo_redo_manager.add_do_property(_voxel, "base_texture_cell", texture_cell)
				_undo_redo_manager.add_undo_property(_voxel, "base_texture_cell", previous_texture)
			else:
				_undo_redo.add_do_property(_voxel, "base_texture_cell", texture_cell)
				_undo_redo.add_undo_property(_voxel, "base_texture_cell", previous_texture)
			_commit_undo_action()
		else:
			_voxel.base_texture_cell = texture_cell
	else:
		if _create_undo_action("Texture %d Voxel Faces" % _atlas_target_faces.size(), voxel_set):
			for face in _atlas_target_faces:
				var previous_texture := _atlas_originals.get(face, _voxel.get_face_texture_cell(face))
				if _undo_redo_manager:
					_undo_redo_manager.add_do_method(_voxel, "set_face_texture_cell", face, texture_cell)
					_undo_redo_manager.add_undo_method(_voxel, "set_face_texture_cell", face, previous_texture)
				else:
					_undo_redo.add_do_method(_voxel.set_face_texture_cell.bind(face, texture_cell))
					_undo_redo.add_undo_method(_voxel.set_face_texture_cell.bind(face, previous_texture))
			_commit_undo_action()
		else:
			for face in _atlas_target_faces:
				_voxel.set_face_texture_cell(face, texture_cell)
	
	changed.emit()
	_update_view()
	for face in _atlas_target_faces:
		face_edited.emit(voxel_id, face)
	_notify_voxel_set_changed()


## Restores the original cells and closes the picker.
func _on_atlas_cancel() -> void:
	var picker = _atlas_texture_picker_window.get_atlas_texture_picker()
	# Disconnect live preview
	if picker.texture_cell_selected.is_connected(_on_atlas_preview):
		picker.texture_cell_selected.disconnect(_on_atlas_preview)
	if picker.texture_cell_unselected.is_connected(_on_atlas_preview):
		picker.texture_cell_unselected.disconnect(_on_atlas_preview)
	
	# Restore original_material_id textures
	if _voxel:
		if _is_atlas_base_mode and _atlas_originals.has("base"):
			_voxel.base_texture_cell = _atlas_originals["base"]
		else:
			for face in _atlas_originals:
				if face is Vector3i:
					_voxel.set_face_texture_cell(face, _atlas_originals[face])
		_update_view()

## Handles settings menu actions.
func _on_settings_action(id: int) -> void:
	match id:
		ContextAction.CHANGE_ENVIRONMENT:
			_file_dialog.popup_centered()
		ContextAction.RESET_ENVIRONMENT:
			_reset_environment()

## Loads the selected environment file.
func _on_env_file_selected(path: String) -> void:
	_env_path = path
	_save_env_config()
	_set_environment(load(path))

## Applies an environment to the viewport.
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

## Restores the default environment.
func _reset_environment() -> void:
	_env_path = ""
	_save_env_config()
	# Re-enable transparent background for the default clean look
	_viewport.transparent_bg = true
	_setup_3d_default_environment()

## Creates the built-in 3D default environment.
func _setup_3d_default_environment() -> void:
	var env := load(DEFAULT_ENV_PATH) as Environment
	if env:
		_set_environment(env)
	else:
		# Fallback in case the default .tres is missing.
		var fallback := Environment.new()
		fallback.background_mode = Environment.BG_CLEAR_COLOR
		fallback.ambient_light_color = Color(0.25, 0.25, 0.3)
		fallback.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_set_environment(fallback)

## Restores the environment from the saved config.
func _load_env_config() -> void:
	_env_path = VoxlyConfig.get_value("voxel_editor", "voxel_editor", "env_path", "")
	if not _env_path.is_empty():
		var env := load(_env_path)
		if env is Environment:
			_set_environment(env)
			return
	_setup_3d_default_environment()

## Persists the environment path to the config.
func _save_env_config() -> void:
	VoxlyConfig.set_value("voxel_editor", "voxel_editor", "env_path", _env_path)

## Cancels the color picker session.
func _on_color_picker_window_color_canceled():
	_cancel_color_picker()

## Applies the confirmed color.
func _on_color_picker_window_color_confirmed(color):
	_apply_color_picker(color)

## Cancels the color picker on close.
func _on_color_picker_window_close_requested():
	_cancel_color_picker()

## Opens the material editor for the given faces.
func _open_material_editor(target_faces: Array[Vector3i]) -> void:
	if not _voxel:
		return
	_material_target_faces = target_faces
	_material_originals.clear()
	var current_material_id := ""
	if _is_material_base_mode:
		current_material_id = _voxel.get_base_material_id()
		_material_originals["base"] = current_material_id
	else:
		for face in target_faces:
			var face_material_id := _voxel.get_face_material_id(face, false)
			_material_originals[face] = face_material_id
			if current_material_id.is_empty() and not face_material_id.is_empty():
				current_material_id = face_material_id
	_material_editor_window.voxel_set = voxel_set
	_material_editor_window.edit_mode = MaterialEditorWindowScript.EditMode.EDITABLE
	_material_editor_window.material_id = current_material_id
	_material_editor_window.picker_allow_unset = true
	_material_editor_window.popup_centered_clamped()

## Refreshes the view when the material editor changes.
func _on_material_editor_window_changed() -> void:
	_update_view()
	changed.emit()
	_notify_voxel_set_changed()

## Applies the new material ID live.
func _on_material_editor_material_id_changed(new_material_id: String) -> void:
	if not _voxel:
		return
	if _material_target_faces.is_empty() and not _is_material_base_mode:
		return
	if _is_material_base_mode:
		_voxel.base_material_id = new_material_id
	else:
		for face in _material_target_faces:
			_voxel.set_face_material_id(face, new_material_id)
	_update_view()

## Commits the material edits through undo/redo.
func _on_material_editor_session_finished() -> void:
	if not _voxel:
		return
	if _material_target_faces.is_empty() and not _is_material_base_mode:
		return
	
	if _is_material_base_mode:
		var current_material_id := _voxel.get_base_material_id()
		var original_material_id: String = _material_originals.get("base", "")
		if current_material_id != original_material_id:
			if _create_undo_action("Edit Voxel Base Material", voxel_set):
				if _undo_redo_manager:
					_undo_redo_manager.add_do_property(_voxel, "base_material_id", current_material_id)
					_undo_redo_manager.add_undo_property(_voxel, "base_material_id", original_material_id)
				else:
					_undo_redo.add_do_property(_voxel, "base_material_id", current_material_id)
					_undo_redo.add_undo_property(_voxel, "base_material_id", original_material_id)
				_commit_undo_action()
		changed.emit()
		_update_view()
		_notify_voxel_set_changed()
	else:
		var action_name := "Edit %d Voxel Faces Material" % _material_target_faces.size()
		if _material_target_faces.size() == 1:
			action_name = "Edit %s Material" % Voxel.FACE_NAMES[_material_target_faces[0]]
		if _create_undo_action(action_name, voxel_set):
			for face in _material_target_faces:
				var current := _voxel.get_face_material_id(face, false)
				var original_material_id: String = _material_originals.get(face, "")
				if current == original_material_id:
					continue
				if _undo_redo_manager:
					_undo_redo_manager.add_do_method(_voxel, "set_face_material_id", face, current)
					_undo_redo_manager.add_undo_method(_voxel, "set_face_material_id", face, original_material_id)
				else:
					_undo_redo.add_do_method(_voxel.set_face_material_id.bind(face, current))
					_undo_redo.add_undo_method(_voxel.set_face_material_id.bind(face, original_material_id))
			_commit_undo_action()
		changed.emit()
		_update_view()
		for face in _material_target_faces:
			face_edited.emit(voxel_id, face)
		_notify_voxel_set_changed()
	
	_material_target_faces.clear()
	_material_originals.clear()
