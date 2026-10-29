extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL traffic streaming: ", message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for seed_value in [118, 1, 42, 2026]:
		var network := RoadGenerator.generate(Vector2(2400,2400), seed_value, 0.5, Vector3(40,30,18), false)
		var city := CityGenerator.generate(network)
		var traffic := TrafficSpawner.new()
		traffic.max_vehicles = 18
		traffic.build(network, city)
		root.add_child(traffic)
		check(traffic.get_vehicle_count() > 0 and traffic.get_vehicle_count() <= 18, "nearby traffic density")
		var initial_cars := traffic.get_cars().duplicate()
		var first: TrafficCar = initial_cars[0]
		var model: Node3D = first.get_node("CarModel")
		check(model.get_child_count() == 1, "real car model missing")
		check(absf(model.rotation.y) > PI - 0.001, "car visual must face traffic forward")
		var shape: CollisionShape3D = first.get_node("CollisionShape3D")
		check(shape.shape.size.x > 0 and shape.shape.size.z <= 4.25, "model collision bounds")
		var old_position: Vector3 = first.position
		var start_count := traffic.get_vehicle_count()
		_set_first_car_green(traffic.get_traffic_signals(), first)
		for step in 200:
			await physics_frame
		check(first.get_distance_travelled() > 10.0 and first.position.distance_to(old_position) > 5.0, "vehicle did not accelerate and move")
		check(traffic.get_vehicle_count() <= 18, "active cap")
		var distance_before_recycle: float = first.get_distance_travelled()
		var distances: Array[float] = []
		for candidate in initial_cars:
			distances.append(candidate.get_distance_travelled())
		check(distances.max() > 10.0, "nearby flow stalled")
		var far := network.nodes[0]
		for point in network.nodes:
			if point.distance_to(Vector2(city.player_start.position.x, city.player_start.position.z)) > far.distance_to(Vector2(city.player_start.position.x, city.player_start.position.z)):
				far = point
		traffic.update_traffic(Vector3(far.x,0,far.y), true)
		check(traffic.get_recycled_count() > 0, "old area not recycled")
		check(traffic.get_pool_count() <= 18, "pool exceeds cap")
		check(traffic.get_vehicle_count() <= 18, "new area exceeds cap")
		var generated := traffic.get_vehicle_count()
		traffic.update_traffic(Vector3(far.x,0,far.y), false)
		check(traffic.get_vehicle_count() >= generated, "stable focus loses active cars")
		print("TRAFFIC seed=", seed_value, " initial=", start_count, " active=", traffic.get_vehicle_count(), " pooled=", traffic.get_pool_count(), " moved=", distance_before_recycle)
		traffic.free()
		await process_frame
	var model_network := RoadGenerator.generate(Vector2(2400,2400), 118, 0.5, Vector3(40,30,18), false)
	for index in TrafficCar.Catalog.MODELS.size():
		var info: Dictionary = TrafficCar.Catalog.MODELS[index]
		check(ResourceLoader.exists(info.path), "missing GLB " + info.path)
		var car := TrafficCar.new()
		var network := model_network
		if network.edges.is_empty():
			car.free()
			continue
		var edge: Dictionary = network.edges[0]
		var rng := RandomNumberGenerator.new()
		car.setup(network, TrafficRoute.build_adjacency(network), 0, edge.a, 25.0, 8.0, rng, Color.WHITE, index)
		check(car.model_index == index and car.has_node("CarModel"), "GLB variant not instantiated")
		check(absf(car.get_node("CarModel").rotation.y) > PI - 0.001, "GLB variant is visually reversed")
		car.free()
	print("PASS traffic streaming" if failures == 0 else "FAIL traffic streaming count=%d" % failures)
	quit(0 if failures == 0 else 1)


func _set_first_car_green(signals: TrafficSignals, car: TrafficCar) -> void:
	if not is_instance_valid(signals):
		return
	var junction := car.get_next_junction()
	if not junction.is_finite():
		return
	var node_id := signals.find_signal_node(
		junction,
		TrafficSignals.VEHICLE_APPROACH_DISTANCE_M
	)
	if node_id < 0 or not signals.is_signalized(node_id):
		return
	var forward := car.get_forward()
	for sample in 500:
		signals.set_phase_seconds(float(sample) * 0.1)
		if signals.get_vehicle_state(node_id, forward) == TrafficSignals.VehicleState.GREEN:
			return
