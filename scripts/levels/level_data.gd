class_name LevelData
extends RefCounted
## Parsed, validated mission definition. Built only by LevelLoader.

var id: String = ""
var display_name: String = ""
var width: int = 0
var height: int = 0
var cell_size: int = 64
var starting_credits: int = 0
var base_max_hp: int = 20
## Movement classes that may appear in this mission. Construction must keep a
## route open from every spawn to the base for each of them.
var movement_mask: int = MovementClass.ALL_GROUND
var terrain: PackedByteArray = PackedByteArray()
var spawn_cells: Array[Vector2i] = []
var base_cells: Array[Vector2i] = []
## Base cell used as pathfinding target (the base cell closest to its centroid).
var goal_cell: Vector2i = Vector2i.ZERO
## Structure ids offered in the build bar, in display order.
var available_structures: PackedStringArray = PackedStringArray()
## Whether the player may build during combat (validated against live units).
var allow_build_during_combat: bool = true
## Whether the player may remove structures during combat.
var allow_remove_during_combat: bool = false
## Extra fraction charged for new construction during combat (0.25 = +25 %).
var combat_build_surcharge: float = 0.25

# --- Mission identity and flow (Milestone 4) ---
var region: String = ""
var briefing: String = ""
## Visual identity key (terrain/ambience set). "desert" is the only one so far.
var theme: String = "desert"
## Optional names for spawn_cells (same order), used by wave data and intel.
var spawn_names: PackedStringArray = PackedStringArray()
var victory_type: String = "survive_all_waves"
## Seconds the post-wave debrief (WAVE_COMPLETED) lasts before PREPARATION.
var debrief_seconds: float = 3.0
var waves: Array[WaveData] = []


func spawn_name(index: int) -> String:
	return spawn_names[index] if index < spawn_names.size() else "spawn %d" % index


func terrain_at(cell: Vector2i) -> int:
	return terrain[cell.y * width + cell.x]
