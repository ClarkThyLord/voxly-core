## Tag list editor.
##
## Shows tags as toggleable buttons with add, remove, rename, and selection
## actions, optional single-select mode, and a right-click context menu.
@tool
extends VBoxContainer

## Emitted when the tag list or selection changes.
signal changed

## Emitted when a tag is toggled on/off.
signal tag_toggled(tag: String, selected: bool)

## Title shown in the toolbar.
@export var title: String = "Tags":
	set = _set_title

## Maximum number of tags allowed (-1 = unlimited).
@export var tag_limit: int = -1

## If false, disables all editing (toolbar buttons disabled, toggling blocked).
## The toolbar remains visible so users can still see the buttons.
@export var disable_editing: bool = false:
	set = _set_disable_editing

## Show or hide the toolbar (Add, Remove, Select buttons).
@export var show_toolbar: bool = true:
	set = _set_show_toolbar

## Minimum tags that must remain selected.
@export var selection_min: int = 0

## Maximum tags that can be selected (-1 = unlimited).
@export var selection_max: int = -1

## Optional regex pattern for tag validation.
## The tag must match this pattern to be valid.
## Example: set to `^[a-zA-Z0-9_]{2,16}$` for 2-16 alphanumeric chars.
@export var tag_validator: String = ""

## The list of all available tags.
@export var tags: Array[String] = []:
	set = _set_tags,
	get = _get_tags

## Currently selected tags.
@export var selected_tags: Array[String] = []:
	set = _set_selected_tags,
	get = _get_selected_tags

## Toolbar with add/remove/select actions.
@onready var _toolbar: VBoxContainer = %ToolBarContainer
## Title label.
@onready var _title_label: Label = %TitleLabel
## Menu button for adding tags.
@onready var _add_button: MenuButton = %AddButton
## Menu button for removing tags.
@onready var _remove_button: MenuButton = %RemoveButton
## Menu button for selection actions.
@onready var _select_button: MenuButton = %SelectButton
## Container holding the tag toggle buttons.
@onready var _tags_container: HFlowContainer = %TagsContainer
## Popup for entering a new tag name.
@onready var _name_window: Window = %NameWindow
## Tag name input field.
@onready var _name_line_edit: LineEdit = %LineEdit
## Confirms the new tag name.
@onready var _name_ok: Button = %OkButton
## Cancels the tag name window.
@onready var _name_cancel: Button = %CancelButton
## Right-click context menu for tags.
@onready var _context_menu: PopupMenu = %ContextMenu

## Toggle buttons keyed by tag name.
var _tag_buttons: Dictionary[String, Button] = {}

## True while a rebuild is queued for the ready state.
var _pending_rebuild := false

## Tag being renamed, or empty when adding a new tag.
var _rename_old_tag: String = ""

## Actions available in the tag context menu.
enum ContextAction {
	TOGGLE_SELECTION,
	RENAME,
	REMOVE,
	SELECT_ALL,
	UNSELECT_ALL,
	REMOVE_SELECTED,
	REMOVE_ALL,
	ADD_TAG,
}

## Updates the tag list and rebuilds the buttons.
func _set_tags(new_tags: Array[String]) -> void:
	tags = new_tags.duplicate()
	for tag in selected_tags.duplicate():
		if tag not in tags:
			selected_tags.erase(tag)
	if is_inside_tree():
		_rebuild()
	else:
		_pending_rebuild = true

## Returns the current tag list.
func _get_tags() -> Array[String]:
	return tags

## Updates the selected tags, filtering invalid names.
func _set_selected_tags(new_selected: Array[String]) -> void:
	var valid: Array[String] = []
	for tag in new_selected:
		if tag in tags and tag not in valid:
			valid.append(tag)
	selected_tags = valid
	_update_button_states()
	changed.emit()

## Returns the currently selected tags.
func _get_selected_tags() -> Array[String]:
	return selected_tags

## Toggles whether tag editing is disabled.
func _set_disable_editing(value: bool) -> void:
	disable_editing = value
	_update_toolbar_disabled_state()

## Toggles toolbar visibility.
func _set_show_toolbar(value: bool) -> void:
	show_toolbar = value
	if _toolbar:
		_toolbar.visible = value

## Returns whether only one tag can be selected.
func _is_single_select() -> bool:
	return selection_max == 1

## Enables or disables toolbar buttons by state.
func _update_toolbar_disabled_state() -> void:
	if not _add_button:
		return
	_update_add_button()
	
	# Disabled if no tags and no selection, or editing is disabled.
	var has_sel := not selected_tags.is_empty()
	var has_tags := not tags.is_empty()
	_remove_button.disabled = (not has_sel and not has_tags) or disable_editing
	
	# Hidden in single-select mode, otherwise disabled if no tags.
	if _is_single_select():
		_select_button.hide()
	else:
		_select_button.show()
		_select_button.disabled = not has_tags

## Updates the title label text.
func _set_title(value: String) -> void:
	title = value
	if _title_label:
		_title_label.text = value

## Applies initial visibility and rebuilds the tags.
func _ready() -> void:
	_toolbar.visible = show_toolbar
	_title_label.text = title
	_update_toolbar_disabled_state()
	
	# Add button.
	_add_button.get_popup().id_pressed.connect(_on_toolbar_add_action)
	_add_button.get_popup().clear(true)
	_add_button.get_popup().add_item("Add New Tag", 0)
	
	# Remove button.
	_remove_button.get_popup().about_to_popup.connect(_update_remove_menu)
	_remove_button.get_popup().id_pressed.connect(_on_toolbar_remove_action)
	
	# Select button.
	_select_button.get_popup().about_to_popup.connect(_update_select_menu)
	_select_button.get_popup().id_pressed.connect(_on_toolbar_select_action)
	
	# Name window.
	_name_ok.pressed.connect(_on_name_ok)
	_name_cancel.pressed.connect(_on_name_cancel)
	_name_line_edit.text_submitted.connect(_on_name_ok)
	_name_window.close_requested.connect(_on_name_cancel)
	
	# Context menu.
	_context_menu.id_pressed.connect(_on_context_action)
	
	# Right-click on the tags container for the global context menu.
	_tags_container.gui_input.connect(_on_tags_container_gui_input)
	
	_name_window.hide()
	
	# Initialize the toolbar select menu with default items.
	_select_button.get_popup().clear(true)
	_select_button.get_popup().add_item("Select All", ContextAction.SELECT_ALL)
	_select_button.get_popup().add_item("Unselect All", ContextAction.UNSELECT_ALL)
	
	if _pending_rebuild:
		_rebuild()

## Returns the button for the given tag.
func get_tag_button(tag: String) -> Button:
	return _tag_buttons.get(tag)

## Rebuilds the tag buttons.
func refresh() -> void:
	_rebuild()

## Recreates all tag buttons from the tag list.
func _rebuild() -> void:
	if not _tags_container:
		_pending_rebuild = true
		return
	_pending_rebuild = false
	
	for button in _tag_buttons.values():
		if is_instance_valid(button):
			_tags_container.remove_child(button)
			button.queue_free()
	_tag_buttons.clear()
	
	for tag in tags:
		var button := Button.new()
		button.text = tag
		button.toggle_mode = not disable_editing
		button.button_pressed = tag in selected_tags
		button.pressed.connect(_on_tag_toggled.bind(tag, button))
		button.connect("gui_input", _on_tag_gui_input.bind(tag, button))
		_tags_container.add_child(button)
		_tag_buttons[tag] = button
	
	_update_toolbar_disabled_state()

## Syncs button toggle state with the selection.
func _update_button_states() -> void:
	for tag in _tag_buttons:
		var button = _tag_buttons[tag]
		if is_instance_valid(button):
			button.button_pressed = tag in selected_tags

## Updates the selection when a tag button toggles.
func _on_tag_toggled(tag: String, button: Button) -> void:
	if disable_editing:
		button.button_pressed = false
		return
	
	if button.button_pressed:
		if selection_max >= 0 and selected_tags.size() >= selection_max:
			button.button_pressed = false
			return
		if tag not in selected_tags:
			selected_tags.append(tag)
			tag_toggled.emit(tag, true)
	else:
		if selected_tags.size() <= selection_min:
			button.button_pressed = true
			return
		selected_tags.erase(tag)
		tag_toggled.emit(tag, false)
	
	changed.emit()
	_update_toolbar_disabled_state()

## Shows the context menu on tag right-click.
func _on_tag_gui_input(event: InputEvent, tag: String, button: Button) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_show_tag_context_menu(tag, button.get_screen_position() + event.position)
		accept_event()

## Shows the global context menu on empty-area right-click.
func _on_tags_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# Empty context in the container (no specific tag), show global actions.
		_show_global_context_menu(_tags_container.get_screen_position() + event.position)

## Builds the per-tag context menu.
func _show_tag_context_menu(tag: String, at_position: Vector2) -> void:
	_context_menu.clear()
	
	if tag in selected_tags:
		_context_menu.add_item("Unselect", ContextAction.TOGGLE_SELECTION)
	else:
		_context_menu.add_item("Select", ContextAction.TOGGLE_SELECTION)
	
	if not disable_editing:
		_context_menu.add_item("Rename Tag", ContextAction.RENAME)
		_context_menu.add_item("Remove Tag", ContextAction.REMOVE)
	
	if not disable_editing:
		_context_menu.add_separator()
		_context_menu.add_item("Add New Tag", ContextAction.ADD_TAG)
	
	if not _is_single_select():
		_context_menu.add_separator()
		if selected_tags.size() < tags.size():
			_context_menu.add_item("Select All", ContextAction.SELECT_ALL)
		if selected_tags.size() > 0:
			_context_menu.add_item("Unselect All", ContextAction.UNSELECT_ALL)
	
	if not disable_editing and selected_tags.size() > 0:
		_context_menu.add_item("Remove Selected (%d)" % selected_tags.size(), ContextAction.REMOVE_SELECTED)
	
	_context_menu.set_meta("context_tag", tag)
	_context_menu.reset_size()
	_context_menu.popup(Rect2i(at_position, _context_menu.get_contents_minimum_size()))

## Builds the empty-area context menu.
func _show_global_context_menu(at_position: Vector2) -> void:
	_context_menu.clear()
	
	if not disable_editing:
		_context_menu.add_item("Add New Tag", ContextAction.ADD_TAG)
	
	if not _is_single_select():
		if selected_tags.size() > 0:
			_context_menu.add_separator()
			_context_menu.add_item("Unselect All (%d)" % selected_tags.size(), ContextAction.UNSELECT_ALL)
		elif tags.size() > 0:
			_context_menu.add_separator()
			_context_menu.add_item("Select All (%d)" % tags.size(), ContextAction.SELECT_ALL)
	
	_context_menu.set_meta("context_tag", "")
	_context_menu.reset_size()
	_context_menu.popup(Rect2i(at_position, _context_menu.get_contents_minimum_size()))

## Handles context menu actions.
func _on_context_action(action_id: int) -> void:
	var tag: String = _context_menu.get_meta("context_tag", "")
	
	match action_id:
		ContextAction.TOGGLE_SELECTION:
			if tag in selected_tags:
				_deselect_tag(tag)
			else:
				_select_tag(tag)
		
		ContextAction.RENAME:
			_open_rename_window(tag)
		
		ContextAction.REMOVE:
			_remove_tag(tag)
		
		ContextAction.SELECT_ALL:
			for _tag in tags:
				_select_tag(_tag)
		
		ContextAction.UNSELECT_ALL:
			for _tag in selected_tags.duplicate():
				_deselect_tag(_tag)
		
		ContextAction.REMOVE_SELECTED:
			for _tag in selected_tags.duplicate():
				_remove_tag(_tag)
		
		ContextAction.ADD_TAG:
			_on_add_pressed()
	
	changed.emit()

## Selects a tag, enforcing the single-select rule.
func _select_tag(tag: String) -> void:
	if tag in selected_tags:
		return
	elif selection_max >= 0 and selected_tags.size() >= selection_max:
		return
	
	selected_tags.append(tag)
	var button = _tag_buttons.get(tag)
	if button:
		button.button_pressed = true
	
	tag_toggled.emit(tag, true)

## Deselects a tag.
func _deselect_tag(tag: String) -> void:
	if tag not in selected_tags:
		return
	elif selected_tags.size() <= selection_min:
		return
	
	selected_tags.erase(tag)
	var button = _tag_buttons.get(tag)
	if button:
		button.button_pressed = false
	tag_toggled.emit(tag, false)

## Removes a tag from the list.
func _remove_tag(tag: String) -> void:
	tags.erase(tag)
	selected_tags.erase(tag)
	var button = _tag_buttons.get(tag)
	
	if button:
		_tags_container.remove_child(button)
		button.queue_free()
		_tag_buttons.erase(tag)
	
	_update_toolbar_disabled_state()
	changed.emit()

## Opens the name window for a new tag.
func _on_toolbar_add_action(id: int) -> void:
	if id == 0:
		_on_add_pressed()

## Opens the add-tag name window.
func _on_add_pressed() -> void:
	_rename_old_tag = ""
	_name_window.title = "Add Tag"
	_name_ok.text = "Add"
	_name_line_edit.text = ""
	_name_line_edit.placeholder_text = "Tag name..."
	_name_window.popup_centered_clamped()
	_name_line_edit.grab_focus()

## Builds the remove-tag menu.
func _update_remove_menu() -> void:
	var popup := _remove_button.get_popup()
	popup.clear()
	var has_sel := not selected_tags.is_empty()
	var count := tags.size()
	_remove_button.disabled = (not has_sel and count == 0) or disable_editing
	if has_sel:
		popup.add_item("Remove Selected (%d)" % selected_tags.size(), ContextAction.REMOVE_SELECTED)
		popup.add_item("Remove All (%d)" % count, ContextAction.REMOVE_ALL)
	else:
		popup.add_item("Remove All (%d)" % count, ContextAction.REMOVE_ALL)

## Removes the selected tag.
func _on_toolbar_remove_action(id: int) -> void:
	match id:
		ContextAction.REMOVE_SELECTED:
			for tag in selected_tags.duplicate():
				_remove_tag(tag)
		ContextAction.REMOVE_ALL:
			for tag in tags.duplicate():
				_remove_tag(tag)

## Builds the select-tag menu.
func _update_select_menu() -> void:
	var popup := _select_button.get_popup()
	popup.clear()
	var count := tags.size()
	_select_button.disabled = count == 0
	popup.add_item("Select All (%d)" % count, ContextAction.SELECT_ALL)
	if not selected_tags.is_empty():
		popup.add_item("Unselect All (%d)" % selected_tags.size(), ContextAction.UNSELECT_ALL)

## Applies a select-menu action.
func _on_toolbar_select_action(id: int) -> void:
	match id:
		ContextAction.SELECT_ALL:
			for tag in tags:
				_select_tag(tag)
			changed.emit()
		ContextAction.UNSELECT_ALL:
			for tag in selected_tags.duplicate():
				_deselect_tag(tag)
			changed.emit()

## Opens the rename window for a tag.
func _open_rename_window(old_tag: String) -> void:
	_rename_old_tag = old_tag
	_name_window.title = "Rename Tag"
	_name_ok.text = "Rename"
	_name_line_edit.text = old_tag
	_name_line_edit.placeholder_text = "New tag name..."
	_name_window.popup_centered_clamped()
	_name_line_edit.grab_focus()
	_name_line_edit.select_all()

## Hides the add button when editing is disabled.
func _update_add_button() -> void:
	if not _add_button:
		return
	
	if tag_limit >= 0 and tags.size() >= tag_limit:
		_add_button.disabled = true
		_add_button.tooltip_text = "Maximum %d tags reached" % tag_limit
	else:
		_add_button.disabled = disable_editing
		_add_button.tooltip_text = ""

## Adds or renames a tag from the name window.
func _on_name_ok(_new_text := "") -> void:
	var tag_name := _name_line_edit.text.strip_edges()
	if tag_name.is_empty():
		return
	
	# Run the regex validator if set.
	if tag_validator:
		var regex := RegEx.new()
		regex.compile(tag_validator)
		if not regex.search(tag_name):
			_name_line_edit.placeholder_text = "Invalid tag format"
			_name_line_edit.text = ""
			_name_line_edit.grab_focus()
			return
	
	if _rename_old_tag != "":
		# Renaming an existing tag.
		if tag_name == _rename_old_tag:
			_name_window.hide()
			_rename_old_tag = ""
			return
		if tag_name in tags:
			_name_line_edit.placeholder_text = "Already exists"
			_name_line_edit.text = ""
			_name_line_edit.grab_focus()
			return
		var index := tags.find(_rename_old_tag)
		if index >= 0:
			tags[index] = tag_name
		if _rename_old_tag in selected_tags:
			selected_tags.erase(_rename_old_tag)
			selected_tags.append(tag_name)
		_rename_old_tag = ""
		_rebuild()
		_name_window.hide()
		changed.emit()
	else:
		# Adding a new tag.
		if tag_limit >= 0 and tags.size() >= tag_limit:
			_name_line_edit.placeholder_text = "Maximum %d tags reached" % tag_limit
			_name_line_edit.text = ""
			_name_line_edit.grab_focus()
			return
		
		if tag_name in tags:
			_name_line_edit.placeholder_text = "Already exists"
			_name_line_edit.text = ""
			_name_line_edit.grab_focus()
			return
		
		tags.append(tag_name)
		_rebuild()
		_select_tag(tag_name)
		_name_window.hide()
		changed.emit()

## Cancels the name window.
func _on_name_cancel() -> void:
	_rename_old_tag = ""
	_name_window.hide()
