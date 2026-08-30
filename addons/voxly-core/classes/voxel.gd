## A resource that defines the visual properties of a single voxel type.
##
## Stores the base color, texture atlas cell, and material reference, plus
## optional per-face overrides for each of those properties. Voxels are stored
## inside a [VoxelSet] palette, keyed by a voxel ID.
@tool
@icon("res://addons/voxly-core/assets/icons/voxel.svg")
class_name Voxel
extends Resource

## Emitted when the voxel's name is changed.
signal name_changed

## Emitted when the voxel's tags are changed.
signal tags_changed

## Emitted when the voxel's base color is changed.
signal base_color_changed

## Emitted when a specific face color is changed.
signal face_color_changed(face: Vector3i)

## Emitted when the voxel's base texture cell is changed.
signal base_texture_cell_changed

## Emitted when a specific face texture cell is changed.
signal face_texture_cell_changed(face: Vector3i)

## Emitted when the voxel's base material ID is changed.
signal base_material_id_changed

## Emitted when a specific face material ID is changed.
signal face_material_id_changed(face: Vector3i)

## The upward-facing normal direction.
const FACE_TOP := Vector3i.UP
## The downward-facing normal direction.
const FACE_BOTTOM := Vector3i.DOWN
## The forward-facing normal direction.
const FACE_FRONT := Vector3i.FORWARD
## The backward-facing normal direction.
const FACE_BACK := Vector3i.BACK
## The right-facing normal direction.
const FACE_RIGHT := Vector3i.RIGHT
## The left-facing normal direction.
const FACE_LEFT := Vector3i.LEFT

## All six face directions.
const FACES: Array[Vector3i] = [
	FACE_TOP,
	FACE_BOTTOM,
	FACE_FRONT,
	FACE_BACK,
	FACE_RIGHT,
	FACE_LEFT,
]

## Display names for each face direction, used for logging and UI.
const FACE_NAMES: Dictionary[Vector3i, String] = {
	FACE_TOP: "Top",
	FACE_BOTTOM: "Bottom",
	FACE_FRONT: "Front",
	FACE_BACK: "Back",
	FACE_RIGHT: "Right",
	FACE_LEFT: "Left",
}

## Adjacent face mappings used by greedy meshing.
## Each entry maps a face to its adjacent faces in [right, left, down, up] order.
const ADJACENT_FACES: Dictionary[Vector3i, Array] = {
	FACE_TOP: [FACE_RIGHT, FACE_LEFT, FACE_BACK, FACE_FRONT],
	FACE_BOTTOM: [FACE_RIGHT, FACE_LEFT, FACE_BACK, FACE_FRONT],
	FACE_RIGHT: [FACE_TOP, FACE_BOTTOM, FACE_BACK, FACE_FRONT],
	FACE_LEFT: [FACE_TOP, FACE_BOTTOM, FACE_BACK, FACE_FRONT],
	FACE_FRONT: [FACE_TOP, FACE_BOTTOM, FACE_RIGHT, FACE_LEFT],
	FACE_BACK: [FACE_TOP, FACE_BOTTOM, FACE_RIGHT, FACE_LEFT],
}

## Sentinel color meaning "no color set". A color is considered unset when its
## alpha is 0, regardless of the RGB values.
const UNSET_COLOR := Color.TRANSPARENT

## Sentinel cell meaning "no texture set". A cell is considered unset when
## either coordinate is negative.
const UNSET_TEXTURE_XY := -Vector2i.ONE

## Sentinel material ID meaning "no material set". The empty string is reserved.
const UNSET_MATERIAL_ID := ""

@export_category("Base Properties")

## Display name for this voxel type.
@export var name: String = "":
	set = set_name,
	get = get_name

## Tag identifiers (e.g. [code]["flammable", "ore", "solid"][/code]).
@export var tags: Array[String] = []:
	set = set_tags,
	get = get_tags

## Base color applied to all faces unless overridden per-face.
## A color with alpha 0 renders as white on all faces that have no color set.
@export var base_color: Color = Color.WHITE:
	set = set_base_color,
	get = get_base_color

## Base texture atlas cell (grid position within the atlas).
## A negative coordinate on either axis means "no texture set".
@export var base_texture_cell: Vector2i = UNSET_TEXTURE_XY:
	set = set_base_texture_cell,
	get = get_base_texture_cell

## Base material ID string, referencing a material in the owning [VoxelSet].
## The empty string means no material override.
@export var base_material_id: String = UNSET_MATERIAL_ID:
	set = set_base_material_id,
	get = get_base_material_id

@export_group("Face Overrides")

@export_subgroup("Colors")

## Color override for the top face. [constant UNSET_COLOR] disables the override.
@export var top_face_color: Color = UNSET_COLOR:
	set = set_top_face_color
## Color override for the bottom face. [constant UNSET_COLOR] disables the override.
@export var bottom_face_color: Color = UNSET_COLOR:
	set = set_bottom_face_color
## Color override for the front face. [constant UNSET_COLOR] disables the override.
@export var front_face_color: Color = UNSET_COLOR:
	set = set_front_face_color
## Color override for the back face. [constant UNSET_COLOR] disables the override.
@export var back_face_color: Color = UNSET_COLOR:
	set = set_back_face_color
## Color override for the right face. [constant UNSET_COLOR] disables the override.
@export var right_face_color: Color = UNSET_COLOR:
	set = set_right_face_color
## Color override for the left face. [constant UNSET_COLOR] disables the override.
@export var left_face_color: Color = UNSET_COLOR:
	set = set_left_face_color

@export_subgroup("Textures")

## Texture cell override for the top face. [constant UNSET_TEXTURE_XY] disables it.
@export var top_face_texture_cell: Vector2i = UNSET_TEXTURE_XY:
	set = set_top_face_texture_cell
## Texture cell override for the bottom face. [constant UNSET_TEXTURE_XY] disables it.
@export var bottom_face_texture_cell: Vector2i = UNSET_TEXTURE_XY:
	set = set_bottom_face_texture_cell
## Texture cell override for the front face. [constant UNSET_TEXTURE_XY] disables it.
@export var front_face_texture_cell: Vector2i = UNSET_TEXTURE_XY:
	set = set_front_face_texture_cell
## Texture cell override for the back face. [constant UNSET_TEXTURE_XY] disables it.
@export var back_face_texture_cell: Vector2i = UNSET_TEXTURE_XY:
	set = set_back_face_texture_cell
## Texture cell override for the right face. [constant UNSET_TEXTURE_XY] disables it.
@export var right_face_texture_cell: Vector2i = UNSET_TEXTURE_XY:
	set = set_right_face_texture_cell
## Texture cell override for the left face. [constant UNSET_TEXTURE_XY] disables it.
@export var left_face_texture_cell: Vector2i = UNSET_TEXTURE_XY:
	set = set_left_face_texture_cell

@export_subgroup("Materials")

## Material ID override for the top face. [constant UNSET_MATERIAL_ID] disables it.
@export var top_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_top_face_material_id
## Material ID override for the bottom face. [constant UNSET_MATERIAL_ID] disables it.
@export var bottom_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_bottom_face_material_id
## Material ID override for the front face. [constant UNSET_MATERIAL_ID] disables it.
@export var front_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_front_face_material_id
## Material ID override for the back face. [constant UNSET_MATERIAL_ID] disables it.
@export var back_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_back_face_material_id
## Material ID override for the right face. [constant UNSET_MATERIAL_ID] disables it.
@export var right_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_right_face_material_id
## Material ID override for the left face. [constant UNSET_MATERIAL_ID] disables it.
@export var left_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_left_face_material_id

## Sets the display name of this voxel.
func set_name(new_name: String) -> void:
	if new_name == name:
		return
	name = new_name
	name_changed.emit()
	changed.emit()

## Returns the display name of this voxel.
func get_name() -> String:
	return name

## Sets the tag list of this voxel.
func set_tags(new_tags: Array[String]) -> void:
	if new_tags == tags:
		return
	tags = new_tags
	tags_changed.emit()
	changed.emit()

## Returns the tag list of this voxel.
func get_tags() -> Array[String]:
	return tags

## Sets the base color of this voxel.
func set_base_color(new_base_color: Color) -> void:
	if new_base_color == base_color:
		return
	base_color = new_base_color
	base_color_changed.emit()
	changed.emit()

## Sets the color of a specific face, dispatching to the matching per-face setter.
func set_face_color(face: Vector3i, face_color_value: Color) -> void:
	if not FACE_NAMES.has(face):
		return
	match face:
		FACE_TOP:
			top_face_color = face_color_value
		FACE_BOTTOM:
			bottom_face_color = face_color_value
		FACE_FRONT:
			front_face_color = face_color_value
		FACE_BACK:
			back_face_color = face_color_value
		FACE_RIGHT:
			right_face_color = face_color_value
		FACE_LEFT:
			left_face_color = face_color_value
		_:
			return

## Sets the color of the top face.
func set_top_face_color(color_value: Color) -> void:
	if color_value == top_face_color:
		return
	top_face_color = color_value
	face_color_changed.emit(FACE_TOP)
	changed.emit()

## Sets the color of the bottom face.
func set_bottom_face_color(color_value: Color) -> void:
	if color_value == bottom_face_color:
		return
	bottom_face_color = color_value
	face_color_changed.emit(FACE_BOTTOM)
	changed.emit()

## Sets the color of the front face.
func set_front_face_color(color_value: Color) -> void:
	if color_value == front_face_color:
		return
	front_face_color = color_value
	face_color_changed.emit(FACE_FRONT)
	changed.emit()

## Sets the color of the back face.
func set_back_face_color(color_value: Color) -> void:
	if color_value == back_face_color:
		return
	back_face_color = color_value
	face_color_changed.emit(FACE_BACK)
	changed.emit()

## Sets the color of the right face.
func set_right_face_color(color_value: Color) -> void:
	if color_value == right_face_color:
		return
	right_face_color = color_value
	face_color_changed.emit(FACE_RIGHT)
	changed.emit()

## Sets the color of the left face.
func set_left_face_color(color_value: Color) -> void:
	if color_value == left_face_color:
		return
	left_face_color = color_value
	face_color_changed.emit(FACE_LEFT)
	changed.emit()

## Returns true if the base color is set (alpha greater than 0).
func has_base_color() -> bool:
	return base_color.a > 0

## Returns the base color of this voxel.
func get_base_color() -> Color:
	return base_color

## Returns true if the given face has a color set, falling back to the base
## color when [param include_base] is true.
func has_face_color(face: Vector3i, include_base: bool = true) -> bool:
	match face:
		FACE_TOP:
			return top_face_color.a > 0 or (include_base and base_color.a > 0)
		FACE_BOTTOM:
			return bottom_face_color.a > 0 or (include_base and base_color.a > 0)
		FACE_FRONT:
			return front_face_color.a > 0 or (include_base and base_color.a > 0)
		FACE_BACK:
			return back_face_color.a > 0 or (include_base and base_color.a > 0)
		FACE_RIGHT:
			return right_face_color.a > 0 or (include_base and base_color.a > 0)
		FACE_LEFT:
			return left_face_color.a > 0 or (include_base and base_color.a > 0)
	return (include_base and base_color.a > 0)

## Returns the resolved color of the given face: the face override when set,
## otherwise the base color when [param include_base] is true.
func get_face_color(face: Vector3i, include_base: bool = true) -> Color:
	match face:
		FACE_TOP:
			return top_face_color if top_face_color.a > 0 or not include_base else base_color
		FACE_BOTTOM:
			return bottom_face_color if bottom_face_color.a > 0 or not include_base else base_color
		FACE_FRONT:
			return front_face_color if front_face_color.a > 0 or not include_base else base_color
		FACE_BACK:
			return back_face_color if back_face_color.a > 0 or not include_base else base_color
		FACE_RIGHT:
			return right_face_color if right_face_color.a > 0 or not include_base else base_color
		FACE_LEFT:
			return left_face_color if left_face_color.a > 0 or not include_base else base_color
	return base_color

## Returns the resolved color of the top face.
func get_top_face_color(include_base: bool = true) -> Color:
	return get_face_color(FACE_TOP, include_base)

## Returns the resolved color of the bottom face.
func get_bottom_face_color(include_base: bool = true) -> Color:
	return get_face_color(FACE_BOTTOM, include_base)

## Returns the resolved color of the front face.
func get_front_face_color(include_base: bool = true) -> Color:
	return get_face_color(FACE_FRONT, include_base)

## Returns the resolved color of the back face.
func get_back_face_color(include_base: bool = true) -> Color:
	return get_face_color(FACE_BACK, include_base)

## Returns the resolved color of the right face.
func get_right_face_color(include_base: bool = true) -> Color:
	return get_face_color(FACE_RIGHT, include_base)

## Returns the resolved color of the left face.
func get_left_face_color(include_base: bool = true) -> Color:
	return get_face_color(FACE_LEFT, include_base)

## Sets the base texture cell of this voxel.
func set_base_texture_cell(new_base_texture_cell: Vector2i) -> void:
	if new_base_texture_cell == base_texture_cell:
		return
	base_texture_cell = new_base_texture_cell
	base_texture_cell_changed.emit()
	changed.emit()

## Sets the texture cell of a specific face, dispatching to the matching
## per-face setter.
func set_face_texture_cell(face: Vector3i, new_texture_cell: Vector2i) -> void:
	if not ADJACENT_FACES.has(face):
		return
	match face:
		FACE_TOP:
			set_top_face_texture_cell(new_texture_cell)
		FACE_BOTTOM:
			set_bottom_face_texture_cell(new_texture_cell)
		FACE_FRONT:
			set_front_face_texture_cell(new_texture_cell)
		FACE_BACK:
			set_back_face_texture_cell(new_texture_cell)
		FACE_RIGHT:
			set_right_face_texture_cell(new_texture_cell)
		FACE_LEFT:
			set_left_face_texture_cell(new_texture_cell)
		_:
			return

## Sets the texture cell of the top face.
func set_top_face_texture_cell(texture_cell: Vector2i) -> void:
	if texture_cell == top_face_texture_cell:
		return
	top_face_texture_cell = texture_cell
	face_texture_cell_changed.emit(FACE_TOP)
	changed.emit()

## Sets the texture cell of the bottom face.
func set_bottom_face_texture_cell(texture_cell: Vector2i) -> void:
	if texture_cell == bottom_face_texture_cell:
		return
	bottom_face_texture_cell = texture_cell
	face_texture_cell_changed.emit(FACE_BOTTOM)
	changed.emit()

## Sets the texture cell of the front face.
func set_front_face_texture_cell(texture_cell: Vector2i) -> void:
	if texture_cell == front_face_texture_cell:
		return
	front_face_texture_cell = texture_cell
	face_texture_cell_changed.emit(FACE_FRONT)
	changed.emit()

## Sets the texture cell of the back face.
func set_back_face_texture_cell(texture_cell: Vector2i) -> void:
	if texture_cell == back_face_texture_cell:
		return
	back_face_texture_cell = texture_cell
	face_texture_cell_changed.emit(FACE_BACK)
	changed.emit()

## Sets the texture cell of the right face.
func set_right_face_texture_cell(texture_cell: Vector2i) -> void:
	if texture_cell == right_face_texture_cell:
		return
	right_face_texture_cell = texture_cell
	face_texture_cell_changed.emit(FACE_RIGHT)
	changed.emit()

## Sets the texture cell of the left face.
func set_left_face_texture_cell(texture_cell: Vector2i) -> void:
	if texture_cell == left_face_texture_cell:
		return
	left_face_texture_cell = texture_cell
	face_texture_cell_changed.emit(FACE_LEFT)
	changed.emit()

## Returns true if the base texture cell is set (not negative coordinates).
func has_base_texture_cell() -> bool:
	return base_texture_cell.x >= 0 and base_texture_cell.y >= 0

## Returns the base texture cell of this voxel.
func get_base_texture_cell() -> Vector2i:
	return base_texture_cell

## Returns true if the given face has a texture cell set, falling back to the
## base cell when [param include_base] is true.
func has_face_texture_cell(face: Vector3i, include_base: bool = true) -> bool:
	match face:
		FACE_TOP:
			return top_face_texture_cell > UNSET_TEXTURE_XY or (include_base and base_texture_cell > UNSET_TEXTURE_XY)
		FACE_BOTTOM:
			return bottom_face_texture_cell > UNSET_TEXTURE_XY or (include_base and base_texture_cell > UNSET_TEXTURE_XY)
		FACE_FRONT:
			return front_face_texture_cell > UNSET_TEXTURE_XY or (include_base and base_texture_cell > UNSET_TEXTURE_XY)
		FACE_BACK:
			return back_face_texture_cell > UNSET_TEXTURE_XY or (include_base and base_texture_cell > UNSET_TEXTURE_XY)
		FACE_RIGHT:
			return right_face_texture_cell > UNSET_TEXTURE_XY or (include_base and base_texture_cell > UNSET_TEXTURE_XY)
		FACE_LEFT:
			return left_face_texture_cell > UNSET_TEXTURE_XY or (include_base and base_texture_cell > UNSET_TEXTURE_XY)
	return (include_base and base_texture_cell > UNSET_TEXTURE_XY)

## Returns the resolved texture cell of the given face: the face override when
## set, otherwise the base cell when [param include_base] is true.
func get_face_texture_cell(face: Vector3i, include_base: bool = true) -> Vector2i:
	match face:
		FACE_TOP:
			return top_face_texture_cell if top_face_texture_cell > UNSET_TEXTURE_XY else (base_texture_cell if include_base else UNSET_TEXTURE_XY)
		FACE_BOTTOM:
			return bottom_face_texture_cell if bottom_face_texture_cell > UNSET_TEXTURE_XY else (base_texture_cell if include_base else UNSET_TEXTURE_XY)
		FACE_FRONT:
			return front_face_texture_cell if front_face_texture_cell > UNSET_TEXTURE_XY else (base_texture_cell if include_base else UNSET_TEXTURE_XY)
		FACE_BACK:
			return back_face_texture_cell if back_face_texture_cell > UNSET_TEXTURE_XY else (base_texture_cell if include_base else UNSET_TEXTURE_XY)
		FACE_RIGHT:
			return right_face_texture_cell if right_face_texture_cell > UNSET_TEXTURE_XY else (base_texture_cell if include_base else UNSET_TEXTURE_XY)
		FACE_LEFT:
			return left_face_texture_cell if left_face_texture_cell > UNSET_TEXTURE_XY else (base_texture_cell if include_base else UNSET_TEXTURE_XY)
	return base_texture_cell if include_base else UNSET_TEXTURE_XY

## Returns the resolved texture cell of the top face.
func get_top_face_texture_cell(include_base: bool = true) -> Vector2i:
	return get_face_texture_cell(FACE_TOP, include_base)

## Returns the resolved texture cell of the bottom face.
func get_bottom_face_texture_cell(include_base: bool = true) -> Vector2i:
	return get_face_texture_cell(FACE_BOTTOM, include_base)

## Returns the resolved texture cell of the front face.
func get_front_face_texture_cell(include_base: bool = true) -> Vector2i:
	return get_face_texture_cell(FACE_FRONT, include_base)

## Returns the resolved texture cell of the back face.
func get_back_face_texture_cell(include_base: bool = true) -> Vector2i:
	return get_face_texture_cell(FACE_BACK, include_base)

## Returns the resolved texture cell of the right face.
func get_right_face_texture_cell(include_base: bool = true) -> Vector2i:
	return get_face_texture_cell(FACE_RIGHT, include_base)

## Returns the resolved texture cell of the left face.
func get_left_face_texture_cell(include_base: bool = true) -> Vector2i:
	return get_face_texture_cell(FACE_LEFT, include_base)

## Sets the base material ID of this voxel.
func set_base_material_id(new_base_material_id: String) -> void:
	if new_base_material_id == base_material_id:
		return
	base_material_id = new_base_material_id
	base_material_id_changed.emit()
	changed.emit()

## Sets the material ID of a specific face, dispatching to the matching
## per-face setter.
func set_face_material_id(face: Vector3i, new_material_id: String) -> void:
	if not ADJACENT_FACES.has(face):
		return
	match face:
		FACE_TOP:
			set_top_face_material_id(new_material_id)
		FACE_BOTTOM:
			set_bottom_face_material_id(new_material_id)
		FACE_FRONT:
			set_front_face_material_id(new_material_id)
		FACE_BACK:
			set_back_face_material_id(new_material_id)
		FACE_RIGHT:
			set_right_face_material_id(new_material_id)
		FACE_LEFT:
			set_left_face_material_id(new_material_id)
		_:
			return

## Sets the material ID of the top face.
func set_top_face_material_id(material: String) -> void:
	if material == top_face_material_id:
		return
	top_face_material_id = material
	face_material_id_changed.emit(FACE_TOP)
	changed.emit()

## Sets the material ID of the bottom face.
func set_bottom_face_material_id(material: String) -> void:
	if material == bottom_face_material_id:
		return
	bottom_face_material_id = material
	face_material_id_changed.emit(FACE_BOTTOM)
	changed.emit()

## Sets the material ID of the front face.
func set_front_face_material_id(material: String) -> void:
	if material == front_face_material_id:
		return
	front_face_material_id = material
	face_material_id_changed.emit(FACE_FRONT)
	changed.emit()

## Sets the material ID of the back face.
func set_back_face_material_id(material: String) -> void:
	if material == back_face_material_id:
		return
	back_face_material_id = material
	face_material_id_changed.emit(FACE_BACK)
	changed.emit()

## Sets the material ID of the right face.
func set_right_face_material_id(material: String) -> void:
	if material == right_face_material_id:
		return
	right_face_material_id = material
	face_material_id_changed.emit(FACE_RIGHT)
	changed.emit()

## Sets the material ID of the left face.
func set_left_face_material_id(material: String) -> void:
	if material == left_face_material_id:
		return
	left_face_material_id = material
	face_material_id_changed.emit(FACE_LEFT)
	changed.emit()

## Returns true if the base material ID is set (not the empty sentinel).
func has_base_material_id() -> bool:
	return base_material_id != UNSET_MATERIAL_ID

## Returns the base material ID of this voxel.
func get_base_material_id() -> String:
	return base_material_id

## Returns true if the given face has a material ID set, falling back to the
## base material when [param include_base] is true.
func has_face_material_id(face: Vector3i, include_base: bool = true) -> bool:
	match face:
		FACE_TOP:
			return top_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
		FACE_BOTTOM:
			return bottom_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
		FACE_FRONT:
			return front_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
		FACE_BACK:
			return back_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
		FACE_RIGHT:
			return right_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
		FACE_LEFT:
			return left_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
	return (include_base and base_material_id != UNSET_MATERIAL_ID)

## Returns the resolved material ID of the given face: the face override when
## set, otherwise the base material when [param include_base] is true.
func get_face_material_id(face: Vector3i, include_base: bool = true) -> String:
	match face:
		FACE_TOP:
			return top_face_material_id if top_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
		FACE_BOTTOM:
			return bottom_face_material_id if bottom_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
		FACE_FRONT:
			return front_face_material_id if front_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
		FACE_BACK:
			return back_face_material_id if back_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
		FACE_RIGHT:
			return right_face_material_id if right_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
		FACE_LEFT:
			return left_face_material_id if left_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
	return base_material_id if include_base else UNSET_MATERIAL_ID

## Returns the resolved material ID of the top face.
func get_top_face_material_id(include_base: bool = true) -> String:
	return get_face_material_id(FACE_TOP, include_base)

## Returns the resolved material ID of the bottom face.
func get_bottom_face_material_id(include_base: bool = true) -> String:
	return get_face_material_id(FACE_BOTTOM, include_base)

## Returns the resolved material ID of the front face.
func get_front_face_material_id(include_base: bool = true) -> String:
	return get_face_material_id(FACE_FRONT, include_base)

## Returns the resolved material ID of the back face.
func get_back_face_material_id(include_base: bool = true) -> String:
	return get_face_material_id(FACE_BACK, include_base)

## Returns the resolved material ID of the right face.
func get_right_face_material_id(include_base: bool = true) -> String:
	return get_face_material_id(FACE_RIGHT, include_base)

## Returns the resolved material ID of the left face.
func get_left_face_material_id(include_base: bool = true) -> String:
	return get_face_material_id(FACE_LEFT, include_base)

## Returns true if the base color is translucent (0 < alpha < 1.0).
## An alpha of 0 is the "unset" sentinel and does not apply a tint, so it must
## not make the voxel translucent.
func is_base_color_translucent() -> bool:
	return base_color.a > 0.0 and base_color.a < 1.0

## Returns true if the resolved color of the given face is translucent
## (0 < alpha < 1.0). When [param include_base] is true, the base color is
## considered when the face has no override.
func is_face_color_translucent(face: Vector3i, include_base: bool = true) -> bool:
	var face_color := get_face_color(face, include_base)
	return face_color.a > 0.0 and face_color.a < 1.0

## Returns true if the resolved top face color is translucent.
func is_top_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_TOP, include_base)

## Returns true if the resolved bottom face color is translucent.
func is_bottom_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_BOTTOM, include_base)

## Returns true if the resolved front face color is translucent.
func is_front_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_FRONT, include_base)

## Returns true if the resolved back face color is translucent.
func is_back_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_BACK, include_base)

## Returns true if the resolved right face color is translucent.
func is_right_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_RIGHT, include_base)

## Returns true if the resolved left face color is translucent.
func is_left_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_LEFT, include_base)

## Returns true if the base color or any per-face color override is translucent.
## This is the color-only test for translucency; material transparency must be
## checked separately via [method VoxelSet.is_voxel_opaque].
func has_translucent_colors() -> bool:
	if is_base_color_translucent():
		return true
	# Check per-face color overrides (face-only, no base fallback).
	for face in FACES:
		if is_face_color_translucent(face, false):
			return true
	return false

## Copies all properties from another Voxel into this one.
func copy_from(source_voxel: Voxel) -> void:
	if not source_voxel:
		return
	
	name = source_voxel.name
	tags = source_voxel.tags.duplicate()
	base_color = source_voxel.base_color
	base_texture_cell = source_voxel.base_texture_cell
	base_material_id = source_voxel.base_material_id
	
	top_face_color = source_voxel.top_face_color
	bottom_face_color = source_voxel.bottom_face_color
	front_face_color = source_voxel.front_face_color
	back_face_color = source_voxel.back_face_color
	right_face_color = source_voxel.right_face_color
	left_face_color = source_voxel.left_face_color
	
	top_face_texture_cell = source_voxel.top_face_texture_cell
	bottom_face_texture_cell = source_voxel.bottom_face_texture_cell
	front_face_texture_cell = source_voxel.front_face_texture_cell
	back_face_texture_cell = source_voxel.back_face_texture_cell
	right_face_texture_cell = source_voxel.right_face_texture_cell
	left_face_texture_cell = source_voxel.left_face_texture_cell
	
	top_face_material_id = source_voxel.top_face_material_id
	bottom_face_material_id = source_voxel.bottom_face_material_id
	front_face_material_id = source_voxel.front_face_material_id
	back_face_material_id = source_voxel.back_face_material_id
	right_face_material_id = source_voxel.right_face_material_id
	left_face_material_id = source_voxel.left_face_material_id
