class_name StructureCatalog
extends RefCounted
## Registry of placeable structures. Adding a structure = create its .tres in
## data/structures/ and add one line here. An explicit list (instead of
## scanning the folder) keeps exported builds deterministic: exported
## resources may be remapped/converted, so directory listings are unreliable.

const PATHS := {
	&"sandbags": "res://data/structures/sandbags.tres",
	&"concrete_wall": "res://data/structures/concrete_wall.tres",
	&"antitank_barrier": "res://data/structures/antitank_barrier.tres",
}


static func has_id(id: StringName) -> bool:
	return PATHS.has(id)


## Loads and validates one structure. Returns null and reports on failure.
static func load_structure(id: StringName) -> StructureData:
	if not PATHS.has(id):
		push_error("StructureCatalog: unknown structure id '%s'" % id)
		return null
	var res := load(PATHS[id])
	var data := res as StructureData
	if data == null:
		push_error("StructureCatalog: '%s' is not a StructureData resource" % PATHS[id])
		return null
	var errors := data.validate()
	if String(data.id) != String(id):
		errors.append("id mismatch: catalog '%s' vs resource '%s'" % [id, data.id])
	if not errors.is_empty():
		push_error("StructureCatalog: invalid '%s': %s" % [id, "; ".join(errors)])
		return null
	return data


## Loads the given ids in order, skipping (and reporting) invalid ones.
static func load_many(ids: PackedStringArray) -> Array[StructureData]:
	var result: Array[StructureData] = []
	for id in ids:
		var data := load_structure(StringName(id))
		if data != null:
			result.append(data)
	return result
