extends SceneTree

## 行为采集测试：会话 ID、事件清洗、批量上限、上报载荷、
## 道路与 NPC 拥挤度辅助函数，以及任务起止点字段。
## 非 Web 环境中 TelemetryClient 不会联网，测试只检查本地队列。

const RoadGenerator = preload("res://scripts/world/road_generator.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var telemetry := TelemetryClient.new()
	root.add_child(telemetry)
	await process_frame

	telemetry.start_session()
	_expect(
		RegEx.create_from_string("^s[0-9a-f]{24}$").search(telemetry.session_id) != null,
		"会话 ID 应是 s 加 24 位十六进制：%s" % telemetry.session_id
	)

	var pending := telemetry.get_pending_events()
	_expect(pending.size() == 1 and pending[0].n == "session", "开始时应记录一条 session 事件")
	_expect(pending[0].t >= 0, "事件时间戳不应为负")

	var payload := telemetry.make_payload(pending)
	_expect(payload.token == TelemetryClient.TOKEN, "上报载荷应带采集 token")
	_expect(payload.session_id == telemetry.session_id, "上报载荷应带会话 ID")
	_expect(payload.start > 0, "上报载荷应带客户端起始时间")

	telemetry.record("pos", {
		"x": 12.25,
		"z": -3.5,
		"ok": true,
		"tag": "x".repeat(400),
		"vector": Vector3.ONE,
		"nan": NAN,
	})
	var pos_event: Dictionary = telemetry.get_pending_events().back()
	_expect(pos_event.n == "pos", "事件名应保留")
	_expect(pos_event.p.x == 12.25 and pos_event.p.z == -3.5, "数值属性应保留")
	_expect(pos_event.p.ok == true, "布尔属性应保留")
	_expect(pos_event.p.tag.length() == TelemetryClient.MAX_STRING, "字符串应截断")
	_expect(not pos_event.p.has("vector"), "非基础类型属性应丢弃")
	_expect(not pos_event.p.has("nan"), "非有限数值应丢弃")

	var many := {}
	for index in 40:
		many["k%d" % index] = index
	telemetry.record("many", many)
	var many_event: Dictionary = telemetry.get_pending_events().back()
	_expect(
		many_event.p.size() == TelemetryClient.MAX_PROPS_KEYS,
		"属性数量应限制在 %d：%d" % [TelemetryClient.MAX_PROPS_KEYS, many_event.p.size()]
	)

	for index in TelemetryClient.MAX_QUEUE + 20:
		telemetry.record("pos", {"i": index})
	_expect(
		telemetry.get_pending_events().size() == TelemetryClient.MAX_QUEUE,
		"本地队列应限制在 %d" % TelemetryClient.MAX_QUEUE
	)

	_expect(not telemetry.active, "headless 环境不应开启联网上报")
	_expect(telemetry.get_node_or_null("Http") == null, "未启用时不应创建 HTTPRequest")

	_expect(
		is_equal_approx(TelemetryClient.planar_speed(Vector3(3.0, -9.8, 4.0)), 5.0),
		"平面速度应忽略竖直分量"
	)

	# 道路辅助函数：用真实生成的路网检查最近路段和道路属性。
	var network: RoadNetwork = RoadGenerator.generate(
		Vector2(2400, 2400), 42, 0.5, Vector3(40, 30, 18)
	)
	var edge: Dictionary = network.edges[0]
	var a: Vector2 = network.nodes[int(edge.a)]
	var b: Vector2 = network.nodes[int(edge.b)]
	var midpoint := a.lerp(b, 0.5)
	var road := TelemetryClient.nearest_edge(Vector3(midpoint.x, 0.0, midpoint.y), network)
	_expect(road >= 0 and road < network.edges.size(), "应能找到最近路段：%d" % road)
	var found: Dictionary = network.edges[road]
	var found_distance := Geometry2D.get_closest_point_to_segment(
		midpoint, network.nodes[int(found.a)], network.nodes[int(found.b)]
	).distance_to(midpoint)
	var own_distance := Geometry2D.get_closest_point_to_segment(midpoint, a, b).distance_to(midpoint)
	_expect(found_distance <= own_distance + 0.001, "最近路段应是距离最小的路段")
	var context := TelemetryClient.get_road_context(
		Vector3(midpoint.x, 0.0, midpoint.y), network, null
	)
	_expect(context.road >= 0 and context.rk >= 0 and context.rk <= 2, "道路属性应带路段和等级")
	_expect(context.cars == 0 and context.peds == 0 and context.near == 0, "没有交通时应为 0")

	# 订单关键事件：接单、开始、拒绝、结算都应进入队列，属性与订单一致。
	var order := DeliveryOrder.new()
	order.city_seed = 42
	order.order_seed = 42
	order.pickup_path_length_m = 120.4
	order.delivery_path_length_m = 350.6
	order.start = SpawnPoint.new()
	order.start.kind = SpawnPoint.Kind.PLAYER_START
	order.start.position = Vector3(12.0, 0.0, -8.0)
	order.merchant = CitySite.new()
	order.merchant.kind = CitySite.Kind.MERCHANT
	order.merchant.spawn_point = SpawnPoint.new()
	order.merchant.spawn_point.position = Vector3(100.0, 0.0, 50.0)
	order.customer = CitySite.new()
	order.customer.kind = CitySite.Kind.RESIDENTIAL
	order.customer.spawn_point = SpawnPoint.new()
	order.customer.spawn_point.position = Vector3(-40.0, 0.0, 210.0)
	telemetry._on_order_offered(order)
	telemetry._on_order_started(order)
	telemetry._on_order_rejected(order)
	telemetry._on_order_finished(true)
	var tail := telemetry.get_pending_events().slice(-4)
	_expect(tail[0].n == "offer" and tail[0].p.seed == 42, "应记录 offer 事件")
	_expect(tail[0].p.pick == 120 and tail[0].p.drop == 351, "offer 应带取餐与送达路程")
	_expect(tail[0].p.city == 42, "offer 应带城市种子")
	_expect(tail[1].n == "start" and tail[1].p.seed == 42, "应记录 start 事件")
	_expect(
		tail[1].p.sx == 12.0 and tail[1].p.sz == -8.0,
		"start 应带任务起点：%s" % [tail[1].p]
	)
	_expect(
		tail[1].p.px == 100.0 and tail[1].p.pz == 50.0,
		"start 应带取餐点：%s" % [tail[1].p]
	)
	_expect(
		tail[1].p.dx == -40.0 and tail[1].p.dz == 210.0,
		"start 应带送达点：%s" % [tail[1].p]
	)
	_expect(tail[2].n == "reject" and tail[2].p.seed == 42, "应记录 reject 事件")
	_expect(
		tail[3].n == "finish" and tail[3].p.ok == true and tail[3].p.why == "none",
		"应记录 finish 事件及结果"
	)

	# 本地调试开关：参数与环境变量都能打开，默认关闭。
	_expect(
		TelemetryClient.recording_requested(PackedStringArray(["--headless", "--record"]), ""),
		"启动参数 --record 应开启本地记录"
	)
	_expect(
		TelemetryClient.recording_requested(PackedStringArray(), "1")
		and TelemetryClient.recording_requested(PackedStringArray(), " TRUE "),
		"环境变量 SWM_RECORD 为 1/true 时应开启本地记录"
	)
	_expect(
		not TelemetryClient.recording_requested(PackedStringArray(["--headless"]), "0")
		and not TelemetryClient.recording_requested(PackedStringArray(), ""),
		"没有开关时不应开启本地记录"
	)
	_expect(not telemetry.local_recording, "headless 测试默认不写出本地记录")

	# 开关打开后写出的 JSON 应与页面数据同构，能直接交给 render_behavior_png.py。
	telemetry.local_recording = true
	telemetry.local_record_dir = "user://test-recordings/%s" % telemetry.session_id
	telemetry.record("pos", {"x": 1.5, "z": -2.5})
	telemetry.write_local_recording()
	var record_path := telemetry.local_record_dir.path_join("analytics.json")
	var written := FileAccess.get_file_as_string(record_path)
	_expect(not written.is_empty(), "本地记录应写出 analytics.json")
	var parsed: Variant = JSON.parse_string(written)
	_expect(parsed is Dictionary and parsed.has("sessions"), "本地记录应是页面 JSON 结构")
	_expect(
		parsed != null and parsed.sessions[0].events.size() == 1
		and parsed.sessions[0].events[0].p.x == 1.5,
		"本地记录应只包含开关打开后的事件：%s" % [written]
	)
	_expect(parsed != null and parsed.meta.demo == false, "本地记录不应标成演示数据")
	_expect(
		parsed != null and parsed.sessions[0].id == telemetry.session_id,
		"本地记录应带会话 ID"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(record_path))
	telemetry.local_recording = false
	telemetry.local_record_dir = ""

	telemetry.queue_free()
	await process_frame
	if _failed:
		printerr("FAIL telemetry")
	else:
		print("PASS telemetry")
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL ", message)
