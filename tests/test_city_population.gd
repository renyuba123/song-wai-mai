extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1

func run() -> void:
	var network := RoadGenerator.generate(Vector2(2400, 2400), 118, 0.5, Vector3(40, 30, 18), false)
	var city := CityGenerator.generate(network)
	var scene: Node3D = load("res://scenes/city/city_population.tscn").instantiate()
	root.add_child(scene)
	var buildings := scene.get_node("GeneratedBuildings")
	var decorations := scene.get_node("GeneratedDecorations")
	var decoration_count := decorations.get_child_count()
	check(buildings.get_child_count() == 240, "Missing baked buildings")
	var footprints: Array[Rect2] = []
	for container in [buildings, decorations]:
		for item in container.get_children():
			var rect: Rect2 = item.get_meta("footprint")
			for previous in footprints:
				check(not rect.intersects(previous), "Overlapping model footprint")
			footprints.append(rect)
			for edge in network.edges:
				var a: Vector2 = network.nodes[edge.a]
				var b: Vector2 = network.nodes[edge.b]
				var corridor := Rect2(a.min(b), (a - b).abs()).grow(network.widths[edge.kind] * 0.5)
				check(not rect.intersects(corridor), "Model occupies road/sidewalk/junction")
	for site in city.sites:
		var model := buildings.get_node_or_null(String(site.id))
		check(model != null, "Unpopulated delivery site")
		if model == null:
			return
		check(model.has_node("EntryApproach"), "Missing entrance approach")
		var target := Vector2(site.spawn_point.position.x, site.spawn_point.position.z)
		for rect in footprints:
			check(not rect.grow(1.0).has_point(target), "Blocked delivery trigger")
		var footprint: Rect2 = model.get_meta("footprint")
		var door := footprint.get_center() + Vector2(-sin(site.facing_yaw), -cos(site.facing_yaw)) * footprint.size * 0.5
		for step in range(10):
			var sample := target.lerp(door, float(step) / 10.0)
			for rect in footprints:
				check(not rect.has_point(sample), "Obstructed delivery approach")
	# Preserve this fixture test independently of the new runtime streaming scene.
	scene.free()
	if failures > 0:
		quit(1)
		return
	print("PASS population: 32 sites, 240 buildings, ", decoration_count, " decorations; roads, approaches, saved Seed 118 fixture")
	quit(1 if failures > 0 else 0)
