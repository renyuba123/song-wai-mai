extends Control

## 玩家居中的圆形小地图。道路与导航路线都读取现有系统数据。
const RADIUS := 100.0
const VIEW_RANGE_M := 310.0
const ROUTE_REFRESH_S := 0.7
const ROUTE_MOVE_M := 8.0
const BG := Color("17222d")
const MAIN_ROAD := Color("8a98a6")
const SECONDARY_ROAD := Color("6b7a89")
const LOCAL_ROAD := Color("526372")
const ROUTE_COLOR := Color("f4bd4f")

var player: PlayerController
var network: RoadNetwork
var navigation: NavigationService
var orders: OrderManager
var destination := Vector3.INF
var route := PackedVector3Array()
var route_length_m := INF
var _route_start := Vector3.INF
var _refresh_elapsed := 0.0
var _last_session: OrderSession
var _last_state := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * (RADIUS * 2.0 + 8.0)


func setup(source_player: PlayerController, source_network: RoadNetwork, source_navigation: NavigationService, source_orders: OrderManager) -> void:
	player = source_player
	network = source_network
	navigation = source_navigation
	orders = source_orders
	queue_redraw()


func set_network(source_network: RoadNetwork) -> void:
	network = source_network
	route.clear()
	_route_start = Vector3.INF
	queue_redraw()


func set_destination(world_position: Vector3) -> void:
	destination = world_position
	route.clear()
	route_length_m = INF
	_route_start = Vector3.INF
	_refresh_elapsed = ROUTE_REFRESH_S
	queue_redraw()


func clear_destination() -> void:
	set_destination(Vector3.INF)


func _process(delta: float) -> void:
	if player == null:
		return
	_sync_order_target()
	_refresh_elapsed += delta
	if destination.is_finite() and _refresh_elapsed >= ROUTE_REFRESH_S:
		if not _route_start.is_finite() or _route_start.distance_to(player.global_position) >= ROUTE_MOVE_M or route.is_empty():
			_refresh_route()
		_refresh_elapsed = 0.0
	queue_redraw()


func _sync_order_target() -> void:
	if orders == null:
		return
	var session := orders.get_session()
	var state := session.state if session != null else -1
	if session == _last_session and state == _last_state:
		return
	if session != _last_session:
		if _last_session != null and _last_session.state_changed.is_connected(_on_session_state_changed):
			_last_session.state_changed.disconnect(_on_session_state_changed)
		if session != null:
			session.state_changed.connect(_on_session_state_changed)
	_last_session = session
	_last_state = state
	if session != null and session.is_active():
		set_destination(session.get_target_position())
	else:
		clear_destination()


func _on_session_state_changed(_state: int) -> void:
	_sync_order_target()


func _refresh_route() -> void:
	if navigation == null or not navigation.is_ready():
		return
	_route_start = player.global_position
	route = navigation.find_path(_route_start, destination)
	route_length_m = NavigationService.get_path_length(route) if route.size() >= 2 else INF


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, RADIUS + 4.0, Color("0b141e"))
	draw_circle(center, RADIUS, BG)
	if player == null or network == null:
		_draw_border(center)
		return
	var scale_factor := RADIUS / VIEW_RANGE_M
	for edge in network.edges:
		var a: Vector2 = network.nodes[int(edge["a"])]
		var b: Vector2 = network.nodes[int(edge["b"])]
		var kind: int = int(edge["kind"])
		var color := LOCAL_ROAD
		var width := 2.0
		if kind == RoadNetwork.MAIN:
			color = MAIN_ROAD
			width = 5.0
		elif kind == RoadNetwork.SECONDARY:
			color = SECONDARY_ROAD
			width = 3.5
		_draw_clipped_line(center, _map_point(a, scale_factor), _map_point(b, scale_factor), color, width)
	for index in range(1, route.size()):
		var a := _map_point(Vector2(route[index - 1].x, route[index - 1].z), scale_factor)
		var b := _map_point(Vector2(route[index].x, route[index].z), scale_factor)
		_draw_clipped_line(center, a, b, Color("17222d"), 8.0)
		_draw_clipped_line(center, a, b, ROUTE_COLOR, 4.5)
	if destination.is_finite():
		var target := _map_point(Vector2(destination.x, destination.z), scale_factor)
		var marker := target.limit_length(RADIUS - 11.0)
		draw_circle(center + marker, 8.0, BG)
		draw_circle(center + marker, 5.5, ROUTE_COLOR)
	# 玩家始终朝上，底图随玩家转向。
	var arrow := PackedVector2Array([center + Vector2(0, -10), center + Vector2(-7, 8), center + Vector2(0, 4), center + Vector2(7, 8), center + Vector2(0, -10)])
	draw_colored_polygon(arrow, Color.WHITE)
	draw_polyline(arrow, BG, 1.5, true)
	_draw_border(center)


func _draw_border(center: Vector2) -> void:
	draw_arc(center, RADIUS + 1.0, 0.0, TAU, 96, Color("d9e1e8"), 2.0, true)


func _map_point(world_xz: Vector2, scale_factor: float) -> Vector2:
	var origin := Vector2(player.global_position.x, player.global_position.z)
	return (world_xz - origin).rotated(player.global_rotation.y) * scale_factor


func _draw_clipped_line(center: Vector2, a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var clipped := _clip_line_to_circle(a, b, RADIUS - width * 0.5)
	if clipped.size() == 2:
		draw_line(center + clipped[0], center + clipped[1], color, width, true)


static func _clip_line_to_circle(a: Vector2, b: Vector2, radius: float) -> PackedVector2Array:
	var delta := b - a
	var length_squared := delta.length_squared()
	if length_squared < 0.0001:
		return PackedVector2Array()
	var points: Array[float] = [0.0, 1.0]
	var linear := 2.0 * a.dot(delta)
	var constant := a.length_squared() - radius * radius
	var discriminant := linear * linear - 4.0 * length_squared * constant
	if discriminant >= 0.0:
		var root := sqrt(discriminant)
		for value in [(-linear - root) / (2.0 * length_squared), (-linear + root) / (2.0 * length_squared)]:
			if value > 0.0 and value < 1.0:
				points.append(value)
	points.sort()
	for index in range(points.size() - 1):
		var first := points[index]
		var last := points[index + 1]
		if last - first > 0.0001 and (a + delta * ((first + last) * 0.5)).length_squared() <= radius * radius:
			return PackedVector2Array([a + delta * first, a + delta * last])
	return PackedVector2Array()
