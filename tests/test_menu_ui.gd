extends SceneTree

## 开始/结算界面测试：标题页文案、主菜单不显示种子、结算统计、路线和按钮布局。
## 这里只挂载 OrderHUD，不加载主场景和模型，避免 headless 下已知的
## RendererDummy / RID 退出崩溃影响界面断言；主场景集成由 test_orders 覆盖。

var _failed := false
var _hud: OrderHUD = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_hud = OrderHUD.new()
	root.add_child(_hud)
	await process_frame
	await process_frame
	_check_start_menu()
	await _check_toast()
	_check_success_result()
	_check_failure_result()
	if _failed:
		printerr("FAIL menu ui")
	else:
		print("PASS menu ui")
	_hud.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL menu ui: ", message)


func _check_start_menu() -> void:
	_hud.show_start_menu()
	_expect(_hud.is_start_menu_visible(), "启动时应显示开始界面")
	_expect(_hud.get_start_title_text() == "大城市送外卖", "开始界面标题错误")
	_expect(_hud.get_start_subtitle_text().contains("程序化"), "开始界面应说明城市由程序生成")
	_expect(_hud.get_start_button_text().contains("开始接单"), "开始按钮文案错误")
	_expect(not _hud.get_start_footer_text().contains("种子"), "主菜单不应显示种子")
	_expect(_hud.is_any_modal_visible(), "开始界面应被视为模态界面")
	_check_inside(_hud.get_start_content_rect(), "开始界面内容")
	print("PASS menu ui start")


func _check_toast() -> void:
	var message := "撞到行人，赔偿 1000 元"
	_hud.show_toast(message, 0.08)
	_expect(_hud.get_toast_text() == message, "提示文本错误")
	_expect(_hud.is_toast_visible(), "提示显示时应可见")
	await create_timer(0.16).timeout
	_expect(not _hud.is_toast_visible(), "提示应在计时结束后自动隐藏")
	print("PASS menu ui toast")


func _check_success_result() -> void:
	var order := _make_order(1)
	var session := OrderSession.new(order, 5.0)
	_expect(session.try_interact(order.merchant.spawn_point.position), "成功用例取餐失败")
	_expect(session.try_interact(order.customer.spawn_point.position), "成功用例送达失败")
	_expect(session.is_success(), "成功用例状态错误")
	_hud.show_result(order, session)
	_expect(_hud.is_result_visible(), "送达后应显示结算界面")
	_expect(_hud.get_result_title() == "订单完成", "成功结算标题错误")
	_expect(_hud.get_result_route_text().contains("城市广场"), "成功结算缺少商家名")
	_expect(_hud.get_result_route_text().contains("拾光书店"), "成功结算缺少顾客名")
	_expect(_hud.get_result_route_text().contains("取餐") and _hud.get_result_route_text().contains("送达"), "成功结算缺少取送路线")
	_expect(_hud.get_result_stat_text(0) == "1490 m", "总路程统计错误")
	_expect(_hud.get_result_stat_text(1) == "0:00", "用时统计错误")
	_expect(_hud.get_result_stat_text(2) == "8:27", "剩余时间统计错误")
	_expect(_hud.get_result_income_text().contains("¥"), "成功结算缺少收入")
	_expect(_hud.get_result_body().contains("城市种子 118"), "结算正文缺少城市种子")
	_expect(_hud.get_result_body().contains("剩余时间"), "成功结算正文缺少剩余时间")
	_check_inside(_hud.get_result_card_rect(), "成功结算卡片")
	print("PASS menu ui success")


func _check_failure_result() -> void:
	var order := _make_order(2)
	var session := OrderSession.new(order, 5.0)
	_expect(session.fail(OrderSession.FailureReason.HIT_BY_CAR), "撞车失败应结算")
	_hud.show_result(order, session)
	_expect(_hud.is_result_visible(), "失败后应显示结算界面")
	_expect(_hud.get_result_title() == "订单失败", "失败结算标题错误")
	_expect(_hud.get_result_body().contains("撞"), "失败结算正文应说明撞车原因")
	_expect(_hud.get_result_stat_text(2) == "未完成", "失败结算的完成统计错误")
	_expect(_hud.get_result_income_text().contains("¥0.00"), "失败结算收入应为 0")
	_expect(_hud.get_result_route_text().contains("城市广场"), "失败结算缺少商家名")
	_check_inside(_hud.get_result_card_rect(), "失败结算卡片")
	print("PASS menu ui failure")


func _make_order(order_seed: int) -> DeliveryOrder:
	var order := DeliveryOrder.new()
	order.city_seed = 118
	order.order_seed = order_seed
	order.start = _make_spawn(SpawnPoint.Kind.PLAYER_START, &"", Vector3(0, 0, 10))
	order.merchant = _make_site(&"merchant_1", CitySite.Kind.MERCHANT, "城市广场", Vector3.ZERO)
	order.customer = _make_site(&"customer_1", CitySite.Kind.RESIDENTIAL, "拾光书店", Vector3(0, 0, 100))
	order.pickup_path_length_m = 620.0
	order.delivery_path_length_m = 870.0
	return order


func _make_spawn(kind: SpawnPoint.Kind, site_id: StringName, position: Vector3) -> SpawnPoint:
	var spawn := SpawnPoint.new()
	spawn.kind = kind
	spawn.site_id = site_id
	spawn.position = position
	spawn.lateral_offset_m = 1.0
	return spawn


func _make_site(id: StringName, kind: CitySite.Kind, display_name: String, position: Vector3) -> CitySite:
	var site := CitySite.new()
	site.id = id
	site.kind = kind
	site.display_name = display_name
	site.spawn_point = _make_spawn(
		SpawnPoint.Kind.MERCHANT if kind == CitySite.Kind.MERCHANT else SpawnPoint.Kind.CUSTOMER,
		id,
		position
	)
	return site


func _check_inside(rect: Rect2, label: String) -> void:
	var view := _hud.get_viewport().get_visible_rect()
	var inside := (
		rect.size.x > 0.0 and rect.size.y > 0.0
		and rect.position.x >= -1.0 and rect.position.y >= -1.0
		and rect.end.x <= view.size.x + 1.0 and rect.end.y <= view.size.y + 1.0
	)
	_expect(
		inside,
		"%s超出可视区域：rect=%s viewport=%s" % [label, str(rect), str(view.size)]
	)
