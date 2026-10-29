extends SceneTree

## 右上角面板测试：配送收支数字、开始/结算时隐藏、F9 开关和自检行内容。
## 和 test_menu_ui 一样只挂载 OrderHUD，不加载主场景。

var _failed := false
var _hud: OrderHUD = null
var _wallet: DeliveryWallet = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_hud = OrderHUD.new()
	root.add_child(_hud)
	await process_frame
	await process_frame
	_wallet = DeliveryWallet.new()
	_hud.bind_wallet(_wallet)
	await process_frame
	_check_wallet_panel()
	_check_visibility()
	await _check_self_check()
	await _check_bounds()
	if _failed:
		printerr("FAIL hud panels")
	else:
		print("PASS hud panels")
	_hud.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL hud panels: ", message)


func _check_wallet_panel() -> void:
	_hud.show_waiting()
	_expect(_hud.is_wallet_panel_visible(), "配送中应显示右上角收支面板")
	_expect(_hud.get_balance_text() == "500", "初始余额应为 500：%s" % _hud.get_balance_text())
	_expect(_hud.get_wallet_row_text(0) == "+0", "本单收入初始为 +0")
	_expect(_hud.get_wallet_row_text(1) == "0", "累计收入初始为 0")
	_expect(_hud.get_wallet_row_text(2) == "-0", "累计赔偿初始为 -0")

	_wallet.add_income(23.4)
	_expect(
		_hud.get_balance_text() == "523.40",
		"收入后余额应为 523.40：%s" % _hud.get_balance_text()
	)
	_expect(
		_hud.get_wallet_row_text(0) == "+23.40",
		"本单收入应显示 +23.40：%s" % _hud.get_wallet_row_text(0)
	)
	_expect(
		_hud.get_wallet_row_text(1) == "23.40",
		"累计收入应显示 23.40：%s" % _hud.get_wallet_row_text(1)
	)

	_wallet.add_compensation(DeliveryWallet.HIT_COMPENSATION)
	_expect(
		_hud.get_balance_text() == "473.40",
		"赔偿后余额应为 473.40：%s" % _hud.get_balance_text()
	)
	_expect(
		_hud.get_wallet_row_text(2) == "-50",
		"累计赔偿应显示 -50：%s" % _hud.get_wallet_row_text(2)
	)

	_wallet.reset()
	_expect(_hud.get_balance_text() == "500", "重置后余额应回到 500")
	print("PASS hud panels wallet")


func _check_visibility() -> void:
	_hud.show_start_menu(118)
	_expect(not _hud.is_wallet_panel_visible(), "开始界面不应显示收支面板")

	_hud.show_waiting()
	_expect(_hud.is_wallet_panel_visible(), "进入配送后应重新显示收支面板")

	var order := _make_order()
	var session := OrderSession.new(order, 5.0)
	session.try_interact(order.merchant.spawn_point.position)
	session.try_interact(order.customer.spawn_point.position)
	_hud.show_result(order, session)
	_expect(not _hud.is_wallet_panel_visible(), "结算界面不应显示收支面板")
	print("PASS hud panels visibility")


func _check_self_check() -> void:
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载玩家场景")
		return
	var player := packed.instantiate() as PlayerController
	root.add_child(player)
	await process_frame
	_hud.bind_player(player)
	_hud.show_waiting()
	_hud.refresh_self_check()

	var focus_text := _hud.get_self_check_value(0)
	_expect(
		focus_text == "已获得" or focus_text == "未获得",
		"窗口焦点行应给出明确状态：%s" % focus_text
	)
	_expect(
		_hud.get_self_check_value(1) == "已连接",
		"玩家可控时输入应显示已连接：%s" % _hud.get_self_check_value(1)
	)
	_expect(
		_hud.get_self_check_value(3).begins_with("可控制"),
		"角色状态应显示可控制：%s" % _hud.get_self_check_value(3)
	)
	_expect(
		_hud.get_self_check_value(3).contains("m/s"),
		"角色状态应带速度：%s" % _hud.get_self_check_value(3)
	)

	player.set_controls_enabled(false)
	_hud.refresh_self_check()
	_expect(
		_hud.get_self_check_value(1) == "已暂停",
		"关闭控制后输入应显示已暂停：%s" % _hud.get_self_check_value(1)
	)
	_expect(
		_hud.get_self_check_value(3).begins_with("菜单中"),
		"关闭控制后角色状态应显示菜单中：%s" % _hud.get_self_check_value(3)
	)

	_expect(_hud.is_self_check_visible(), "自检面板默认可见")
	_hud.toggle_self_check()
	_expect(not _hud.is_self_check_visible(), "F9 应隐藏自检面板")
	_hud.toggle_self_check()
	_expect(_hud.is_self_check_visible(), "再按 F9 应恢复自检面板")
	print("PASS hud panels self check")

	player.queue_free()
	await process_frame


func _check_bounds() -> void:
	_hud.show_waiting()
	await process_frame
	var view := _hud.get_viewport().get_visible_rect()
	var rect := _hud.get_right_column_rect()
	_expect(rect.size.x > 0.0 and rect.size.y > 0.0, "右上角面板应有实际尺寸")
	_expect(rect.position.x > view.size.x * 0.4, "右上角面板应靠右：%s" % str(rect))
	_expect(
		rect.position.x >= -1.0 and rect.end.x <= view.size.x + 1.0,
		"右上角面板不应超出屏幕：rect=%s viewport=%s" % [str(rect), str(view.size)]
	)
	print("PASS hud panels bounds")


func _make_order() -> DeliveryOrder:
	var order := DeliveryOrder.new()
	order.city_seed = 118
	order.order_seed = 1
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
