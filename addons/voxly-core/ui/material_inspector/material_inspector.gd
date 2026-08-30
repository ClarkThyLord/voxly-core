## Material property inspector.
##
## Edits the selected material roughness, metallic, specular, emission, and
## refraction properties, with undo/redo support and edit/view-only modes.
@tool
extends BoxContainer

## Emitted when the user edits a material property.
signal changed

## Whether the material inspector is editable or view-only.
enum EditMode {
	VIEW_ONLY,
	EDITABLE,
}

## The VoxelSet whose material to inspect.
@export var voxel_set: VoxelSet = null:
	set = _set_voxel_set

## Currently selected material id. Empty string means nothing selected.
@export var material_id: String = "":
	set = _set_material_id

## Whether the controls are editable or read-only.
@export var edit_mode: EditMode = EditMode.EDITABLE:
	set = _set_edit_mode

## Roughness slider.
@onready var _roughness_slider: HSlider = %RoughnessHSlider
## Roughness numeric readout.
@onready var _roughness_value_spinbox: SpinBox = %RoughnessValueSpinBox
## Metallic slider.
@onready var _metallic_slider: HSlider = %MetallicHSlider
## Metallic numeric readout.
@onready var _metallic_value_spinbox: SpinBox = %MetallicValueSpinBox
## Specular slider.
@onready var _specular_slider: HSlider = %SpecularHSlider
## Specular numeric readout.
@onready var _specular_value_spinbox: SpinBox = %SpecularValueSpinBox
## Toggles emission on the material.
@onready var _emission_enabled_check: CheckBox = %EmissionEnabledCheckBox
## Emission energy slider.
@onready var _emission_energy_slider: HSlider = %EmissionEnergyMultiplierHSlider
## Emission energy numeric readout.
@onready var _emission_energy_value_spinbox: SpinBox = %EmissionEnergyMultiplierValueSpinBox
## Emission color picker.
@onready var _emission_color_picker: ColorPickerButton = %EmissionColorPickerButton
## Toggles refraction on the material.
@onready var _refraction_enabled_check: CheckBox = %RefractionEnabledCheckBox
## Refraction scale slider.
@onready var _refraction_scale_slider: HSlider = %RefractionScaleHSlider
## Refraction scale numeric readout.
@onready var _refraction_scale_value_spinbox: SpinBox = %RefractionScaleValueSpinBox
## Shown when refraction requires transparency.
@onready var _refraction_notice_label: Label = %RefractionNoticeLabel

## The material currently being inspected.
var _material: BaseMaterial3D = null
## True while a refresh is queued for the ready state.
var _pending_refresh := false
## True while controls are being synced to the material.
var _syncing := false

## Plain UndoRedo stack used when not in the editor.
var _undo_redo: UndoRedo = null
## Editor undo/redo manager used inside the editor.
var _undo_redo_manager: EditorUndoRedoManager = null

## Updates the voxel set and refreshes the controls.
func _set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if voxel_set == new_voxel_set:
		return
	if voxel_set and voxel_set.materials_changed.is_connected(_refresh):
		voxel_set.materials_changed.disconnect(_refresh)
	voxel_set = new_voxel_set
	# Empty id resolves to the VoxelSet's default_material via get_material().
	_material = voxel_set.get_material(material_id) if voxel_set else null
	if voxel_set and not voxel_set.materials_changed.is_connected(_refresh):
		voxel_set.materials_changed.connect(_refresh)
	if is_inside_tree():
		_refresh()
	else:
		_pending_refresh = true

## Updates the material being inspected.
func _set_material_id(new_material_id: String) -> void:
	if new_material_id == material_id:
		return
	material_id = new_material_id
	# Empty id resolves to the VoxelSet's default_material via get_material().
	_material = voxel_set.get_material(material_id) if voxel_set else null
	if is_inside_tree():
		_refresh()
	else:
		_pending_refresh = true

## Updates the edit/read-only mode.
func _set_edit_mode(new_edit_mode: EditMode) -> void:
	if new_edit_mode == edit_mode:
		return
	edit_mode = new_edit_mode
	_update_controls_enabled()

## Subscribes to undo/redo version changes for refresh.
func _connect_undo_version_changed() -> void:
	if _undo_redo_manager and not _undo_redo_manager.version_changed.is_connected(_refresh):
		_undo_redo_manager.version_changed.connect(_refresh)
	if _undo_redo and not _undo_redo.version_changed.is_connected(_refresh):
		_undo_redo.version_changed.connect(_refresh)

## Sets a plain UndoRedo for standalone usage.
func set_undo_redo(undo_redo: UndoRedo) -> void:
	_undo_redo = undo_redo
	_connect_undo_version_changed()

## Sets an EditorUndoRedoManager for editor plugin integration.
func set_undo_redo_manager(manager: EditorUndoRedoManager) -> void:
	_undo_redo_manager = manager
	_connect_undo_version_changed()

## Connects the control signals and subscribes to undo changes.
func _ready() -> void:
	_connect_undo_version_changed()
	_roughness_slider.value_changed.connect(_on_slider_changed.bind("roughness", _roughness_value_spinbox))
	_roughness_value_spinbox.value_changed.connect(_on_spinbox_changed.bind("roughness", _roughness_slider))
	
	_metallic_slider.value_changed.connect(_on_slider_changed.bind("metallic", _metallic_value_spinbox))
	_metallic_value_spinbox.value_changed.connect(_on_spinbox_changed.bind("metallic", _metallic_slider))
	
	_specular_slider.value_changed.connect(_on_slider_changed.bind("metallic_specular", _specular_value_spinbox))
	_specular_value_spinbox.value_changed.connect(_on_spinbox_changed.bind("metallic_specular", _specular_slider))
	
	_emission_enabled_check.toggled.connect(_on_toggled.bind("emission_enabled"))
	
	_emission_energy_slider.value_changed.connect(_on_slider_changed.bind("emission_energy_multiplier", _emission_energy_value_spinbox))
	_emission_energy_value_spinbox.value_changed.connect(_on_spinbox_changed.bind("emission_energy_multiplier", _emission_energy_slider))
	
	_emission_color_picker.color_changed.connect(_on_color_changed)
	
	_refraction_enabled_check.toggled.connect(_on_toggled.bind("refraction_enabled"))
	
	_refraction_scale_slider.value_changed.connect(_on_slider_changed.bind("refraction_scale", _refraction_scale_value_spinbox))
	_refraction_scale_value_spinbox.value_changed.connect(_on_spinbox_changed.bind("refraction_scale", _refraction_scale_slider))
	
	if _pending_refresh:
		_refresh()

## Re-reads the material properties and syncs all controls.
func refresh() -> void:
	_refresh()

## Syncs all controls with the current material.
func _refresh() -> void:
	if not _roughness_slider:
		_pending_refresh = true
		return
	_pending_refresh = false
	
	_update_controls_enabled()
	
	if not _material:
		return
	
	_syncing = true
	
	_roughness_slider.value = _material.roughness
	_roughness_value_spinbox.value = _material.roughness
	_metallic_slider.value = _material.metallic
	_metallic_value_spinbox.value = _material.metallic
	_specular_slider.value = _material.metallic_specular
	_specular_value_spinbox.value = _material.metallic_specular
	_emission_enabled_check.button_pressed = _material.emission_enabled
	_emission_energy_slider.value = _material.emission_energy_multiplier
	_emission_energy_value_spinbox.value = _material.emission_energy_multiplier
	_emission_color_picker.get_picker().set_pick_color(_material.emission)
	_emission_color_picker.color = _material.emission
	_refraction_enabled_check.button_pressed = _material.refraction_enabled
	_refraction_scale_slider.value = _material.refraction_scale
	_refraction_scale_value_spinbox.value = _material.refraction_scale
	_refraction_notice_label.visible = _material.refraction_enabled
	
	_syncing = false

## Enables or disables editing controls by mode.
func _update_controls_enabled() -> void:
	var editable := edit_mode == EditMode.EDITABLE and _material != null
	_roughness_slider.editable = editable
	_roughness_value_spinbox.editable = editable
	_metallic_slider.editable = editable
	_metallic_value_spinbox.editable = editable
	_specular_slider.editable = editable
	_specular_value_spinbox.editable = editable
	_emission_enabled_check.disabled = not editable
	_emission_energy_slider.editable = editable
	_emission_energy_value_spinbox.editable = editable
	_emission_color_picker.disabled = not editable
	_refraction_enabled_check.disabled = not editable
	_refraction_scale_slider.editable = editable
	_refraction_scale_value_spinbox.editable = editable

## Applies a slider change to the material property.
func _on_slider_changed(value: float, property: String, spinbox: SpinBox) -> void:
	if _syncing or not _material or edit_mode != EditMode.EDITABLE:
		return
	_syncing = true
	spinbox.value = value
	_syncing = false
	_set_property_undo_step(property, value)
	changed.emit()

## Applies a spinbox change to the material property.
func _on_spinbox_changed(value: float, property: String, slider: HSlider) -> void:
	if _syncing or not _material or edit_mode != EditMode.EDITABLE:
		return
	_syncing = true
	slider.value = value
	_syncing = false
	_set_property_undo_step(property, value)
	changed.emit()

## Applies a checkbox toggle to the material property.
func _on_toggled(pressed: bool, property: String) -> void:
	if _syncing or not _material or edit_mode != EditMode.EDITABLE:
		return
	_set_property_undo_step(property, pressed)
	if property == "refraction_enabled":
		_refraction_notice_label.visible = pressed
	changed.emit()

## Applies an emission color change to the material.
func _on_color_changed(color: Color) -> void:
	if _syncing or not _material or edit_mode != EditMode.EDITABLE:
		return
	_set_property_undo_step("emission", color)
	changed.emit()

## Records and applies a property change through undo/redo.
func _set_property_undo_step(property: String, new_value: Variant) -> void:
	var old_value := _material.get(property)
	if old_value == new_value:
		return
	if _undo_redo_manager:
		_undo_redo_manager.create_action("Edit Material %s" % property, UndoRedo.MERGE_ENDS, _material)
		_undo_redo_manager.add_do_property(_material, property, new_value)
		_undo_redo_manager.add_undo_property(_material, property, old_value)
		_undo_redo_manager.commit_action()
	elif _undo_redo:
		_undo_redo.create_action("Edit Material %s" % property, UndoRedo.MERGE_ENDS)
		_undo_redo.add_do_property(_material, property, new_value)
		_undo_redo.add_undo_property(_material, property, old_value)
		_undo_redo.commit_action()
	else:
		_material.set(property, new_value)
