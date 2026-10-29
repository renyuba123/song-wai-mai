extends SceneTree

## 站点与订单可读性测试：店名确定性、三维标牌、目标高亮、
## 接单/取餐/送达时 HUD 与信标文本是否一致。

var _failed := false
var _main: Node = null
var _world: WorldGenerator = null
var _navigation: NavigationService = null
var _player: PlayerController = null
var _orders: OrderManager = null
var _signage: SiteSignage = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _setup_main()
	if _world != null and _world.city != null:
		_check_sites()
		await _check_order_flow()
	if _failed:
		printerr("FAIL site readability")
	else:
		print("PASS site readability")
	if _main != null:
		_main.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL site readability: ", message)


func _setup_main() -> void:
	GameSeeds.pin(118, 1)
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
	_signage = _world.get_site_signage()
	_expect(_signage != null, "世界没有创建店名牌节点")
	if _signage != null:
		_expect(
			_signage.get_label_count() == _world.city.sites.size(),
			"店名牌数量与站点数量不一致"
		)
		_expect(_signage.get_active_target().is_empty(), "开始界面不应高亮任何站点")


func _check_sites() -> void:
	var paths := {}
	for item in _world.city_builder.population_layout.buildings:
		var site_id := String(item.get("site_id", ""))
		if not site_id.is_empty():
			paths[site_id] = String(item.get("path", ""))
	var names := {}
	for site in _world.city.sites:
		_expect(site != null, "城市包含空站点")
		if site == null:
			continue
		_expect(not site.display_name.is_empty(), "站点 %s 没有店名" % site.id)
		_expect(paths.has(String(site.id)), "站点 %s 没有对应的建筑模型" % site.id)
		if paths.has(String(site.id)):
			var expected := SiteNaming.name_for_path(
				String(paths[String(site.id)]), String(site.id)
			)
			_expect(
				site.display_name == expected,
				"站点 %s 的店名与模型/编号不匹配" % site.id
			)
			_expect(
				SiteNaming.name_for_path(
					String(paths[String(site.id)]), String(site.id)
				) == expected,
				"站点 %s 的店名不确定" % site.id
			)
		names[site.display_name] = true
		if _signage != null:
			_expect(
				_signage.get_label_text(site.id) == site.display_name,
				"站点 %s 的三维标牌文本与店名不一致" % site.id
			)
	_expect(names.size() >= 2, "全部站点不应共用一个店名")
	var unknown := CitySite.new()
	unknown.id = &"merchant_001"
	_expect(
		OrderHUD.site_label(unknown) == "商家 #001",
		"无店名站点应回退到编号"
	)
	_expect(
		SiteNaming.name_for_path("res://unknown/nowhere.glb", "merchant_001").is_empty(),
		"未知模型不应凭空生成店名"
	)


func _check_order_flow() -> void:
	if _signage == null:
		return
	_expect(_orders.start_game(), "开始按钮应启动游戏")
	var order: DeliveryOrder = null
	for _frame in 120:
		order = _orders.get_current_order()
		if order != null and _orders.is_offer_visible():
			break
		await physics_frame
	_expect(order != null, "订单系统没有生成首单")
	if order == null:
		return

	var offer := _orders.get_offer_text()
	_expect(
		offer.contains(order.merchant.display_name),
		"接单界面没有显示商家店名"
	)
	_expect(
		offer.contains(order.customer.display_name),
		"接单界面没有显示顾客店名"
	)
	_expect(offer.contains("（商家）"), "接单界面没有标出商家角色")
	_expect(offer.contains("（顾客）"), "接单界面没有标出顾客角色")

	_expect(_orders.accept_order(), "接单按钮应开始订单")
	var session := _orders.get_session()
	if session == null:
		_expect(false, "接单后没有会话")
		return
	_expect(
		session.get_objective_text() == "前往「%s」取餐" % order.merchant.display_name,
		"取餐阶段目标文本未带店名"
	)
	_expect(
		_signage.get_active_target() == String(order.merchant.id),
		"取餐阶段没有高亮商家标牌"
	)
	_expect(
		_signage.get_label_text(order.merchant.id).begins_with("★ "),
		"高亮标牌没有星标"
	)
	for other in _world.city.sites:
		if other != null and other.id != order.merchant.id:
			_expect(
				not _signage.get_label_text(other.id).begins_with("★ "),
				"非目标站点 %s 不应带星标" % other.id
			)

	_player.global_position = order.merchant.spawn_point.position
	_expect(_orders.try_interact(_player.global_position), "取餐交互失败")
	_expect(
		session.get_objective_text() == "送达「%s」" % order.customer.display_name,
		"送达阶段目标文本未带店名"
	)
	_expect(
		_signage.get_active_target() == String(order.customer.id),
		"送达阶段没有高亮顾客标牌"
	)
	_expect(
		_signage.get_label_text(order.customer.id).begins_with("★ "),
		"送达阶段的顾客标牌没有星标"
	)
	var beacon := _orders.get_node_or_null("TargetBeacon") as MeshInstance3D
	_expect(beacon != null and beacon.visible, "送达阶段信标未显示")

	_player.global_position = order.customer.spawn_point.position
	_expect(_orders.try_interact(_player.global_position), "送达交互失败")
	_expect(session.is_finished(), "送达后会话应结束")
	_expect(_signage.get_active_target().is_empty(), "结算后应取消标牌高亮")
	if beacon != null:
		_expect(not beacon.visible, "结算后信标应隐藏")
