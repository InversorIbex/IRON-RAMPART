class_name Terrain
extends RefCounted
## Static terrain types and their rules. Terrain never changes during a mission;
## player structures live in GridModel's occupancy layer, not here.

const GROUND := 0 ## Walkable, buildable.
const ROCK := 1 ## Impassable for every ground class, not buildable.
const ROAD := 2 ## Walkable, not buildable (spawn mouths, fixed corridors).
const SPAWN := 3 ## Enemy entry point. Walkable, not buildable.
const BASE := 4 ## Player HQ footprint. Walkable (enemies enter it), not buildable.

## ASCII legend used by level files (docs/GAME_DESIGN.md#formato-de-niveles).
const LEGEND := {
	".": GROUND,
	"#": ROCK,
	"~": ROAD,
	"S": SPAWN,
	"B": BASE,
}


static func from_char(c: String) -> int:
	return LEGEND.get(c, -1)


static func is_buildable(terrain: int) -> bool:
	return terrain == GROUND


## Movement classes that cannot cross this terrain.
static func blocks_mask(terrain: int) -> int:
	if terrain == ROCK:
		return MovementClass.ALL_GROUND
	return MovementClass.NONE
