extends RefCounted
## Shared fixtures for unit tests. Levels are built from inline ASCII so each
## test documents its own map.

## 7x5 corridor: spawn left, base right, single 1-cell-wide gap in column 3.
const CHOKE_LAYOUT := [
	"...#...",
	"...#...",
	"S......",
	"...#..B",
	"...#...",
]

## Open 8x5 field.
const OPEN_LAYOUT := [
	"........",
	"........",
	"S......B",
	"........",
	"........",
]


static func level_dict(layout: Array, credits: int = 1000, rules: Dictionary = {}) -> Dictionary:
	return {
		"rules": rules,
		"format_version": 1,
		"id": "test_level",
		"name": "Test",
		"cell_size": 64,
		"starting_credits": credits,
		"movement_classes": ["infantry", "wheeled", "tracked"],
		"available_structures": ["sandbags", "concrete_wall", "antitank_barrier"],
		"layout": layout,
	}


static func make_session(layout: Array, credits: int = 1000, rules: Dictionary = {}) -> GameSession:
	var result := LevelLoader.parse_dict(level_dict(layout, credits, rules), "test")
	assert(result.is_ok(), "fixture level invalid: %s" % [result.errors])
	return GameSession.new(result.level)


static func structure(id: String, cost: int, blocks_mask: int, footprint := Vector2i.ONE) -> StructureData:
	var d := StructureData.new()
	d.id = StringName(id)
	d.display_name = id
	d.cost = cost
	d.max_hp = 100
	d.blocks_mask = blocks_mask
	d.footprint = footprint
	d.refund_ratio = 0.5
	return d


static func wall(cost: int = 25) -> StructureData:
	return structure("wall", cost, MovementClass.ALL_GROUND)
