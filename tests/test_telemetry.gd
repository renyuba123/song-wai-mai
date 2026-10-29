extends SceneTree

## 行为采集测试：会话 ID、事件清洗、批量上限和上报载荷。
## 非 Web 环境中 TelemetryClient 不会联网，测试只检查本地队列。

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

	# 订单关键事件：接单、开始、结算都应进入队列，属性与订单一致。
	var order := DeliveryOrder.new()
	order.order_seed = 42
	order.pickup_path_length_m = 120.4
	order.delivery_path_length_m = 350.6
	telemetry._on_order_offered(order)
	telemetry._on_order_started(order)
	telemetry._on_order_finished(true)
	var tail := telemetry.get_pending_events().slice(-3)
	_expect(tail[0].n == "offer" and tail[0].p.seed == 42, "应记录 offer 事件")
	_expect(tail[0].p.pick == 120 and tail[0].p.drop == 351, "offer 应带取餐与送达路程")
	_expect(tail[1].n == "start" and tail[1].p.seed == 42, "应记录 start 事件")
	_expect(
		tail[2].n == "finish" and tail[2].p.ok == true and tail[2].p.why == "none",
		"应记录 finish 事件及结果"
	)

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
