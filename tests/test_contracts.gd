extends SceneTree

## 阶段零共享契约测试：路网冻结字段、出生点、城市站点和外卖订单。

const Generator = preload("res://scripts/world/road_generator.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var network: RoadNetwork = Generator.generate(
		Vector2(2400.0, 2400.0), 42, 0.5, Vector3(40.0, 30.0, 18.0)
	)
	_check_road_network(network)
	_check_spawn_points(network)
	_check_city_sites(network)
	_check_delivery_orders(network)
	if _failed:
		printerr("FAIL contracts")
	else:
		print("PASS contracts nodes=", network.nodes.size(), " edges=", network.edges.size())
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL ", message)


func _edge_length(network: RoadNetwork, edge_id: int) -> float:
	var edge: Dictionary = network.edges[edge_id]
	return network.nodes[edge.a].distance_to(network.nodes[edge.b])


func _find_edge(network: RoadNetwork, minimum_length: float) -> int:
	for index in network.edges.size():
		if _edge_length(network, index) >= minimum_length:
			return index
	return -1


func _spawn_on_edge(network: RoadNetwork, edge_id: int, kind: SpawnPoint.Kind, site_id: StringName) -> SpawnPoint:
	var edge: Dictionary = network.edges[edge_id]
	var a: Vector2 = network.nodes[edge.a]
	var b: Vector2 = network.nodes[edge.b]
	var spawn := SpawnPoint.new()
	spawn.kind = kind
	spawn.site_id = site_id
	spawn.road_edge_id = edge_id
	spawn.road_offset_m = a.distance_to(b) * 0.5
	var point := a.lerp(b, 0.5)
	spawn.position = Vector3(point.x, 0.0, point.y)
	return spawn


func _make_site(network: RoadNetwork, edge_id: int, id: StringName, kind: CitySite.Kind) -> CitySite:
	var site := CitySite.new()
	site.id = id
	site.kind = kind
	site.road_edge_id = edge_id
	var spawn_kind: SpawnPoint.Kind = (
		SpawnPoint.Kind.MERCHANT if kind == CitySite.Kind.MERCHANT else SpawnPoint.Kind.CUSTOMER
	)
	site.spawn_point = _spawn_on_edge(network, edge_id, spawn_kind, id)
	var edge: Dictionary = network.edges[edge_id]
	var point: Vector2 = network.nodes[edge.a].lerp(network.nodes[edge.b], 0.5)
	site.position = Vector3(point.x, 0.0, point.y)
	return site


func _check_road_network(network: RoadNetwork) -> void:
	_expect(network.seed_value == 42, "路网种子未冻结为 42")
	_expect(network.map_size == Vector2(2400.0, 2400.0), "路网尺寸字段不符")
	_expect(network.widths == Vector3(40.0, 30.0, 18.0), "路网宽度字段不符")
	_expect(not network.nodes.is_empty(), "路网没有节点")
	_expect(not network.edges.is_empty(), "路网没有路段")
	_expect(not network.x_axes.is_empty() and not network.y_axes.is_empty(), "路网缺少轴线字段")
	_expect(network.edges[0].has("a") and network.edges[0].has("b") and network.edges[0].has("kind"), "路段字段不完整")
	_expect(network.entrances.is_empty(), "新生成路网不应已有出入口")
	_expect(network.validate().valid, "路网校验未通过")
	var route := network.find_route(0, network.nodes.size() - 1)
	_expect(route.size() >= 2, "路网寻路结果不足两个节点")


func _check_spawn_points(network: RoadNetwork) -> void:
	var edge_id := _find_edge(network, 260.0)
	_expect(edge_id >= 0, "找不到足够长的测试路段")
	if edge_id < 0:
		return
	var spawn := _spawn_on_edge(network, edge_id, SpawnPoint.Kind.MERCHANT, &"merchant_a")
	_expect(spawn.is_valid(network), "路段中点的商家出生点应有效")

	var at_junction := _spawn_on_edge(network, edge_id, SpawnPoint.Kind.MERCHANT, &"merchant_a")
	at_junction.road_offset_m = 0.0
	var edge: Dictionary = network.edges[edge_id]
	var start: Vector2 = network.nodes[edge.a]
	at_junction.position = Vector3(start.x, 0.0, start.y)
	_expect(not at_junction.is_valid(network), "交叉口附近的出生点应因退让不足失败")

	var bad_edge := _spawn_on_edge(network, edge_id, SpawnPoint.Kind.MERCHANT, &"merchant_a")
	bad_edge.road_edge_id = 9999
	_expect(not bad_edge.is_valid(network), "无效路段应让出生点失败")

	var no_site := _spawn_on_edge(network, edge_id, SpawnPoint.Kind.MERCHANT, &"")
	_expect(not no_site.is_valid(network), "商家出生点缺少站点编号时应失败")

	var player_start := _spawn_on_edge(network, edge_id, SpawnPoint.Kind.PLAYER_START, &"")
	_expect(player_start.is_valid(network), "玩家起点可以不关联站点")


func _check_city_sites(network: RoadNetwork) -> void:
	var edge_id := _find_edge(network, 260.0)
	_expect(edge_id >= 0, "找不到足够长的测试路段")
	if edge_id < 0:
		return
	var merchant := _make_site(network, edge_id, &"merchant_a", CitySite.Kind.MERCHANT)
	_expect(merchant.is_valid(network), "合法商家站点应通过")

	var residential := _make_site(network, edge_id, &"customer_a", CitySite.Kind.RESIDENTIAL)
	_expect(residential.is_valid(network), "合法住宅站点应通过")

	var wrong_spawn := _make_site(network, edge_id, &"merchant_b", CitySite.Kind.MERCHANT)
	wrong_spawn.spawn_point.kind = SpawnPoint.Kind.PLAYER_START
	_expect(not wrong_spawn.is_valid(network), "出生点类型与站点类型不匹配时应失败")

	var wrong_id := _make_site(network, edge_id, &"merchant_c", CitySite.Kind.MERCHANT)
	wrong_id.spawn_point.site_id = &"merchant_other"
	_expect(not wrong_id.is_valid(network), "出生点站点编号不匹配时应失败")

	var no_spawn := _make_site(network, edge_id, &"merchant_d", CitySite.Kind.MERCHANT)
	no_spawn.spawn_point = null
	_expect(not no_spawn.is_valid(network), "站点缺少出生点时应失败")

	var no_anchor := _make_site(network, edge_id, &"merchant_e", CitySite.Kind.MERCHANT)
	no_anchor.road_edge_id = -1
	_expect(not no_anchor.is_valid(network), "站点既无地块又无路段时应失败")


func _check_delivery_orders(network: RoadNetwork) -> void:
	var edge_id := _find_edge(network, 260.0)
	_expect(edge_id >= 0, "找不到足够长的测试路段")
	if edge_id < 0:
		return
	var order := DeliveryOrder.new()
	order.city_seed = network.seed_value
	order.start = _spawn_on_edge(network, edge_id, SpawnPoint.Kind.PLAYER_START, &"")
	order.merchant = _make_site(network, edge_id, &"merchant_a", CitySite.Kind.MERCHANT)
	order.customer = _make_site(network, edge_id, &"customer_a", CitySite.Kind.RESIDENTIAL)
	order.pickup_path_length_m = 120.0
	order.delivery_path_length_m = 80.5
	_expect(order.is_valid(network), "合法订单应通过")
	_expect(is_equal_approx(order.get_total_path_length_m(), 200.5), "订单总路径长度计算错误")

	order.city_seed = network.seed_value + 1
	_expect(not order.is_valid(network), "城市种子不一致时应失败")
	order.city_seed = network.seed_value

	order.customer.id = order.merchant.id
	order.customer.spawn_point.site_id = order.merchant.id
	_expect(not order.is_valid(network), "商家和顾客为同一站点时应失败")
	order.customer.id = &"customer_a"
	order.customer.spawn_point.site_id = &"customer_a"

	order.start = _spawn_on_edge(network, edge_id, SpawnPoint.Kind.MERCHANT, &"merchant_a")
	_expect(not order.is_valid(network), "订单起点类型不是玩家起点时应失败")
	order.start = _spawn_on_edge(network, edge_id, SpawnPoint.Kind.PLAYER_START, &"")

	order.pickup_path_length_m = DeliveryOrder.NO_ROUTE_DISTANCE
	_expect(not order.is_valid(network), "未计算路径长度时应失败")
	_expect(
		is_equal_approx(order.get_total_path_length_m(), DeliveryOrder.NO_ROUTE_DISTANCE),
		"未计算路径长度时总长度应返回 NO_ROUTE_DISTANCE"
	)
