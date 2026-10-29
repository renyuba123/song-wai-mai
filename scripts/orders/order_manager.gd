extends Node3D
class_name OrderManager

## 订单运行时：等待导航就绪，生成订单，等待玩家接单，传送玩家，
## 维护目标信标、HUD 和输入。状态机本身在 OrderSession 中；
## 本节点只处理场景、输入和展示。

signal order_offered(order: DeliveryOrder)
signal order_rejected(order: DeliveryOrder)
signal order_started(order: DeliveryOrder)
signal order_finished(success: bool)

const NAV_READY_MAX_FRAMES := 120
const NEXT_SEED_ATTEMPTS := 10
const BEACON_HEIGHT := 4.0
const MERCHANT_COLOR := Color(1.0, 0.55, 0.18, 1.0)
const CUSTOMER_COLOR := Color(0.15, 0.85, 0.95, 1.0)

@export var initial_order_seed := 1

var _world: WorldGenerator = null
var _navigation: NavigationService = null
var _player: PlayerController = null
var _hud: OrderHUD = null
var _phone: OrderPhone = null
var _beacon: MeshInstance3D = null
var _beacon_material: StandardMaterial3D = null
var _route_guide: RouteGuide = null

var _current_order: DeliveryOrder = null
var _session: OrderSession = null
var _order_seed := 1
var _configured := false
var _at_start_screen := true
var _pending_offer := false
var _pending_generation := false
var _pending_seed := 1
var _avoid_signature := ""
var _nav_wait_frames := 0


func _ready() -> void:
	_ensure_hud()
	_ensure_beacon()
	_ensure_route_guide()


func setup(
	world: WorldGenerator,
	navigation: NavigationService,
	player: PlayerController
) -> void:
	_world = world
	_navigation = navigation
	_player = player
	_configured = world != null and navigation != null and player != null
	_ensure_hud()
	_ensure_phone()
	_ensure_beacon()
	_ensure_route_guide()
	_route_guide.setup(_navigation)
	if not _configured:
		_route_guide.hide_route()
		_hud.show_error("订单系统缺少世界、导航或玩家")
		return
	_order_seed = initial_order_seed
	_current_order = null
	_session = null
	_pending_offer = false
	_pending_generation = false
	_at_start_screen = true
	_player.set_controls_enabled(false)
	if _phone != null:
		_phone.hide_offer()
	_hud.show_start_menu(_city_seed())
	_sync_signage()


func get_current_order() -> DeliveryOrder:
	return _current_order


func get_session() -> OrderSession:
	return _session


func get_order_seed() -> int:
	return _order_seed


func get_hud() -> OrderHUD:
	return _hud


func get_phone() -> OrderPhone:
	return _phone


func get_route_guide() -> RouteGuide:
	return _route_guide


func is_start_screen_visible() -> bool:
	return _at_start_screen and _hud != null and _hud.is_start_menu_visible()


func is_offer_visible() -> bool:
	return (
		_pending_offer
		and _phone != null
		and _phone.is_offer_visible()
		and _hud != null
		and _hud.is_offer_visible()
	)


func get_offer_text() -> String:
	if _phone != null and _phone.is_offer_visible():
		return _phone.get_screen_text()
	return _hud.get_offer_text() if _hud != null else ""


func start_game() -> bool:
	if not _configured or not _at_start_screen:
		return false
	_at_start_screen = false
	_hud.hide_start_menu()
	_begin_generation(_order_seed, "")
	return true


func accept_order() -> bool:
	if not _configured or not _pending_offer or _current_order == null:
		return false
	_pending_offer = false
	# 手机不隐藏：接单后切换到配送模式，继续显示在车把左侧。
	_hud.hide_offer()
	_activate_order(_current_order)
	return true


func reject_order() -> bool:
	## 拒单和超时走同一条路：丢掉当前订单，按新种子继续找下一单。
	if not _configured or not _pending_offer or _current_order == null:
		return false
	var rejected := _current_order
	var signature := OrderGenerator.signature(rejected)
	_pending_offer = false
	_current_order = null
	if _phone != null:
		_phone.hide_offer()
	_hud.hide_offer()
	if _route_guide != null:
		_route_guide.hide_route()
	order_rejected.emit(rejected)
	_begin_generation(_order_seed + 1, signature)
	return true


func return_to_start_menu() -> bool:
	if not _configured:
		return false
	_pending_generation = false
	_pending_offer = false
	_current_order = null
	_session = null
	_at_start_screen = true
	_order_seed += 1
	if _phone != null:
		_phone.hide_offer()
	if _beacon != null:
		_beacon.visible = false
	if _route_guide != null:
		_route_guide.hide_route()
	if _player != null:
		_player.set_controls_enabled(false)
	_hud.show_start_menu(_city_seed())
	_sync_signage()
	return true


func try_interact(player_position: Vector3) -> bool:
	if _session == null:
		return false
	var changed := _session.try_interact(player_position)
	if changed and _session.is_active():
		_update_beacon()
		_refresh_hud()
	return changed


func notify_player_hit(_position: Vector3 = Vector3.ZERO) -> bool:
	## 交通模块只报告“碰到玩家”，是否构成失败由订单系统判断。
	## 菜单、接单界面、结算界面和上帝视角都不会有活动会话，直接忽略。
	if not _configured or _session == null or not _session.is_active():
		return false
	if _player == null or not _player.is_physics_processing():
		return false
	return _session.fail(OrderSession.FailureReason.HIT_BY_CAR)


func handle_restart() -> bool:
	if not _configured:
		return false
	if _at_start_screen:
		return start_game()
	if _pending_offer:
		return accept_order()
	if _pending_generation:
		return false
	if _current_order == null:
		_begin_generation(_order_seed + 1, "")
		return true
	if _session == null:
		return false
	if _session.is_active():
		_restart_same_order()
		return true
	if _session.is_finished():
		_begin_next_order()
		return true
	return false


func _process(delta: float) -> void:
	if not _configured or not _pending_offer or _phone == null:
		return
	_phone.advance(delta)


func _physics_process(delta: float) -> void:
	if not _configured:
		return
	if _pending_generation:
		_attempt_generation()
		if not _pending_generation:
			return
		_nav_wait_frames += 1
		if _nav_wait_frames > NAV_READY_MAX_FRAMES:
			_pending_generation = false
			_hud.show_error("导航在 %d 个物理帧内未就绪，按 R 重试" % NAV_READY_MAX_FRAMES)
		return
	if _current_order == null or _session == null or not _session.is_active():
		return
	if _player != null and not _player.is_physics_processing():
		return
	_session.advance(delta)
	if _session.is_finished():
		return
	_refresh_hud()
	_refresh_route(delta, false)


func _unhandled_input(event: InputEvent) -> void:
	if not _configured or _player == null:
		return
	if not _player.is_physics_processing():
		return
	if event is InputEventKey and event.is_echo():
		return
	if event.is_action_pressed("order_accept"):
		if _pending_offer and accept_order():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("order_reject"):
		if _pending_offer and reject_order():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		var handled := false
		if _at_start_screen:
			handled = start_game()
		elif _pending_offer:
			# 保留 E 作为接单的兼容键，界面提示以 Y/N 为准。
			handled = accept_order()
		else:
			handled = try_interact(_player.global_position)
		if handled:
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		if handle_restart():
			get_viewport().set_input_as_handled()


func _begin_generation(seed_value: int, avoid_signature: String) -> void:
	_current_order = null
	_session = null
	_pending_offer = false
	_pending_generation = true
	_pending_seed = seed_value
	_avoid_signature = avoid_signature
	_nav_wait_frames = 0
	if _phone != null:
		_phone.hide_offer()
	if _beacon != null:
		_beacon.visible = false
	if _route_guide != null:
		_route_guide.hide_route()
	if _hud != null:
		_hud.show_waiting("正在生成订单…")
	_sync_signage()
	_attempt_generation()


func _attempt_generation() -> void:
	if not _pending_generation:
		return
	if _navigation == null or not _navigation.is_ready():
		return
	var seed_value := _pending_seed
	for attempt in NEXT_SEED_ATTEMPTS:
		var order := OrderGenerator.generate(
			_world.city, _world.network, _navigation, seed_value
		)
		if order != null:
			var signature := OrderGenerator.signature(order)
			if (
				_avoid_signature.is_empty()
				or signature != _avoid_signature
				or attempt == NEXT_SEED_ATTEMPTS - 1
			):
				_order_seed = seed_value
				_pending_generation = false
				_offer_order(order)
				return
		seed_value += 1
	_pending_generation = false
	_hud.show_error("订单生成失败：没有可达的起点/商家/顾客组合，按 R 重试")


func _offer_order(order: DeliveryOrder) -> void:
	## 生成成功后先展示商家、顾客、路程和时限，玩家接单后才开始计时。
	_current_order = order
	_order_seed = order.order_seed
	_session = null
	_pending_offer = true
	if _beacon != null:
		_beacon.visible = false
	if _route_guide != null:
		_route_guide.hide_route()
	if _player != null:
		_player.set_controls_enabled(false)
	_sync_signage()
	var time_limit := OrderSession.calculate_time_limit(
		order, _player.move_speed if _player != null else 5.0
	)
	if _phone != null:
		_phone.show_offer(order, time_limit)
	_hud.show_offer(order, time_limit)
	order_offered.emit(order)


func _activate_order(order: DeliveryOrder) -> void:
	_current_order = order
	_order_seed = order.order_seed
	_pending_offer = false
	_session = OrderSession.new(order, _player.move_speed if _player != null else 5.0)
	_session.state_changed.connect(_on_session_state_changed)
	_session.finished.connect(_on_session_finished)
	if _player != null:
		_player.reset_to(order.start)
		_player.set_controls_enabled(true)
	if _phone != null:
		_phone.show_active(order, _session)
		if _player != null:
			_phone.update_active(_session, _player.global_position)
	_hud.show_active(order, _session)
	_update_beacon()
	_refresh_hud()
	_refresh_route(0.0, true)
	order_started.emit(order)


func _restart_same_order() -> void:
	if _current_order == null:
		return
	_session = OrderSession.new(_current_order, _player.move_speed if _player != null else 5.0)
	_session.state_changed.connect(_on_session_state_changed)
	_session.finished.connect(_on_session_finished)
	if _player != null:
		_player.reset_to(_current_order.start)
		_player.set_controls_enabled(true)
	if _phone != null:
		_phone.show_active(_current_order, _session)
		if _player != null:
			_phone.update_active(_session, _player.global_position)
	_hud.show_active(_current_order, _session)
	_update_beacon()
	_refresh_hud()
	_refresh_route(0.0, true)
	order_started.emit(_current_order)


func _begin_next_order() -> void:
	var previous := _current_order
	var previous_signature := OrderGenerator.signature(previous)
	_begin_generation(_order_seed + 1, previous_signature)


func _on_session_state_changed(_state: int) -> void:
	_update_beacon()
	_refresh_hud()
	# 取餐后目标从商家切到顾客，强制重算一次；终态则由活动判断隐藏。
	_refresh_route(0.0, true)


func _on_session_finished(_success: bool) -> void:
	if _phone != null:
		_phone.hide_offer()
	if _beacon != null:
		_beacon.visible = false
	if _route_guide != null:
		_route_guide.hide_route()
	if _player != null:
		_player.set_controls_enabled(false)
	_sync_signage()
	if _current_order != null and _session != null and _hud != null:
		_hud.show_result(_current_order, _session)
	order_finished.emit(_session.is_success() if _session != null else false)


func _refresh_hud() -> void:
	if _hud == null or _player == null:
		return
	if _current_order == null or _session == null or not _session.is_active():
		return
	_hud.update_active(
		_current_order, _session, _player.global_position, _player.rotation.y
	)
	if _phone != null:
		_phone.update_active(_session, _player.global_position)


func _ensure_hud() -> void:
	if _hud != null:
		return
	_hud = OrderHUD.new()
	_hud.name = "OrderHUD"
	_hud.start_pressed.connect(start_game)
	_hud.next_order_pressed.connect(handle_restart)
	_hud.menu_pressed.connect(return_to_start_menu)
	add_child(_hud)


func _ensure_phone() -> void:
	if _player == null:
		return
	var anchor: Node3D = _player.camera if _player.camera != null else _player
	if _phone == null:
		_phone = OrderPhone.new()
		_phone.name = "OrderPhone"
		anchor.add_child(_phone)
		_phone.accept_pressed.connect(accept_order)
		_phone.reject_pressed.connect(reject_order)
		_phone.offer_expired.connect(_on_offer_expired)
	elif _phone.get_parent() != anchor:
		_phone.reparent(anchor, false)
	_phone.setup(_player.camera)
	_phone.hide_offer()


func _on_offer_expired() -> void:
	## 手机倒计时归零：按拒单处理，继续生成下一单。
	reject_order()


func _city_seed() -> int:
	if _world != null and _world.network != null:
		return _world.network.seed_value
	return 0


func _ensure_route_guide() -> void:
	if _route_guide != null:
		return
	_route_guide = RouteGuide.new()
	_route_guide.name = "RouteGuide"
	add_child(_route_guide)
	_route_guide.setup(_navigation)


func _refresh_route(delta: float, force: bool) -> void:
	if _route_guide == null:
		return
	if (
		not _configured
		or _player == null
		or _session == null
		or not _session.is_active()
	):
		_route_guide.hide_route()
		return
	var target := _session.get_target_position()
	if not target.is_finite():
		_route_guide.hide_route()
		return
	_route_guide.update_route(
		_player.global_position, target, delta, force
	)


func _ensure_beacon() -> void:
	if _beacon != null:
		return
	_beacon = MeshInstance3D.new()
	_beacon.name = "TargetBeacon"
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.45
	mesh.height = BEACON_HEIGHT
	mesh.radial_segments = 16
	_beacon.mesh = mesh
	_beacon_material = StandardMaterial3D.new()
	_beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_material.emission_enabled = true
	_beacon_material.emission_energy_multiplier = 1.8
	_beacon.material_override = _beacon_material
	_beacon.visible = false
	add_child(_beacon)


func _update_beacon() -> void:
	_ensure_beacon()
	_sync_signage()
	if _session == null or not _session.is_active():
		_beacon.visible = false
		return
	var target := _session.get_target_position()
	if not target.is_finite():
		_beacon.visible = false
		return
	_beacon.global_position = target + Vector3(0.0, BEACON_HEIGHT * 0.5, 0.0)
	var color := MERCHANT_COLOR
	if _session.state == OrderSession.State.TO_CUSTOMER:
		color = CUSTOMER_COLOR
	_beacon_material.albedo_color = color
	_beacon_material.emission = color
	_beacon.visible = true


func _sync_signage() -> void:
	## 把当前订单目标同步给城市店名牌；没有活动会话时恢复常态。
	if _world == null:
		return
	var signage := _world.get_site_signage()
	if signage == null:
		return
	var site: CitySite = null
	if _session != null and _session.is_active():
		site = _session.get_target_site()
	signage.set_active_target(site.id if site != null else &"")
