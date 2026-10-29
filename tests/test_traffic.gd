extends SceneTree

## 交通测试：车道数学、确定性生成、出生安全、碰撞层、行驶路径，
## 以及“碰到汽车 → 当前订单失败”的主场景信号链。

const Generator = preload("res://scripts/world/road_generator.gd")
const WIDTHS := Vector3(40.0, 30.0, 18.0)
const MAP_SIZE := Vector2(1200.0, 1200.0)
const MAP_SEED := 1
const MAP_DENSITY := 1.0
const EPS := 0.001
const HORN_STREAM := preload("res://assets/audio/traffic_horn.ogg")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_lane_math()
	_check_speed_and_density_defaults()
	var network: RoadNetwork = Generator.generate(MAP_SIZE, MAP_SEED, MAP_DENSITY, WIDTHS)
	var city: CityContent = CityGenerator.generate(network)
	_expect(network.validate().valid, "交通测试路网校验失败")
	_expect(city.is_valid(network), "交通测试城市校验失败")
	_check_spawn(network, city)
	_check_nearby_vehicle_floor(network, city)
	_check_movement(network, city)
	_check_horn(network, city)
	await _check_distant_red_motion(network)
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


func _check_speed_and_density_defaults() -> void:
	var traffic := TrafficSpawner.new()
	_expect(
		TrafficSpawner.SPEEDS == [18.0, 13.5, 10.5],
		"主/次/支路基础车速应整体提高"
	)
	_expect(
		is_equal_approx(traffic.traffic_density, 3.0),
		"默认交通密度应为 3.0"
	)
	_expect(traffic.max_vehicles == 120, "默认车辆上限应为 120")
	_expect(is_equal_approx(traffic.max_speed_kmh, 72.0), "汽车限速上限应提高到 72 km/h")
	_expect(
		is_equal_approx(traffic.min_vehicle_spacing, 18.0),
		"高密度车流的默认跟车间距应为 18 米"
	)
	_expect(is_equal_approx(traffic.acceleration_mps2, 3.2), "汽车应使用更快的起步加速度")
	_expect(is_equal_approx(traffic.braking_mps2, 7.0), "提速后应同步增强制动能力")
	var fastest_cruise := TrafficSpawner.SPEEDS[0] * 1.1
	var stopping_distance := (
		fastest_cruise * fastest_cruise / (2.0 * traffic.braking_mps2)
	)
	_expect(
		stopping_distance <= TrafficSignals.RED_BRAKE_DISTANCE_M,
		"最高目标车速必须能在红灯制动区内停住"
	)
	var player := PlayerController.new()
	_expect(is_equal_approx(player.move_speed, 23.0), "玩家移动速度应提高到 23 m/s")
	player.free()
	traffic.free()


func _check_spawn(network: RoadNetwork, city: CityContent) -> void:
	var first := _make_spawner(network, city, 8)
	var second := _make_spawner(network, city, 8)
	var signals := first.get_traffic_signals()
	_expect(signals != null, "正常构建后应创建交通信号控制器")
	_expect(
		signals != null and not signals.get_signal_node_ids().is_empty(),
		"交通信号控制器应识别至少一个多岔路口"
	)
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
	var edge_counts := {}
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
		# High-density traffic may put several cars on one long road segment.
		edge_counts[edge_id] = int(edge_counts.get(edge_id, 0)) + 1

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

	for edge_id in edge_counts:
		var kind: int = network.edges[edge_id].kind
		_expect(
			int(edge_counts[edge_id]) <= first.get_edge_capacity(kind),
			"spawned cars must respect the configured per-edge capacity"
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


func _check_horn(network: RoadNetwork, city: CityContent) -> void:
	_expect(HORN_STREAM != null, "鸣笛音频资源未导入")
	if HORN_STREAM != null:
		_expect(HORN_STREAM.get_length() > 0.1, "鸣笛音频不应为空")

	var traffic := _make_spawner(network, city, 16)
	var player := PlayerController.new()
	root.add_child(player)
	root.add_child(traffic)
	traffic.set_player(player)
	var cars := traffic.get_cars()
	_expect(not cars.is_empty(), "鸣笛测试缺少车辆")
	if cars.is_empty():
		player.free()
		traffic.free()
		return

	var car := cars[0]
	var forward := car.get_forward()
	car.speed_mps = 8.0
	player.global_position = car.global_position
	player.controls_enabled = true
	player.velocity = Vector3(-forward.x, 0.0, -forward.y) * 12.0
	_expect(
		traffic.detect_horn_reason() == &"wrong_way",
		"与车流反向行驶时应识别为逆行鸣笛"
	)

	var signals := traffic.get_traffic_signals()
	var red_node := -1
	var red_direction := Vector2.ZERO
	if signals != null:
		for node_id in signals.get_signal_node_ids():
			for direction in [
				Vector2(0.0, -1.0),
				Vector2(1.0, 0.0),
				Vector2(0.0, 1.0),
				Vector2(-1.0, 0.0),
			]:
				if (
					signals.get_vehicle_state(node_id, direction)
					== TrafficSignals.VehicleState.RED
				):
					red_node = node_id
					red_direction = direction
					break
			if red_node >= 0:
				break
	_expect(red_node >= 0, "鸣笛测试未找到红灯相位")
	if red_node >= 0:
		player.global_position = signals.get_junction_position(red_node)
		var red_event := traffic._find_red_light_horn(red_direction)
		_expect(
			StringName(red_event.get("reason", &"")) == &"red_light",
			"红灯穿越路口时应识别为闯红灯鸣笛"
		)

	player.global_position = car.global_position - Vector3(
		forward.x, 0.0, forward.y
	) * 10.0
	var near_miss := traffic._find_near_miss_horn(forward, 15.0)
	_expect(
		StringName(near_miss.get("reason", &"")) == &"near_miss",
		"高速擦肩超车时应识别为贴近鸣笛"
	)

	var horn_player := traffic.get_horn_player()
	_expect(horn_player != null, "交通系统应创建 3D 鸣笛播放器")
	if horn_player != null:
		_expect(horn_player.stream == HORN_STREAM, "鸣笛播放器未加载鸣笛音频")
		_expect(is_equal_approx(horn_player.max_distance, 100.0), "鸣笛可听距离错误")
	var first_play := traffic._play_horn(&"wrong_way", player.global_position)
	var second_play := traffic._play_horn(&"red_light", player.global_position)
	_expect(first_play, "鸣笛播放器首次播放应成功")
	_expect(not second_play, "鸣笛播放期间不应叠播")
	_expect(traffic.get_horn_count() == 1, "鸣笛次数统计错误")
	_expect(traffic.get_last_horn_reason() == &"wrong_way", "最近鸣笛原因错误")
	_expect(traffic.is_horn_playing(), "播放后应进入鸣笛保护期")

	player.free()
	traffic.free()


func _check_distant_red_motion(network: RoadNetwork) -> void:
	## A forced red must only brake cars near the stop line. This exercises
	## the spawner update loop with real physics frames so a rule that zeroes
	## target speed at the full 60 m detection radius cannot regress silently.
	var traffic := TrafficSpawner.new()
	traffic.max_vehicles = 0
	traffic.build(network)
	var signals := traffic.get_traffic_signals()
	if signals == null:
		_expect(false, "远处红灯移动测试缺少信号控制器")
		traffic.free()
		return

	var signal_node := -1
	var edge_id := -1
	var from_node := -1
	for candidate_node in signals.get_signal_node_ids():
		for candidate_edge in network.edges.size():
			var edge: Dictionary = network.edges[candidate_edge]
			var candidate_from := -1
			if int(edge.a) == int(candidate_node):
				candidate_from = int(edge.b)
			elif int(edge.b) == int(candidate_node):
				candidate_from = int(edge.a)
			if candidate_from < 0:
				continue
			var lane := TrafficRoute.edge_lane(network, candidate_edge, candidate_from)
			if not lane.is_empty() and float(lane.length) >= 60.0:
				signal_node = int(candidate_node)
				edge_id = candidate_edge
				from_node = candidate_from
				break
		if signal_node >= 0:
			break
	if signal_node < 0:
		_expect(false, "远处红灯移动测试找不到足够的信号路口进口道")
		traffic.free()
		return

	var lane := TrafficRoute.edge_lane(network, edge_id, from_node)
	var car := TrafficCar.new()
	var car_rng := RandomNumberGenerator.new()
	car_rng.seed = 20261029
	car.setup(
		network,
		TrafficRoute.build_adjacency(network),
		edge_id,
		from_node,
		float(lane.length) - 45.0,
		8.0,
		car_rng,
		Color.WHITE
	)
	car.set_simulation_enabled(false)

	traffic.max_vehicles = 1
	var vehicles := Node3D.new()
	vehicles.name = "TestVehicles"
	traffic.add_child(vehicles)
	traffic._vehicles = vehicles
	vehicles.add_child(car)
	traffic._cars.append(car)
	traffic._focus = car.position
	root.add_child(traffic)

	signals.trigger_main_controller_red(signal_node, car.get_forward(), 60.0)
	var start_distance := car.get_distance_travelled()
	var junction := car.get_next_junction()
	_expect(
		car.position.distance_to(junction) > TrafficSignals.RED_BRAKE_DISTANCE_M,
		"回归车辆应从红灯制动区外开始"
	)
	_expect(
		not signals.should_vehicle_stop(
			signal_node,
			car.get_forward(),
			car.position.distance_to(junction)
		),
		"远处强制红灯不应要求车辆停车"
	)

	for _frame in 90:
		await physics_frame
	_expect(
		car.speed_mps > 2.0,
		"红灯制动区外的车辆被错误减速停车"
	)
	_expect(
		car.get_distance_travelled() - start_distance > 8.0,
		"红灯制动区外的车辆没有继续前进"
	)

	traffic.free()
	await process_frame


func _check_limits(network: RoadNetwork, city: CityContent) -> void:
	var zero := TrafficSpawner.new()
	var zero_ready: Array = []
	zero.traffic_ready.connect(func() -> void: zero_ready.append(true))
	zero.max_vehicles = 0
	zero.build(network, city)
	_expect(zero.get_vehicle_count() == 0, "max_vehicles=0 时不应生成汽车")
	_expect(zero_ready.size() == 1, "max_vehicles=0 时也应发出 traffic_ready")
	_expect(
		zero.get_traffic_signals() != null,
		"max_vehicles=0 时仍应创建交通信号控制器"
	)
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


func _check_nearby_vehicle_floor(
	network: RoadNetwork,
	city: CityContent
) -> void:
	var traffic := _make_spawner(network, city, 12)
	var center := city.player_start.position
	for car in traffic.get_cars().duplicate():
		var distance := Vector2(car.position.x - center.x, car.position.z - center.z).length()
		if distance <= TrafficSpawner.NEARBY_VEHICLE_RADIUS_M:
			traffic.recycle_car(car)
	_expect(
		traffic.get_nearby_vehicle_count(center) < TrafficSpawner.MIN_NEARBY_VEHICLES,
		"nearby-floor test should start below the configured minimum"
	)
	traffic.update_traffic(center, false)
	_expect(
		traffic.get_nearby_vehicle_count(center)
			>= TrafficSpawner.NEARBY_VEHICLE_TARGET,
		"traffic update should refill to the nearby vehicle target"
	)

	var moved_center := center
	for node in network.nodes:
		var candidate := Vector3(node.x, RoadNetwork.SURFACE_Y, node.y)
		if candidate.distance_to(center) > 180.0:
			moved_center = candidate
			break
	_expect(
		moved_center != center,
		"nearby-floor movement test should find a distant road node"
	)
	traffic.update_traffic(moved_center, true)
	var moved_nearby_count := traffic.get_nearby_vehicle_count(moved_center)
	_expect(
		moved_nearby_count >= TrafficSpawner.MIN_NEARBY_VEHICLES,
		"moving the player must keep the four-car hard floor, got %d"
			% moved_nearby_count
	)
	_expect(
		TrafficSpawner.NEARBY_VEHICLE_TARGET
			> TrafficSpawner.MIN_NEARBY_VEHICLES,
		"the nearby refill target must exceed the four-car hard floor"
	)
	traffic.free()


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
