@tool
extends Window

## Emitted when Ok is pressed with a valid selection.
signal confirmed

## Emitted when Cancel is pressed or the window is closed.
signal canceled

## Minimum number of textures that must be selected before Ok is allowed.
@export_range(0, 64, 1)
var min_selection: int = 1:
	set = set_min_selection

## Maximum number of textures that can be selected (-1 = unlimited, 0 = no selection).
@export_range(-1, 64, 1, "or_greater")
var max_selection: int = 1:
	set = set_max_selection

@onready
var _atlas_texture_picker = %AtlasTexturePicker

@onready
var _ok_button: Button = %AtlasTexturePickerWindowOkButton

@onready
var _cancel_button: Button = %AtlasTexturePickerWindowCancelButton

@onready
var _selection_warning_dialog: AcceptDialog = %AcceptDialog

func set_min_selection(value: int) -> void:
	if value == min_selection:
		return
	min_selection = value

func set_max_selection(value: int) -> void:
	if value == max_selection:
		return
	max_selection = value
	if _atlas_texture_picker:
		_atlas_texture_picker.selection_max = value

func _ready() -> void:
	_ok_button.pressed.connect(_on_ok)
	_cancel_button.pressed.connect(_on_cancel)
	close_requested.connect(_on_cancel)
	
	# Apply any exported values that were set before the picker was ready.
	_atlas_texture_picker.selection_max = max_selection

## Configure the window before showing it.
func setup(title: String, ok_text := "Ok", cancel_text := "Cancel") -> void:
	self.title = title
	_ok_button.text = ok_text
	_cancel_button.text = cancel_text

## Returns the underlying AtlasTexturePicker node for advanced customization.
func get_atlas_texture_picker():
	return _atlas_texture_picker

func _on_ok() -> void:
	if _atlas_texture_picker.get_selected_texture_xy().size() < min_selection:
		_show_min_selection_warning()
		return
	confirmed.emit()
	hide()

func _on_cancel() -> void:
	canceled.emit()
	hide()

func _show_min_selection_warning() -> void:
	_selection_warning_dialog.dialog_text = "Select at least %d texture(s) before confirming." % min_selection
	_selection_warning_dialog.popup_centered_clamped()
