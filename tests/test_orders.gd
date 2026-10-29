extends SceneTree

## 阶段二订单测试：随机起点、确定性生成、可达性、状态机、
## HUD 方向提示和订单管理器重开/换单/超时。

var _failed := false
var _main: Node = null
var _world: WorldGenerator = null
var _navigation: NavigationService = null
var _player: PlayerController = null
var _orders: OrderManager = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _setup_main()
	if _world != null:
		_check_starts()
		var order := _check_generation()
		if order != null:
			_check_session(order)
		_check_hud_direction()
		await _check_manager()
	if _failed:
		printerr("FAIL orders")
	else:
		print("PASS orders")
	if _main != null:
		_main.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL orders: ", message)


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
		if not _orders.get_phone_offer().is_empty():
			_expect(_orders.accept_phone_order(str(_orders.get_phone_offer().get("id", ""))), "接单失败")
		ready = _navigation.is_ready()
		if ready and _orders.get_current_order() != null:
			break
		await physics_frame
	_expect(ready, "导航在 120 个物理帧内未就绪")
	_expect(_orders.get_current_order() != null, "订单系统在 120 个物理帧内没有生成首单")
	_expect(_world.city != null and _world.city.is_valid(_world.network), "主场景城市校验失败")


func _check_starts() -> void:
	var starts: Array[SpawnPoint] = _world.city.get_available_player_starts()
	_expect(starts.size() >= 1, "城市至少需要一个安全玩家起点")
	_expect(starts.size() <= 1, "当前兼容模式只允许一个确定性玩家起点")
	_expect(
		_world.city.player_start == starts[0],
		"player_start 应指向 player_starts 首项"
	)
	for index in starts.size():
		var start: SpawnPoint = starts[index]
		_expect(start != null, "玩家起点 %d 为空" % index)
		if start == null:
			continue
		_expect(start.is_valid(_world.network), "玩家起点 %d 契约无效" % index)
		_expect(start.kind == SpawnPoint.Kind.PLAYER_START, "玩家起点 %d 类型错误" % index)
		_expect(start.site_id == &"", "玩家起点 %d 不应关联站点" % index)
		_expect(
			not _point_in_building(start.position, _world.city),
			"玩家起点 %d 落在建筑内" % index
		)
	print("PASS orders starts=", starts.size())


func _check_generation() -> DeliveryOrder:
	var first := OrderGenerator.generate(
		_world.city, _world.network, _navigation, 1
	)
	var second := OrderGenerator.generate(
		_world.city, _world.network, _navigation, 1
	)
	_expect(first != null, "订单种子 1 生成失败")
	_expect(second != null, "订单种子 1 第二次生成失败")
	if first == null or second == null:
		return first
	_expect(
		OrderGenerator.signature(first) == OrderGenerator.signature(second),
		"同种子订单签名不确定"
	)
	_expect(first.start == second.start, "同种子订单起点不确定")
	_expect(first.merchant.id == second.merchant.id, "同种子订单商家不确定")
	_expect(first.customer.id == second.customer.id, "同种子订单顾客不确定")
	_expect(
		is_equal_approx(first.pickup_path_length_m, second.pickup_path_length_m),
		"同种子取餐路径长度不确定"
	)
	_expect(
		is_equal_approx(first.delivery_path_length_m, second.delivery_path_length_m),
		"同种子送达路径长度不确定"
	)
	_expect(first.is_valid(_world.network), "订单契约无效：%s" % str(first.validate(_world.network)))
	_expect(_world.city.get_available_player_starts().has(first.start), "订单起点不在玩家起点的列表中")
	_expect(first.merchant.kind == CitySite.Kind.MERCHANT, "订单商家类型错误")
	_expect(first.customer.kind == CitySite.Kind.RESIDENTIAL, "订单顾客类型错误")

	var signatures := {}
	var start_positions := {}
	for seed_value in range(1, 9):
		var order := OrderGenerator.generate(
			_world.city, _world.network, _navigation, seed_value
		)
		_expect(order != null, "订单种子 %d 生成失败" % seed_value)
		if order == null:
			continue
		_expect(
			order.is_valid(_world.network),
			"订单种子 %d 契约无效：%s" % [seed_value, str(order.validate(_world.network))]
		)
		signatures[OrderGenerator.signature(order)] = true
		start_positions["%s" % order.start.position] = true
		_check_route(order, seed_value)
	_expect(signatures.size() >= 2, "不同订单种子应产生不同订单")
	if _world.city.get_available_player_starts().size() >= 2:
		_expect(start_positions.size() >= 2, "不同订单种子应产生不同随机起点")

	var unbuilt := NavigationService.new()
	var no_nav_order := OrderGenerator.generate(
		_world.city, _world.network, unbuilt, 1
	)
	_expect(no_nav_order == null, "导航未就绪时不应生成订单")
	unbuilt.free()
	return first


func _check_route(order: DeliveryOrder, seed_value: int) -> void:
	var from := _navigation.get_closest_point(order.start.position)
	var pickup := _navigation.get_closest_point(order.merchant.spawn_point.position)
	var customer := _navigation.get_closest_point(order.customer.spawn_point.position)
	_expect(from.is_finite() and pickup.is_finite() and customer.is_finite(), "订单种子 %d 的起点/站点无法吸附导航" % seed_value)
	var pickup_path := _navigation.find_path(from, pickup)
	var delivery_path := _navigation.find_path(pickup, customer)
	_expect(pickup_path.size() >= 2, "订单种子 %d 的取餐路径不可达" % seed_value)
	_expect(delivery_path.size() >= 2, "订单种子 %d 的送达路径不可达" % seed_value)
	if pickup_path.size() >= 2:
		_expect(
			is_equal_approx(
				NavigationService.get_path_length(pickup_path),
				order.pickup_path_length_m
			),
			"订单种子 %d 的取餐路径长度不一致" % seed_value
		)
	if delivery_path.size() >= 2:
		_expect(
			is_equal_approx(
				NavigationService.get_path_length(delivery_path),
				order.delivery_path_length_m
			),
			"订单种子 %d 的送达路径长度不一致" % seed_value
		)


func _check_session(order: DeliveryOrder) -> void:
	var session := OrderSession.new(order, _player.move_speed)
	var finished_events: Array = []
	session.finished.connect(func(success: bool) -> void: finished_events.append(success))
	_expect(session.state == OrderSession.State.TO_MERCHANT, "新会话应处于取餐阶段")
	_expect(session.time_limit >= OrderSession.MIN_TIME_LIMIT_S, "订单时限过短")
	_expect(session.is_active(), "新会话应处于活动状态")
	_expect(
		not session.try_interact(Vector3(100000.0, 0.0, 100000.0)),
		"远离目标时不应能交互"
	)

	_expect(
		session.try_interact(order.merchant.spawn_point.position),
		"在商家处应能取餐"
	)
	_expect(session.state == OrderSession.State.TO_CUSTOMER, "取餐后应进入送达阶段")
	_expect(session.get_target_site() == order.customer, "取餐后目标应切换到顾客")
	_expect(session.get_interact_prompt() == "按 E 送达", "取餐后 E 提示错误")

	session.advance(1.0)
	_expect(session.time_remaining < session.time_limit, "倒计时应减少")
	_expect(
		session.try_interact(order.customer.spawn_point.position),
		"在顾客处应能送达"
	)
	_expect(session.state == OrderSession.State.DELIVERED, "送达后应完成订单")
	_expect(session.is_success(), "成功订单状态错误")
	_expect(finished_events == [true], "成功应只触发一次 finished(true)")
	var remaining := session.time_remaining
	session.advance(10.0)
	_expect(
		not session.try_interact(order.customer.spawn_point.position),
		"终态后不应再次交互"
	)
	_expect(
		is_equal_approx(session.time_remaining, remaining),
		"终态后倒计时不应继续"
	)
	_expect(finished_events.size() == 1, "终态后不应重复触发 finished")

	var failed_order := OrderGenerator.generate(
		_world.city, _world.network, _navigation, 2
	)
	if failed_order == null:
		_expect(false, "无法生成超时测试订单")
		return
	var failed := OrderSession.new(failed_order, _player.move_speed)
	var fail_events: Array = []
	failed.finished.connect(func(success: bool) -> void: fail_events.append(success))
	failed.advance(failed.time_limit + 1.0)
	_expect(failed.state == OrderSession.State.FAILED, "超时应进入失败状态")
	_expect(fail_events == [false], "超时应只触发一次 finished(false)")
	_expect(is_zero_approx(failed.time_remaining), "失败后剩余时间应为 0")
	failed.advance(10.0)
	_expect(fail_events.size() == 1, "失败后不应重复结算")


func _check_hud_direction() -> void:
	_expect(
		OrderHUD.direction_arrow(Vector3.ZERO, 0.0, Vector3(0.0, 0.0, -10.0)) == "↑",
		"朝向北侧的方向箭头错误"
	)
	_expect(
		OrderHUD.direction_arrow(Vector3.ZERO, 0.0, Vector3(10.0, 0.0, 0.0)) == "→",
		"朝向东侧的方向箭头错误"
	)
	_expect(
		OrderHUD.direction_arrow(Vector3.ZERO, 0.0, Vector3(0.0, 0.0, 10.0)) == "↓",
		"朝向南侧的方向箭头错误"
	)


func _check_manager() -> void:
	var order := _orders.get_current_order()
	_expect(order != null, "订单管理器没有当前订单")
	if order == null:
		return
	var hud := _orders.get_hud()
	_expect(hud != null, "订单管理器缺少 HUD")
	if hud == null:
		return
	_expect(not hud.get_objective_text().is_empty(), "HUD 目标文本为空")
	_expect(not hud.get_detail_text().is_empty(), "HUD 距离/时间文本为空")
	var player_xz := Vector2(_player.global_position.x, _player.global_position.z)
	var start_xz := Vector2(order.start.position.x, order.start.position.z)
	_expect(player_xz.distance_to(start_xz) < 1.0, "玩家没有传送到订单起点")
	_expect(
		not _orders.try_interact(Vector3(100000.0, 0.0, 100000.0)),
		"远离目标时管理器不应允许交互"
	)

	_player.global_position = order.merchant.spawn_point.position
	_expect(_orders.try_interact(_player.global_position), "经理取餐交互失败")
	_expect(
		_orders.get_session().state == OrderSession.State.TO_CUSTOMER,
		"经理取餐后状态错误"
	)
	_expect(hud.get_objective_text() == "送达顾客", "经理取餐后 HUD 未更新")
	var beacon := _orders.get_node_or_null("TargetBeacon") as MeshInstance3D
	_expect(beacon != null and beacon.visible, "目标信标未显示")

	_player.global_position = order.customer.spawn_point.position
	_expect(_orders.try_interact(_player.global_position), "经理送达交互失败")
	_expect(
		_orders.get_session().state == OrderSession.State.DELIVERED,
		"经理送达后状态错误"
	)
	_expect(hud.is_result_visible(), "完成后结算面板未显示")
	_expect(hud.get_result_title() == "订单完成", "成功结算标题错误")

	var completed_seed := _orders.get_order_seed()
	var completed_signature := OrderGenerator.signature(order)
	_expect(_orders.handle_restart(), "结算后 R 应生成下一单")
	_expect(_orders.get_order_seed() > completed_seed, "下一单种子没有递增")
	_expect(not _orders.get_phone_offer().is_empty(), "下一单应先等待手机确认")
	_expect(_orders.accept_phone_order(str(_orders.get_phone_offer().get("id", ""))), "下一单接单失败")
	var next_order := _orders.get_current_order()
	_expect(next_order != null, "下一单没有生成")
	if next_order == null:
		return
	_expect(
		OrderGenerator.signature(next_order) != completed_signature,
		"下一单不应与上一单完全相同"
	)
	_expect(not hud.is_result_visible(), "新订单未隐藏结算面板")
	_expect(
		_orders.get_session().state == OrderSession.State.TO_MERCHANT,
		"新订单状态未重置"
	)
	_expect(
		is_equal_approx(_orders.get_session().time_remaining, _orders.get_session().time_limit),
		"新订单倒计时未重置"
	)

	var restarted_seed := _orders.get_order_seed()
	var restarted_signature := OrderGenerator.signature(next_order)
	_expect(_orders.handle_restart(), "配送中 R 应重开同一单")
	_expect(_orders.get_order_seed() == restarted_seed, "重开同一单不应改变订单种子")
	_expect(
		OrderGenerator.signature(_orders.get_current_order()) == restarted_signature,
		"重开同一单不应改变订单"
	)
	_expect(
		_orders.get_session().state == OrderSession.State.TO_MERCHANT,
		"重开同一单后状态未重置"
	)
	_expect(
		is_equal_approx(_orders.get_session().time_remaining, _orders.get_session().time_limit),
		"重开同一单后倒计时未重置"
	)

	var timeout_seed := _orders.get_order_seed()
	_orders.get_session().advance(_orders.get_session().time_limit + 1.0)
	_expect(
		_orders.get_session().state == OrderSession.State.FAILED,
		"超时后状态应为失败"
	)
	_expect(hud.is_result_visible(), "超时后结算面板未显示")
	_expect(hud.get_result_title() == "订单失败", "失败结算标题错误")
	_expect(_orders.handle_restart(), "失败后 R 应生成下一单")
	_expect(not _orders.get_phone_offer().is_empty(), "失败后下一单应先等待手机确认")
	_expect(_orders.accept_phone_order(str(_orders.get_phone_offer().get("id", ""))), "失败后下一单接单失败")
	_expect(_orders.get_order_seed() > timeout_seed, "失败后订单种子没有递增")
	_expect(
		_orders.get_session() != null and _orders.get_session().state == OrderSession.State.TO_MERCHANT,
		"失败后新订单状态未重置"
	)
	_expect(not hud.is_result_visible(), "失败后新订单未隐藏结算面板")


func _point_in_building(point: Vector3, city: CityContent) -> bool:
	var xz := Vector2(point.x, point.z)
	for building in city.buildings:
		if Rect2(building.rect).has_point(xz):
			return true
	return false
