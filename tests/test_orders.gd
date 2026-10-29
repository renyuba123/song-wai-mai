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
		ready = _navigation.is_ready()
		if ready:
			break
		await physics_frame
	_expect(ready, "导航在 120 个物理帧内未就绪")
	_expect(_orders.is_start_screen_visible(), "启动时应显示开始界面")
	_expect(_orders.get_current_order() == null, "开始界面前不应生成订单")
	_expect(not _player.controls_enabled, "菜单期间应关闭玩家控制")
	_expect(_orders.start_game(), "开始按钮应启动游戏")
	for _frame in 120:
		if _orders.get_current_order() != null and _orders.is_offer_visible():
			break
		await physics_frame
	_expect(_orders.get_current_order() != null, "订单系统在 120 个物理帧内没有生成首单")
	_expect(_orders.is_offer_visible(), "生成首单后应显示接单界面")
	_expect(_orders.get_session() == null, "接单前不应开始倒计时")
	_expect(_orders.get_offer_text().contains("限时"), "接单界面应显示时限")
	_expect(_orders.accept_order(), "接单按钮应开始订单")
	_expect(_orders.get_session() != null and _orders.get_session().is_active(), "接单后订单应进入活动状态")
	_expect(_player.controls_enabled, "接单后应恢复玩家控制")
	_expect(_world.city != null and _world.city.is_valid(_world.network), "主场景城市校验失败")


func _check_starts() -> void:
	var starts := _world.city.player_starts
	_expect(starts.size() >= 2, "随机起点需要至少两个安全玩家起点")
	_expect(starts.size() <= CityGenerator.MAX_PLAYER_STARTS, "玩家起点数量超过上限")
	_expect(
		_world.city.player_start == starts[0],
		"player_start 应指向 player_starts 首项"
	)
	for index in starts.size():
		var start := starts[index]
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
	_expect(_world.city.player_starts.has(first.start), "订单起点不在玩家起点的列表中")
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
	_expect(
		is_equal_approx(
			session.time_limit,
			OrderSession.calculate_time_limit(order, _player.move_speed)
		),
		"接单界面与会话的时限公式不一致"
	)
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
	_expect(
		failed.get_failure_reason() == OrderSession.FailureReason.TIMEOUT,
		"超时失败原因错误"
	)
	_expect(failed.get_failure_text() == "倒计时已结束", "超时失败文本错误")
	_expect(
		not failed.fail(OrderSession.FailureReason.HIT_BY_CAR),
		"已结束的订单不应再次失败"
	)
	failed.advance(10.0)
	_expect(fail_events.size() == 1, "失败后不应重复结算")

	var car_order := OrderGenerator.generate(
		_world.city, _world.network, _navigation, 3
	)
	if car_order == null:
		_expect(false, "无法生成撞车测试订单")
		return
	var car_failed := OrderSession.new(car_order, _player.move_speed)
	var car_events: Array = []
	car_failed.finished.connect(func(success: bool) -> void: car_events.append(success))
	car_failed.advance(5.0)
	var car_remaining := car_failed.time_remaining
	var car_elapsed := car_failed.get_elapsed_s()
	_expect(
		not car_failed.fail(OrderSession.FailureReason.NONE),
		"失败原因为空时不应结束订单"
	)
	_expect(
		car_failed.fail(OrderSession.FailureReason.HIT_BY_CAR),
		"活动订单应能被标记为撞车失败"
	)
	_expect(
		car_failed.state == OrderSession.State.FAILED,
		"撞车后应进入失败状态"
	)
	_expect(
		car_failed.get_failure_reason() == OrderSession.FailureReason.HIT_BY_CAR,
		"撞车失败原因错误"
	)
	_expect(
		is_equal_approx(car_failed.time_remaining, car_remaining),
		"撞车失败不应清空剩余时间"
	)
	_expect(
		is_equal_approx(car_failed.get_elapsed_s(), car_elapsed),
		"撞车失败不应改变已用时间"
	)
	_expect(car_failed.get_failure_text().contains("撞"), "撞车失败文本未说明原因")
	_expect(car_events == [false], "撞车应只触发一次 finished(false)")
	_expect(
		not car_failed.fail(OrderSession.FailureReason.HIT_BY_CAR),
		"撞车失败后不应重复结算"
	)
	_expect(car_events.size() == 1, "撞车失败后不应重复触发 finished")
	_expect(
		not session.fail(OrderSession.FailureReason.HIT_BY_CAR),
		"已成功送达的订单不应被撞车失败覆盖"
	)


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
	var merchant := CitySite.new()
	merchant.id = &"merchant_007"
	merchant.kind = CitySite.Kind.MERCHANT
	_expect(OrderHUD.site_label(merchant) == "商家 #007", "商家站点回退名称错误")
	merchant.display_name = "麦香面包房"
	_expect(
		OrderHUD.site_label(merchant) == "麦香面包房（商家）",
		"商家站点未优先显示店名"
	)
	var customer := CitySite.new()
	customer.id = &"customer_012"
	customer.kind = CitySite.Kind.RESIDENTIAL
	_expect(OrderHUD.site_label(customer) == "顾客 #012", "顾客站点回退名称错误")
	customer.display_name = "拾光书店"
	_expect(
		OrderHUD.site_label(customer) == "拾光书店（顾客）",
		"顾客站点未优先显示店名"
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
	var customer_name := order.customer.display_name
	var expected_objective := (
		"送达「%s」" % customer_name if not customer_name.is_empty() else "送达顾客"
	)
	_expect(hud.get_objective_text() == expected_objective, "经理取餐后 HUD 未更新")
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
	var next_order := _orders.get_current_order()
	_expect(next_order != null, "下一单没有生成")
	if next_order == null:
		return
	_expect(
		OrderGenerator.signature(next_order) != completed_signature,
		"下一单不应与上一单完全相同"
	)
	_expect(not hud.is_result_visible(), "新订单未隐藏结算面板")
	_expect(_orders.is_offer_visible(), "下一单应先显示接单界面")
	_expect(_orders.get_session() == null, "接单前不应开始倒计时")
	_expect(not _player.controls_enabled, "接单界面应关闭玩家控制")
	_expect(_orders.accept_order(), "下一单接单按钮应开始订单")
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
	_expect(
		hud.get_result_body().contains("倒计时已结束"),
		"超时结算正文应说明倒计时结束"
	)
	_expect(not _player.controls_enabled, "结算界面应关闭玩家控制")
	_expect(_orders.handle_restart(), "失败后 R 应生成下一单")
	_expect(_orders.get_order_seed() > timeout_seed, "失败后订单种子没有递增")
	_expect(_orders.is_offer_visible(), "失败后下一单应先显示接单界面")
	_expect(_orders.accept_order(), "失败后下一单应能接单")
	_expect(
		_orders.get_session() != null and _orders.get_session().state == OrderSession.State.TO_MERCHANT,
		"失败后新订单状态未重置"
	)
	_expect(not hud.is_result_visible(), "失败后新订单未隐藏结算面板")

	_expect(_orders.return_to_start_menu(), "结算后应能返回主菜单")
	_expect(hud.is_start_menu_visible(), "返回主菜单后应显示开始界面")
	_expect(_orders.get_current_order() == null, "返回主菜单后不应保留当前订单")
	_expect(_orders.get_session() == null, "返回主菜单后不应保留会话")
	_expect(not _player.controls_enabled, "主菜单应关闭玩家控制")
	_expect(_orders.start_game(), "返回主菜单后应能重新开始")
	_expect(_orders.is_offer_visible(), "重新开始后应生成待接订单")
	_expect(_orders.accept_order(), "重新开始后应能接单")
	_expect(_orders.get_session().is_active(), "重新开始后订单应处于活动状态")


func _point_in_building(point: Vector3, city: CityContent) -> bool:
	var xz := Vector2(point.x, point.z)
	for building in city.buildings:
		if Rect2(building.rect).has_point(xz):
			return true
	return false
