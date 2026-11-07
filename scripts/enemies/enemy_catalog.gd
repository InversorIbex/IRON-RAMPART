class_name EnemyCatalog
extends RefCounted
## Registry of enemy types (same pattern and reasons as StructureCatalog).

const PATHS := {
	&"infantry": "res://data/enemies/infantry.tres",
	&"light_vehicle": "res://data/enemies/light_vehicle.tres",
	&"heavy_tank": "res://data/enemies/heavy_tank.tres",
}

static var _cache: Dictionary = {}


static func has_id(id: StringName) -> bool:
	return PATHS.has(id)


## Loads and validates one enemy type. Returns null and reports on failure.
static func get_data(id: StringName) -> EnemyData:
	if _cache.has(id):
		return _cache[id]
	if not PATHS.has(id):
		push_error("EnemyCatalog: unknown enemy id '%s'" % id)
		return null
	var data := load(PATHS[id]) as EnemyData
	if data == null:
		push_error("EnemyCatalog: '%s' is not an EnemyData resource" % PATHS[id])
		return null
	var errors := data.validate()
	if String(data.id) != String(id):
		errors.append("id mismatch: catalog '%s' vs resource '%s'" % [id, data.id])
	if not errors.is_empty():
		push_error("EnemyCatalog: invalid '%s': %s" % [id, "; ".join(errors)])
		return null
	_cache[id] = data
	return data
