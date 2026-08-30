## Material library editor.
##
## Manages the named materials of a [VoxelSet]: add, rename, duplicate,
## remove, and edit materials, with undo/redo support and a
## picker/info/inspector layout.
@tool
extends BoxContainer

## Emitted when materials are added, renamed, duplicated, removed, or a material
## property is edited.
signal changed

## Emitted when the selected material changes, such as from the picker or when
## a newly added material is auto-selected.
signal material_id_changed(material_id: String)

## Emitted when the user clicks "Edit in Inspector".
signal edit_in_inspector_requested(material_id: String)

## Whether the material editor is editable or view-only.
enum EditMode {
	VIEW_ONLY,
	EDITABLE,
}

## Whether the name window is renaming or duplicating a material.
enum NameMode {
	RENAME,
	DUPLICATE,
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
## VoxelSet's default_material.
@export var picker_allow_default: bool = false:
	set = _set_picker_allow_default

## Toolbar with material actions.
@onready var _toolbar: HBoxContainer = %ToolbarHBoxContainer
## Material selector dropdown.
@onready var _picker: OptionButton = %MaterialPicker
## Material info panel.
@onready var _info: Control = %MaterialInfo
## Material property inspector.
@onready var _inspector: Control = %MaterialInspector
## Notice shown when no material is selected.
@onready var _notice_label: Label = %NoticeLabel
## Main content container.
@onready var _content: VBoxContainer = %ContentVBoxContainer
## Adds a new material.
@onready var _add_button: Button = %AddButton
## Renames the selected material.
@onready var _rename_button: Button = %RenameButton
## Duplicates the selected material.
@onready var _duplicate_button: Button = %DuplicateButton
## Removes the selected material.
@onready var _remove_button: Button = %RemoveButton
## Opens the selected material in the editor inspector.
@onready var _edit_in_inspector_button: Button = %EditInInspectorButton
## Popup for entering a new material name.
@onready var _name_window: Window = %NameWindow
## Name input field.
@onready var _name_line_edit: LineEdit = %NameWindowLineEdit
## Confirms the new name.
@onready var _name_ok_button: Button = %NameWindowOkButton
## Cancels the rename.
@onready var _name_cancel_button: Button = %NameWindowCancelButton
## Confirmation dialog for destructive actions.
@onready var _confirm_window: ConfirmationDialog = %ConfirmWindow

## True while a refresh is queued for the ready state.
var _pending_refresh := false
## Whether the name window is renaming or duplicating.
var _name_mode: NameMode = NameMode.RENAME
## Material ID being renamed or duplicated.
var _name_old_material_id: String = ""
## Material ID awaiting removal confirmation.
var _pending_remove_material_id: String = ""

## Plain UndoRedo stack used when not in the editor.
var _undo_redo: UndoRedo = null
## Editor undo/redo manager used inside the editor.
var _undo_redo_manager: EditorUndoRedoManager = null

## Updates the voxel set and schedules a refresh.
func _set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if voxel_set == new_voxel_set:
		return
	if voxel_set and voxel_set.materials_changed.is_connected(_refresh):
		voxel_set.materials_changed.disconnect(_refresh)
	voxel_set = new_voxel_set
	if voxel_set and not voxel_set.materials_changed.is_connected(_refresh):
		voxel_set.materials_changed.connect(_refresh)
	if is_inside_tree():
		_refresh()
	else:
		_pending_refresh = true

## Updates the selected material and schedules a refresh.
func _set_material_id(new_material_id: String) -> void:
	if new_material_id == material_id:
		return
	material_id = new_material_id
	if _picker:
		_picker.material_id = new_material_id
	if _info:
		_info.material_id = new_material_id
	if _inspector:
		_inspector.material_id = new_material_id
	_update_toolbar_buttons()
	_apply_notice_state()

## Updates the edit/read-only mode.
func _set_edit_mode(new_edit_mode: EditMode) -> void:
	if new_edit_mode == edit_mode:
		return
	edit_mode = new_edit_mode
	_apply_edit_mode()

## Toggles the unset option in the material picker.
func _set_picker_allow_unset(value: bool) -> void:
	if value == picker_allow_unset:
		return
	picker_allow_unset = value
	_refresh()

## Toggles the default option in the material picker.
func _set_picker_allow_default(value: bool) -> void:
	if value == picker_allow_default:
		return
	picker_allow_default = value
	_refresh()

## Connects all toolbar and window signals.
func _ready() -> void:
	# Toolbar buttons.
	_add_button.pressed.connect(_on_add_pressed)
	_rename_button.pressed.connect(_on_rename_pressed)
	_duplicate_button.pressed.connect(_on_duplicate_pressed)
	_remove_button.pressed.connect(_on_remove_pressed)
	_edit_in_inspector_button.pressed.connect(_on_edit_in_inspector_pressed)
	
	# Name window.
	_name_ok_button.pressed.connect(_on_name_ok)
	_name_cancel_button.pressed.connect(_on_name_cancel)
	_name_line_edit.text_submitted.connect(_on_name_ok)
	_name_window.close_requested.connect(_on_name_cancel)
	
	# Confirm window.
	_confirm_window.confirmed.connect(_on_remove_confirmed)
	
	# Wire children.
	_inspector.changed.connect(func() -> void: changed.emit())
	_picker.material_id_changed.connect(_on_picker_material_id_changed)
	
	# Only show the "Edit in Inspector" button when running inside the Godot
	# editor.
	_edit_in_inspector_button.visible = Engine.is_editor_hint()
	
	_apply_edit_mode()
	
	if _pending_refresh:
		_refresh()

## Rebuilds the material list and child panels.
func _refresh() -> void:
	if not _picker:
		_pending_refresh = true
		return
	_pending_refresh = false
	
	_picker.voxel_set = voxel_set
	_info.voxel_set = voxel_set
	_inspector.voxel_set = voxel_set
	
	# Unselect if the material no longer exists.
	if not material_id.is_empty() and not voxel_set.material_id_exists(material_id):
		_set_material_id("")
	
	# "Unset" only makes sense when there are materials to unset from.
	_picker.show_unset = picker_allow_unset and voxel_set and voxel_set.get_materials_count() > 0
	# The default material always exists, so "Default" only needs a VoxelSet.
	_picker.show_default = picker_allow_default and voxel_set != null
	
	# Selection to empty when there are no materials.
	if voxel_set and voxel_set.get_materials_count() == 0:
		_set_material_id("")
	
	_apply_notice_state()
	_set_material_id(material_id)
	_update_toolbar_buttons()

## Shows or hides the no-material notice.
func _apply_notice_state() -> void:
	if not _notice_label or not _content:
		return
	var has_set := voxel_set != null
	var count := voxel_set.get_materials_count() if voxel_set else 0
	# An empty material id represents the default material when the Default
	# picker option is enabled; otherwise it means nothing is selected.
	var is_default_selected := picker_allow_default and has_set and material_id.is_empty()
	if not has_set:
		_notice_label.text = "No VoxelSet."
		_content.visible = false
		_notice_label.visible = true
	elif count == 0 and not is_default_selected:
		_notice_label.text = "VoxelSet has no materials.\nUse \"Add\" to create one."
		_content.visible = false
		_notice_label.visible = true
	elif not is_default_selected and (material_id.is_empty() or not voxel_set.material_id_exists(material_id)):
		_notice_label.text = "No material selected.\nPick a material, or \"Unset\" to leave it unassigned."
		_content.visible = false
		_notice_label.visible = true
	else:
		_notice_label.visible = false
		_content.visible = true

## Applies the edit mode to the toolbar.
func _apply_edit_mode() -> void:
	if not _toolbar:
		return
	var editable := edit_mode == EditMode.EDITABLE
	_toolbar.visible = editable
	_inspector.edit_mode = EditMode.EDITABLE if editable else EditMode.VIEW_ONLY

## Enables or disables toolbar buttons by state.
func _update_toolbar_buttons() -> void:
	if not _add_button:
		return
	var has_set := voxel_set != null
	var has_selection := has_set and not material_id.is_empty() and voxel_set.material_id_exists(material_id)
	# The default material can be duplicated and edited, but never renamed or
	# removed.
	var is_default_selection := has_set and picker_allow_default and material_id.is_empty()
	var can_duplicate := has_selection or is_default_selection
	_add_button.disabled = not has_set
	_rename_button.disabled = not has_selection
	_duplicate_button.disabled = not can_duplicate
	_remove_button.disabled = not has_selection
	_edit_in_inspector_button.disabled = not can_duplicate

## Sets a plain UndoRedo for standalone usage. Propagated to the inspector.
func set_undo_redo(undo_redo: UndoRedo) -> void:
	_undo_redo = undo_redo
	if _inspector and _inspector.has_method("set_undo_redo"):
		_inspector.set_undo_redo(undo_redo)

## Sets an EditorUndoRedoManager for editor plugin integration. Propagated to
## the inspector.
func set_undo_redo_manager(manager: EditorUndoRedoManager) -> void:
	_undo_redo_manager = manager
	if _inspector and _inspector.has_method("set_undo_redo_manager"):
		_inspector.set_undo_redo_manager(manager)

## Begins an undo action on the active undo/redo stack.
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

## Adds a new material to the voxel set.
func _on_add_pressed() -> void:
	if not voxel_set:
		return
	# The freshly added material should also be applied to the target in
	# assignment sessions.
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	var new_material_id := voxel_set.next_material_id()
	if _create_undo_action("Add Material", voxel_set):
		if _undo_redo_manager:
			_undo_redo_manager.add_do_method(voxel_set, "set_material", new_material_id, material)
			_undo_redo_manager.add_undo_method(voxel_set, "remove_material", new_material_id)
		else:
			_undo_redo.add_do_method(voxel_set.set_material.bind(new_material_id, material))
			_undo_redo.add_undo_method(voxel_set.remove_material.bind(new_material_id))
		_commit_undo_action()
	else:
		voxel_set.set_material(new_material_id, material)
	_set_material_id(new_material_id)
	material_id_changed.emit(new_material_id)
	changed.emit()

## Opens the name window in rename mode.
func _on_rename_pressed() -> void:
	if material_id.is_empty():
		return
	_name_mode = NameMode.RENAME
	_name_old_material_id = material_id
	_name_window.title = "Rename Material"
	_name_ok_button.text = "Rename"
	_name_line_edit.text = material_id
	_name_line_edit.placeholder_text = "New material id..."
	_name_window.popup_centered_clamped()
	_name_line_edit.grab_focus()
	_name_line_edit.select_all()

## Opens the name window in duplicate mode.
func _on_duplicate_pressed() -> void:
	if material_id.is_empty():
		return
	_name_mode = NameMode.DUPLICATE
	_name_old_material_id = material_id
	_name_window.title = "Duplicate Material"
	_name_ok_button.text = "Duplicate"
	# Pre-fill the next available id.
	_name_line_edit.text = voxel_set.next_material_id()
	_name_line_edit.placeholder_text = "New material id..."
	_name_window.popup_centered_clamped()
	_name_line_edit.grab_focus()
	_name_line_edit.select_all()

## Applies the rename or duplicate from the name window.
func _on_name_ok(_submitted_text := "") -> void:
	var new_material_id := _name_line_edit.text.strip_edges()
	
	match _name_mode:
		NameMode.RENAME:
			if new_material_id.is_empty():
				return
			if new_material_id == _name_old_material_id:
				_name_window.hide()
				return
			if voxel_set.material_id_exists(new_material_id):
				_name_line_edit.placeholder_text = "Already exists"
				_name_line_edit.text = ""
				_name_line_edit.grab_focus()
				return
			_do_rename(_name_old_material_id, new_material_id)
		NameMode.DUPLICATE:
			if new_material_id.is_empty():
				return
			if voxel_set.material_id_exists(new_material_id):
				_name_line_edit.placeholder_text = "Already exists"
				_name_line_edit.text = ""
				_name_line_edit.grab_focus()
				return
			_do_duplicate(new_material_id)
	
	_name_window.hide()
	_name_old_material_id = ""
	changed.emit()

## Cancels the name window.
func _on_name_cancel() -> void:
	_name_old_material_id = ""
	_name_window.hide()

## Renames a material and updates all voxel references.
func _do_rename(old_material_id: String, new_material_id: String) -> void:
	var material := voxel_set.get_material(old_material_id)
	if material == voxel_set.default_material:
		return
	var refs := _collect_material_refs(old_material_id)
	if _create_undo_action("Rename Material", voxel_set):
		if _undo_redo_manager:
			_undo_redo_manager.add_do_method(self, "_apply_rename", old_material_id, new_material_id, refs)
			_undo_redo_manager.add_undo_method(self, "_apply_rename", new_material_id, old_material_id, refs)
		else:
			_undo_redo.add_do_method(_apply_rename.bind(old_material_id, new_material_id, refs))
			_undo_redo.add_undo_method(_apply_rename.bind(new_material_id, old_material_id, refs))
		_commit_undo_action()
	else:
		_apply_rename(old_material_id, new_material_id, refs)
	_set_material_id(new_material_id)

## Re-points voxel base and face materials to the new ID.
func _apply_rename(from_material_id: String, to_material_id: String, refs: Dictionary) -> void:
	var material := voxel_set.get_material(from_material_id)
	if material and material != voxel_set.default_material:
		voxel_set.set_material(to_material_id, material)
		voxel_set.remove_material(from_material_id)
	for voxel_id in refs.base:
		var voxel := voxel_set.get_voxel(voxel_id)
		if voxel:
			voxel.set_base_material_id(to_material_id)
	for voxel_id in refs.faces:
		var voxel := voxel_set.get_voxel(voxel_id)
		if not voxel:
			continue
		for face in refs.faces[voxel_id]:
			voxel.set_face_material_id(face, to_material_id)

## Collects the voxels that reference the given material id, split into base
## references and per-face references.
func _collect_material_refs(material_id: String) -> Dictionary:
	var base_refs: Array[int] = []
	var face_refs: Dictionary = {}
	for voxel_id in voxel_set.get_voxel_ids():
		var voxel := voxel_set.get_voxel(voxel_id)
		if voxel.get_base_material_id() == material_id:
			base_refs.append(voxel_id)
		for face in Voxel.FACES:
			if voxel.get_face_material_id(face, false) == material_id:
				if not face_refs.has(voxel_id):
					face_refs[voxel_id] = []
				face_refs[voxel_id].append(face)
	return {"base": base_refs, "faces": face_refs}

## Creates a copy of the selected material.
func _do_duplicate(new_material_id: String) -> void:
	var source := voxel_set.get_material(material_id)
	var is_default: bool = material_id.is_empty() and picker_allow_default
	if source == voxel_set.default_material and not is_default:
		return
	var material_copy: BaseMaterial3D = source.duplicate()
	if _create_undo_action("Duplicate Material", voxel_set):
		if _undo_redo_manager:
			_undo_redo_manager.add_do_method(voxel_set, "set_material", new_material_id, material_copy)
			_undo_redo_manager.add_undo_method(voxel_set, "remove_material", new_material_id)
		else:
			_undo_redo.add_do_method(voxel_set.set_material.bind(new_material_id, material_copy))
			_undo_redo.add_undo_method(voxel_set.remove_material.bind(new_material_id))
		_commit_undo_action()
	else:
		voxel_set.set_material(new_material_id, material_copy)
	_set_material_id(new_material_id)
	material_id_changed.emit(new_material_id)

## Confirms and removes the selected material.
func _on_remove_pressed() -> void:
	if material_id.is_empty():
		return
	_pending_remove_material_id = material_id
	var usage := _count_material_usage(material_id)
	var message := "Remove material \"%s\"?" % material_id
	if usage.voxels > 0:
		message += "\n\nUsed by %d voxel(s) (base: %d, faces: %d).\nThey will be unset." % [usage.voxels, usage.base, usage.faces]
	else:
		message += "\n\nNot used by any voxels."
	_confirm_window.dialog_text = message
	_confirm_window.popup_centered_clamped()

## Removes the pending material and clears its references.
func _on_remove_confirmed() -> void:
	if _pending_remove_material_id.is_empty():
		return
	var removed := voxel_set.get_material(_pending_remove_material_id)
	var refs := _collect_material_refs(_pending_remove_material_id)
	if _create_undo_action("Remove Material", voxel_set):
		if _undo_redo_manager:
			_undo_redo_manager.add_do_method(voxel_set, "remove_material", _pending_remove_material_id)
			_undo_redo_manager.add_undo_method(voxel_set, "set_material", _pending_remove_material_id, removed)
			_undo_redo_manager.add_do_method(self, "_clear_material_refs", _pending_remove_material_id, refs)
			_undo_redo_manager.add_undo_method(self, "_restore_material_refs", _pending_remove_material_id, refs)
		else:
			_undo_redo.add_do_method(voxel_set.remove_material.bind(_pending_remove_material_id))
			_undo_redo.add_undo_method(voxel_set.set_material.bind(_pending_remove_material_id, removed))
			_undo_redo.add_do_method(_clear_material_refs.bind(_pending_remove_material_id, refs))
			_undo_redo.add_undo_method(_restore_material_refs.bind(_pending_remove_material_id, refs))
		_commit_undo_action()
	else:
		voxel_set.remove_material(_pending_remove_material_id)
		_clear_material_refs(_pending_remove_material_id, refs)
	_pending_remove_material_id = ""
	_set_material_id("")
	changed.emit()

## Sets base/face material references on all voxels that used the removed
## material to "unset".
func _clear_material_refs(removed_material_id: String, refs: Dictionary) -> void:
	for voxel_id in refs.base:
		var voxel := voxel_set.get_voxel(voxel_id)
		if voxel:
			voxel.set_base_material_id(Voxel.UNSET_MATERIAL_ID)
	for voxel_id in refs.faces:
		var voxel := voxel_set.get_voxel(voxel_id)
		if not voxel:
			continue
		for face in refs.faces[voxel_id]:
			voxel.set_face_material_id(face, Voxel.UNSET_MATERIAL_ID)

## Restores base/face material references back to the removed material id.
func _restore_material_refs(removed_material_id: String, refs: Dictionary) -> void:
	for voxel_id in refs.base:
		var voxel := voxel_set.get_voxel(voxel_id)
		if voxel:
			voxel.set_base_material_id(removed_material_id)
	for voxel_id in refs.faces:
		var voxel := voxel_set.get_voxel(voxel_id)
		if not voxel:
			continue
		for face in refs.faces[voxel_id]:
			voxel.set_face_material_id(face, removed_material_id)

## Opens the selected material in the editor inspector.
func _on_edit_in_inspector_pressed() -> void:
	if not Engine.is_editor_hint():
		return
	if not voxel_set:
		return
	# Empty id only represents the default material when the Default picker
	# option is enabled; otherwise there is nothing to edit.
	if material_id.is_empty() and not picker_allow_default:
		return
	var material := voxel_set.get_material(material_id)
	if material == voxel_set.default_material and not picker_allow_default:
		return
	edit_in_inspector_requested.emit(material_id)
	EditorInterface.edit_resource(material)

## Counts how many voxels reference the given material.
func _count_material_usage(material_id: String) -> Dictionary:
	var base_count := 0
	var face_refs := 0
	var voxels_used := 0
	for voxel_id in voxel_set.get_voxel_ids():
		var voxel := voxel_set.get_voxel(voxel_id)
		var uses := false
		if voxel.get_base_material_id() == material_id:
			base_count += 1
			uses = true
		for face in Voxel.FACES:
			if voxel.get_face_material_id(face, false) == material_id:
				face_refs += 1
				uses = true
		if uses:
			voxels_used += 1
	return {"base": base_count, "faces": face_refs, "voxels": voxels_used}

## Updates the editor when the picker selection changes.
func _on_picker_material_id_changed(new_material_id: String) -> void:
	_set_material_id(new_material_id)
	material_id_changed.emit(new_material_id)
