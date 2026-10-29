extends SceneTree

## 行人测试：人行道数学、确定性生成、出生位置约束、沿人行道行走、
## 路口横穿后回到对侧、附近生成/远处回收、上限、碰撞层，
## 以及“行人不会触发撞车失败”的主场景行为。

const Generator = preload("res://scripts/world/road_generator.gd")
const WIDTHS := Vector3(40.0, 30.0, 18.0)
const MAP_SIZE := Vector2(1200.0, 1200.0)
const MAP_SEED := 1
const MAP_DENSITY := 1.0
const EPS := 0.01

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_sidewalk_math()
	var network: RoadNetwork = Generator.generate(MAP_SIZE, MAP_SEED, MAP_DENSITY, WIDTHS)
	var city: CityContent = CityGenerator.generate(network)
	_expect(network.validate().valid, "行人测试路网校验失败")
	_expect(city.is_valid(network), "行人测试城市校验失败")
	_check_spawn(network, city)
	_check_walk(network)
	_check_motion_speed(network)
	_check_crossing(network)
	_check_signal_crossing_lock(network)
	_check_recycle_and_cap(network, city)
	_check_limits(network, city)
	await _check_player_pedestrian_impact()
	await _check_no_hit(network)
	await _check_main_scene()
	if _failed:
		printerr("FAIL pedestrians")
	else:
		print("PASS pedestrians")
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL pedestrians: ", message)


func _check_sidewalk_math() -> void:
	_expect(
		is_equal_approx(RoadNetwork.sidewalk_offset(40.0), 15.5),
		"主干路人行道中心应为 15.5 米"
	)
	_expect(
		is_equal_approx(RoadNetwork.sidewalk_offset(30.0), 11.625),
		"次干路人行道中心应为 11.625 米"
	)
	_expect(
		is_equal_approx(RoadNetwork.sidewalk_offset(18.0), 6.975),
		"支路人行道中心应为 6.975 米"
	)
	var band := Pedestrian.sidewalk_band(40.0)
	_expect(
		is_equal_approx(band.x, 11.0) and is_equal_approx(band.y, 20.0),
		"主干路人行道带应为 11..20 米"
	)
	_expect(
		is_equal_approx(Pedestrian.lateral_for_band(40.0, 0.5), 15.5),
		"band_ratio=0.5 应落在人行道中心"
	)
	for ratio in [0.35, 0.65]:
		var lateral := Pedestrian.lateral_for_band(40.0, ratio)
		_expect(lateral > band.x + EPS, "band_ratio=%.2f 落在车行道内" % ratio)
		_expect(lateral < band.y - EPS, "band_ratio=%.2f 超出人行道带" % ratio)


func _check_spawn(network: RoadNetwork, city: CityContent) -> void:
	var first := _make_spawner(network, city, 10)
	var second := _make_spawner(network, city, 10)
	var first_pedestrians := first.get_pedestrians()
	var second_pedestrians := second.get_pedestrians()
	_expect(first.get_pedestrian_count() > 0, "应至少生成一个行人")
	_expect(
		first.get_pedestrian_count() <= 10,
		"行人数量不应超过 max_pedestrians"
	)
	_expect(
		first.get_pedestrian_count() == second.get_pedestrian_count(),
		"相同路网/城市应生成相同数量的行人"
	)
	_expect(
		_pedestrian_signatures(first_pedestrians) == _pedestrian_signatures(second_pedestrians),
		"相同路网/城市的行人签名不确定"
	)

	for pedestrian in first_pedestrians:
		_expect(pedestrian is AnimatableBody3D, "行人应为 AnimatableBody3D")
		_expect(pedestrian.position.is_finite(), "行人生成位置无效")
		_expect(
			absf(pedestrian.position.y - RoadNetwork.SURFACE_Y) < EPS,
			"行人生成高度应贴地"
		)
		_expect(
			pedestrian.collision_layer == CollisionLayers.PEDESTRIAN,
			"行人碰撞层应为 PEDESTRIAN"
		)
		_expect(pedestrian.collision_mask == 0, "行人不应主动检测碰撞")
		_expect(
			pedestrian.collision_layer & CollisionLayers.WORLD_STATIC == 0,
			"行人不应加入静态世界层"
		)
		_expect(
			not pedestrian.is_in_group(CollisionLayers.NAVIGATION_SOURCE_GROUP),
			"行人不应成为导航源"
		)
		var collision := pedestrian.get_node_or_null("CollisionShape3D") as CollisionShape3D
		_expect(
			collision != null and collision.shape is CapsuleShape3D,
			"行人碰撞体应为 CapsuleShape3D"
		)
		var model := pedestrian.get_node_or_null("PedestrianModel") as Node3D
		_expect(
			model != null,
			"行人应创建 PedestrianModel 视觉根节点"
		)
		var character := model.get_node_or_null("Character") as Node3D if model != null else null
		_expect(
			character != null,
			"行人视觉应实例化 GLB 人形模型"
		)
		if character != null:
			_expect(
				is_equal_approx(character.scale.x, Pedestrian.PEDESTRIAN_MODEL_SCALE),
				"行人模型缩放未按贴地高度设置"
			)
			_expect(
				absf(character.position.y - Pedestrian.PEDESTRIAN_MODEL_OFFSET_Y) < EPS,
				"行人模型脚底未对齐路面"
			)
			_expect(
				is_equal_approx(
					character.rotation_degrees.y,
					Pedestrian.PEDESTRIAN_MODEL_YAW_DEGREES
				),
				"行人模型正面未对齐运动方向"
			)
			var animation_player := character.get_node_or_null("AnimationPlayer") as AnimationPlayer
			_expect(
				animation_player != null
				and animation_player.has_animation(Pedestrian.PEDESTRIAN_WALK_ANIMATION),
				"行人模型应包含 Walk 动画"
			)
			_expect(
				animation_player != null
				and animation_player.current_animation
				== StringName(Pedestrian.PEDESTRIAN_WALK_ANIMATION),
				"行人模型应播放 Walk 动画"
			)
		_expect(
			model.get_node_or_null("FallbackCapsule") == null if model != null else false,
			"GLB 正常加载时不应创建胶囊占位视觉"
		)

		var edge_id := pedestrian.get_spawn_edge_id()
		_expect(edge_id >= 0 and edge_id < network.edges.size(), "行人生成路段无效")
		if edge_id < 0 or edge_id >= network.edges.size():
			continue
		var edge: Dictionary = network.edges[edge_id]
		var a: Vector2 = network.nodes[int(edge.a)]
		var b: Vector2 = network.nodes[int(edge.b)]
		var here := Vector2(pedestrian.position.x, pedestrian.position.z)
		var closest := Geometry2D.get_closest_point_to_segment(here, a, b)
		var lateral := here.distance_to(closest)
		var redline := float(network.widths[int(edge.kind)])
		var carriageway := redline * RoadNetwork.CARRIAGEWAY_RATIO
		_expect(
			lateral > carriageway * 0.5 + EPS,
			"行人生成在车行道中央附近：%.2f 米" % lateral
		)
		_expect(
			lateral <= redline * 0.5 + EPS,
			"行人生成超出人行道带：%.2f 米" % lateral
		)
		var along := a.distance_to(closest)
		var start_margin := Pedestrian.junction_half_width(network, int(edge.a))
		var end_margin := Pedestrian.junction_half_width(network, int(edge.b))
		var total := a.distance_to(b)
		_expect(
			along >= start_margin - EPS and along <= total - end_margin + EPS,
			"行人生成在交叉口范围内：%.2f 米" % along
		)

	first.free()
	second.free()


func _check_walk(network: RoadNetwork) -> void:
	var edge_id := _first_usable_edge(network)
	_expect(edge_id >= 0, "找不到可用于行走测试的路段")
	if edge_id < 0:
		return
	var adjacency := TrafficRoute.build_adjacency(network)
	var edge: Dictionary = network.edges[edge_id]
	var pedestrian := _make_pedestrian(
		network, adjacency, edge_id, int(edge.a), 8.0, 1, 0.0, 5
	)
	var start := pedestrian.position
	var lane_direction: Vector2 = (
		network.nodes[int(edge.b)] - network.nodes[int(edge.a)]
	).normalized()
	pedestrian.advance(5.0)
	var moved := pedestrian.position - start
	_expect(
		absf(moved.length() - 5.0) < 0.05,
		"行人固定步长前进距离应与传入距离一致"
	)
	_expect(absf(moved.y) < EPS, "行人前进时不应改变高度")
	_expect(
		Vector2(moved.x, moved.z).normalized().dot(lane_direction) > 0.99,
		"行人应沿人行道方向前进"
	)
	_expect(not pedestrian.is_crossing(), "短距离行走不应进入横穿状态")
	var redline := float(network.widths[int(edge.kind)])
	_expect(
		absf(pedestrian.get_lateral_offset()) > redline * RoadNetwork.CARRIAGEWAY_RATIO * 0.5,
		"行人在步行状态下应位于车行道之外"
	)
	pedestrian.free()


func _check_motion_speed(network: RoadNetwork) -> void:
	var edge_id := _first_usable_edge(network)
	_expect(edge_id >= 0, "找不到可用于速度测试的路段")
	if edge_id < 0:
		return
	var adjacency := TrafficRoute.build_adjacency(network)
	var edge: Dictionary = network.edges[edge_id]
	var pedestrian := _make_pedestrian(
		network, adjacency, edge_id, int(edge.a), 8.0, 1, 0.0, 23
	)
	var starting_speed := pedestrian.get_current_speed_mps()
	pedestrian.advance_motion(0.5, true)
	_expect(
		pedestrian.get_current_speed_mps() > starting_speed,
		"行人放行后应平滑加速"
	)
	_expect(
		pedestrian.get_current_speed_mps() <= pedestrian.get_speed_mps() + EPS,
		"行人实际速度不应超过目标步速"
	)
	for _step in 20:
		pedestrian.advance_motion(0.05, true)
	_expect(
		is_equal_approx(
			pedestrian.get_current_speed_mps(),
			pedestrian.get_speed_mps()
		),
		"行人持续行走后应达到目标步速"
	)

	for _step in 20:
		pedestrian.advance_motion(0.05, false)
	_expect(
		pedestrian.get_current_speed_mps() <= Pedestrian.MOTION_SPEED_EPS,
		"红灯等待时行人应平滑停车"
	)
	var stopped_position := pedestrian.position
	pedestrian.advance_motion(1.0, false)
	_expect(
		pedestrian.position.distance_to(stopped_position) < EPS,
		"行人停车后不应继续滑行车行道"
	)
	pedestrian.free()


func _check_crossing(network: RoadNetwork) -> void:
	var edge_id := _first_usable_edge(network)
	_expect(edge_id >= 0, "找不到可用于过街测试的路段")
	if edge_id < 0:
		return
	var adjacency := TrafficRoute.build_adjacency(network)
	var edge: Dictionary = network.edges[edge_id]
	var from_node := int(edge.a)
	var redline := float(network.widths[int(edge.kind)])
	var lateral := Pedestrian.lateral_for_band(redline, 0.5)
	var lane := Pedestrian.sidewalk_lane(network, edge_id, from_node, 1, lateral)
	if lane.is_empty():
		_expect(false, "过街测试路段缺少人行道")
		return
	var offset := maxf(0.0, float(lane.length) - 6.0)

	var pedestrian := _make_pedestrian(network, adjacency, edge_id, from_node, offset, 1, 1.0, 7)
	var side_before := pedestrian.get_side()
	var lateral_before := _signed_lateral(network, edge_id, pedestrian.position)
	var crossing_seen := false
	var crossing_end_seen := false
	var lateral_at_cross_end := 0.0
	for _step in 6000:
		pedestrian.advance(0.1)
		if pedestrian.is_crossing():
			crossing_seen = true
		elif crossing_seen:
			crossing_end_seen = true
			lateral_at_cross_end = _signed_lateral(network, edge_id, pedestrian.position)
			break
	_expect(crossing_seen, "行人走到路口后应发生过街")
	_expect(crossing_end_seen, "过街应在有限步内结束")
	_expect(lateral_before > 0.0, "过街前应在本侧人行道")
	_expect(lateral_at_cross_end < 0.0, "过街时应朝对侧移动")

	var returned_to_sidewalk := false
	for _step in 6000:
		pedestrian.advance(0.1)
		if pedestrian.is_crossing():
			continue
		var current_edge := pedestrian.get_current_edge_id()
		if current_edge < 0 or current_edge >= network.edges.size():
			continue
		var current_redline := float(network.widths[int(network.edges[current_edge].kind)])
		var band := Pedestrian.sidewalk_band(current_redline)
		var lateral_now := absf(pedestrian.get_lateral_offset())
		if (
			pedestrian.get_side() == -side_before
			and lateral_now >= band.x - EPS
			and lateral_now <= band.y + EPS
		):
			returned_to_sidewalk = true
			break
	_expect(returned_to_sidewalk, "过街后应回到对侧人行道")

	var first := _make_pedestrian(network, adjacency, edge_id, from_node, offset, 1, 1.0, 11)
	var second := _make_pedestrian(network, adjacency, edge_id, from_node, offset, 1, 1.0, 11)
	first.advance(50.0)
	second.advance(50.0)
	_expect(
		first.get_signature() == second.get_signature(),
		"相同种子的行人固定步长推进结果应一致"
	)
	pedestrian.free()
	first.free()
	second.free()


func _check_signal_crossing_lock(network: RoadNetwork) -> void:
	var signals := TrafficSignals.new()
	signals.build(network)
	_expect(
		not signals.get_signal_node_ids().is_empty(),
		"signal crossing test needs at least one signalized junction"
	)
	if signals.get_signal_node_ids().is_empty():
		signals.free()
		return

	var edge_id := -1
	var from_node := -1
	var signal_node := -1
	for candidate_id in network.edges.size():
		var edge: Dictionary = network.edges[candidate_id]
		for endpoint in [int(edge.a), int(edge.b)]:
			var other := TrafficRoute.other_node(edge, endpoint)
			if not signals.is_signalized(other):
				continue
			var redline := float(network.widths[int(edge.kind)])
			var lateral := Pedestrian.lateral_for_band(redline, 0.5)
			var lane := Pedestrian.sidewalk_lane(
				network,
				candidate_id,
				endpoint,
				1,
				lateral
			)
			if not lane.is_empty() and float(lane.length) > 12.0:
				edge_id = candidate_id
				from_node = endpoint
				signal_node = other
				break
		if edge_id >= 0:
			break
	_expect(edge_id >= 0 and signal_node >= 0, "no usable sidewalk reaches a signal")
	if edge_id < 0 or signal_node < 0:
		signals.free()
		return

	var edge: Dictionary = network.edges[edge_id]
	var redline := float(network.widths[int(edge.kind)])
	var lateral := Pedestrian.lateral_for_band(redline, 0.5)
	var lane := Pedestrian.sidewalk_lane(network, edge_id, from_node, 1, lateral)
	var adjacency := TrafficRoute.build_adjacency(network)
	var pedestrian := _make_pedestrian(
		network,
		adjacency,
		edge_id,
		from_node,
		float(lane.length) - 3.0,
		1,
		1.0,
		19
	)
	for _step in 2000:
		if pedestrian.needs_crossing_permission():
			break
		pedestrian.advance(0.05)

	_expect(
		pedestrian.needs_crossing_permission(),
		"pedestrian should wait at the signalized crossing"
	)
	_expect(
		pedestrian.get_active_crossing_node() == -1,
		"crossing must not become active before permission"
	)
	_expect(
		pedestrian.get_pending_crossing_node() == signal_node,
		"pending crossing should reference the signalized junction"
	)

	var red_phase := -1.0
	for sample in 100:
		var phase := float(sample) * 0.5
		signals.set_phase_seconds(phase)
		if not signals.can_pedestrian_cross(signal_node):
			red_phase = phase
			break
	_expect(red_phase >= 0.0, "a vehicle phase must keep pedestrians waiting")
	_expect(
		not signals.can_pedestrian_cross(signal_node),
		"pedestrian should not receive a walk phase during vehicle traffic"
	)

	var committed := pedestrian.commit_crossing()
	_expect(committed == signal_node, "commit_crossing should return the junction")
	_expect(
		pedestrian.get_active_crossing_node() == signal_node,
		"committed crossing must become active"
	)
	_expect(pedestrian.is_crossing(), "committed pedestrian should be crossing")

	pedestrian.advance(0.05)
	_expect(
		pedestrian.get_active_crossing_node() == signal_node,
		"a signal change must not interrupt an active crossing"
	)
	_expect(
		not signals.can_pedestrian_cross(signal_node),
		"test should still be in the red vehicle phase"
	)

	for _step in 2000:
		if pedestrian.get_active_crossing_node() == -1:
			break
		pedestrian.advance(0.05)
	_expect(
		pedestrian.get_active_crossing_node() == -1,
		"active crossing should clear after the crossing segment completes"
	)

	pedestrian.free()
	signals.free()


func _check_recycle_and_cap(network: RoadNetwork, city: CityContent) -> void:
	var spawner := _make_spawner(network, city, 10)
	_expect(spawner.get_pedestrian_count() > 0, "回收测试应先生成行人")
	_expect(
		spawner.get_pedestrian_count() <= 10,
		"回收测试行人数量不应超过上限"
	)
	var far_node := _farthest_node(network, city.player_start.position)
	var far := Vector3(far_node.x, RoadNetwork.SURFACE_Y, far_node.y)
	var recycled_before := spawner.get_recycled_count()
	spawner.update_pedestrians(far, true)
	_expect(
		spawner.get_recycled_count() > recycled_before,
		"焦点远离后应回收行人"
	)
	_expect(
		spawner.get_pedestrian_count() <= 10,
		"换区补生成后行人数量不应超过上限"
	)
	var outer := maxf(spawner.despawn_radius, spawner.spawn_radius + 30.0) + EPS
	for pedestrian in spawner.get_pedestrians():
		var distance := Vector2(
			pedestrian.position.x - far.x,
			pedestrian.position.z - far.z
		).length()
		_expect(distance <= outer, "活动行人应在回收半径内：%.1f 米" % distance)

	spawner.update_pedestrians(city.player_start.position, true)
	_expect(spawner.get_pedestrian_count() > 0, "回到玩家起点附近应重新生成行人")
	spawner.free()


func _check_limits(network: RoadNetwork, city: CityContent) -> void:
	var zero := PedestrianSpawner.new()
	zero.max_pedestrians = 0
	zero.build(network, [], city, [])
	_expect(zero.get_pedestrian_count() == 0, "max_pedestrians=0 时不应生成行人")
	zero.free()

	var empty := PedestrianSpawner.new()
	empty.build(null, [], null, [])
	_expect(empty.get_pedestrian_count() == 0, "空路网不应生成行人")
	empty.free()

	var rebuild := _make_spawner(network, city, 4)
	var rebuild_pedestrians := rebuild.get_pedestrians()
	_expect(not rebuild_pedestrians.is_empty(), "重复构建测试应先生成行人")
	if rebuild_pedestrians.is_empty():
		rebuild.free()
		return
	var old_pedestrian: Pedestrian = rebuild_pedestrians[0]
	var old_count := rebuild.get_pedestrian_count()
	rebuild.build(network, [], city, [])
	_expect(
		rebuild.get_pedestrian_count() == old_count,
		"重复构建后行人数量应保持一致"
	)
	_expect(
		not is_instance_valid(old_pedestrian),
		"重复构建应释放旧行人节点"
	)
	rebuild.free()

	var traffic := TrafficSpawner.new()
	traffic.max_vehicles = 6
	traffic.build(network, city)
	_expect(
		traffic.get_pedestrian_count() > 0,
		"TrafficSpawner 应默认创建行人管理器并生成行人"
	)
	_expect(
		traffic.get_pedestrians().size() == traffic.get_pedestrian_count(),
		"TrafficSpawner 行人访问器数量不一致"
	)
	traffic.max_pedestrians = 0
	traffic.build(network, city)
	_expect(
		traffic.get_pedestrian_count() == 0,
		"max_pedestrians=0 时 TrafficSpawner 不应生成行人"
	)
	traffic.free()


func _check_no_hit(network: RoadNetwork) -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var adjacency := TrafficRoute.build_adjacency(network)
	var edge_id := _first_usable_edge(network)
	var edge: Dictionary = network.edges[edge_id]
	var from_node := int(edge.a)
	var lane := TrafficRoute.edge_lane(network, edge_id, from_node)
	var car := TrafficCar.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	car.setup(
		network, adjacency, edge_id, from_node, float(lane.length) * 0.5,
		0.0, rng, Color.WHITE
	)
	car.set_simulation_enabled(false)
	arena.add_child(car)
	var hits: Array = []
	car.player_entered.connect(func(_body: Node3D) -> void: hits.append(true))
	_expect(
		car.get_hit_area().collision_mask & CollisionLayers.PEDESTRIAN == 0,
		"车辆命中 Area 不应检测行人层"
	)

	var pedestrian := _make_pedestrian(
		network, adjacency, edge_id, from_node,
		float(lane.length) * 0.5, 1, 0.0, 3
	)
	pedestrian.position = car.position
	arena.add_child(pedestrian)
	for _frame in 20:
		await physics_frame
	_expect(hits.is_empty(), "行人不应触发车辆命中玩家信号")
	arena.free()
	await process_frame


func _check_player_pedestrian_impact() -> void:
	_expect(
		CollisionLayers.PLAYER_MASK & CollisionLayers.PEDESTRIAN == 0,
		"player collision mask must not block pedestrians"
	)
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	_expect(packed != null, "could not load player scene for pedestrian impact")
	if packed == null:
		return

	var arena := Node3D.new()
	root.add_child(arena)
	var player := packed.instantiate() as PlayerController
	arena.add_child(player)
	await process_frame
	player.set_physics_process(false)
	player.velocity = Vector3(0.0, 0.0, -8.0)

	var hit_area := player.get_pedestrian_hit_area()
	_expect(hit_area != null, "player must create a pedestrian hit area")
	if hit_area != null:
		_expect(hit_area.monitoring, "pedestrian hit area must monitor bodies")
		_expect(
			hit_area.collision_mask == CollisionLayers.PEDESTRIAN,
			"pedestrian hit area must only scan the pedestrian layer"
		)

	var compensation_events: Array[int] = []
	player.pedestrian_hit.connect(
		func(_pedestrian: Pedestrian, amount: int) -> void:
			compensation_events.append(amount)
	)
	var first := Pedestrian.new()
	first.name = "ImpactTestPedestrian"
	first.position = Vector3(0.0, 0.0, -0.8)
	arena.add_child(first)
	for _frame in 30:
		await physics_frame
		if not compensation_events.is_empty():
			break

	_expect(
		compensation_events.size() == 1,
		"driving into a pedestrian should emit exactly one compensation event"
	)
	_expect(
		compensation_events.is_empty()
			or compensation_events[0] == PlayerController.PEDESTRIAN_COMPENSATION,
		"pedestrian compensation should be 1000"
	)
	_expect(
		is_equal_approx(
			player.get_pedestrian_speed_multiplier(),
			PlayerController.PEDESTRIAN_SLOWDOWN_MULTIPLIER
		),
		"hitting a pedestrian should slow the player for the configured duration"
	)
	_expect(
		not player.handle_pedestrian_impact(first),
		"the same pedestrian must not charge compensation twice"
	)
	_expect(
		compensation_events.size() == 1,
		"repeated contact with one pedestrian must not duplicate compensation"
	)

	var blocking_hit := player.move_and_collide(Vector3(0.0, 0.0, -2.4), true)
	_expect(blocking_hit == null, "pedestrian capsule must not physically block the player")

	var second := Pedestrian.new()
	second.name = "SecondImpactTestPedestrian"
	second.position = Vector3(20.0, 0.0, 20.0)
	arena.add_child(second)
	player.velocity = Vector3(0.0, 0.0, -4.0)
	_expect(
		player.handle_pedestrian_impact(second),
		"each different pedestrian should be chargeable once"
	)
	_expect(
		compensation_events == [
			PlayerController.PEDESTRIAN_COMPENSATION,
			PlayerController.PEDESTRIAN_COMPENSATION,
		],
		"two different pedestrians should add two separate compensation events"
	)

	for _step in 5:
		player._physics_process(0.6)
	_expect(
		is_equal_approx(player.get_pedestrian_speed_multiplier(), 1.0),
		"pedestrian slowdown should expire after 2.5 seconds"
	)

	arena.queue_free()
	await process_frame

	var overlap_arena := Node3D.new()
	root.add_child(overlap_arena)
	var overlap_player := packed.instantiate() as PlayerController
	overlap_arena.add_child(overlap_player)
	await process_frame
	overlap_player.set_physics_process(false)
	overlap_player.velocity = Vector3.ZERO
	var overlap_events: Array[int] = []
	overlap_player.pedestrian_hit.connect(
		func(_pedestrian: Pedestrian, amount: int) -> void:
			overlap_events.append(amount)
	)
	var overlapping_pedestrian := Pedestrian.new()
	overlapping_pedestrian.name = "OverlappingPedestrian"
	overlapping_pedestrian.position = Vector3(0.0, 0.0, -0.8)
	overlap_arena.add_child(overlapping_pedestrian)
	for _frame in 30:
		await physics_frame
	_expect(
		overlap_events.is_empty(),
		"a stationary player must not be charged for an overlapping pedestrian"
	)
	overlap_player.velocity = Vector3(0.0, 0.0, -8.0)
	overlap_player._process_pending_pedestrian_hits()
	_expect(
		overlap_events == [PlayerController.PEDESTRIAN_COMPENSATION],
		"accelerating out of an overlap must charge exactly once"
	)
	overlap_arena.queue_free()
	await process_frame


func _check_main_scene() -> void:
	GameSeeds.pin(118, 1)
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载主场景")
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	var traffic := main.get_node_or_null("TrafficSystem") as TrafficSpawner
	var orders := main.get_node_or_null("OrderSystem") as OrderManager
	if traffic == null:
		_expect(false, "主场景缺少 TrafficSystem")
		main.queue_free()
		await process_frame
		return
	var player := main.get_node_or_null("Player") as PlayerController
	var economy := main.get("_economy") as EconomyHUD
	_expect(player != null, "主场景缺少 Player")
	_expect(economy != null, "主场景缺少 EconomyHUD")
	_expect(orders != null, "主场景缺少 OrderSystem")
	if player != null and economy != null:
		var balance_before := economy.get_balance()
		var pedestrian := Pedestrian.new()
		player.pedestrian_hit.emit(
			pedestrian,
			PlayerController.PEDESTRIAN_COMPENSATION
		)
		_expect(
			economy.get_total_compensation()
				== PlayerController.PEDESTRIAN_COMPENSATION,
			"pedestrian compensation should be added to the economy"
		)
		_expect(
			economy.get_balance()
				== balance_before - PlayerController.PEDESTRIAN_COMPENSATION,
			"pedestrian compensation should reduce the economy balance"
		)
		if orders != null and orders.get_hud() != null:
			_expect(
				orders.get_hud().get_toast_text().contains("赔偿 1000 元"),
				"pedestrian hit should show a 1000 yuan compensation toast"
			)
			_expect(
				orders.get_hud().is_toast_visible(),
				"pedestrian compensation toast should be visible"
			)
		pedestrian.free()
	_expect(
		traffic.get_pedestrian_spawner() != null,
		"TrafficSpawner 应由代码创建行人管理器"
	)
	_expect(traffic.get_pedestrian_count() > 0, "主场景应生成行人")
	_expect(
		traffic.get_pedestrian_count() <= traffic.max_pedestrians,
		"主场景行人数量不应超过 max_pedestrians"
	)
	var hits: Array = []
	traffic.player_hit.connect(
		func(_car: TrafficCar, _position: Vector3) -> void: hits.append(true)
	)
	for _frame in 10:
		await physics_frame
	_expect(hits.is_empty(), "行人不应触发撞车失败")
	main.queue_free()
	await process_frame


func _make_spawner(
	network: RoadNetwork, city: CityContent, max_pedestrians: int
) -> PedestrianSpawner:
	var spawner := PedestrianSpawner.new()
	spawner.max_pedestrians = max_pedestrians
	spawner.build(network, [], city, [])
	return spawner


func _make_pedestrian(
	network: RoadNetwork,
	adjacency: Array,
	edge_id: int,
	from_node: int,
	offset: float,
	side: int,
	cross_chance: float,
	rng_seed: int
) -> Pedestrian:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var pedestrian := Pedestrian.new()
	pedestrian.setup(
		network, adjacency, edge_id, from_node, offset, side, 0.5,
		1.4, rng, 0, cross_chance
	)
	return pedestrian


func _first_usable_edge(network: RoadNetwork) -> int:
	for edge_id in network.edges.size():
		var edge: Dictionary = network.edges[edge_id]
		var redline := float(network.widths[int(edge.kind)])
		var lateral := Pedestrian.lateral_for_band(redline, 0.5)
		var lane := Pedestrian.sidewalk_lane(network, edge_id, int(edge.a), 1, lateral)
		if not lane.is_empty() and float(lane.length) > 24.0:
			return edge_id
	return -1


func _signed_lateral(network: RoadNetwork, edge_id: int, position: Vector3) -> float:
	if edge_id < 0 or edge_id >= network.edges.size():
		return 0.0
	var edge: Dictionary = network.edges[edge_id]
	var a: Vector2 = network.nodes[int(edge.a)]
	var b: Vector2 = network.nodes[int(edge.b)]
	var direction := (b - a).normalized()
	if direction.length_squared() < 0.000001:
		return 0.0
	var left := Vector2(direction.y, -direction.x)
	return (Vector2(position.x, position.z) - a).dot(left)


func _farthest_node(network: RoadNetwork, origin: Vector3) -> Vector2:
	var best := Vector2.ZERO
	var best_distance := -1.0
	var origin_xz := Vector2(origin.x, origin.z)
	for node in network.nodes:
		var distance := node.distance_to(origin_xz)
		if distance > best_distance:
			best_distance = distance
			best = node
	return best


func _pedestrian_signatures(pedestrians: Array[Pedestrian]) -> Array[String]:
	var result: Array[String] = []
	for pedestrian in pedestrians:
		result.append(pedestrian.get_signature())
	return result
