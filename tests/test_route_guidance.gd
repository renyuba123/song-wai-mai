extends SceneTree

## 地面路线指引测试：可见性、节流、偏航/传送/目标切换重算，
## 以及订单结束和返回菜单后的隐藏。

const DEVIATION_OFFSET_M := 9.0

var _failed := false
var _main: Node = null
var _world: WorldGenerator = null
var _navigation: NavigationService = null
var _player: PlayerController = null
var _orders: OrderManager = null
var _guide: RouteGuide = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_pure_helpers()
	await _setup_main()
	if _guide != null:
		await _check_throttle_and_rebuilds()
		_check_hidden_after_finish()
	if _failed:
		printerr("FAIL route guidance")
	else:
		print("PASS route guidance")
	if _main != null:
		_main.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL route guidance: ", message)


func _check_pure_helpers() -> void:
	var straight := PackedVector3Array([Vector3.ZERO, Vector3(10.0, 0.0, 0.0)])
	_expect(
		is_equal_approx(
			RouteGuide.distance_to_path_xz(Vector3(5.0, 0.0, 3.0), straight), 3.0
		),
		"线段旁的点距离应为 3 米"
	)
	_expect(
		is_equal_approx(
			RouteGuide.distance_to_path_xz(Vector3(15.0, 0.0, 0.0), straight), 5.0
		),
		"线段端点外的点距离应为 5 米"
	)
	_expect(
		is_inf(RouteGuide.distance_to_path_xz(Vector3.ZERO, PackedVector3Array())),
		"空路径的偏航距离应为 INF"
	)


func _setup_main() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载主场景")
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	_world = _main.get_node_or_null("World") as WorldGenerator
	_navigation = _main.get_node_or_null("NavigationSystem") as NavigationService
	_player = _main.get_node_or_null("Player") as PlayerController
	_orders = _main.get_node_or_null("OrderSystem") as OrderManager
	if _world == null or _navigation == null or _player == null or _orders == null:
		_expect(false, "主场景缺少世界、导航、玩家或订单系统")
		return
	var ready := false
	for _frame in 120:
		ready = _navigation.is_ready()
		if ready:
			break
		await physics_frame
	_expect(ready, "导航在 120 个物理帧内未就绪")
	if not ready:
		return

	_guide = _orders.get_route_guide()
	_expect(_guide != null, "订单管理器没有创建路线指引节点")
	if _guide == null:
		return
	_expect(not _guide.is_route_visible(), "开始菜单不应显示地面路线")

	_expect(_orders.start_game(), "开始按钮应启动游戏")
	for _frame in 120:
		if _orders.get_current_order() != null and _orders.is_offer_visible():
			break
		await physics_frame
	_expect(_orders.is_offer_visible(), "生成订单后应显示接单界面")
	_expect(not _guide.is_route_visible(), "接单界面不应显示地面路线")
	_expect(_orders.accept_order(), "接单按钮应开始订单")

	var session := _orders.get_session()
	if session == null:
		_expect(false, "接单后没有会话")
		return
	var target := session.get_target_position()
	for _frame in 30:
		if _guide.is_route_visible() and _guide.get_point_count() >= 2:
			break
		_guide.update_route(_player.global_position, target, 0.0, true)
		await physics_frame
	_expect(_guide.is_route_visible(), "活动订单应显示地面路线")
	_expect(_guide.get_point_count() >= 2, "路线至少需要两个点")
	_expect(
		_guide.get_vertex_count() == _guide.get_point_count() * 2,
		"条带顶点数应为路径点数的两倍"
	)
	var path := _guide.get_route_path()
	_expect(NavigationService.get_path_length(path) > 0.0, "路线长度应大于 0")
	_expect(
		_guide.get_target().distance_to(target) <= RouteGuide.TARGET_MOVE_EPS_M,
		"路线目标点与订单目标不一致"
	)
	if path.size() >= 2:
		var snapped_start := _navigation.get_closest_point(_player.global_position)
		var snapped_target := _navigation.get_closest_point(target)
		_expect(
			path[0].distance_to(snapped_start) < 2.0,
			"路线起点未吸附到导航网格"
		)
		_expect(
			path[path.size() - 1].distance_to(snapped_target) < 2.0,
			"路线终点未吸附到导航网格"
		)


func _check_throttle_and_rebuilds() -> void:
	var session := _orders.get_session()
	var order := _orders.get_current_order()
	if session == null or order == null:
		_expect(false, "节流测试缺少活动订单")
		return
	var target := session.get_target_position()

	var stable := _guide.get_rebuild_count()
	for _frame in 10:
		await physics_frame
	_expect(
		_guide.get_rebuild_count() == stable,
		"玩家静止在路线上时不应持续重算"
	)

	# 关闭订单管理器的物理帧更新，用固定 delta 精确验证节流逻辑。
	_orders.set_physics_process(false)
	var player_position := _player.global_position
	_guide.update_route(player_position, target, 0.0, true)
	var baseline := _guide.get_rebuild_count()

	for _index in 5:
		_guide.update_route(player_position, target, 0.02, false)
	_expect(_guide.get_rebuild_count() == baseline, "原地重复更新不应重算路线")

	var path := _guide.get_route_path()
	var off_route := Vector3.INF
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var candidate: Vector3 = player_position + direction * DEVIATION_OFFSET_M
		var moved := _distance_xz(player_position, candidate)
		if (
			RouteGuide.distance_to_path_xz(candidate, path) > RouteGuide.DEVIATION_THRESHOLD_M
			and moved < RouteGuide.TELEPORT_THRESHOLD_M
		):
			off_route = candidate
			break
	_expect(off_route.is_finite(), "无法找到既不传送又明显偏航的测试位置")
	if off_route.is_finite():
		for _index in 5:
			_guide.update_route(off_route, target, 0.02, false)
		_expect(
			_guide.get_rebuild_count() == baseline,
			"节流窗口内偏航不应立即重算"
		)
		_guide.update_route(off_route, target, 0.5, false)
		_expect(
			_guide.get_rebuild_count() == baseline + 1,
			"超过节流窗口且偏航时应重算一次"
		)

	var teleport_position := _farthest_road_node(
		off_route if off_route.is_finite() else player_position
	)
	var before_teleport := _guide.get_rebuild_count()
	_guide.update_route(teleport_position, target, 0.0, false)
	_expect(
		_guide.get_rebuild_count() == before_teleport + 1,
		"传送后应立即重算路线"
	)

	var new_target := order.customer.spawn_point.position
	var before_target := _guide.get_rebuild_count()
	_guide.update_route(teleport_position, new_target, 0.0, false)
	_expect(
		_guide.get_rebuild_count() == before_target + 1,
		"目标变化后应立即重算路线"
	)
	_expect(
		_guide.get_target().distance_to(new_target) <= RouteGuide.TARGET_MOVE_EPS_M,
		"路线目标没有切换到新目标"
	)


func _check_hidden_after_finish() -> void:
	var session := _orders.get_session()
	if session == null:
		_expect(false, "结束检查缺少会话")
		return
	session.advance(session.time_limit + 1.0)
	_expect(session.is_finished(), "超时后订单应结束")
	_expect(not _guide.is_route_visible(), "订单结束后应隐藏地面路线")
	var hud := _orders.get_hud()
	_expect(
		hud != null and hud.is_result_visible(),
		"订单结束后应显示结算面板"
	)
	_expect(_orders.return_to_start_menu(), "结算后应能返回主菜单")
	_expect(not _guide.is_route_visible(), "返回主菜单后应隐藏地面路线")
	_expect(_orders.get_session() == null, "返回主菜单后不应保留会话")
	_expect(_orders.get_current_order() == null, "返回主菜单后不应保留订单")


func _farthest_road_node(origin: Vector3) -> Vector3:
	if _world == null or _world.network == null:
		return origin + Vector3(500.0, 0.0, 0.0)
	var flat_origin := Vector2(origin.x, origin.z)
	var farthest := Vector2.ZERO
	var best := -1.0
	for node in _world.network.nodes:
		var flat := Vector2(node.x, node.y)
		var distance := flat.distance_to(flat_origin)
		if distance > best:
			best = distance
			farthest = flat
	return Vector3(farthest.x, 0.0, farthest.y)


func _distance_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
