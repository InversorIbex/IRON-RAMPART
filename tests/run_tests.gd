extends SceneTree
## Headless test runner. Usage (from the project root):
##   godot --headless --import            # once, registers class_name scripts
##   godot --headless --script res://tests/run_tests.gd
## Exit code 0 = all passed, 1 = failures. See docs/TESTING.md.

const SUITES := [
	"res://tests/unit/test_grid_model.gd",
	"res://tests/unit/test_wallet.gd",
	"res://tests/unit/test_construction.gd",
	"res://tests/unit/test_level_loader.gd",
	"res://tests/unit/test_catalog.gd",
	"res://tests/unit/test_flow_field.gd",
	"res://tests/unit/test_enemies.gd",
	"res://tests/unit/test_scenes_smoke.gd",
]


func _initialize() -> void:
	# The root viewport is not inside the tree yet during _initialize(), so nodes
	# added now would not receive _ready(). Run once the main loop has started.
	_run.call_deferred()


func _run() -> void:
	var total := 0
	var failed := 0
	print("IRON RAMPART tests - Godot %s" % Engine.get_version_info()["string"])
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null:
			printerr("[LOAD FAIL] %s" % path)
			failed += 1
			continue
		print("\n== %s" % path.get_file())
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			var suite: RefCounted = script.new()
			if suite.has_method("set_tree"):
				suite.call("set_tree", self)
			suite.call("before_each")
			# Tests may be coroutines (use `await`); awaiting a plain call is a no-op.
			await suite.call(name)
			suite.call("after_each")
			var failures: Array[String] = suite.get("failures")
			if failures.is_empty():
				print("  [PASS] %s" % name)
			else:
				failed += 1
				print("  [FAIL] %s" % name)
				for f in failures:
					print("         - %s" % f)
	print("\n%d tests, %d passed, %d failed" % [total, total - failed, failed])
	quit(1 if failed > 0 else 0)
