@tool
extends Window

## Emitted when the user clicks Ok with the selected color.
signal color_confirmed(color: Color)

## Emitted when the user clicks Cancel or closes the window.
signal color_canceled

@export
var color: Color = Color.WHITE:
	set = set_color,
	get = get_color

## Whether the alpha channel can be edited.
@export
var edit_alpha: bool = true:
	set = set_edit_alpha,
	get = get_edit_alpha

@export
var color_mode: ColorPicker.ColorModeType = ColorPicker.ColorModeType.MODE_RGB:
	set = set_color_mode,
	get = get_color_mode

@export
var picker_shape: ColorPicker.PickerShapeType = ColorPicker.PickerShapeType.SHAPE_HSV_RECTANGLE:
	set = set_picker_shape,
	get = get_picker_shape

## Whether the user can add swatches to the picker.
@export
var can_add_swatches: bool = true:
	set = set_can_add_swatches,
	get = get_can_add_swatches

## Whether the ColorPicker node has been synced with the exported properties.
## While false (before _ready), the getters return the stored backing values so
## values set before the picker exists are not lost.
var _picker_synced := false

@onready
var _color_picker: ColorPicker = %ColorPicker

@onready
var _ok_button: Button = %Ok

@onready
var _cancel_button: Button = %Cancel

func set_color(value: Color) -> void:
	if value == (_color_picker.color if _picker_synced else color):
		return
	color = value
	if _color_picker:
		_color_picker.color = value

func get_color() -> Color:
	return _color_picker.color if _picker_synced else color

func set_edit_alpha(value: bool) -> void:
	if value == (_color_picker.edit_alpha if _picker_synced else edit_alpha):
		return
	edit_alpha = value
	if _color_picker:
		_color_picker.edit_alpha = value

func get_edit_alpha() -> bool:
	return _color_picker.edit_alpha if _picker_synced else edit_alpha

func set_color_mode(value: ColorPicker.ColorModeType) -> void:
	if value == (_color_picker.color_mode if _picker_synced else color_mode):
		return
	color_mode = value
	if _color_picker:
		_color_picker.color_mode = value

func get_color_mode() -> ColorPicker.ColorModeType:
	return _color_picker.color_mode if _picker_synced else color_mode

func set_picker_shape(value: ColorPicker.PickerShapeType) -> void:
	if value == (_color_picker.picker_shape if _picker_synced else picker_shape):
		return
	picker_shape = value
	if _color_picker:
		_color_picker.picker_shape = value

func get_picker_shape() -> ColorPicker.PickerShapeType:
	return _color_picker.picker_shape if _picker_synced else picker_shape

func set_can_add_swatches(value: bool) -> void:
	if value == (_color_picker.can_add_swatches if _picker_synced else can_add_swatches):
		return
	can_add_swatches = value
	if _color_picker:
		_color_picker.can_add_swatches = value

func get_can_add_swatches() -> bool:
	return _color_picker.can_add_swatches if _picker_synced else can_add_swatches

func _ready() -> void:
	_ok_button.pressed.connect(_on_ok)
	_cancel_button.pressed.connect(_on_cancel)
	close_requested.connect(_on_cancel)
	
	# Apply any exported values that were set before the ColorPicker node was ready.
	_color_picker.color = color
	_color_picker.edit_alpha = edit_alpha
	_color_picker.color_mode = color_mode
	_color_picker.picker_shape = picker_shape
	_color_picker.can_add_swatches = can_add_swatches
	_picker_synced = true

## Configure the window before showing it.
func setup(title: String, initial_color: Color, ok_text := "Ok", cancel_text := "Cancel") -> void:
	self.title = title
	color = initial_color
	_ok_button.text = ok_text
	_cancel_button.text = cancel_text

## Returns the underlying ColorPicker node for advanced customization.
func get_color_picker() -> ColorPicker:
	return _color_picker

func _on_ok() -> void:
	color_confirmed.emit(_color_picker.color)
	hide()

func _on_cancel() -> void:
	color_canceled.emit()
	hide()
