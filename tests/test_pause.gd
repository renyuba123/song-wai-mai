extends SceneTree

## 暂停菜单测试：Esc 在菜单/接单/结算界面不打开暂停；配送中 Esc
## 冻结场景树、停玩家控制并显示种子；“重开本单”“返回主菜单”走
## 现有 OrderManager 接口。

var _failed := false
var _main: Node = null
var _navigation: NavigationService = null
var _player: PlayerController = null
var _orders: OrderManager = null
var _pause: PauseController = null
var _settings: GameSettings = null
var _traffic: TrafficSpawner = null
var _settings_test_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _setup_main()
	if _pause != null:
		_check_start_menu_guard()
		await _check_offer_guard()
		await _check_pause_and_resume()
		_check_restart_order()
		_check_result_guard()
		await _check_return_to_menu()
	paused = false
	if _main != null:
		_main.queue_free()
	await process_frame
	_cleanup_settings_file()
	if _failed:
		printerr("FAIL pause")
		quit(1)
	else:
		print("PASS pause")
		quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL pause: ", message)


func _setup_main() -> void:
	_settings_test_path = "res://.godot/test_pause_settings_%d.cfg" % OS.get_process_id()
	_cleanup_settings_file()
	GameSeeds.pin(118, 1)
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载主场景")
		return
	_main = packed.instantiate()
	# 城市精细视觉的 GLB 仍是 LFS pointer；关掉流式加载，只验证暂停逻辑。
	var stream := _main.get_node_or_null("World/CityStreaming") as CityStreaming
	if stream != null:
		stream.set_process(false)
	root.add_child(_main)
	await process_frame
	_navigation = _main.get_node_or_null("NavigationSystem") as NavigationService
	_player = _main.get_node_or_null("Player") as PlayerController
	_orders = _main.get_node_or_null("OrderSystem") as OrderManager
	_pause = _main.get_node_or_null("PauseMenu") as PauseController
	_traffic = _main.get_node_or_null("TrafficSystem") as TrafficSpawner
	_settings = _main.call("get_game_settings") as GameSettings
	if _navigation == null or _player == null or _orders == null:
		_expect(false, "主场景缺少导航、玩家或订单系统")
		return
	_expect(_pause != null, "主场景缺少暂停层 PauseMenu")
	if _pause == null:
		return
	_expect(_settings != null, "主场景缺少持久化设置")
	_expect(_traffic != null, "主场景缺少交通系统")
	if _settings != null:
		_settings.config_path = _settings_test_path
		_settings.reset_to_defaults(false)
		_settings.apply_to(_player, _traffic)
	var ready := false
	for _frame in 120:
		ready = _navigation.is_ready()
		if ready:
			break
		await physics_frame
	_expect(ready, "导航在 120 个物理帧内未就绪")


func _check_start_menu_guard() -> void:
	_expect(_orders.is_start_screen_visible(), "启动时应显示开始界面")
	_press_pause()
	_expect(not paused, "开始界面按 Esc 不应暂停")
	_expect(not _pause.is_pause_visible(), "开始界面按 Esc 不应显示暂停层")
	_expect(_orders.is_start_screen_visible(), "开始界面按 Esc 不应改变界面")


func _check_offer_guard() -> void:
	_expect(_orders.start_game(), "开始按钮应启动游戏")
	for _frame in 120:
		if _orders.is_offer_visible():
			break
		await physics_frame
	_expect(_orders.is_offer_visible(), "生成首单后应显示接单界面")
	_press_pause()
	_expect(not paused, "接单界面按 Esc 不应暂停")
	_expect(not _pause.is_pause_visible(), "接单界面按 Esc 不应显示暂停层")
	_expect(_orders.is_offer_visible(), "接单界面按 Esc 不应关闭接单面板")


func _check_pause_and_resume() -> void:
	_expect(_orders.accept_order(), "接单后应开始订单")
	await physics_frame
	var order := _orders.get_current_order()
	var session := _orders.get_session()
	_expect(order != null and session != null and session.is_active(), "接单后订单应处于活动状态")
	if order == null or session == null:
		return
	_expect(_player.controls_enabled, "配送中应启用玩家控制")

	_press_pause()
	_expect(paused, "配送中按 Esc 应暂停场景树")
	_expect(_pause.is_pause_visible(), "暂停后应显示暂停层")
	_expect(not _player.controls_enabled, "暂停后应关闭玩家控制")
	if DisplayServer.get_name() != "headless":
		_expect(
			Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE,
			"暂停后应释放并显示鼠标"
		)
	var seed_text := _pause.get_seed_text()
	_expect(seed_text.contains("城市种子"), "暂停层应显示城市种子")
	_expect(seed_text.contains("订单种子"), "暂停层应显示订单种子")
	_expect(seed_text.contains(str(order.city_seed)), "暂停层城市种子与当前订单不一致")
	_expect(seed_text.contains(str(order.order_seed)), "暂停层订单种子与当前订单不一致")
	_check_settings_page()

	var remaining := session.time_remaining
	var player_position := _player.global_position
	for _frame in 5:
		await physics_frame
	_expect(is_equal_approx(session.time_remaining, remaining), "暂停期间订单倒计时应冻结")
	_expect(
		_player.global_position.distance_to(player_position) < 0.001,
		"暂停期间玩家不应移动"
	)

	_press_pause()
	_expect(not paused, "再次按 Esc 应恢复时间")
	_expect(not _pause.is_pause_visible(), "恢复后应隐藏暂停层")
	_expect(_player.controls_enabled, "恢复后应重新启用玩家控制")
	if DisplayServer.get_name() != "headless":
		_expect(
			Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED,
			"恢复后应捕获鼠标"
		)


func _check_settings_page() -> void:
	_expect(not _pause.is_settings_visible(), "暂停首页不应显示设置页")
	_pause.open_settings()
	_expect(_pause.is_pause_visible(), "打开设置后仍应保持暂停")
	_expect(_pause.is_settings_visible(), "暂停页应能打开设置")
	var pause_page := _pause.find_child("PausePage", true, false) as VBoxContainer
	var settings_page := _pause.find_child("SettingsPage", true, false) as VBoxContainer
	var volume := _pause.find_child("VolumeSlider", true, false) as HSlider
	var sensitivity := _pause.find_child("SensitivitySlider", true, false) as HSlider
	var density := _pause.find_child("DensitySlider", true, false) as HSlider
	var fullscreen := _pause.find_child("FullscreenCheck", true, false) as CheckBox
	var reset := _pause.find_child("ResetButton", true, false) as Button
	var back := _pause.find_child("BackButton", true, false) as Button
	_expect(pause_page != null and not pause_page.visible, "设置页应隐藏暂停首页")
	_expect(settings_page != null and settings_page.visible, "设置页节点应可见")
	_expect(volume != null, "设置页缺少主音量滑块")
	_expect(sensitivity != null, "设置页缺少鼠标灵敏度滑块")
	_expect(density != null, "设置页缺少交通密度滑块")
	_expect(fullscreen != null, "设置页缺少全屏开关")
	_expect(reset != null, "设置页缺少恢复默认按钮")
	_expect(back != null, "设置页缺少返回按钮")
	if (
		volume == null
		or sensitivity == null
		or density == null
		or reset == null
		or back == null
		or _settings == null
	):
		return

	volume.value = 0.35
	sensitivity.value = 0.0065
	density.value = 2.3
	_expect(
		is_equal_approx(_settings.master_volume, 0.35),
		"主音量滑块应更新设置"
	)
	_expect(
		is_equal_approx(_settings.mouse_sensitivity, 0.0065),
		"灵敏度滑块应更新设置"
	)
	_expect(
		is_equal_approx(_settings.traffic_density, 2.3),
		"交通密度滑块应更新设置"
	)
	_expect(
		is_equal_approx(_player.mouse_sensitivity, 0.0065),
		"灵敏度滑块应立即作用于玩家"
	)
	_expect(
		_traffic != null and is_equal_approx(_traffic.traffic_density, 2.3),
		"交通密度滑块应立即作用于交通系统"
	)

	reset.emit_signal("pressed")
	_expect(
		is_equal_approx(_settings.master_volume, GameSettings.DEFAULT_MASTER_VOLUME),
		"恢复默认应重置主音量"
	)
	_expect(
		is_equal_approx(
			_settings.mouse_sensitivity,
			GameSettings.DEFAULT_MOUSE_SENSITIVITY
		),
		"恢复默认应重置鼠标灵敏度"
	)
	_expect(
		is_equal_approx(
			_settings.traffic_density,
			GameSettings.DEFAULT_TRAFFIC_DENSITY
		),
		"恢复默认应重置交通密度"
	)

	volume.value = 0.35
	sensitivity.value = 0.0065
	density.value = 2.3
	back.emit_signal("pressed")
	_expect(not _pause.is_settings_visible(), "返回后应隐藏设置页")
	_expect(_pause.is_pause_visible(), "返回后仍应保持暂停")
	_expect(
		FileAccess.file_exists(_settings_test_path),
		"返回暂停首页时应保存临时设置文件"
	)

	var restored := GameSettings.new()
	restored.config_path = _settings_test_path
	_expect(restored.load_settings(), "暂停页保存的设置应能重新加载")
	_expect(is_equal_approx(restored.master_volume, 0.35), "暂停页主音量未持久化")
	_expect(
		is_equal_approx(restored.mouse_sensitivity, 0.0065),
		"暂停页鼠标灵敏度未持久化"
	)
	_expect(
		is_equal_approx(restored.traffic_density, 2.3),
		"暂停页交通密度未持久化"
	)
	restored.free()


func _check_restart_order() -> void:
	var order := _orders.get_current_order()
	var session := _orders.get_session()
	_expect(order != null and session != null and session.is_active(), "重开前订单应处于活动状态")
	if order == null or session == null:
		return
	var order_seed := _orders.get_order_seed()
	var signature := OrderGenerator.signature(order)
	_press_pause()
	_expect(paused and _pause.is_pause_visible(), "重开前应能暂停")
	_pause.restart_order()
	_expect(not paused, "重开后应恢复时间")
	_expect(not _pause.is_pause_visible(), "重开后应隐藏暂停层")
	_expect(_orders.get_order_seed() == order_seed, "重开本单不应改变订单种子")
	var restarted := _orders.get_current_order()
	_expect(restarted != null, "重开后应保留当前订单")
	if restarted != null:
		_expect(OrderGenerator.signature(restarted) == signature, "重开本单不应改变订单内容")
	_expect(
		_orders.get_session() != null and _orders.get_session().is_active(),
		"重开后订单应重新进入活动状态"
	)
	_expect(_player.controls_enabled, "重开后应恢复玩家控制")
	var player_xz := Vector2(_player.global_position.x, _player.global_position.z)
	var start_xz := Vector2(order.start.position.x, order.start.position.z)
	_expect(player_xz.distance_to(start_xz) < 1.0, "重开后玩家应回到本单起点")


func _check_result_guard() -> void:
	var session := _orders.get_session()
	_expect(session != null, "结算前应有活动会话")
	if session == null:
		return
	session.advance(session.time_limit + 1.0)
	_expect(_orders.get_hud().is_result_visible(), "超时后应显示结算面板")
	_press_pause()
	_expect(not paused, "结算界面按 Esc 不应暂停")
	_expect(not _pause.is_pause_visible(), "结算界面按 Esc 不应显示暂停层")
	_expect(_orders.get_hud().is_result_visible(), "结算界面按 Esc 不应关闭结算面板")


func _check_return_to_menu() -> void:
	_expect(_orders.handle_restart(), "结算后应能生成下一单")
	for _frame in 120:
		if _orders.is_offer_visible():
			break
		await physics_frame
	_expect(_orders.is_offer_visible(), "下一单应先显示接单界面")
	_expect(_orders.accept_order(), "下一单应能接单")
	await physics_frame
	_expect(_orders.get_session() != null and _orders.get_session().is_active(), "新订单应处于活动状态")
	_press_pause()
	_expect(paused and _pause.is_pause_visible(), "返回主菜单前应能暂停")
	_pause.return_to_menu()
	_expect(not paused, "返回主菜单后应恢复时间")
	_expect(not _pause.is_pause_visible(), "返回主菜单后应隐藏暂停层")
	_expect(_orders.is_start_screen_visible(), "返回主菜单后应显示开始界面")
	_expect(_orders.get_session() == null, "返回主菜单后不应保留会话")
	_expect(not _player.controls_enabled, "主菜单应关闭玩家控制")


func _press_pause() -> void:
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	_pause._unhandled_input(event)


func _cleanup_settings_file() -> void:
	if _settings_test_path.is_empty():
		return
	if not FileAccess.file_exists(_settings_test_path):
		return
	var error := DirAccess.remove_absolute(
		ProjectSettings.globalize_path(_settings_test_path)
	)
	if error != OK:
		_expect(false, "无法清理暂停设置临时文件：%s" % error)
