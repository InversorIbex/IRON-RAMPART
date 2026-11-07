class_name LevelLoader
extends RefCounted
## Loads mission JSON files into LevelData, with strict validation.
## Invalid data never fails silently: every problem is collected in
## `Result.errors` and (unless `report_errors` is false) sent to push_error.
## Format reference: docs/GAME_DESIGN.md#formato-de-niveles.

const SUPPORTED_FORMAT_VERSION := 1
const THEMES := ["desert"]
const VICTORY_TYPES := ["survive_all_waves"]

## Tests that deliberately feed bad data set this to false to keep logs clean.
static var report_errors: bool = true


class Result:
	extends RefCounted
	var level: LevelData = null
	var errors: Array[String] = []

	func is_ok() -> bool:
		return level != null and errors.is_empty()


static func load_file(path: String) -> Result:
	if not FileAccess.file_exists(path):
		return _fail(Result.new(), "%s: file not found" % path)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return _fail(Result.new(), "%s: file is empty or unreadable" % path)
	return parse_json_text(text, path)


static func parse_json_text(text: String, source: String = "<memory>") -> Result:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return _fail(Result.new(), "%s: invalid JSON at line %d: %s"
				% [source, json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _fail(Result.new(), "%s: root must be a JSON object" % source)
	return parse_dict(json.data, source)


static func parse_dict(d: Dictionary, source: String = "<memory>") -> Result:
	var result := Result.new()
	var errors := result.errors
	var level := LevelData.new()

	# --- Header ---
	var version: Variant = d.get("format_version")
	if not _is_number(version) or int(version) != SUPPORTED_FORMAT_VERSION:
		errors.append("format_version must be %d (got %s)" % [SUPPORTED_FORMAT_VERSION, version])
	level.id = str(d.get("id", ""))
	if level.id.is_empty():
		errors.append("missing 'id'")
	level.display_name = str(d.get("name", level.id))
	level.cell_size = _read_int(d, "cell_size", 64, 8, 512, errors)
	level.starting_credits = _read_int(d, "starting_credits", 0, 0, 1000000, errors)
	level.base_max_hp = _read_int(d, "base_max_hp", 20, 1, 100000, errors)

	# --- Movement classes ---
	var classes: Variant = d.get("movement_classes", ["infantry", "wheeled", "tracked"])
	level.movement_mask = MovementClass.NONE
	if typeof(classes) != TYPE_ARRAY or (classes as Array).is_empty():
		errors.append("'movement_classes' must be a non-empty array")
	else:
		for c in classes:
			var bit := MovementClass.from_name(str(c))
			if bit == MovementClass.NONE:
				errors.append("unknown movement class '%s'" % c)
			level.movement_mask |= bit

	# --- Structures offered ---
	var structures: Variant = d.get("available_structures", [])
	if typeof(structures) != TYPE_ARRAY:
		errors.append("'available_structures' must be an array")
	else:
		var ids := PackedStringArray()
		for s in structures:
			if not StructureCatalog.has_id(StringName(str(s))):
				errors.append("unknown structure id '%s'" % s)
			else:
				ids.append(str(s))
		level.available_structures = ids

	# --- Rules ---
	var rules: Variant = d.get("rules", {})
	if typeof(rules) != TYPE_DICTIONARY:
		errors.append("'rules' must be an object")
	else:
		level.allow_build_during_combat = bool(rules.get("allow_build_during_combat", true))
		level.allow_remove_during_combat = bool(rules.get("allow_remove_during_combat", false))
		var surcharge: Variant = rules.get("combat_build_surcharge", 0.25)
		if not _is_number(surcharge) or float(surcharge) < 0.0 or float(surcharge) > 5.0:
			errors.append("'rules.combat_build_surcharge' must be a number in [0, 5] (got %s)" % [surcharge])
		else:
			level.combat_build_surcharge = float(surcharge)

	# --- Layout ---
	_parse_layout(d.get("layout"), level, errors)

	# --- Mission identity + waves (need the spawn count from the layout) ---
	_parse_mission(d, level, errors)
	_parse_waves(d.get("waves", []), level, errors)

	# --- Connectivity (only meaningful if the layout itself is valid) ---
	if errors.is_empty():
		var grid := GridModel.new(level)
		var nav := NavGrid.new(grid, level.goal_cell)
		for bit in MovementClass.ALL:
			if level.movement_mask & bit:
				for spawn in level.spawn_cells:
					if not nav.can_reach_goal(bit, spawn):
						errors.append("spawn %s has no route to the base for '%s'"
								% [spawn, MovementClass.to_name(bit)])

	if not errors.is_empty():
		if report_errors:
			for e in errors:
				push_error("LevelLoader %s: %s" % [source, e])
		return result
	result.level = level
	return result


static func _parse_mission(d: Dictionary, level: LevelData, errors: Array[String]) -> void:
	var m: Variant = d.get("mission", {})
	if typeof(m) != TYPE_DICTIONARY:
		errors.append("'mission' must be an object")
		return
	level.region = str(m.get("region", ""))
	level.briefing = str(m.get("briefing", ""))
	level.theme = str(m.get("theme", "desert"))
	if not THEMES.has(level.theme):
		errors.append("unknown mission theme '%s' (known: %s)" % [level.theme, ", ".join(THEMES)])
	var names: Variant = m.get("spawn_names", [])
	if typeof(names) != TYPE_ARRAY:
		errors.append("'mission.spawn_names' must be an array")
	else:
		var list := PackedStringArray()
		for n in names:
			list.append(str(n))
		if not list.is_empty() and list.size() != level.spawn_cells.size():
			errors.append("'mission.spawn_names' has %d names but the layout has %d spawns"
					% [list.size(), level.spawn_cells.size()])
		level.spawn_names = list
	var debrief: Variant = m.get("debrief_seconds", 3.0)
	if not _is_number(debrief) or float(debrief) < 0.0 or float(debrief) > 60.0:
		errors.append("'mission.debrief_seconds' must be a number in [0, 60]")
	else:
		level.debrief_seconds = float(debrief)
	var victory: Variant = d.get("victory", {"type": "survive_all_waves"})
	if typeof(victory) != TYPE_DICTIONARY or not VICTORY_TYPES.has(str(victory.get("type", ""))):
		errors.append("'victory.type' must be one of: %s" % ", ".join(VICTORY_TYPES))
	else:
		level.victory_type = str(victory["type"])


static func _parse_waves(raw: Variant, level: LevelData, errors: Array[String]) -> void:
	if typeof(raw) != TYPE_ARRAY:
		errors.append("'waves' must be an array")
		return
	var ids := {}
	for wi in (raw as Array).size():
		var w: Variant = raw[wi]
		var where := "wave %d" % (wi + 1)
		if typeof(w) != TYPE_DICTIONARY:
			errors.append("%s must be an object" % where)
			continue
		var wave := WaveData.new()
		wave.id = str(w.get("id", ""))
		if wave.id.is_empty() or ids.has(wave.id):
			errors.append("%s needs a unique 'id'" % where)
		ids[wave.id] = true
		where = "wave '%s'" % wave.id
		wave.display_name = str(w.get("name", wave.id))
		wave.reward = _read_int(w, "reward", 0, 0, 100000, errors)
		var mods: Variant = w.get("modifiers", {})
		if typeof(mods) != TYPE_DICTIONARY:
			errors.append("%s: 'modifiers' must be an object" % where)
		else:
			wave.hp_multiplier = _read_float(mods, "hp", 1.0, 0.1, 10.0, where, errors)
			wave.speed_multiplier = _read_float(mods, "speed", 1.0, 0.1, 5.0, where, errors)
		wave.completion = str(w.get("completion", WaveData.COMPLETE_ALL_CLEARED))
		if wave.completion != WaveData.COMPLETE_ALL_CLEARED:
			errors.append("%s: unknown completion '%s'" % [where, wave.completion])
		var groups: Variant = w.get("groups")
		if typeof(groups) != TYPE_ARRAY or (groups as Array).is_empty():
			errors.append("%s needs a non-empty 'groups' array" % where)
			continue
		for gi in (groups as Array).size():
			var g: Variant = groups[gi]
			var gwhere := "%s group %d" % [where, gi + 1]
			if typeof(g) != TYPE_DICTIONARY:
				errors.append("%s must be an object" % gwhere)
				continue
			var group := WaveData.Group.new()
			group.enemy_id = StringName(str(g.get("enemy", "")))
			if not EnemyCatalog.has_id(group.enemy_id):
				errors.append("%s: unknown enemy '%s'" % [gwhere, group.enemy_id])
			group.count = _read_int(g, "count", 0, 1, 1000, errors)
			if not g.has("count"):
				errors.append("%s: missing 'count'" % gwhere)
			group.start = _read_float(g, "start", 0.0, 0.0, 3600.0, gwhere, errors)
			group.interval = _read_float(g, "interval", 1.0, 0.05, 120.0, gwhere, errors)
			group.spawn = _parse_spawn(g.get("spawn", "alternate"), level, gwhere, errors)
			wave.groups.append(group)
		level.waves.append(wave)


static func _parse_spawn(v: Variant, level: LevelData, where: String, errors: Array[String]) -> int:
	if typeof(v) == TYPE_STRING:
		if v == "alternate":
			return WaveData.ALTERNATE
		var i := level.spawn_names.find(v)
		if i < 0:
			errors.append("%s: unknown spawn '%s' (names: %s)" % [where, v, ", ".join(level.spawn_names)])
			return 0
		return i
	if _is_number(v) and int(v) >= 0 and int(v) < level.spawn_cells.size() and float(v) == floor(float(v)):
		return int(v)
	errors.append("%s: 'spawn' must be a spawn name, an index < %d, or \"alternate\"" % [where, level.spawn_cells.size()])
	return 0


static func _read_float(d: Dictionary, key: String, default: float, min_v: float, max_v: float,
		where: String, errors: Array[String]) -> float:
	if not d.has(key):
		return default
	var v: Variant = d[key]
	if not _is_number(v) or float(v) < min_v or float(v) > max_v:
		errors.append("%s: '%s' must be a number in [%s, %s] (got %s)" % [where, key, min_v, max_v, v])
		return default
	return float(v)


static func _parse_layout(layout: Variant, level: LevelData, errors: Array[String]) -> void:
	if typeof(layout) != TYPE_ARRAY or (layout as Array).is_empty():
		errors.append("'layout' must be a non-empty array of strings")
		return
	var rows: Array = layout
	level.height = rows.size()
	level.width = -1
	for y in rows.size():
		if typeof(rows[y]) != TYPE_STRING:
			errors.append("layout row %d is not a string" % y)
			return
		var row: String = rows[y]
		if level.width == -1:
			level.width = row.length()
		elif row.length() != level.width:
			errors.append("layout row %d has length %d, expected %d" % [y, row.length(), level.width])
			return
	if level.width < 2 or level.height < 2:
		errors.append("layout must be at least 2x2")
		return

	var terrain := PackedByteArray()
	terrain.resize(level.width * level.height)
	for y in level.height:
		var row: String = rows[y]
		for x in level.width:
			var ch := row[x]
			var t := Terrain.from_char(ch)
			if t < 0:
				errors.append("unknown layout character '%s' at (%d, %d)" % [ch, x, y])
				continue
			terrain[y * level.width + x] = t
			if t == Terrain.SPAWN:
				level.spawn_cells.append(Vector2i(x, y))
			elif t == Terrain.BASE:
				level.base_cells.append(Vector2i(x, y))
	level.terrain = terrain
	if level.spawn_cells.is_empty():
		errors.append("layout has no spawn ('S')")
	if level.base_cells.is_empty():
		errors.append("layout has no base ('B')")
	else:
		level.goal_cell = _closest_to_centroid(level.base_cells)


static func _closest_to_centroid(cells: Array[Vector2i]) -> Vector2i:
	var sum := Vector2.ZERO
	for c in cells:
		sum += Vector2(c)
	var centroid := sum / cells.size()
	var best := cells[0]
	var best_d := INF
	for c in cells:
		var dist := Vector2(c).distance_squared_to(centroid)
		if dist < best_d:
			best_d = dist
			best = c
	return best


static func _read_int(d: Dictionary, key: String, default: int, min_v: int, max_v: int,
		errors: Array[String]) -> int:
	if not d.has(key):
		return default
	var v: Variant = d[key]
	if not _is_number(v) or float(v) != floor(float(v)):
		errors.append("'%s' must be an integer (got %s)" % [key, v])
		return default
	var i := int(v)
	if i < min_v or i > max_v:
		errors.append("'%s' = %d is outside [%d, %d]" % [key, i, min_v, max_v])
		return default
	return i


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _fail(result: Result, message: String) -> Result:
	result.errors.append(message)
	if report_errors:
		push_error("LevelLoader: " + message)
	return result
