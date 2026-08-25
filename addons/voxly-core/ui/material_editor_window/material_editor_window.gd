@tool
extends Window

## Emitted when the inner editor modifies materials or material properties.
signal changed

## Emitted when the user selects a different material inside the editor.
signal material_id_changed(material_id: String)

## Emitted when the user clicks "Edit in Inspector" inside the editor.
signal edit_in_inspector_requested(material_id: String)

## Emitted when Ok is pressed
signal confirmed

## Emitted when the user closes the window or clicks Close.
signal canceled

enum EditMode {
	VIEW_ONLY,
	EDITABLE,
}

## The VoxelSet whose materials to edit.
@export
var voxel_set: VoxelSet = null:
	set = _set_voxel_set

## Currently selected material id. Empty string means nothing selected.
@export
var material_id: String = "":
	set = _set_material_id

## Whether the toolbar and material inspector are editable.
@export
var edit_mode: EditMode = EditMode.EDITABLE:
	set = _set_edit_mode

## When true, the material picker shows an "Unset" option so an assignment
## can be cleared. Used by the voxel editor for per-face/base assignment.
@export
var picker_allow_unset: bool = false:
	set = _set_picker_allow_unset

## When true, the material picker shows a "Default" option representing the
## VoxelSet's default_material. Selecting it allows viewing/editing the
## default material and duplicating it into a named material.
@export
var picker_allow_default: bool = false:
	set = _set_picker_allow_default

@onready
var _material_editor: Control = %MaterialEditor

@onready
var _ok_button: Button = %Ok

@onready
var _cancel_button: Button = %Cancel

var _undo_redo: UndoRedo = null
var _undo_redo_manager: EditorUndoRedoManager = null

func _set_voxel_set(new_set: VoxelSet) -> void:
	if voxel_set == new_set:
		return
	voxel_set = new_set
	if _material_editor:
		_material_editor.voxel_set = new_set

func _set_material_id(new_id: String) -> void:
	if new_id == material_id:
		return
	material_id = new_id
	if _material_editor:
		_material_editor.material_id = new_id

func _set_edit_mode(new_mode: EditMode) -> void:
	if new_mode == edit_mode:
		return
	edit_mode = new_mode
	if _material_editor:
		_material_editor.edit_mode = new_mode

func _set_picker_allow_unset(value: bool) -> void:
	if value == picker_allow_unset:
		return
	picker_allow_unset = value
	if _material_editor:
		_material_editor.picker_allow_unset = value

func _set_picker_allow_default(value: bool) -> void:
	if value == picker_allow_default:
		return
	picker_allow_default = value
	if _material_editor:
		_material_editor.picker_allow_default = value

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

## Configure the window before showing it.
func setup(
	title: String,
	p_voxel_set: VoxelSet,
	p_material_id: String,
	p_edit_mode: EditMode,
	p_picker_allow_unset := false,
	p_picker_allow_default := false) -> void:
	self.title = title
	voxel_set = p_voxel_set
	material_id = p_material_id
	edit_mode = p_edit_mode
	picker_allow_unset = p_picker_allow_unset
	picker_allow_default = p_picker_allow_default

## Returns the underlying MaterialEditor
func get_material_editor() -> Control:
	return _material_editor

func set_undo_redo(undo_redo: UndoRedo) -> void:
	_undo_redo = undo_redo
	_propagate_undo_redo()

func set_undo_redo_manager(manager: EditorUndoRedoManager) -> void:
	_undo_redo_manager = manager
	_propagate_undo_redo()

func _propagate_undo_redo() -> void:
	if _material_editor:
		_material_editor.set_undo_redo(_undo_redo)
		_material_editor.set_undo_redo_manager(_undo_redo_manager)

func _on_inner_material_id_changed(id: String) -> void:
	material_id = id
	material_id_changed.emit(id)

func _on_ok() -> void:
	confirmed.emit()
	hide()

func _on_cancel() -> void:
	canceled.emit()
	hide()
