extends "res://tests/framework/test_case.gd"
## Validates the real data files in data/structures/.


func test_every_catalog_entry_loads_and_validates() -> void:
	for id in StructureCatalog.PATHS:
		var data := StructureCatalog.load_structure(id)
		assert_not_null(data, "structure '%s' failed to load" % id)
		if data != null:
			assert_eq(data.validate().size(), 0, "'%s' validation" % id)
			assert_eq(String(data.id), String(id))


func test_barriers_have_distinct_roles() -> void:
	# Design rule (GAME_DESIGN.md): no two barriers may block the same classes.
	var masks := {}
	for id in StructureCatalog.PATHS:
		var data := StructureCatalog.load_structure(id)
		if data == null or data.category != StructureData.Category.BARRIER:
			continue
		assert_false(masks.has(data.blocks_mask), "'%s' duplicates the role of '%s'" % [id, masks.get(data.blocks_mask)])
		masks[data.blocks_mask] = id


func test_specific_roles() -> void:
	var bags := StructureCatalog.load_structure(&"sandbags")
	var wall := StructureCatalog.load_structure(&"concrete_wall")
	var at := StructureCatalog.load_structure(&"antitank_barrier")
	if bags == null or wall == null or at == null:
		assert_true(false, "catalog incomplete")
		return
	assert_eq(bags.blocks_mask, MovementClass.INFANTRY | MovementClass.WHEELED)
	assert_eq(wall.blocks_mask, MovementClass.ALL_GROUND)
	assert_eq(at.blocks_mask, MovementClass.WHEELED | MovementClass.TRACKED)
	assert_true(bags.cost < wall.cost and wall.cost < at.cost, "cost ordering from the design brief")
