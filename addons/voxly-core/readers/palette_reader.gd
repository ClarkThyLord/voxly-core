## Multi-format palette file reader.
## Reads color palette files from various external tools and converts them into
## [Voxel] resources suitable for use in [VoxelSet]s.
##
## Supported formats:
## - .gpl : GIMP Palette
## - .txt : Simple text format (R,G,B or R G B per line, one color per line)
## - .json : Custom JSON palette format (see [method _read_json] for schema)
## - .pal : Paint.NET palette (RGB hex values, one per line)
## - .hex : Simple hex color list (RRGGBB or #RRGGBB, one per line)
@tool
class_name PaletteReader
extends RefCounted

## Reads a palette file and returns a voxel palette plus an empty voxels
## dictionary. Optional dictionary supports "allow_repeated" (bool).
## When false (default), duplicate color values are removed keeping only unique
## colors. When true, all color entries are kept including duplicates.
## Returns a Dictionary with "error", "voxels", and "palette" keys.
static func read_file(palette_path: String, options: Dictionary = {}) -> Dictionary:
	var extension := palette_path.get_extension().to_lower()
	# When false remove duplicates, when true keep all.
	var allow_repeated: bool = options.get("allow_repeated", false)
	
	match extension:
		"gpl":
			return _read_gpl(palette_path, allow_repeated)
		"json":
			return _read_json(palette_path, allow_repeated)
		"txt":
			return _read_txt(palette_path, allow_repeated)
		"pal":
			return _read_pal(palette_path, allow_repeated)
		"hex":
			return _read_hex(palette_path, allow_repeated)
		_:
			# Try as text with one hex color per line.
			return _read_txt(palette_path, allow_repeated)

## Normalizes tabs to spaces so splitting logic is consistent regardless of
## whether tabs or spaces are used as separators.
static func _normalize_tabs(line: String) -> String:
	return line.replace("\t", " ")

## Tracks seen color values to optionally deduplicate palette entries.
static var _seen_color_keys: Dictionary = {}

## Resets the seen-color tracking set.
static func _reset_seen_colors() -> void:
	_seen_color_keys.clear()

## Returns true if the color has already been seen.
static func _is_duplicate_color(color: Color) -> bool:
	var key := "%d_%d_%d" % [roundi(color.r8), roundi(color.g8), roundi(color.b8)]
	if _seen_color_keys.has(key):
		return true
	_seen_color_keys[key] = true
	return false

## Reads a GIMP palette file (.gpl).
## Format:
## [codeblock]
## GIMP Palette
## Name: Palette Name
## Columns: N
## R G B \t ColorName (optional)
## R G B HexCode (some files include hex as a 4th token)
## [/codeblock]
## Lines can use tabs or spaces as separators.
static func _read_gpl(file_path: String, allow_repeated: bool = false) -> Dictionary:
	var result := {
		"error": OK,
		"voxels": {},
		"palette": {},
	}
	
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		result["error"] = FileAccess.get_open_error()
		return result
	
	var header: String = file.get_line().strip_edges()
	if header != "GIMP Palette":
		result["error"] = ERR_FILE_UNRECOGNIZED
		file.close()
		return result
	
	var next_id: int = 0
	_reset_seen_colors()
	
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		
		# Skip empty lines and comments.
		if line.is_empty() or line.begins_with("#"):
			continue
		
		# Skip metadata lines.
		if line.begins_with("Name:") or line.begins_with("Columns:"):
			continue
		
		# Normalize tabs to spaces for consistent parsing.
		line = _normalize_tabs(line)
		
		# Parse the color line: tokens can be:
		#   R G B
		#   R G B ColorName
		#   R G B HexCode  (4th token is hex, used as name)
		var tokens := line.split(" ", false)
		
		if tokens.size() >= 3:
			var r := float(tokens[0]) / 255.0
			var g := float(tokens[1]) / 255.0
			var b := float(tokens[2]) / 255.0
			var color := Color(r, g, b, 1.0)
			
			# Determine the name: the remainder after the 3 RGB values.
			var name: String = ""
			if tokens.size() > 3:
				name = " ".join(tokens.slice(3)).strip_edges()
				# Remove parenthetical comments from the name.
				var parenthesis_index := name.find("(")
				if parenthesis_index > 0:
					name = name.substr(0, parenthesis_index).strip_edges()
			
			# Check for duplicates if mode is unique-only.
			if not allow_repeated and _is_duplicate_color(color):
				continue
			
			var voxel := Voxel.new()
			voxel.base_color = color
			voxel.name = name if not name.is_empty() else "palette_%d" % next_id
			result["palette"][next_id] = voxel
			next_id += 1
	
	file.close()
	
	if result["palette"].is_empty():
		result["error"] = ERR_FILE_EOF
	
	return result

## Reads a JSON palette file.
## Expected schema (array of color objects):
## [codeblock]
## [
##   { "name": "Red", "color": [1.0, 0.0, 0.0] },
##   { "name": "Green", "color": "#00FF00" },
##   { "color": "255, 0, 0" }
## ]
## [/codeblock]
## Color can be:
## - Array of [r, g, b] floats (0.0–1.0)
## - Hex string "#RRGGBB" or "#RRGGBBAA"
## - String "R, G, B" or "R G B" (0–255)
## If name is omitted, one is auto-generated.
static func _read_json(file_path: String, allow_repeated: bool = false) -> Dictionary:
	var result := {
		"error": OK,
		"voxels": {},
		"palette": {},
	}
	
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		result["error"] = FileAccess.get_open_error()
		return result
	
	var content: String = file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var parse_err := json.parse(content)
	if parse_err != OK:
		result["error"] = parse_err
		return result
	
	var data = json.get_data()
	if typeof(data) != TYPE_ARRAY:
		result["error"] = ERR_INVALID_DATA
		return result
	
	var colors: Array = data
	var next_id: int = 0
	_reset_seen_colors()
	
	for entry in colors:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		
		var entry_dict: Dictionary = entry
		var json_color = entry_dict.get("color", null)
		if json_color == null:
			continue
		var color := _parse_json_color(json_color)
		if color == null:
			continue
		
		if not allow_repeated and _is_duplicate_color(color):
			continue
		
		var name: String = entry_dict.get("name", "")
		if name.is_empty():
			name = "json_%d" % next_id
		
		var voxel := Voxel.new()
		voxel.base_color = color
		voxel.name = name
		result["palette"][next_id] = voxel
		next_id += 1
	
	if result["palette"].is_empty():
		result["error"] = ERR_FILE_EOF
	
	return result

## Parses a color value from a JSON entry.
## Supports: Array, hex string, or comma/space-separated string.
static func _parse_json_color(value) -> Color:
	var value_type = typeof(value)
	
	if value_type == TYPE_ARRAY:
		var array: Array = value
		if array.size() >= 3:
			return Color(
				float(array[0]),
				float(array[1]),
				float(array[2]),
				1.0
			)
	
	elif value_type == TYPE_STRING:
		var string: String = value
		if string.begins_with("#"):
			return _parse_hex_color(string)
		
		# Try comma or space separated R, G, B.
		var parts := string.split(",", false)
		if parts.size() < 3:
			parts = string.split(" ", false)
		
		if parts.size() >= 3:
			return Color(
				float(parts[0].strip_edges()) / 255.0,
				float(parts[1].strip_edges()) / 255.0,
				float(parts[2].strip_edges()) / 255.0,
				1.0
			)
	
	return Color.TRANSPARENT

## Reads a simple text palette file.
## Each line should contain a hex color like "FF0000" or "#FF0000" or
## "AARRGGBB" or "R G B". Lines starting with # or // are comments.
static func _read_txt(file_path: String, allow_repeated: bool = false) -> Dictionary:
	var result := {
		"error": OK,
		"voxels": {},
		"palette": {},
	}
	
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		result["error"] = FileAccess.get_open_error()
		return result
	
	var next_id: int = 0
	_reset_seen_colors()
	
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		
		if line.is_empty() or line.begins_with("#") or line.begins_with("//") or line.begins_with(";"):
			continue
		
		var color := _parse_txt_color(line)
		if color != null:
			# Check for duplicates if mode is unique-only.
			if not allow_repeated and _is_duplicate_color(color):
				continue
			
			var voxel := Voxel.new()
			voxel.base_color = color
			voxel.name = "txt_%d" % next_id
			result["palette"][next_id] = voxel
			next_id += 1
	
	file.close()
	
	if result["palette"].is_empty():
		result["error"] = ERR_FILE_EOF
	
	return result

## Parses a single line of text as a color, parsing:
## Hex (FF0000, #FF0000), 8-char hex with alpha prefix (AARRGGBB),
## RGB decimal (255 0 0), CSV (255,0,0).
static func _parse_txt_color(line: String) -> Color:
	# Try hex format.
	var hex: String = line.replace("#", "").strip_edges()
	if hex.is_valid_html_color() and hex.length() >= 6:
		return _parse_hex_color(hex)
	
	# Try space or comma separated values.
	var parts := line.split(",", false)
	if parts.size() < 3:
		parts = line.split(" ", false)
	
	if parts.size() >= 3:
		return Color(
			float(parts[0].strip_edges()) / 255.0,
			float(parts[1].strip_edges()) / 255.0,
			float(parts[2].strip_edges()) / 255.0,
			1.0
		)
	
	return Color.TRANSPARENT

## Parses a hex color string into a [Color].
## Supports: "RRGGBB", "RRGGBBAA", "#RRGGBB", "AARRGGBB".
## For 8-char hex, the first 2 chars are treated as alpha.
static func _parse_hex_color(hex: String) -> Color:
	var hex_code: String = hex.replace("#", "").strip_edges()
	
	if hex_code.length() == 8:
		# AARRGGBB: first 2 chars = alpha, remaining 6 = RGB.
		var alpha := float("0x" + hex_code.substr(0, 2)) / 255.0
		var rgb_str := "#" + hex_code.substr(2, 6)
		var color := Color(rgb_str)
		color.a = alpha
		return color
	
	# RRGGBB or RRGGBBAA.
	return Color("#" + hex_code)

## Reads a Paint.NET palette file (.pal).
## Supports two formats:
## JASC-PAL format (header + decimal "R G B" values):
## [codeblock]
## JASC-PAL
## 0100
## <count>
## R G B
## [/codeblock]
## Simple hex format (one "RRGGBB" hex per line):
## [codeblock]
## FF0000
## 00FF00
## [/codeblock]
static func _read_pal(file_path: String, allow_repeated: bool = false) -> Dictionary:
	var result := {
		"error": OK,
		"voxels": {},
		"palette": {},
	}
	
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		result["error"] = FileAccess.get_open_error()
		return result
	
	# Peek at the first line to detect the JASC-PAL format.
	var first_line: String = file.get_line().strip_edges()
	var is_jasc_pal: bool = first_line == "JASC-PAL"
	
	var next_id: int = 0
	_reset_seen_colors()
	
	if is_jasc_pal:
		# JASC-PAL format: skip header + version + count lines.
		var version_line: String = file.get_line().strip_edges()  # "0100"
		var count_line: String = file.get_line().strip_edges()   # number of colors (optional, we ignore)
		
		while not file.eof_reached():
			var line: String = file.get_line().strip_edges()
			
			if line.is_empty() or line.begins_with(";"):
				continue
			
			# Parse R G B (space separated decimal values 0-255).
			var parts := line.split(" ", false)
			if parts.size() >= 3:
				var r := float(parts[0]) / 255.0
				var g := float(parts[1]) / 255.0
				var b := float(parts[2]) / 255.0
				var color := Color(r, g, b, 1.0)
				
				# Check for duplicates if mode is unique-only.
				if not allow_repeated and _is_duplicate_color(color):
					continue
				
				var voxel := Voxel.new()
				voxel.base_color = color
				voxel.name = "pal_%d" % next_id
				result["palette"][next_id] = voxel
				next_id += 1
	else:
		# Simple hex format, one "RRGGBB" hex per line.
		# The first line was already read; process it too.
		if not first_line.is_empty() and not first_line.begins_with(";"):
			if first_line.length() == 6 and first_line.is_valid_html_color():
				var color := Color("#" + first_line)
				
				if allow_repeated or not _is_duplicate_color(color):
					var voxel := Voxel.new()
					voxel.base_color = color
					voxel.name = "pal_%d" % next_id
					result["palette"][next_id] = voxel
					next_id += 1
		
		while not file.eof_reached():
			var line: String = file.get_line().strip_edges()
			
			if line.is_empty() or line.begins_with(";"):
				continue
			
			# Paint.NET pal format: RRGGBB hex (no # prefix).
			if line.length() == 6 and line.is_valid_html_color():
				var color := Color("#" + line)
				
				if allow_repeated or not _is_duplicate_color(color):
					var voxel := Voxel.new()
					voxel.base_color = color
					voxel.name = "pal_%d" % next_id
					result["palette"][next_id] = voxel
					next_id += 1
	
	file.close()
	
	if result["palette"].is_empty():
		result["error"] = ERR_FILE_EOF
	
	return result

## Reads a simple hex color palette file (.hex).
## Each line contains one hex color: "RRGGBB", "AARRGGBB", or "#RRGGBB".
## Lines starting with # or // are comments.
static func _read_hex(file_path: String, allow_repeated: bool = false) -> Dictionary:
	var result := {
		"error": OK,
		"voxels": {},
		"palette": {},
	}
	
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		result["error"] = FileAccess.get_open_error()
		return result
	
	var next_id: int = 0
	_reset_seen_colors()
	
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		
		if line.is_empty() or line.begins_with("#") or line.begins_with("//") or line.begins_with(";"):
			continue
		
		# Parse the hex color.
		var hex: String = line.replace("#", "").strip_edges()
		if hex.is_valid_html_color() and hex.length() >= 6:
			var color := _parse_hex_color(hex)
			
			# Check for duplicates if mode is unique-only.
			if not allow_repeated and _is_duplicate_color(color):
				continue
			
			var voxel := Voxel.new()
			voxel.base_color = color
			voxel.name = "hex_%d" % next_id
			result["palette"][next_id] = voxel
			next_id += 1
	
	file.close()
	
	if result["palette"].is_empty():
		result["error"] = ERR_FILE_EOF
	
	return result
