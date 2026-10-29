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
	await _check_start_settings()
	_check_offer_detail()
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
	_expect(_hud.get_start_title_text() == "大城市\n送外卖", "开始界面标题错误")
	_expect(_hud.get_start_subtitle_text() == "CITY DELIVERY", "开始界面副标题错误")
	_expect(_hud.get_start_button_text().contains("START GAME"), "开始按钮文案错误")
	_expect(_hud.find_child("StartSettingsButton", true, false) != null, "开始界面缺少设置入口")
	var art := _hud.find_child("StartBackdrop", true, false) as StartMenuArt
	_expect(art != null, "开始界面应使用参考图层")
	if art != null:
		var image := art.get_node("ReferenceImage") as TextureRect
		_expect(image.texture.resource_path == "res://assets/ui/start_reference.png", "开始界面必须使用原图")
		_expect(art.get_node_or_null("ContinueButton") == null, "不应保留 CONTINUE 按钮")
		_expect(art.get_node_or_null("LoadButton") == null, "不应显示 LOAD GAME 按钮")
		var start := art.get_node("StartButton") as Button
		var settings := art.get_node("SettingsButton") as Button
		var exit := art.get_node("ExitButton") as Button
		var exit_requested := {"value": false}
		art.exit_pressed.connect(func() -> void: exit_requested["value"] = true)
		exit.emit_signal("pressed")
		_expect(exit_requested["value"], "开始界面的退出按钮应发出确认请求")
		_expect(is_equal_approx(settings.position.y - start.position.y, exit.position.y - settings.position.y), "三个菜单选项应等距排列")
		for button_name in ["StartButton", "SettingsButton", "ExitButton"]:
			var button := art.get_node(button_name) as Button
			_expect(button.text.is_empty(), "%s 不应重复绘制文字" % button_name)
			_expect(button.get_theme_stylebox("normal") is StyleBoxEmpty, "%s 背景必须透明" % button_name)
	_expect(not _hud.get_start_footer_text().contains("种子"), "主菜单不应显示种子")
	_expect(_hud.is_any_modal_visible(), "开始界面应被视为模态界面")
	_check_inside(_hud.get_start_content_rect(), "开始界面内容")
	print("PASS menu ui start")


func _check_start_settings() -> void:
	var pause := PauseController.new()
	root.add_child(pause)
	await process_frame
	pause.open_start_settings()
	_expect(pause.is_settings_visible(), "开始界面应能打开设置")
	var help := pause.find_child("ControlsHelp", true, false) as Label
	_expect(help != null and help.text.contains("W / S"), "操作说明应放在设置中")
	pause.back_to_pause()
	_expect(not pause.is_pause_visible(), "返回设置后应回到开始界面")
	pause.open_exit_confirmation()
	_expect(pause.is_exit_confirmation_visible(), "开始界面退出应打开确认框")
	var cancel := pause.find_child("CancelExitButton", true, false) as Button
	_expect(cancel != null, "退出确认框应有取消按钮")
	if cancel != null:
		cancel.emit_signal("pressed")
	_expect(not pause.is_pause_visible(), "取消退出后应回到开始界面")
	pause.queue_free()
	await process_frame


func _check_offer_detail() -> void:
	var order := _make_order(3)
	var time_limit := 90.0
	var expected_income := DeliveryIncome.calculate(
		order.get_total_path_length_m(), time_limit
	)
	_hud.show_offer(order, time_limit)
	_expect(_hud.is_offer_visible(), "接单阶段应显示接单状态")
	_expect(_hud.is_offer_detail_visible(), "接单阶段右侧应显示详情面板")
	var detail := _hud.get_offer_detail_text()
	_expect(detail.contains("取餐 · 城市广场（商家）"), "右侧详情商家名错误")
	_expect(detail.contains("送达 · 拾光书店（顾客）"), "右侧详情顾客名错误")
	_expect(detail.contains("总路程 1.5 km"), "右侧详情总路程错误")
	_expect(
		detail.contains("预计收入  ¥%d" % expected_income),
		"右侧详情预计收入与 DeliveryIncome 不一致"
	)
	_expect(detail.contains("限时 1:30"), "右侧详情时限错误")
	_expect(detail.contains("剩余 10 秒"), "右侧详情初始倒计时错误")
	_hud.update_offer_countdown(3.2)
	_expect(_hud.get_offer_detail_text().contains("剩余 4 秒"), "右侧详情倒计时未更新")
	_expect(detail.contains("城市种子 118"), "右侧详情缺少城市种子")
	_expect(detail.contains("订单种子 3"), "右侧详情缺少订单种子")
	_expect(detail.contains("Y 接单") and detail.contains("N 拒单"), "右侧详情缺少操作提示")
	_check_inside(_hud.get_offer_detail_rect(), "接单详情面板")
	_hud.hide_offer()
	_expect(not _hud.is_offer_detail_visible(), "离开接单后右侧详情应隐藏")
	print("PASS menu ui offer detail")


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
	_expect(
		_hud.get_result_income_text() == "本单收入  ¥%d" % DeliveryIncome.calculate(
			order.get_total_path_length_m(), session.time_remaining
		),
		"成功结算收入与 DeliveryIncome 公式不一致"
	)
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
	_expect(_hud.get_result_income_text() == "本单收入  ¥0", "失败结算收入应为 0")
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
