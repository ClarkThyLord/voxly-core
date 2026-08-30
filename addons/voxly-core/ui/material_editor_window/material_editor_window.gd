## Popup window for editing a single material.
##
## Hosts the material editor with its own Ok/Cancel buttons and undo/redo
## plumbing for the embedded picker and inspector.
@tool
extends Window

## Emitted when the inner editor modifies materials or material properties.
signal changed

## Emitted when the user selects a different material inside the editor.
signal material_id_changed(material_id: String)

## Emitted when the user clicks "Edit in Inspector" inside the editor.
signal edit_in_inspector_requested(material_id: String)

## Emitted when Ok is pressed.
signal confirmed

## Emitted when the user closes the window or clicks Close.
signal canceled

## Whether the material editor window is editable or view-only.
enum EditMode {
	VIEW_ONLY,
	EDITABLE,
}

## The VoxelSet whose materials to edit.
@export var voxel_set: VoxelSet = null:
	set = _set_voxel_set

## Currently selected material id. Empty string means nothing selected.
@export var material_id: String = "":
	set = _set_material_id

## Whether the toolbar and material inspector are editable.
@export var edit_mode: EditMode = EditMode.EDITABLE:
	set = _set_edit_mode

## When true, the material picker shows an "Unset" option so an assignment can
## be cleared. Used by the voxel editor for per-face/base assignment.
@export var picker_allow_unset: bool = false:
	set = _set_picker_allow_unset

## When true, the material picker shows a "Default" option representing the
## VoxelSet's default_material. Selecting it allows viewing/editing the default
## material and duplicating it into a named material.
@export var picker_allow_default: bool = false:
	set = _set_picker_allow_default

## The embedded material editor widget.
@onready var _material_editor: Control = %MaterialEditor
## Confirms the edited material.
@onready var _ok_button: Button = %Ok
## Dismisses the window without changes.
@onready var _cancel_button: Button = %Cancel

## Plain UndoRedo stack used when not in the editor.
var _undo_redo: UndoRedo = null
## Editor undo/redo manager used inside the editor.
var _undo_redo_manager: EditorUndoRedoManager = null

## Updates the voxel set for the material picker.
func _set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if voxel_set == new_voxel_set:
		return
	voxel_set = new_voxel_set
	if _material_editor:
		_material_editor.voxel_set = new_voxel_set

## Updates the material being edited.
func _set_material_id(new_material_id: String) -> void:
	if new_material_id == material_id:
		return
	material_id = new_material_id
	if _material_editor:
		_material_editor.material_id = new_material_id

## Updates the edit/read-only mode.
func _set_edit_mode(new_edit_mode: EditMode) -> void:
	if new_edit_mode == edit_mode:
		return
	edit_mode = new_edit_mode
	if _material_editor:
		_material_editor.edit_mode = new_edit_mode

## Toggles the unset option in the material picker.
func _set_picker_allow_unset(value: bool) -> void:
	if value == picker_allow_unset:
		return
	picker_allow_unset = value
	if _material_editor:
		_material_editor.picker_allow_unset = value

## Toggles the default option in the material picker.
func _set_picker_allow_default(value: bool) -> void:
	if value == picker_allow_default:
		return
	picker_allow_default = value
	if _material_editor:
		_material_editor.picker_allow_default = value

## Connects the window buttons and inner editor signals.
func _ready() -> void:
	_ok_button.pressed.connect(_on_ok)
	_cancel_button.pressed.connect(_on_cancel)
	close_requested.connect(_on_cancel)
	
	# Forward inner editor signals so parents connect only to the window.
	_material_editor.changed.connect(func() -> void: changed.emit())
	_material_editor.material_id_changed.connect(_on_inner_material_id_changed)
	_material_editor.edit_in_inspector_requested.connect(func(id: String) -> void: edit_in_inspector_requested.emit(id))
	
	_propagate_undo_redo()
	_material_editor.voxel_set = voxel_set
	_material_editor.material_id = material_id
	_material_editor.edit_mode = edit_mode
	_material_editor.picker_allow_unset = picker_allow_unset
	_material_editor.picker_allow_default = picker_allow_default

## Configures the window before showing it.
func setup(
		title: String,
		voxel_set: VoxelSet,
		material_id: String,
		edit_mode: EditMode,
		picker_allow_unset := false,
		picker_allow_default := false) -> void:
	self.title = title
	self.voxel_set = voxel_set
	self.material_id = material_id
	self.edit_mode = edit_mode
	self.picker_allow_unset = picker_allow_unset
	self.picker_allow_default = picker_allow_default

## Returns the underlying MaterialEditor.
func get_material_editor() -> Control:
	return _material_editor

## Sets the plain undo/redo stack.
func set_undo_redo(undo_redo: UndoRedo) -> void:
	_undo_redo = undo_redo
	_propagate_undo_redo()

## Sets the editor undo/redo manager.
func set_undo_redo_manager(manager: EditorUndoRedoManager) -> void:
	_undo_redo_manager = manager
	_propagate_undo_redo()

## Shares the undo/redo stack with the inner editor.
func _propagate_undo_redo() -> void:
	if _material_editor:
		_material_editor.set_undo_redo(_undo_redo)
		_material_editor.set_undo_redo_manager(_undo_redo_manager)

## Syncs the window material ID from the inner editor.
func _on_inner_material_id_changed(material_id: String) -> void:
	self.material_id = material_id
	material_id_changed.emit(material_id)

## Emits the confirmed signal.
func _on_ok() -> void:
	confirmed.emit()
	hide()

## Emits the canceled signal.
func _on_cancel() -> void:
	canceled.emit()
	hide()
