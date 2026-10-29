extends Node
class_name TelemetryClient

## 展览行为采集：把关键事件和两秒一次的位置轨迹批量发给云函数。
## 只记录随机会话 ID 与游戏内数据，不采集姓名、账号、设备标识；
## 只在 Web 导出中真正发送，桌面和 headless 测试不会联网。

const ENDPOINT := "https://passive-sailfish-d0e1nvt8175333a.service.tcloudbase.com/log"
const TOKEN := "1355f19d6d7fad23e8701d45"
const FLUSH_INTERVAL_S := 8.0
const POSITION_INTERVAL_S := 2.0
const MAX_BATCH := 40
const MAX_QUEUE := 300
const MAX_PROPS_KEYS := 16
const MAX_STRING := 120

var active := false
var session_id := ""

var _orders: OrderManager = null
var _player: PlayerController = null
var _http: HTTPRequest = null
var _queue: Array = []
var _inflight: Array = []
var _sending := false
var _flush_accum := 0.0
var _position_accum := 0.0
var _start_offset_ms := 0
var _start_unix_ms := 0
var _started := false
var _last_state := -1


static func is_web_build() -> bool:
	return OS.has_feature("web")


func setup(orders: OrderManager, player: PlayerController) -> void:
	_orders = orders
	_player = player
	active = is_web_build()
	if active:
		_http = HTTPRequest.new()
		_http.name = "Http"
		_http.timeout = 10.0
		add_child(_http)
		_http.request_completed.connect(_on_request_completed)
	start_session()
	if active:
		# 页面刚打开就先报一次，快速退出的访客也能计入。
		flush()
	if _orders == null:
		return
	_orders.order_offered.connect(_on_order_offered)
	_orders.order_started.connect(_on_order_started)
	_orders.order_finished.connect(_on_order_finished)


## 生成本次体验的随机会话 ID，并记录尺寸等环境信息。
## 每次页面加载都是一次新会话，不做可跨站跟踪的持久标识。
func start_session() -> void:
	if _started:
		return
	_started = true
	session_id = "s" + Crypto.new().generate_random_bytes(12).hex_encode()
	_start_offset_ms = Time.get_ticks_msec()
	_start_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var size := get_viewport().get_visible_rect().size if get_viewport() else Vector2.ZERO
	record("session", {
		"w": roundi(size.x),
		"h": roundi(size.y),
		"touch": 1 if DisplayServer.is_touchscreen_available() else 0,
	})


func record(event_name: String, props: Dictionary = {}) -> void:
	var clean := _clean_props(props)
	var event := {
		"n": event_name.substr(0, 40),
		"t": maxi(0, Time.get_ticks_msec() - _start_offset_ms),
		"p": clean,
	}
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_queue.append(event)


func get_pending_events() -> Array:
	return _queue.duplicate(true)


func make_payload(events: Array) -> Dictionary:
	return {
		"token": TOKEN,
		"session_id": session_id,
		"start": _start_unix_ms,
		"events": events,
	}


## 把队列里最多 MAX_BATCH 条事件发出去；同一时间只允许一个请求。
func flush() -> void:
	if not active or _sending or _http == null or _queue.is_empty():
		return
	var count := mini(_queue.size(), MAX_BATCH)
	_inflight = _queue.slice(0, count)
	_queue = _queue.slice(count)
	var body := JSON.stringify(make_payload(_inflight))
	var err := _http.request(
		ENDPOINT,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		_queue = _inflight + _queue
		_inflight = []
		return
	_sending = true


func _process(delta: float) -> void:
	if not active:
		return
	_poll_order_state()
	_position_accum += delta
	if _position_accum >= POSITION_INTERVAL_S:
		_position_accum = 0.0
		_sample_position()
	_flush_accum += delta
	if _flush_accum >= FLUSH_INTERVAL_S:
		_flush_accum = 0.0
		flush()


func _poll_order_state() -> void:
	var session := _orders.get_session() if _orders != null else null
	if session == null:
		_last_state = -1
		return
	if session.state == _last_state:
		return
	_last_state = session.state
	if session.state == OrderSession.State.TO_CUSTOMER:
		record("pickup", {"sec": roundi(session.get_elapsed_s())})


func _sample_position() -> void:
	var session := _orders.get_session() if _orders != null else null
	if session == null or not session.is_active() or _player == null:
		return
	var pos := _player.global_position
	var yaw := wrapf(rad_to_deg(_player.rotation.y), -180.0, 180.0)
	var distance := session.get_distance_to_target(pos)
	record("pos", {
		"x": snappedf(pos.x, 0.1),
		"z": snappedf(pos.z, 0.1),
		"yaw": roundi(yaw),
		"d": roundi(distance) if is_finite(distance) else -1,
		"left": roundi(session.time_remaining),
	})


func _on_order_offered(order: DeliveryOrder) -> void:
	if order == null:
		return
	record("offer", {
		"seed": order.order_seed,
		"pick": roundi(maxf(order.pickup_path_length_m, 0.0)),
		"drop": roundi(maxf(order.delivery_path_length_m, 0.0)),
	})


func _on_order_started(order: DeliveryOrder) -> void:
	if order == null:
		return
	_last_state = OrderSession.State.TO_MERCHANT
	record("start", {"seed": order.order_seed})
	flush()


func _on_order_finished(success: bool) -> void:
	var session := _orders.get_session() if _orders != null else null
	var reason := "none"
	var elapsed := 0
	if session != null:
		elapsed = roundi(session.get_elapsed_s())
		match session.get_failure_reason():
			OrderSession.FailureReason.TIMEOUT:
				reason = "timeout"
			OrderSession.FailureReason.HIT_BY_CAR:
				reason = "hit"
	record("finish", {"ok": success, "why": reason, "sec": elapsed})
	flush()


func _on_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray
) -> void:
	_sending = false
	var delivered := _inflight
	_inflight = []
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		return
	# 发送失败就把这一批放回队首，等下一次定时重试；队列过长时丢弃最旧的。
	_queue = delivered + _queue
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()


func _clean_props(props: Dictionary) -> Dictionary:
	var clean := {}
	for key in props:
		if clean.size() >= MAX_PROPS_KEYS:
			break
		if typeof(key) != TYPE_STRING:
			continue
		var name := String(key).substr(0, 32)
		if name.is_empty():
			continue
		var value: Variant = props[key]
		var kind := typeof(value)
		if kind == TYPE_INT or kind == TYPE_FLOAT:
			if not is_finite(float(value)):
				continue
			clean[name] = value
		elif kind == TYPE_BOOL:
			clean[name] = value
		elif kind == TYPE_STRING:
			clean[name] = String(value).substr(0, MAX_STRING)
	return clean
