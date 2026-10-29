extends SceneTree

## 主场景冒烟测试：实例化 main.tscn，确认世界生成和导航就绪。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		printerr("FAIL could not load main scene")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	var world := main.get_node_or_null("World") as WorldGenerator
	var navigation := main.get_node_or_null("NavigationSystem") as NavigationService
	var player := main.get_node_or_null("Player") as PlayerController
	var orders := main.get_node_or_null("OrderSystem") as OrderManager
	var mini_map := main.get_node_or_null("MiniMapLayer/MiniMap") as Control
	var traffic := main.get_node_or_null("TrafficSystem") as TrafficSpawner
	var telemetry := main.get_node_or_null("Telemetry") as TelemetryClient
	var city_builder := main.get_node_or_null("World/CityBuilder")
	var world_environment := main.get_node_or_null("World/WorldEnvironment") as WorldEnvironment
	var sky_ready := (
		world_environment != null and world_environment.environment != null
		and world_environment.environment.sky != null
		and world_environment.environment.background_mode == Environment.BG_SKY
	)
	var ok := (
		world != null and world.network != null and world.city != null
		and navigation != null and player != null and orders != null and mini_map != null
		and traffic != null and traffic.get_vehicle_count() > 0 and traffic.get_vehicle_count() <= traffic.max_vehicles
		and telemetry != null and not telemetry.active and not telemetry.get_pending_events().is_empty()
		and city_builder != null and city_builder.get_child_count() > 0
		and sky_ready
		and bool(world.city_report.get("valid", false))
		and world.city.is_valid(world.network)
	)
	var initial_vehicle_count := 0
	var minimum_vehicle_count := 0
	var minimum_nearby_count := 0
	if ok:
		initial_vehicle_count = traffic.get_vehicle_count()
		minimum_vehicle_count = initial_vehicle_count
		minimum_nearby_count = traffic.get_nearby_vehicle_count(
			player.global_position
		)
		for _step in 8:
			for _frame in 15:
				await physics_frame
			minimum_vehicle_count = mini(
				minimum_vehicle_count,
				traffic.get_vehicle_count()
			)
			minimum_nearby_count = mini(
				minimum_nearby_count,
				traffic.get_nearby_vehicle_count(player.global_position)
			)
		ok = (
			minimum_nearby_count >= TrafficSpawner.MIN_NEARBY_VEHICLES
			and traffic.get_vehicle_count() >= initial_vehicle_count
			and traffic.get_vehicle_count() <= traffic.max_vehicles
		)
	if ok:
		for _frame in 120:
			if navigation.is_ready():
				break
			await physics_frame
		ok = navigation.is_ready() and orders.is_start_screen_visible()
	if ok:
		ok = orders.start_game()
	if ok:
		for _frame in 120:
			if orders.is_offer_visible():
				break
			await physics_frame
		ok = orders.is_offer_visible() and orders.get_session() == null
	if ok:
		ok = orders.accept_order()
		await physics_frame
	if ok:
		var start := orders.get_current_order().start.position
		var player_xz := Vector2(player.global_position.x, player.global_position.z)
		ok = player_xz.distance_to(Vector2(start.x, start.z)) < 1.0
	if ok:
		var session := orders.get_session()
		var target := session.get_target_position()
		var shown_target: Vector3 = mini_map.get("destination")
		var shown_route: PackedVector3Array = mini_map.get("route")
		ok = shown_target.is_equal_approx(target) and shown_route.size() >= 2
		if not ok:
			printerr("MINIMAP target=", shown_target, " expected=", target, " route_points=", shown_route.size())
		if ok:
			session.try_interact(target)
			await process_frame
			shown_target = mini_map.get("destination")
			ok = shown_target.is_equal_approx(session.get_target_position())
			if not ok:
				printerr("MINIMAP after pickup target=", shown_target, " expected=", session.get_target_position(), " state=", session.state)
	if ok:
		print(
			"PASS main scene nodes=", world.network.nodes.size(),
			" lots=", world.city.lots.size(),
			" sites=", world.city.sites.size(),
			" starts=", world.city.player_starts.size(),
			" vehicles=", traffic.get_vehicle_count(),
			" min_nearby=", minimum_nearby_count,
			" min_vehicles=", minimum_vehicle_count,
			" order_seed=", orders.get_order_seed(),
			" sky=", sky_ready
		)
	else:
		printerr("FAIL main scene world=", world != null, " network=", world != null and world.network != null,
			" city=", world != null and world.city != null,
			" city_valid=", world != null and not world.city_report.is_empty() and world.city_report.valid,
			" player=", player != null,
			" orders=", orders != null,
			" traffic=", traffic != null,
			" vehicles=", traffic != null and traffic.get_vehicle_count(),
			" min_nearby=", minimum_nearby_count,
			" min_vehicles=", minimum_vehicle_count,
			" order=", orders != null and orders.get_current_order() != null,
			" start_screen=", orders != null and orders.is_start_screen_visible(),
			" offer=", orders != null and orders.is_offer_visible(),
			" city_builder=", city_builder != null and city_builder.get_child_count() > 0,
			" sky=", sky_ready,
			" navigation_ready=", navigation != null and navigation.is_ready())
	main.queue_free()
	quit(0 if ok else 1)
