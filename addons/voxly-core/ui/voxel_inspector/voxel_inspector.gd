## Inspector for a single voxel entry in a VoxelSet.
##
## Edits the voxel's ID, name, and tags with per-field visibility modes
## (editable/read-only/hidden) and a raw info panel, emitting change signals
## for the owning VoxelSet editor.
@tool
extends VBoxContainer

## Emitted when any voxel data changes.
signal changed

## Emitted when the voxel ID changes.
signal changed_id(old_id, new_id)

## Emitted when the voxel name changes.
signal changed_name(old_name, new_name)

## Emitted when the voxel tags change.
signal changed_tags(old_tags, new_tags)

## Controls how each field is displayed.
enum FieldMode {
	EDITABLE,   # Fully editable.
	READ_ONLY,  # Visible but not editable.
	HIDDEN,     # Not visible.
}

## The voxel ID being inspected.
@export_range(-1, 100, 1, "or_greater")
var voxel_id: int = 0:
	set = _set_voxel_id

## The VoxelSet the inspected voxel belongs to.
@export var voxel_set: VoxelSet = null:
	set = _set_voxel_set

## ID field visibility and editability.
@export var id_mode: FieldMode = FieldMode.EDITABLE:
	set = _set_id_mode

## Name field visibility and editability.
@export var name_mode: FieldMode = FieldMode.EDITABLE:
	set = _set_name_mode

## Tags editor visibility and editability.
@export var tags_mode: FieldMode = FieldMode.EDITABLE:
	set = _set_tags_mode

## Show/hide the raw info panel.
@export var show_info: bool = true:
	set = _set_show_info

## Container for the ID editing row.
@onready var _id_container: HBoxContainer = %IDContainer
## ID text input.
@onready var _id_line_edit: LineEdit = %IDLineEdit
## Confirms an ID change.
@onready var _id_save_button: Button = %IDSaveButton
## Cancels an ID change.
@onready var _id_cancel_button: Button = %IDCancelButton
## Container for the name editing row.
@onready var _name_container: HBoxContainer = %NameContainer
## Name text input.
@onready var _name_line_edit: LineEdit = %NameLineEdit
## Confirms a name change.
@onready var _name_save_button: Button = %NameSaveButton
## Cancels a name change.
@onready var _name_cancel_button: Button = %NameCancelButton
## Embedded tag editor.
@onready var _tag_editor := %TagEditor
## Scroll container for the raw info panel.
@onready var _info_container: ScrollContainer = %InfoContainer
## Label showing the voxel raw data.
@onready var _info_label: Label = %InfoLabel

## The voxel resource currently inspected.
var _voxel: Voxel = null
## True while an update is queued for the ready state.
var _pending_update := false
## Dialog shown when an ID or name is taken.
var _accept_dialog: AcceptDialog = null
# Which field to re-focus after "Ok".
## Field to re-focus after the accept dialog closes.
var _pending_field: LineEdit = null
# Whether we're in the middle of a confirm dialog (ignores focus_exited).
## True while an ID change is awaiting confirmation.
var _confirming_id := false
## True while a name change is awaiting confirmation.
var _confirming_name := false
## True while tag changes are being applied, to avoid echo.
var _syncing_tags := false

## Plain UndoRedo stack used when not in the editor.
var _undo_redo: UndoRedo = null
## Editor undo/redo manager used inside the editor.
var _undo_redo_manager: EditorUndoRedoManager = null

## Subscribes to undo/redo version changes for refresh.
func _connect_undo_version_changed() -> void:
	if _undo_redo_manager and not _undo_redo_manager.version_changed.is_connected(_update):
		_undo_redo_manager.version_changed.connect(_update)
	if _undo_redo and not _undo_redo.version_changed.is_connected(_update):
		_undo_redo.version_changed.connect(_update)

## Sets a plain UndoRedo for standalone usage.
func set_undo_redo(undo_redo: UndoRedo) -> void:
	_undo_redo = undo_redo
	_connect_undo_version_changed()

## Sets an EditorUndoRedoManager for editor plugin integration.
func set_undo_redo_manager(manager: EditorUndoRedoManager) -> void:
	_undo_redo_manager = manager
	_connect_undo_version_changed()

## Updates the inspected voxel ID.
func _set_voxel_id(new_voxel_id: int) -> void:
	if new_voxel_id == voxel_id:
		return
	
	if _voxel and _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.disconnect(_on_voxel_changed)
	
	voxel_id = new_voxel_id
	_voxel = voxel_set.get_voxel(voxel_id) if voxel_set else null
	
	if _voxel and not _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.connect(_on_voxel_changed)
	
	if not is_inside_tree():
		_pending_update = true
	else:
		_update()

## Updates the voxel set and refreshes.
func _set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if new_voxel_set == voxel_set:
		return
	
	if _voxel and _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.disconnect(_on_voxel_changed)
	
	voxel_set = new_voxel_set
	_voxel = voxel_set.get_voxel(voxel_id) if voxel_set else null
	
	if _voxel and not _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.connect(_on_voxel_changed)
	
	if not is_inside_tree():
		_pending_update = true
	else:
		_update()

## Applies the ID field mode.
func _set_id_mode(value: FieldMode) -> void:
	if value == id_mode:
		return
	id_mode = value
	_apply_field_modes()

## Applies the name field mode.
func _set_name_mode(value: FieldMode) -> void:
	if value == name_mode:
		return
	name_mode = value
	_apply_field_modes()

## Applies the tags field mode.
func _set_tags_mode(value: FieldMode) -> void:
	if value == tags_mode:
		return
	tags_mode = value
	_apply_field_modes()

## Toggles the raw info panel.
func _set_show_info(value: bool) -> void:
	if value == show_info:
		return
	show_info = value
	if _info_container:
		_info_container.visible = show_info

## Connects the field signals and applies modes.
func _ready() -> void:
	# ID field.
	_id_line_edit.text_submitted.connect(_on_id_submitted)
	_id_line_edit.text_changed.connect(_on_id_text_changed)
	_id_save_button.pressed.connect(_on_id_save_pressed)
	_id_cancel_button.pressed.connect(_on_id_cancel_pressed)
	
	# Name field.
	_name_line_edit.text_submitted.connect(_on_name_submitted)
	_name_line_edit.text_changed.connect(_on_name_text_changed)
	_name_save_button.pressed.connect(_on_name_save_pressed)
	_name_cancel_button.pressed.connect(_on_name_cancel_pressed)
	
	# Tag editor.
	_tag_editor.changed.connect(_on_tag_editor_changed)
	
	if _pending_update:
		_update()
	else:
		_apply_field_modes()

## Hides the ID save/cancel buttons.
func _hide_id_buttons() -> void:
	_id_save_button.hide()
	_id_cancel_button.hide()

## Hides the name save/cancel buttons.
func _hide_name_buttons() -> void:
	_name_save_button.hide()
	_name_cancel_button.hide()

## Shows the ID save/cancel buttons on edit.
func _on_id_text_changed(new_text: String) -> void:
	if not _voxel or not new_text.is_valid_int():
		_id_save_button.hide()
		_id_cancel_button.hide()
		return
	var new_id := new_text.to_int()
	if new_id == voxel_id:
		_id_save_button.hide()
		_id_cancel_button.hide()
	else:
		_id_save_button.show()
		_id_cancel_button.show()

## Shows the name save/cancel buttons on edit.
func _on_name_text_changed(new_text: String) -> void:
	if not _voxel or new_text == _voxel.name:
		_name_save_button.hide()
		_name_cancel_button.hide()
	else:
		_name_save_button.show()
		_name_cancel_button.show()

## Commits the edited ID.
func _on_id_save_pressed() -> void:
	_hide_id_buttons()
	_try_change_id(_id_line_edit.text)

## Reverts the edited ID.
func _on_id_cancel_pressed() -> void:
	_hide_id_buttons()
	_revert_id()

## Commits the edited name.
func _on_name_save_pressed() -> void:
	_hide_name_buttons()
	_try_change_name(_name_line_edit.text)

## Reverts the edited name.
func _on_name_cancel_pressed() -> void:
	_hide_name_buttons()
	_revert_name()

## Points the inspector at a voxel in the given set.
func set_voxel(voxel_set: VoxelSet, voxel_id: int) -> void:
	self.voxel_set = voxel_set
	self.voxel_id = voxel_id

## Refreshes the displayed voxel data.
func refresh() -> void:
	_update()

## Applies the field visibility and editability modes.
func _apply_field_modes() -> void:
	if not _id_line_edit:
		_pending_update = true
		return
	_apply_field_mode(_id_line_edit, id_mode)
	_apply_field_mode(_name_line_edit, name_mode)
	if _tag_editor:
		_tag_editor.disable_editing = tags_mode != FieldMode.EDITABLE
		_tag_editor.visible = tags_mode != FieldMode.HIDDEN
	if _info_container:
		_info_container.visible = show_info

## Toggles a field's visibility and editability.
func _apply_field_mode(line_edit: LineEdit, mode: FieldMode) -> void:
	if not line_edit:
		return
	var visible := mode != FieldMode.HIDDEN
	line_edit.editable = mode == FieldMode.EDITABLE
	var parent := line_edit.get_parent()
	if parent:
		parent.visible = visible

## Refreshes when the voxel data changes.
func _on_voxel_changed() -> void:
	_update()

## Repopulates all fields from the current voxel.
func _update() -> void:
	if not _id_line_edit:
		_pending_update = true
		return
	_pending_update = false
	
	# Apply field modes first.
	_apply_field_modes()
	
	# Prevent tag_editor.changed from re-triggering _update.
	_syncing_tags = true
	
	if not voxel_set or not _voxel:
		_id_line_edit.text = ""
		_name_line_edit.text = ""
		_tag_editor.tags.clear()
		_info_label.text = ""
		_syncing_tags = false
		return
	
	_id_line_edit.text = str(voxel_id)
	_name_line_edit.text = _voxel.name
	
	# Hide save/cancel buttons on any inspector update.
	_hide_id_buttons()
	_hide_name_buttons()
	
	# Sync tags to the tag editor.
	_tag_editor.selected_tags = _voxel.tags.duplicate()
	_tag_editor.tags = _voxel.tags.duplicate()
	
	_info_label.text = _format_raw_data()
	
	_syncing_tags = false

## Formats the voxel raw data as readable text.
func _format_raw_data() -> String:
	if not _voxel:
		return ""
	var parts: PackedStringArray = []
	var base_color := "unset"
	var base_texture := "unset"
	var base_material := "unset"
	if _voxel.has_base_color():
		base_color = _voxel.base_color.to_html()
	if _voxel.has_base_texture_cell():
		base_texture = str(_voxel.base_texture_cell)
	if _voxel.has_base_material_id():
		base_material = _voxel.base_material_id
	parts.append("Color: %s" % base_color)
	parts.append("Texture XY: %s" % base_texture)
	parts.append("Material ID: %s" % base_material)
	for face in Voxel.FACES:
		var face_color := _voxel.get_face_color(face, false)
		var face_texture := _voxel.get_face_texture_cell(face, false)
		var face_material := _voxel.get_face_material_id(face, false)
		var face_name := Voxel.FACE_NAMES[face]
		parts.append("%s: Color=%s Tex=%s Mat=%s" % [
			face_name,
			face_color.to_html() if face_color.a > 0 else "unset",
			str(face_texture) if face_texture != -Vector2i.ONE else "unset",
			face_material if not face_material.is_empty() else "unset",
		])
	return "\n".join(parts)

## Attempts to change the voxel ID from the input.
func _on_id_submitted(new_text: String) -> void:
	_try_change_id(new_text)

## Validates and applies an ID change.
func _try_change_id(new_id_string: String) -> void:
	if not _voxel or not new_id_string.is_valid_int():
		_id_line_edit.text = str(voxel_id)
		return
	
	var new_id := new_id_string.to_int()
	if new_id == voxel_id:
		_id_line_edit.text = str(voxel_id)
		return
	
	if voxel_set and voxel_set.voxel_id_exists(new_id):
		# Show a dialog: the ID is already taken, offer Ok or Cancel.
		_confirming_id = true
		_pending_field = _id_line_edit
		_show_taken_dialog(
			"ID %d is already taken." % new_id,
			_revert_id
		)
	else:
		_do_change_id(new_id)

## Changes the voxel ID through undo/redo.
func _do_change_id(new_id: int) -> void:
	if not voxel_set or not _voxel:
		return
	
	var old_voxel = _voxel
	var old_id = voxel_id
	
	# Create the undo/redo action.
	var has_undo := false
	if _undo_redo_manager:
		_undo_redo_manager.create_action("Change Voxel ID", UndoRedo.MERGE_DISABLE, voxel_set)
		_undo_redo_manager.add_do_method(voxel_set, "set_voxel", new_id, old_voxel)
		_undo_redo_manager.add_do_method(voxel_set, "remove_voxel", old_id)
		_undo_redo_manager.add_undo_method(voxel_set, "set_voxel", old_id, old_voxel)
		_undo_redo_manager.add_undo_method(voxel_set, "remove_voxel", new_id)
		has_undo = true
	elif _undo_redo:
		_undo_redo.create_action("Change Voxel ID")
		_undo_redo.add_do_method(voxel_set.set_voxel.bind(new_id, old_voxel))
		_undo_redo.add_do_method(voxel_set.remove_voxel.bind(old_id))
		_undo_redo.add_undo_method(voxel_set.set_voxel.bind(old_id, old_voxel))
		_undo_redo.add_undo_method(voxel_set.remove_voxel.bind(new_id))
		has_undo = true
	
	voxel_set.set_voxel(new_id, old_voxel)
	voxel_set.remove_voxel(old_id)
	voxel_id = new_id
	_voxel = old_voxel
	_id_line_edit.text = str(new_id)
	_hide_id_buttons()
	
	if has_undo:
		if _undo_redo_manager:
			_undo_redo_manager.commit_action()
		else:
			_undo_redo.commit_action()
	
	changed_id.emit(old_id, new_id)
	changed.emit()

## Restores the previous ID after a rejected change.
func _revert_id() -> void:
	_confirming_id = false
	_pending_field = null
	_id_line_edit.text = str(voxel_id)
	_hide_id_buttons()

## Attempts to change the voxel name from the input.
func _on_name_submitted(new_text: String) -> void:
	_try_change_name(new_text)

## Validates and applies a name change.
func _try_change_name(new_name: String) -> void:
	if not _voxel or new_name == _voxel.name:
		_revert_name()
		return
	
	var trimmed := new_name.strip_edges()
	if trimmed.is_empty():
		_revert_name()
		return
	
	if voxel_set:
		var existing_id := voxel_set.find_voxel_by_name(trimmed)
		if existing_id >= 0 and existing_id != voxel_id:
			_confirming_name = true
			_pending_field = _name_line_edit
			_show_taken_dialog(
				"Name '%s' is already used by voxel ID %d." % [trimmed, existing_id],
				_revert_name
			)
			return
	
	_do_change_name(trimmed)

## Changes the voxel name through undo/redo.
func _do_change_name(new_name: String) -> void:
	if not _voxel:
		return
	var old_name = _voxel.name
	
	if _undo_redo_manager:
		_undo_redo_manager.create_action("Change Voxel Name", UndoRedo.MERGE_DISABLE, _voxel)
		_undo_redo_manager.add_do_property(_voxel, "name", new_name)
		_undo_redo_manager.add_undo_property(_voxel, "name", old_name)
		_undo_redo_manager.commit_action()
	elif _undo_redo:
		_undo_redo.create_action("Change Voxel Name")
		_undo_redo.add_do_property(_voxel, "name", new_name)
		_undo_redo.add_undo_property(_voxel, "name", old_name)
		_undo_redo.commit_action()
	
	_voxel.name = new_name
	_name_line_edit.text = new_name
	_hide_name_buttons()
	changed_name.emit(old_name, new_name)
	changed.emit()

## Restores the previous name after a rejected change.
func _revert_name() -> void:
	_confirming_name = false
	_pending_field = null
	if _voxel:
		_name_line_edit.text = _voxel.name
	_hide_name_buttons()

## Shows the taken-ID/name dialog with a close callback.
func _show_taken_dialog(message: String, on_close: Callable) -> void:
	if not _accept_dialog:
		# Create a reusable confirmation dialog.
		_accept_dialog = AcceptDialog.new()
		_accept_dialog.gui_embed_subwindows = true
		_accept_dialog.title = "Invalid"
		
		_accept_dialog.confirmed.connect(_on_dialog_close)
		_accept_dialog.close_requested.connect(_on_dialog_close)
		
		add_child(_accept_dialog)
	
	_accept_dialog.dialog_text = message
	_on_dialog_close_callback = on_close
	
	_accept_dialog.popup_centered_clamped()

## Callback invoked when the accept dialog closes.
var _on_dialog_close_callback: Callable

## Hides the dialog and invokes the close callback.
func _on_dialog_close() -> void:
	_accept_dialog.hide()
	
	if _on_dialog_close_callback:
		_on_dialog_close_callback.call()
	_confirming_id = false
	_confirming_name = false
	_pending_field = null

## Applies tag changes back to the voxel.
func _on_tag_editor_changed() -> void:
	if _syncing_tags or not _voxel:
		return
	
	# Sync the tag_editor's tags back to the voxel.
	var old_tags = _voxel.tags
	var new_tags = _tag_editor.tags.duplicate()
	
	if _undo_redo_manager:
		_undo_redo_manager.create_action("Change Voxel Tags", UndoRedo.MERGE_DISABLE, _voxel)
		_undo_redo_manager.add_do_property(_voxel, "tags", new_tags)
		_undo_redo_manager.add_undo_property(_voxel, "tags", old_tags)
		_undo_redo_manager.commit_action()
	elif _undo_redo:
		_undo_redo.create_action("Change Voxel Tags")
		_undo_redo.add_do_property(_voxel, "tags", new_tags)
		_undo_redo.add_undo_property(_voxel, "tags", old_tags)
		_undo_redo.commit_action()
	
	_voxel.tags = new_tags
	changed_tags.emit(old_tags, new_tags)
	changed.emit()
