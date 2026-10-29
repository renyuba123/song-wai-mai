extends SceneTree

## 阶段一城市测试：确定性、契约校验、反向用例、主场景装配和站点可达性。

const Generator = preload("res://scripts/world/road_generator.gd")
const WIDTHS := Vector3(40.0, 30.0, 18.0)

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_city(42, Vector2(2400.0, 2400.0), 0.5)
	_check_city(1, Vector2(1200.0, 1200.0), 1.0)
	_check_different_seed()
	_check_negative_cases()
	await _check_main_scene()
	if _failed:
		printerr("FAIL city")
	else:
		print("PASS city")
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL ", message)


func _make_city(seed_value: int, map_size: Vector2, density: float) -> Dictionary:
	var network: RoadNetwork = Generator.generate(map_size, seed_value, density, WIDTHS)
	var city: CityContent = CityGenerator.generate(network)
	return {"network": network, "city": city}


func _check_city(seed_value: int, map_size: Vector2, density: float) -> void:
	var first := _make_city(seed_value, map_size, density)
	var second := _make_city(seed_value, map_size, density)
	var network: RoadNetwork = first.network
	var city: CityContent = first.city
	var other_city: CityContent = second.city
	var other_network: RoadNetwork = second.network

	_expect(network.validate().valid, "种子 %d 的路网校验失败" % seed_value)
	_expect(city.is_valid(network), "种子 %d 的城市校验失败：%s" % [seed_value, city.validate(network)])
	_expect(city.seed_value == seed_value, "城市种子与请求不一致")
	_expect(city.lots == other_city.lots, "同种子的地块不确定")
	_expect(city.buildings == other_city.buildings, "同种子的建筑不确定")
	_expect(network.entrances == other_network.entrances, "同种子的出入口不确定")
	_expect(_site_signatures(city) == _site_signatures(other_city), "同种子的站点不确定")
	_expect(
		_spawn_signatures(city.player_starts) == _spawn_signatures(other_city.player_starts),
		"同种子的玩家起点列表不确定"
	)
	_expect(
		_spawn_signature(city.player_start) == _spawn_signature(city.player_starts[0]),
		"player_start 应与 player_starts 首项一致"
	)

	_expect(not city.lots.is_empty(), "城市没有地块")
	_expect(city.lots.size() <= CityGenerator.MAX_LOTS, "地块数量超过上限")
	_expect(city.buildings.size() == city.lots.size(), "建筑数量应与地块一致")
	if map_size.x >= 2400.0 and map_size.y >= 2400.0:
		# 斜向、分级生长的街区比旧正交网格更长更宽，可达的临街地块随之减少；
		# 仍要求大地图保持千级地块，避免城市变空。
		_expect(city.lots.size() >= 1000, "大地图地块密度不足：%d" % city.lots.size())
	_expect(not network.entrances.is_empty(), "城市没有出入口")
	_expect(city.get_entrance_lots().size() >= 2, "至少需要两个入口地块")

	var entrance_edges := {}
	var merchant_count := 0
	var customer_count := 0
	for entrance in network.entrances:
		for key in CityContent.ENTRANCE_KEYS:
			_expect(entrance.has(key), "出入口缺少字段 %s" % key)
		var edge_id := int(entrance.edge_id)
		_expect(not entrance_edges.has(edge_id), "路段 %d 有多个出入口" % edge_id)
		entrance_edges[edge_id] = true
		var edge: Dictionary = network.edges[edge_id]
		var length: float = network.nodes[edge.a].distance_to(network.nodes[edge.b])
		var required := network.get_entrance_setback(edge_id)
		_expect(
			minf(float(entrance.offset), length - float(entrance.offset)) >= required - RoadNetwork.EPS,
			"出入口退让不足"
		)
		_expect(float(entrance.width) > 0.0, "出入口宽度无效")

	for site in city.sites:
		if site.kind == CitySite.Kind.MERCHANT:
			merchant_count += 1
		elif site.kind == CitySite.Kind.RESIDENTIAL:
			customer_count += 1
		_expect(site.is_valid(network), "站点 %s 契约无效" % site.id)
		_expect(site.lot_id >= 0 and site.lot_id < city.lots.size(), "站点 %s 的地块无效" % site.id)
		if site.lot_id < 0 or site.lot_id >= city.lots.size():
			continue
		var lot: Dictionary = city.lots[site.lot_id]
		_expect(StringName(lot.site_id) == site.id, "地块与站点引用不一致")
		_expect(int(lot.entrance_id) >= 0, "站点地块没有入口")
		_expect(int(lot.building_id) >= 0, "站点地块没有建筑")
		if int(lot.entrance_id) >= 0:
			var entrance: Dictionary = network.entrances[int(lot.entrance_id)]
			_expect(int(entrance.lot_id) == site.lot_id, "入口与站点地块不一致")
		_expect(absf(site.spawn_point.lateral_offset_m) > RoadNetwork.EPS, "站点出生点在道路中心")
		_expect(
			not _point_in_building(Vector2(site.spawn_point.position.x, site.spawn_point.position.z), city),
			"站点 %s 的出生点落在建筑内" % site.id
		)
	_expect(merchant_count >= 1 and merchant_count <= CityGenerator.MAX_MERCHANTS, "商家数量超出范围")
	_expect(customer_count >= 1 and customer_count <= CityGenerator.MAX_CUSTOMERS, "顾客数量超出范围")

	var start := city.player_start
	_expect(start != null, "城市缺少玩家起点")
	if start != null:
		_expect(start.is_valid(network), "玩家起点契约无效：%s" % str(start.validate(network)))
		_expect(start.kind == SpawnPoint.Kind.PLAYER_START, "玩家起点类型错误")
		_expect(start.site_id == &"", "玩家起点不应关联站点")
		_expect(absf(start.lateral_offset_m) > RoadNetwork.EPS, "玩家起点在道路中心")
		_expect(network.edges[start.road_edge_id].kind != RoadNetwork.LOCAL, "玩家起点不应在支路")
	_expect(city.player_starts.size() >= 2, "城市至少需要两个安全玩家起点")
	_expect(
		city.player_starts.size() <= CityGenerator.MAX_PLAYER_STARTS,
		"玩家起点数量超过上限"
	)
	for index in city.player_starts.size():
		var candidate := city.player_starts[index]
		_expect(candidate != null, "玩家起点 %d 为空" % index)
		if candidate == null:
			continue
		_expect(
			candidate.is_valid(network),
			"玩家起点 %d 契约无效：%s" % [index, str(candidate.validate(network))]
		)
		_expect(candidate.kind == SpawnPoint.Kind.PLAYER_START, "玩家起点 %d 类型错误" % index)
		_expect(candidate.site_id == &"", "玩家起点 %d 不应关联站点" % index)
		_expect(absf(candidate.lateral_offset_m) > RoadNetwork.EPS, "玩家起点 %d 在道路中心" % index)
		_expect(
			network.edges[candidate.road_edge_id].kind != RoadNetwork.LOCAL,
			"玩家起点 %d 不应在支路" % index
		)
		_expect(
			not _point_in_building(Vector2(candidate.position.x, candidate.position.z), city),
			"玩家起点 %d 落在建筑内" % index
		)
	print(
		"PASS city seed=%d lots=%d buildings=%d entrances=%d sites=%d" % [
			seed_value, city.lots.size(), city.buildings.size(),
			network.entrances.size(), city.sites.size()
		]
	)


func _check_different_seed() -> void:
	var first := _make_city(42, Vector2(2400.0, 2400.0), 0.5)
	var other := _make_city(43, Vector2(2400.0, 2400.0), 0.5)
	var first_city: CityContent = first.city
	var other_city: CityContent = other.city
	_expect(
		first_city.lots != other_city.lots
		or _site_signatures(first_city) != _site_signatures(other_city),
		"不同城市种子应得到不同内容"
	)


func _check_negative_cases() -> void:
	var data := _make_city(42, Vector2(2400.0, 2400.0), 0.5)
	var network: RoadNetwork = data.network
	var city: CityContent = data.city
	network.entrances[0]["lot_id"] = 9999
	_expect(not city.is_valid(network), "入口 lot_id 无效时城市应校验失败")

	data = _make_city(42, Vector2(2400.0, 2400.0), 0.5)
	network = data.network
	city = data.city
	network.entrances.append(network.entrances[0].duplicate(true))
	_expect(not city.is_valid(network), "同路段重复入口时城市应校验失败")

	data = _make_city(42, Vector2(2400.0, 2400.0), 0.5)
	network = data.network
	city = data.city
	city.lots[1]["rect"] = city.lots[0]["rect"]
	_expect(not city.is_valid(network), "地块重叠时城市应校验失败")

	data = _make_city(42, Vector2(2400.0, 2400.0), 0.5)
	network = data.network
	city = data.city
	var moved: Rect2 = city.buildings[0].rect
	moved.position += Vector2(1000.0, 1000.0)
	city.buildings[0]["rect"] = moved
	_expect(not city.is_valid(network), "建筑超出地块时城市应校验失败")

	data = _make_city(42, Vector2(2400.0, 2400.0), 0.5)
	network = data.network
	city = data.city
	var site_lot: Dictionary = city.lots[city.sites[0].lot_id]
	site_lot["entrance_id"] = -1
	_expect(not city.is_valid(network), "站点地块缺少入口时城市应校验失败")

	data = _make_city(42, Vector2(2400.0, 2400.0), 0.5)
	network = data.network
	city = data.city
	var start := city.player_start
	start.lateral_offset_m = 0.0
	var edge: Dictionary = network.edges[start.road_edge_id]
	var a: Vector2 = network.nodes[edge.a]
	var b: Vector2 = network.nodes[edge.b]
	var length := a.distance_to(b)
	var point := a.lerp(b, start.road_offset_m / length)
	start.position = Vector3(point.x, RoadNetwork.SURFACE_Y, point.y)
	_expect(start.is_valid(network), "用于测试的居中玩家起点本身应合法")
	_expect(not city.is_valid(network), "玩家起点在道路中心时城市应校验失败")

	data = _make_city(42, Vector2(2400.0, 2400.0), 0.5)
	network = data.network
	city = data.city
	var duplicate_start := city.player_starts[0].duplicate(true) as SpawnPoint
	city.player_starts.append(duplicate_start)
	_expect(not city.is_valid(network), "重复玩家起点时城市应校验失败")

	data = _make_city(42, Vector2(2400.0, 2400.0), 0.5)
	network = data.network
	city = data.city
	city.player_start = city.player_starts[1]
	_expect(not city.is_valid(network), "player_start 与首项不一致时城市应校验失败")


func _check_main_scene() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载主场景")
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	var world := main.get_node_or_null("World") as WorldGenerator
	var navigation := main.get_node_or_null("NavigationSystem") as NavigationService
	var player := main.get_node_or_null("Player") as PlayerController
	var orders := main.get_node_or_null("OrderSystem") as OrderManager
	if (
		world == null or navigation == null or player == null
		or orders == null or world.city == null
	):
		_expect(false, "主场景缺少世界、城市、导航、订单系统或玩家")
		main.queue_free()
		await process_frame
		return

	_expect(world.city.is_valid(world.network), "主场景城市校验失败：%s" % str(world.city.validate(world.network)))
	_expect(bool(world.city_report.get("valid", false)), "主场景城市报告未通过")
	var city_builder := main.get_node_or_null("World/CityBuilder")
	_expect(city_builder != null and city_builder.get_child_count() > 0, "CityBuilder 没有生成节点")
	var road_body := main.get_node_or_null("World/RoadBuilder/RoadCollision") as StaticBody3D
	var building_body := main.get_node_or_null("World/CityBuilder/BuildingCollision") as StaticBody3D
	var sidewalk_body := main.get_node_or_null("World/CityBuilder/SidewalkCollision") as StaticBody3D
	_expect(road_body != null and road_body.is_in_group(CollisionLayers.NAVIGATION_SOURCE_GROUP), "道路碰撞体应在导航源组")
	_expect(building_body != null and not building_body.is_in_group(CollisionLayers.NAVIGATION_SOURCE_GROUP), "建筑碰撞体不应在导航源组")
	_expect(sidewalk_body != null and sidewalk_body.is_in_group(CollisionLayers.NAVIGATION_SOURCE_GROUP), "人行道碰撞体应在导航源组")

	var ready := navigation.is_ready()
	var current_order: DeliveryOrder = null
	for _frame in 120:
		ready = navigation.is_ready()
		if ready:
			break
		await physics_frame
	_expect(ready, "导航在 120 个物理帧内未就绪")
	_expect(orders.is_start_screen_visible(), "启动时应显示开始界面")
	_expect(orders.start_game(), "开始按钮应启动游戏")
	for _frame in 120:
		current_order = orders.get_current_order()
		if current_order != null and orders.is_offer_visible():
			break
		await physics_frame
	_expect(current_order != null, "订单系统在 120 个物理帧内没有生成首单")
	_expect(orders.accept_order(), "接单按钮应开始订单")
	await physics_frame
	if ready and current_order != null:
		var start_xz := Vector2(current_order.start.position.x, current_order.start.position.z)
		var player_xz := Vector2(player.global_position.x, player.global_position.z)
		_expect(player_xz.distance_to(start_xz) < 1.0, "玩家没有出生在订单起点")

		var from := navigation.get_closest_point(world.city.player_start.position)
		_expect(from.is_finite(), "玩家起点无法吸附到导航网格")
		for site in world.city.sites:
			var target := navigation.get_closest_point(site.spawn_point.position)
			_expect(target.is_finite(), "站点 %s 无法吸附到导航网格" % site.id)
			var path := navigation.find_path(from, target)
			_expect(path.size() >= 2, "站点 %s 不可达" % site.id)
			if path.size() >= 2:
				_expect(NavigationService.get_path_length(path) > 0.0, "站点 %s 的路径长度无效" % site.id)

		var first_merchant: CitySite = null
		var first_customer: CitySite = null
		for site in world.city.sites:
			if site.kind == CitySite.Kind.MERCHANT and first_merchant == null:
				first_merchant = site
			elif site.kind == CitySite.Kind.RESIDENTIAL and first_customer == null:
				first_customer = site
		for start in world.city.player_starts:
			var start_from := navigation.get_closest_point(start.position)
			_expect(start_from.is_finite(), "玩家起点无法吸附到导航网格")
			for site in [first_merchant, first_customer]:
				if site == null:
					continue
				var target := navigation.get_closest_point(site.spawn_point.position)
				var path := navigation.find_path(start_from, target)
				_expect(
					path.size() >= 2,
					"玩家起点 %d 到站点 %s 不可达" % [start.road_edge_id, site.id]
				)
	main.queue_free()
	await process_frame


func _site_signatures(city: CityContent) -> Array:
	var result := []
	for site in city.sites:
		result.append([
			site.id, site.kind, site.position, site.facing_yaw, site.lot_id,
			site.road_edge_id, _spawn_signature(site.spawn_point)
		])
	return result


func _spawn_signature(spawn: SpawnPoint) -> Array:
	if spawn == null:
		return []
	return [
		spawn.kind, spawn.site_id, spawn.position, spawn.facing_yaw,
		spawn.road_edge_id, spawn.road_offset_m, spawn.lateral_offset_m
	]


func _spawn_signatures(starts: Array[SpawnPoint]) -> Array:
	var result := []
	for spawn in starts:
		result.append(_spawn_signature(spawn))
	return result


func _point_in_building(point: Vector2, city: CityContent) -> bool:
	for building in city.buildings:
		if Rect2(building.rect).has_point(point):
			return true
	return false
