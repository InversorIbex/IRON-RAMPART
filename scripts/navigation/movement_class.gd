class_name MovementClass
extends RefCounted
## Movement capabilities as bit flags. A structure declares which classes it
## blocks (`StructureData.blocks_mask`); every class gets its own navigation layer.
##
## INFANTRY - soldiers on foot.
## WHEELED  - light vehicles (jeeps, trucks, APCs on wheels).
## TRACKED  - tanks and heavy tracked vehicles.

const NONE := 0
const INFANTRY := 1
const WHEELED := 2
const TRACKED := 4
const ALL_GROUND := 7

## Iteration order for every per-class loop.
const ALL := [INFANTRY, WHEELED, TRACKED]


static func to_name(bit: int) -> String:
	match bit:
		INFANTRY:
			return "infantry"
		WHEELED:
			return "wheeled"
		TRACKED:
			return "tracked"
	return "unknown"


static func from_name(class_name_text: String) -> int:
	match class_name_text.strip_edges().to_lower():
		"infantry":
			return INFANTRY
		"wheeled":
			return WHEELED
		"tracked":
			return TRACKED
	return NONE


static func mask_to_names(mask: int) -> PackedStringArray:
	var names := PackedStringArray()
	for bit in ALL:
		if mask & bit:
			names.append(to_name(bit))
	return names
