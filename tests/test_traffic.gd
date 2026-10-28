extends SceneTree

## 交通测试：车道数学、确定性生成、出生安全、碰撞层、行驶路径，
## 以及“碰到汽车 → 当前订单失败”的主场景信号链。

const Generator = preload("res://scripts/world/road_generator.gd")
const WIDTHS := Vector3(40.0, 30.0, 18.0)
const MAP_SIZE := Vector2(1200.0, 1200.0)
const MAP_SEED := 1
const MAP_DENSITY := 1.0
const EPS := 0.001

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_lane_math()
	var network: RoadNetwork = Generator.generate(MAP_SIZE, MAP_SEED, MAP_DENSITY, WIDTHS)
	var city: CityContent = CityGenerator.generate(network)
	_expect(network.validate().valid, "交通测试路网校验失败")
	_expect(city.is_valid(network), "交通测试城市校验失败")
	_check_spawn(network, city)
	_check_movement(network, city)
	_check_limits(network, city)
	await _check_hit_area(network)
	await _check_main_scene()
	if _failed:
		printerr("FAIL traffic")
	else:
		print("PASS traffic")
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL traffic: ", message)


func _check_lane_math() -> void:
	_expect(
		is_equal_approx(TrafficRoute.lane_offset(40.0), 5.5),
		"主干路右车道偏移应为 5.5 米"
	)
	_expect(
		is_equal_approx(TrafficRoute.lane_offset(30.0), 4.125),
		"次干路右车道偏移应为 4.125 米"
	)
	_expect(
		is_equal_approx(TrafficRoute.lane_offset(18.0), 2.475),
		"支路右车道偏移应为 2.475 米"
	)
	var north := Vector2(0.0, -1.0)
	var east := Vector2(1.0, 0.0)
	_expect(
		TrafficRoute.right_of(north).distance_to(east) < EPS,
		"朝北时右侧应为东"
	)
	_expect(
		is_equal_approx(TrafficRoute.yaw_from_direction(north), 0.0),
		"朝北的偏航角应为 0"
	)
	_expect(
		is_equal_approx(TrafficRoute.yaw_from_direction(east), -PI * 0.5),
		"朝东的偏航角应为 -90 度"
	)


func _check_spawn(network: RoadNetwork, city: CityContent) -> void:
	var first := _make_spawner(network, city, 8)
	var second := _make_spawner(network, city, 8)
	var first_cars := first.get_cars()
	var second_cars := second.get_cars()
	_expect(first.get_vehicle_count() > 0, "应至少生成一辆汽车")
	_expect(
		first.get_vehicle_count() <= 8,
		"汽车数量不应超过 max_vehicles"
	)
	_expect(
		first.get_vehicle_count() == second.get_vehicle_count(),
		"相同路网/城市应生成相同数量的汽车"
	)
	_expect(
		_car_signatures(first_cars) == _car_signatures(second_cars),
		"相同路网/城市的汽车签名不确定"
	)

	var avoidance := _avoidance_points(city)
	var used_edges := {}
	for car in first_cars:
		_expect(car is AnimatableBody3D, "汽车应为 AnimatableBody3D")
		_expect(car.position.is_finite(), "汽车出生位置无效")
		_expect(
			absf(car.position.y - RoadNetwork.SURFACE_Y) < EPS,
			"汽车出生高度应贴地"
		)
		_expect(
			car.collision_layer == CollisionLayers.VEHICLE,
			"汽车碰撞层应为 VEHICLE"
		)
		_expect(
			car.collision_mask & CollisionLayers.PLAYER != 0,
			"汽车应能碰撞玩家"
		)
		_expect(
			car.collision_layer & CollisionLayers.WORLD_STATIC == 0,
			"汽车不应加入静态世界层"
		)
		_expect(
			not car.is_in_group(CollisionLayers.NAVIGATION_SOURCE_GROUP),
			"汽车不应成为导航源"
		)
		var edge_id := car.get_spawn_edge_id()
		_expect(edge_id >= 0 and edge_id < network.edges.size(), "汽车出生路段无效")
		_expect(not used_edges.has(edge_id), "同一路段生成了多辆汽车")
		used_edges[edge_id] = true

		var collision := car.get_node_or_null("CollisionShape3D") as CollisionShape3D
		_expect(
			collision != null and collision.shape is BoxShape3D,
			"汽车碰撞体应为 BoxShape3D"
		)
		_expect(
			car.get_node_or_null("Body") is MeshInstance3D,
			"汽车应有方块车身占位模型"
		)
		var hit_area := car.get_hit_area()
		_expect(hit_area != null, "汽车缺少命中 Area3D")
		if hit_area != null:
			_expect(hit_area.monitoring, "汽车命中 Area3D 应开启 monitoring")
			_expect(
				hit_area.collision_mask & CollisionLayers.PLAYER != 0,
				"汽车命中 Area3D 应检测玩家层"
			)
			_expect(
				hit_area.body_entered.get_connections().size() > 0,
				"汽车命中 Area3D 未连接信号"
			)
		for point in avoidance:
			var distance := Vector2(car.position.x, car.position.z).distance_to(
				Vector2(point.x, point.z)
			)
			_expect(
				distance >= TrafficSpawner.MIN_SPAWN_CLEARANCE_M - EPS,
				"汽车出生点距玩家/站点出生点过近：%.1f 米" % distance
			)

	first.free()
	second.free()


func _check_movement(network: RoadNetwork, city: CityContent) -> void:
	var first := _make_spawner(network, city, 6)
	var second := _make_spawner(network, city, 6)
	var cars_a := first.get_cars()
	var cars_b := second.get_cars()
	if cars_a.is_empty() or cars_b.is_empty():
		_expect(false, "移动测试缺少汽车")
		first.free()
		second.free()
		return
	var car: TrafficCar = cars_a[0]
	var other: TrafficCar = cars_b[0]
	var start_position := car.position
	var forward := car.get_forward()
	var points_before := car.get_path_point_count()
	car.advance(5.0)
	other.advance(5.0)
	var moved := car.position - start_position
	_expect(
		absf(moved.length() - 5.0) < 0.05,
		"汽车一帧前进距离应与传入距离一致"
	)
	_expect(absf(moved.y) < EPS, "汽车前进时不应改变高度")
	_expect(
		Vector2(moved.x, moved.z).normalized().dot(forward) > 0.99,
		"汽车应沿车头方向前进"
	)
	_expect(
		car.position.distance_to(other.position) < 0.01,
		"相同种子的汽车固定步长移动结果应一致"
	)

	car.advance(400.0)
	_expect(
		car.get_distance_travelled() >= 404.9,
		"汽车累计行驶距离未增加"
	)
	_expect(
		car.get_path_point_count() >= points_before,
		"汽车跨路段后路径应继续延伸"
	)
	_expect(car.position.is_finite(), "长距离行驶后位置无效")
	_expect(
		absf(car.position.x) <= MAP_SIZE.x * 0.5 + 200.0
		and absf(car.position.z) <= MAP_SIZE.y * 0.5 + 200.0,
		"汽车长距离行驶后离开了地图范围"
	)

	first.free()
	second.free()


func _check_limits(network: RoadNetwork, city: CityContent) -> void:
	var zero := TrafficSpawner.new()
	var zero_ready: Array = []
	zero.traffic_ready.connect(func() -> void: zero_ready.append(true))
	zero.max_vehicles = 0
	zero.build(network, city)
	_expect(zero.get_vehicle_count() == 0, "max_vehicles=0 时不应生成汽车")
	_expect(zero_ready.size() == 1, "max_vehicles=0 时也应发出 traffic_ready")
	zero.free()

	var empty := TrafficSpawner.new()
	var empty_ready: Array = []
	empty.traffic_ready.connect(func() -> void: empty_ready.append(true))
	empty.build(null)
	_expect(empty.get_vehicle_count() == 0, "空路网不应生成汽车")
	_expect(empty_ready.size() == 1, "空路网也应发出 traffic_ready")
	empty.free()

	var rebuild := _make_spawner(network, city, 4)
	var old_car: TrafficCar = rebuild.get_cars()[0]
	var old_count := rebuild.get_vehicle_count()
	rebuild.build(network, city)
	_expect(
		rebuild.get_vehicle_count() == old_count,
		"重复构建后汽车数量应保持一致"
	)
	_expect(
		not is_instance_valid(old_car),
		"重复构建应释放旧汽车节点"
	)
	rebuild.free()


func _check_hit_area(network: RoadNetwork) -> void:
	## 用一个真实的 Player 层物理体验证 Area3D 能检测到玩家，
	## 而不只是检查信号连接配置。
	var arena := Node3D.new()
	root.add_child(arena)
	var adjacency := TrafficRoute.build_adjacency(network)
	var edge: Dictionary = network.edges[0]
	var from_node := int(edge.a)
	var lane := TrafficRoute.edge_lane(network, 0, from_node)
	var car := TrafficCar.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	car.setup(
		network, adjacency, 0, from_node, float(lane.length) * 0.5,
		0.0, rng, Color.WHITE
	)
	car.set_simulation_enabled(false)
	arena.add_child(car)

	var body := CharacterBody3D.new()
	body.collision_layer = CollisionLayers.PLAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(shape)
	body.position = car.position
	arena.add_child(body)

	var hits: Array = []
	car.player_entered.connect(func(_body: Node3D) -> void: hits.append(true))
	for _frame in 20:
		await physics_frame
		if not hits.is_empty():
			break
	_expect(hits.size() == 1, "汽车命中 Area3D 未检测到 PLAYER 层物理体")
	arena.free()
	await process_frame


func _check_main_scene() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载主场景")
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	var traffic := main.get_node_or_null("TrafficSystem") as TrafficSpawner
	var orders := main.get_node_or_null("OrderSystem") as OrderManager
	var player := main.get_node_or_null("Player") as PlayerController
	var navigation := main.get_node_or_null("NavigationSystem") as NavigationService
	_expect(traffic != null and orders != null and player != null and navigation != null, "主场景缺少交通/订单/玩家/导航节点")
	if traffic == null or orders == null or player == null or navigation == null:
		main.queue_free()
		await process_frame
		return
	_expect(traffic.get_vehicle_count() > 0, "主场景应生成汽车")
	var cars := traffic.get_cars()
	if cars.is_empty():
		main.queue_free()
		await process_frame
		return
	var car: TrafficCar = cars[0]
	car.player_entered.emit(player)
	_expect(orders.get_session() == null, "开始界面被车碰到不应生成失败会话")

	for _frame in 120:
		if navigation.is_ready():
			break
		await physics_frame
	_expect(navigation.is_ready(), "导航在 120 个物理帧内未就绪")
	_expect(orders.start_game(), "开始游戏失败")
	for _frame in 120:
		if orders.is_offer_visible():
			break
		await physics_frame
	_expect(orders.is_offer_visible(), "未生成首单")
	_expect(orders.accept_order(), "接单失败")
	var session := orders.get_session()
	_expect(session != null and session.is_active(), "接单后订单应处于活动状态")
	if session == null:
		main.queue_free()
		await process_frame
		return
	var remaining_before := session.time_remaining
	var elapsed_before := session.get_elapsed_s()
	var hud := orders.get_hud()
	var finished_events: Array = []
	orders.order_finished.connect(func(success: bool) -> void: finished_events.append(success))

	player.set_physics_process(false)
	car.player_entered.emit(player)
	_expect(session.is_active(), "玩家暂停物理时不应判定撞车")
	player.set_physics_process(true)

	car.player_entered.emit(player)
	_expect(
		session.state == OrderSession.State.FAILED,
		"被车撞到后订单应失败"
	)
	_expect(
		session.get_failure_reason() == OrderSession.FailureReason.HIT_BY_CAR,
		"撞车失败原因错误"
	)
	_expect(
		is_equal_approx(session.time_remaining, remaining_before),
		"撞车失败不应清空剩余时间"
	)
	_expect(
		is_equal_approx(session.get_elapsed_s(), elapsed_before),
		"撞车失败不应改变已用时间"
	)
	_expect(finished_events == [false], "撞车应只结算一次失败")
	_expect(hud != null and hud.is_result_visible(), "撞车后应显示结算面板")
	if hud != null:
		_expect(hud.get_result_title() == "订单失败", "撞车结算标题错误")
		_expect(hud.get_result_body().contains("撞"), "撞车结算正文未说明原因")
	_expect(not player.controls_enabled, "撞车后应关闭玩家控制")
	car.player_entered.emit(player)
	_expect(finished_events.size() == 1, "撞车后不应重复结算")

	_expect(orders.handle_restart(), "撞车失败后 R 应进入下一单")
	for _frame in 120:
		if orders.is_offer_visible():
			break
		await physics_frame
	_expect(orders.is_offer_visible(), "撞车失败后未生成下一单")
	_expect(orders.accept_order(), "撞车失败后下一单接单失败")
	_expect(
		orders.get_session() != null and orders.get_session().is_active(),
		"撞车失败后下一单应能正常开始"
	)

	main.queue_free()
	await process_frame


func _make_spawner(
	network: RoadNetwork,
	city: CityContent,
	max_vehicles: int
) -> TrafficSpawner:
	var spawner := TrafficSpawner.new()
	spawner.max_vehicles = max_vehicles
	spawner.build(network, city)
	return spawner


func _avoidance_points(city: CityContent) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if city == null:
		return result
	if city.player_start != null:
		result.append(city.player_start.position)
	for start in city.player_starts:
		if start != null:
			result.append(start.position)
	for site in city.sites:
		if site != null and site.spawn_point != null:
			result.append(site.spawn_point.position)
	return result


func _car_signatures(cars: Array[TrafficCar]) -> Array[String]:
	var result: Array[String] = []
	for car in cars:
		result.append("%d|%.4f|%.4f|%.4f|%.4f|%.4f|%s" % [
			car.get_spawn_edge_id(),
			car.position.x,
			car.position.y,
			car.position.z,
			car.rotation.y,
			car.speed_mps,
			str(car.get_car_color()),
		])
	return result
