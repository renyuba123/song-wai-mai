extends Node
class_name TelemetryClient

## 展览行为采集：把关键事件、沿途状态和两秒一次的位置轨迹批量发给云函数。
## 只记录随机会话 ID 与游戏内数据，不采集姓名、账号、设备标识；
## 只在 Web 导出中真正发送，桌面和 headless 测试不会联网。
##
## 位置采样同时记录速度、当前道路和该道路的 NPC 数量，
## 任务开始时记录起止点与目标点，方便分析页直接画出地图、速度热力
## 轨迹和计时点位置。页面关闭时用 sendBeacon 兜底发送尚未上报的事件。

const ENDPOINT := "https://passive-sailfish-d0e1nvt8175333a.service.tcloudbase.com/log"
const TOKEN := "1355f19d6d7fad23e8701d45"
const FLUSH_INTERVAL_S := 4.0
const POSITION_INTERVAL_S := 2.0
const CHECKPOINT_INTERVAL_S := 30.0
const MAX_BATCH := 50
const MAX_QUEUE := 2000
const MAX_PROPS_KEYS := 24
const MAX_STRING := 120
const NEAR_CAR_RADIUS_M := 80.0

var active := false
var session_id := ""

var _orders: OrderManager = null
var _player: PlayerController = null
var _world: WorldGenerator = null
var _traffic: TrafficSpawner = null
var _http: HTTPRequest = null
var _web_bridge: Object = null
var _queue: Array = []
var _inflight: Array = []
var _sending := false
var _flush_accum := 0.0
var _position_accum := 0.0
var _checkpoint_accum := 0.0
var _checkpoint_index := 0
var _start_offset_ms := 0
var _start_unix_ms := 0
var _started := false
var _last_state := -1


static func is_web_build() -> bool:
	return OS.has_feature("web")


## 平面速度，单位米每秒。PlayerController 的 velocity.y 受重力影响，不能直接取长度。
static func planar_speed(velocity: Vector3) -> float:
	return Vector2(velocity.x, velocity.z).length()


## 距离最近的路段；用于判断玩家和 NPC 当前处在哪条路上。
static func nearest_edge(point: Vector3, network: RoadNetwork) -> int:
	if network == null or network.edges.is_empty():
		return -1
	var here := Vector2(point.x, point.z)
	var best := -1
	var best_distance := INF
	for edge_id in network.edges.size():
		var edge: Dictionary = network.edges[edge_id]
		var a: Vector2 = network.nodes[int(edge.a)]
		var b: Vector2 = network.nodes[int(edge.b)]
		var closest := Geometry2D.get_closest_point_to_segment(here, a, b)
		var distance := closest.distance_to(here)
		if distance < best_distance:
			best_distance = distance
			best = edge_id
	return best


func setup(
	orders: OrderManager,
	player: PlayerController,
	world: WorldGenerator = null,
	traffic: TrafficSpawner = null
) -> void:
	_orders = orders
	_player = player
	# 主场景只传订单和玩家时，从同级节点里补上世界和交通，
	# 保证道路编号与 NPC 拥挤度仍然有数据来源。
	_world = world if world != null else _find_world()
	_traffic = traffic if traffic != null else _find_traffic()
	active = is_web_build()
	if active:
		_http = HTTPRequest.new()
		_http.name = "Http"
		_http.timeout = 10.0
		add_child(_http)
		_http.request_completed.connect(_on_request_completed)
		if Engine.has_singleton("JavaScriptBridge"):
			_web_bridge = Engine.get_singleton("JavaScriptBridge")
	start_session()
	if active:
		_install_web_backlog()
		# 页面刚打开就先报一次，快速退出的访客也能计入。
		flush()
	if _orders == null:
		return
	_orders.order_offered.connect(_on_order_offered)
	_orders.order_started.connect(_on_order_started)
	_orders.order_finished.connect(_on_order_finished)
	_orders.order_rejected.connect(_on_order_rejected)
	if _traffic != null:
		_traffic.player_hit.connect(_on_player_hit)


## 生成本次体验的随机会话 ID，并记录尺寸、地图和交通环境。
## 每次页面加载都是一次新会话，不做可跨站跟踪的持久标识。
func start_session() -> void:
	if _started:
		return
	_started = true
	session_id = "s" + Crypto.new().generate_random_bytes(12).hex_encode()
	_start_offset_ms = Time.get_ticks_msec()
	_start_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var size := get_viewport().get_visible_rect().size if get_viewport() else Vector2.ZERO
	var props := {
		"w": roundi(size.x),
		"h": roundi(size.y),
		"touch": 1 if DisplayServer.is_touchscreen_available() else 0,
	}
	var network := get_network()
	if network != null:
		props["city"] = network.seed_value
		props["mapw"] = roundi(network.map_size.x)
		props["maph"] = roundi(network.map_size.y)
	if _traffic != null:
		props["traffic"] = snappedf(_traffic.traffic_density, 0.1)
		props["cars"] = _traffic.get_vehicle_count()
	record("session", props)


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
	_push_web_event(event)


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
	var session := _orders.get_session() if _orders != null else null
	if session != null and session.is_active() and _player != null:
		_checkpoint_accum += delta
		if _checkpoint_accum >= CHECKPOINT_INTERVAL_S:
			_checkpoint_accum = fmod(_checkpoint_accum, CHECKPOINT_INTERVAL_S)
			_record_checkpoint(session)
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
		var props := {"sec": roundi(session.get_elapsed_s())}
		if _player != null:
			_add_position_props(props, _player.global_position)
		record("pickup", props)


func _sample_position() -> void:
	var session := _orders.get_session() if _orders != null else null
	if session == null or not session.is_active() or _player == null:
		return
	var pos := _player.global_position
	var distance := session.get_distance_to_target(pos)
	var props := {
		"x": snappedf(pos.x, 0.1),
		"z": snappedf(pos.z, 0.1),
		"yaw": roundi(wrapf(rad_to_deg(_player.rotation.y), -180.0, 180.0)),
		"d": roundi(distance) if is_finite(distance) else -1,
		"left": roundi(session.time_remaining),
		"speed": snappedf(planar_speed(_player.velocity), 0.1),
	}
	_add_road_props(props, pos)
	record("pos", props)


## 每 30 秒记一个计时点，分析页据此在轨迹上标出玩家当时的位置。
func _record_checkpoint(session: OrderSession) -> void:
	_checkpoint_index += 1
	var pos := _player.global_position
	var props := {
		"i": _checkpoint_index,
		"sec": roundi(session.get_elapsed_s()),
		"x": snappedf(pos.x, 0.1),
		"z": snappedf(pos.z, 0.1),
		"speed": snappedf(planar_speed(_player.velocity), 0.1),
		"left": roundi(session.time_remaining),
	}
	_add_road_props(props, pos)
	record("checkpoint", props)


func _on_order_offered(order: DeliveryOrder) -> void:
	if order == null:
		return
	record("offer", {
		"seed": order.order_seed,
		"city": order.city_seed,
		"pick": roundi(maxf(order.pickup_path_length_m, 0.0)),
		"drop": roundi(maxf(order.delivery_path_length_m, 0.0)),
	})


func _on_order_started(order: DeliveryOrder) -> void:
	if order == null:
		return
	_last_state = OrderSession.State.TO_MERCHANT
	_checkpoint_accum = 0.0
	_checkpoint_index = 0
	var props := {"seed": order.order_seed, "city": order.city_seed}
	if order.start != null:
		props["sx"] = snappedf(order.start.position.x, 0.1)
		props["sz"] = snappedf(order.start.position.z, 0.1)
	_add_site_props(props, "p", order.merchant)
	_add_site_props(props, "d", order.customer)
	var session := _orders.get_session() if _orders != null else null
	if session != null:
		props["limit"] = roundi(session.time_limit)
	record("start", props)
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
	var props := {"ok": success, "why": reason, "sec": elapsed}
	if _player != null:
		_add_position_props(props, _player.global_position)
	record("finish", props)
	flush()


func _on_order_rejected(order: DeliveryOrder) -> void:
	if order == null:
		return
	var props := {"seed": order.order_seed, "city": order.city_seed}
	if _player != null:
		_add_position_props(props, _player.global_position)
	record("reject", props)
	flush()


func _on_player_hit(_car: TrafficCar, position: Vector3) -> void:
	var props := {"x": snappedf(position.x, 0.1), "z": snappedf(position.z, 0.1)}
	if _player != null:
		props["speed"] = snappedf(planar_speed(_player.velocity), 0.1)
	_add_road_props(props, position)
	record("hit", props)


func _add_site_props(props: Dictionary, prefix: String, site: CitySite) -> void:
	if site == null or site.spawn_point == null:
		return
	props[prefix + "x"] = snappedf(site.spawn_point.position.x, 0.1)
	props[prefix + "z"] = snappedf(site.spawn_point.position.z, 0.1)


func _add_position_props(props: Dictionary, pos: Vector3) -> void:
	props["x"] = snappedf(pos.x, 0.1)
	props["z"] = snappedf(pos.z, 0.1)
	if _player != null:
		props["speed"] = snappedf(planar_speed(_player.velocity), 0.1)
	_add_road_props(props, pos)


## 当前道路和道路上的 NPC 数量。
## cars/peds 统计整条路段，near 统计玩家 80 米内的车辆，
## 分析页把 cars 换算成每百米车辆数后画到路网上。
func _add_road_props(props: Dictionary, pos: Vector3) -> void:
	var context := get_road_context(pos, get_network(), _traffic)
	for key in context:
		props[key] = context[key]


static func get_road_context(
	pos: Vector3, network: RoadNetwork, traffic: TrafficSpawner
) -> Dictionary:
	var context := {"road": -1, "rk": -1, "cars": 0, "peds": 0, "near": 0}
	if network == null:
		return context
	var road := nearest_edge(pos, network)
	if road < 0:
		return context
	context["road"] = road
	context["rk"] = int(network.edges[road].kind)
	if traffic == null:
		return context
	for car in traffic.get_cars():
		if not is_instance_valid(car):
			continue
		var car_position: Vector3 = car.global_position
		if nearest_edge(car_position, network) == road:
			context["cars"] += 1
		var planar := Vector2(car_position.x - pos.x, car_position.z - pos.z)
		if planar.length() <= NEAR_CAR_RADIUS_M:
			context["near"] += 1
	for pedestrian in traffic.get_pedestrians():
		if is_instance_valid(pedestrian) and nearest_edge(pedestrian.global_position, network) == road:
			context["peds"] += 1
	return context


func get_network() -> RoadNetwork:
	if _world != null and _world.network != null:
		return _world.network
	return null


func _find_world() -> WorldGenerator:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is WorldGenerator:
			return child as WorldGenerator
	return null


func _find_traffic() -> TrafficSpawner:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is TrafficSpawner:
			return child as TrafficSpawner
	return null


func _on_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray
) -> void:
	_sending = false
	var delivered := _inflight
	_inflight = []
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		_drop_web_events(delivered.size())
		return
	# 发送失败就把这一批放回队首，等下一次定时重试；队列过长时丢弃最旧的。
	_queue = delivered + _queue
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()


## Web 端维护一份与本地队列同步的 JS 事件数组，页面关闭时由 sendBeacon
## 把还没发完的事件送出去；成功上报后再按条数从 JS 数组移除。
func _install_web_backlog() -> void:
	if _web_bridge == null:
		return
	var init := (
		"window.__swmTelemetry={url:%s,token:%s,session:%s,start:%d,events:[]};"
		% [JSON.stringify(ENDPOINT), JSON.stringify(TOKEN), JSON.stringify(session_id), _start_unix_ms]
	)
	var hook := """
(function(){
  var t = window.__swmTelemetry;
  if (!t || t.hooked) { return; }
  t.hooked = true;
  window.addEventListener('pagehide', function (event) {
    if (event && event.persisted) { return; }
    var data = window.__swmTelemetry;
    if (!data || !data.events || data.events.length === 0) { return; }
    var events = data.events;
    data.events = [];
    for (var i = 0; i < events.length; i += 50) {
      var body = JSON.stringify({
        token: data.token,
        session_id: data.session,
        start: data.start,
        events: events.slice(i, i + 50)
      });
      try {
        if (navigator.sendBeacon) {
          navigator.sendBeacon(data.url, new Blob([body], { type: 'application/json' }));
        } else {
          fetch(data.url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: body,
            keepalive: true
          });
        }
      } catch (error) {}
    }
  });
})();
"""
	_web_bridge.call("eval", init)
	_web_bridge.call("eval", hook)


func _push_web_event(event: Dictionary) -> void:
	if _web_bridge == null:
		return
	_web_bridge.call(
		"eval",
		"if(window.__swmTelemetry){window.__swmTelemetry.events.push(%s);}" % JSON.stringify(event)
	)


func _drop_web_events(count: int) -> void:
	if _web_bridge == null or count <= 0:
		return
	_web_bridge.call(
		"eval",
		"if(window.__swmTelemetry){window.__swmTelemetry.events.splice(0,%d);}" % count
	)


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
