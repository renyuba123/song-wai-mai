extends SceneTree

## 手机接单界面测试：相机前手机、订单信息、Y/N 按钮、配送中常驻、拒单和超时自动换单。

var _failed := false
var _main: Node = null
var _player: PlayerController = null
var _orders: OrderManager = null
var _phone: OrderPhone = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _setup_main()
	if _orders != null and _phone != null:
		await _check_first_offer()
		await _check_reject_and_timeout()
		# headless 下 SubViewport 推送鼠标事件会触发 RID 相关崩溃，
		# 点击转发只在有渲染窗口时验证。
		if DisplayServer.get_name() != "headless":
			await _check_clicks()
	if _failed:
		printerr("FAIL phone orders")
	else:
		print("PASS phone orders")
	if _main != null:
		_main.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL phone orders: ", message)


func _setup_main() -> void:
	GameSeeds.pin(118, 1)
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载主场景")
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	var world := _main.get_node_or_null("World") as WorldGenerator
	var navigation := _main.get_node_or_null("NavigationSystem") as NavigationService
	_player = _main.get_node_or_null("Player") as PlayerController
	_orders = _main.get_node_or_null("OrderSystem") as OrderManager
	if world == null or navigation == null or _player == null or _orders == null:
		_expect(false, "主场景缺少世界、导航、玩家或订单系统")
		return
	for _frame in 120:
		if navigation.is_ready():
			break
		await physics_frame
	_expect(navigation.is_ready(), "导航未就绪")
	_phone = _orders.get_phone()
	_expect(_phone != null, "订单管理器没有创建手机")
	if _phone == null:
		return
	_expect(_phone.get_parent() == _player.camera, "手机应挂在玩家相机下")
	_expect(not _phone.is_phone_visible(), "开始菜单不应显示接单手机")


func _check_first_offer() -> void:
	_expect(_orders.start_game(), "开始游戏失败")
	await _wait_for_offer()
	var order := _orders.get_current_order()
	_expect(order != null, "首单没有生成")
	_expect(_orders.is_offer_visible(), "首单应显示在手机上")
	_expect(_phone.visible, "手机模型应可见")
	_expect(_phone.get_remaining_s() > 0.0, "手机倒计时未开始")
	_expect(_orders.get_session() == null, "接单前不应开始配送计时")
	var hud := _orders.get_hud()
	_expect(hud.get_objective_text().contains("手机收到新订单"), "HUD 未显示新订单提醒")
	_expect(hud.get_objective_text().contains("Y 接单"), "HUD 未显示 Y 接单")
	_expect(hud.get_objective_text().contains("N 拒单"), "HUD 未显示 N 拒单")
	if order == null:
		return

	var expected_time := OrderSession.calculate_time_limit(order, _player.move_speed)
	var screen := _phone.get_screen_text()
	_expect(
		screen == OrderPhone.format_offer_text(order, expected_time),
		"手机屏幕文本与订单不一致"
	)
	_expect(screen.contains("新外卖订单"), "手机屏幕缺少标题")
	_expect(screen.contains("取餐："), "手机屏幕缺少取餐信息")
	_expect(screen.contains("送达："), "手机屏幕缺少送达信息")
	if not order.merchant.display_name.is_empty():
		_expect(screen.contains(order.merchant.display_name), "手机屏幕缺少商家店名")
	if not order.customer.display_name.is_empty():
		_expect(screen.contains(order.customer.display_name), "手机屏幕缺少顾客店名")
	_expect(screen.contains("总路程"), "手机屏幕缺少总路程")
	_expect(screen.contains("km"), "手机屏幕缺少公里单位")
	_expect(screen.contains("预计收入 ¥"), "手机屏幕缺少预计收入")
	_expect(screen.contains("限时"), "手机屏幕缺少时限")

	var total_km := maxf(order.get_total_path_length_m(), 0.0) / 1000.0
	var expected_fee := snappedf(OrderPhone.BASE_FEE + total_km * OrderPhone.FEE_PER_KM, 0.01)
	_expect(
		is_equal_approx(OrderPhone.calculate_fee(order), expected_fee),
		"配送费计算错误"
	)

	var accept_button := _phone.find_child("AcceptButton", true, false) as Button
	var reject_button := _phone.find_child("RejectButton", true, false) as Button
	_expect(
		accept_button != null and accept_button.text.contains("立即接单")
		and accept_button.text.contains("Y"),
		"手机缺少立即接单按钮"
	)
	_expect(
		reject_button != null and reject_button.text.contains("拒绝")
		and reject_button.text.contains("N"),
		"手机缺少拒绝按钮"
	)

	_expect(_orders.accept_order(), "手机接单失败")
	_expect(not _phone.is_offer_visible(), "接单后应离开接单界面")
	_expect(_phone.is_active_visible(), "配送中手机应继续显示在车把左侧")
	_expect(_phone.visible, "配送中手机模型应可见")
	_expect(_orders.get_session() != null and _orders.get_session().is_active(), "接单后订单未开始")
	var session := _orders.get_session()
	if session != null:
		var active_screen := _phone.get_screen_text()
		_expect(active_screen.contains("配送中"), "配送中手机缺少状态标题")
		_expect(
			active_screen.contains(session.get_objective_text()),
			"配送中手机缺少当前目标"
		)
		_expect(active_screen.contains("距离"), "配送中手机缺少距离")
		_expect(active_screen.contains("剩余"), "配送中手机缺少剩余时间")
		session.advance(session.time_limit + 1.0)
	_expect(hud.is_result_visible(), "配送超时后应显示结算")
	_expect(not _phone.is_phone_visible(), "结算时手机应隐藏")
	_expect(_orders.return_to_start_menu(), "应能返回主菜单")
	_expect(not _phone.is_phone_visible(), "主菜单不应显示手机")


func _check_reject_and_timeout() -> void:
	_expect(_orders.start_game(), "返回主菜单后重新开始失败")
	await _wait_for_offer()
	var first := _orders.get_current_order()
	_expect(first != null, "重新开始后没有订单")
	if first == null:
		return
	var first_seed := _orders.get_order_seed()
	var first_signature := OrderGenerator.signature(first)
	_expect(_orders.reject_order(), "拒单失败")
	_expect(_orders.get_session() == null, "拒单不应开始配送")
	_expect(_orders.get_current_order() != null, "拒单后应立即生成下一单")
	_expect(_orders.get_order_seed() > first_seed, "拒单后订单种子没有递增")
	if _orders.get_current_order() != null:
		_expect(
			OrderGenerator.signature(_orders.get_current_order()) != first_signature,
			"拒单后不应重复同一单"
		)
	await _wait_for_offer()
	_expect(_orders.is_offer_visible(), "拒单后新订单应显示在手机上")

	var before_timeout_seed := _orders.get_order_seed()
	_phone.advance(OrderPhone.OFFER_TIMEOUT_S + 1.0)
	_expect(_orders.get_session() == null, "倒计时结束不应开始配送")
	_expect(_orders.get_current_order() != null, "倒计时结束应自动换下一单")
	_expect(
		_orders.get_order_seed() > before_timeout_seed,
		"倒计时结束换单后订单种子没有递增"
	)
	await _wait_for_offer()
	_expect(_orders.is_offer_visible(), "倒计时换单后新订单应显示在手机上")
	_expect(_orders.accept_order(), "自动换单后的订单应能接单")
	_expect(_orders.get_session() != null and _orders.get_session().is_active(), "接单后会话未启动")
	_expect(_phone.is_active_visible(), "接单后手机应切到配送模式并继续显示")


func _check_clicks() -> void:
	_expect(_orders.return_to_start_menu(), "点击测试前应能返回主菜单")
	_expect(_orders.start_game(), "点击测试前应能重新开始")
	await _wait_for_offer()
	await process_frame
	await process_frame
	var seed_before := _orders.get_order_seed()
	_click_screen_point(Vector2(99.0, 482.0))
	_expect(_orders.get_session() == null, "点击拒绝按钮不应开始配送")
	_expect(_orders.get_order_seed() > seed_before, "点击拒绝按钮后应生成下一单")
	await _wait_for_offer()
	await process_frame
	await process_frame
	_expect(_orders.is_offer_visible(), "点击拒绝后应显示新订单")
	_click_screen_point(Vector2(250.0, 482.0))
	_expect(
		_orders.get_session() != null and _orders.get_session().is_active(),
		"点击立即接单按钮应开始配送"
	)
	_expect(_phone.is_active_visible(), "点击接单后手机应切到配送模式")


func _click_screen_point(logical_point: Vector2) -> void:
	## 把屏幕逻辑坐标投回三维手机表面，再走真实的点击转发路径。
	var screen := _phone.find_child("Screen", true, false) as MeshInstance3D
	if screen == null:
		_expect(false, "找不到手机屏幕网格")
		return
	var local_point := Vector3(
		(logical_point.x / OrderPhone.SCREEN_LOGICAL_SIZE.x - 0.5)
		* OrderPhone.SCREEN_QUAD_SIZE.x,
		(0.5 - logical_point.y / OrderPhone.SCREEN_LOGICAL_SIZE.y)
		* OrderPhone.SCREEN_QUAD_SIZE.y,
		0.0
	)
	var screen_position := _player.camera.unproject_position(
		screen.global_transform * local_point
	)
	_phone._push_pointer(screen_position, true)
	_phone._push_pointer(screen_position, false)


func _wait_for_offer() -> void:
	for _frame in 120:
		if _orders.is_offer_visible():
			return
		await physics_frame
