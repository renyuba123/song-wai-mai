extends SceneTree

const Generator = preload("res://scripts/world/road_generator.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cases := [
		{"size": Vector2(2400, 2400), "seed": 42, "density": 0.5},
		{"size": Vector2(1200, 1200), "seed": 1, "density": 0.0},
		{"size": Vector2(3600, 2800), "seed": 73, "density": 1.0},
	]
	var failed := false
	for sample in cases:
		var widths := Vector3(40.0, 30.0, 18.0)
		var first: RoadNetwork = Generator.generate(sample.size, sample.seed, sample.density, widths)
		var again: RoadNetwork = Generator.generate(sample.size, sample.seed, sample.density, widths)
		var result := first.validate()
		var route := first.find_route(0, first.nodes.size() - 1)
		if not result.valid or first.nodes != again.nodes or first.edges != again.edges or route.is_empty():
			failed = true
			printerr("FAIL seed=", sample.seed, " errors=", result.errors)
		else:
			print("PASS seed=", sample.seed, " nodes=", result.nodes, " edges=", result.edges, " kinds=", result.kinds)
	var invalid_width: RoadNetwork = Generator.generate(Vector2(2400, 2400), 42, 0.5, Vector3(10.0, 30.0, 18.0))
	if invalid_width.validate().valid:
		failed = true
		printerr("FAIL invalid arterial width was accepted")
	var invalid_entrance: RoadNetwork = Generator.generate(Vector2(2400, 2400), 42, 0.5, Vector3(40.0, 30.0, 18.0))
	invalid_entrance.entrances.append({"edge_id": 0, "offset": 0.0})
	if invalid_entrance.validate().valid:
		failed = true
		printerr("FAIL entrance inside a junction was accepted")
	quit(1 if failed else 0)
