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
	failed = _growth_checks() or failed
	quit(1 if failed else 0)


func _growth_checks() -> bool:
	var failed := false
	var previous: RoadNetwork = null
	for seed_value in range(32):
		for size in [Vector2(1200, 1200), Vector2(2400, 2400)]:
			var density := float(seed_value % 3) * 0.5
			var network := Generator.generate(size, seed_value, density, Vector3(40, 30, 18))
			var repeat := Generator.generate(size, seed_value, density, Vector3(40, 30, 18))
			var report := network.validate()
			if not report.valid or network.nodes != repeat.nodes or network.edges != repeat.edges:
				printerr("FAIL growth seed=", seed_value, " size=", size, " ", report.errors)
				failed = true
			if network.edges.size() < network.nodes.size():
				printerr("FAIL growth needs at least one cycle seed=", seed_value, " size=", size)
				failed = true
			if size.x == 2400:
				if previous != null and network.nodes == previous.nodes:
					printerr("FAIL different seeds have same geometry")
					failed = true
				previous = network
				var directions: Array[float] = []
				for edge in network.edges:
					if edge.kind == RoadNetwork.SECONDARY:
						directions.append(fposmod((network.nodes[edge.b] - network.nodes[edge.a]).angle(), PI))
				var distinct := false
				for first in directions:
					for second in directions:
						var difference := absf(wrapf(first - second, -PI * 0.5, PI * 0.5))
						distinct = distinct or difference > deg_to_rad(15.0)
				if not distinct:
					printerr("FAIL single global heading seed=", seed_value)
					failed = true
	# 任意角度相交、共线重叠、端点相接和完全分离。
	var geometry_cases := [
		[Vector2(-200, -200), Vector2(200, 200), Vector2(-200, 200), Vector2(200, -200), true],
		[Vector2(0, 0), Vector2(400, 400), Vector2(200, 200), Vector2(600, 600), true],
		[Vector2(0, 0), Vector2(400, 400), Vector2(400, 400), Vector2(600, 200), true],
		[Vector2(0, 0), Vector2(400, 400), Vector2(0, 10), Vector2(400, 410), false],
	]
	for sample in geometry_cases:
		if RoadNetwork._segments_touch_without_node(sample[0], sample[1], sample[2], sample[3]) != sample[4]:
			printerr("FAIL arbitrary-angle intersection predicate")
			failed = true
	# 事务式交叉口切分：旧路段被切成两段，并共享精确节点。
	var generator := Generator.new()
	generator.network = RoadNetwork.new()
	generator.network.map_size = Vector2(2400, 2400)
	generator._add_node(Vector2(0, -400))
	generator._add_node(Vector2(0, 400))
	generator._add_node(Vector2(-300, 0))
	generator._add_edge(0, 1, RoadNetwork.SECONDARY)
	var inserted := generator._insert(2, Vector2(300, 0), RoadNetwork.LOCAL)
	if (
		inserted.is_empty()
		or generator.network.nodes.size() != 4
		or generator.network.edges.size() != 3
		or generator.network.nodes[3] != Vector2.ZERO
	):
		printerr("FAIL intersection split transaction")
		failed = true
	var invalid := Generator.generate(Vector2(2400, 2400), 42, 0.5, Vector3(40, 30, 18))
	invalid.edges.append(invalid.edges[0].duplicate())
	if invalid.validate().valid:
		printerr("FAIL duplicate accepted")
		failed = true
	invalid = Generator.generate(Vector2(2400, 2400), 42, 0.5, Vector3(40, 30, 18))
	invalid.nodes[0] = Vector2(1201, 0)
	if invalid.validate().valid:
		printerr("FAIL out-of-bounds accepted")
		failed = true
	print("Growth sweep: 64 layouts + repeat determinism + angle/split/negative checks; passed=", not failed)
	return failed
