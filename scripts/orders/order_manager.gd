extends Node3D
class_name OrderManager

## 订单运行时：等待导航就绪，生成首单，传送玩家，维护目标信标、HUD 和输入。
## 状态机本身在 OrderSession 中；本节点只处理场景、输入和展示。

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
var _beacon: MeshInstance3D = null
var _beacon_material: StandardMaterial3D = null

var _current_order: DeliveryOrder = null
var _session: OrderSession = null
var _order_seed := 1
var _configured := false
var _pending_generation := false
var _pending_seed := 1
var _avoid_signature := ""
var _nav_wait_frames := 0


func _ready() -> void:
	_ensure_hud()
	_ensure_beacon()


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
	_ensure_beacon()
	if not _configured:
		_hud.show_error("订单系统缺少世界、导航或玩家")
		return
	_order_seed = initial_order_seed
	_begin_generation(_order_seed, "")


func get_current_order() -> DeliveryOrder:
	return _current_order


func get_session() -> OrderSession:
	return _session


func get_order_seed() -> int:
	return _order_seed


func get_hud() -> OrderHUD:
	return _hud


func try_interact(player_position: Vector3) -> bool:
	if _session == null:
		return false
	var changed := _session.try_interact(player_position)
	if changed and _session.is_active():
		_update_beacon()
		_refresh_hud()
	return changed


func handle_restart() -> bool:
	if not _configured:
		return false
	if _current_order == null:
		if _pending_generation:
			return false
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


func _unhandled_input(event: InputEvent) -> void:
	if not _configured or _player == null:
		return
	if not _player.is_physics_processing():
		return
	if event is InputEventKey and event.is_echo():
		return
	if event.is_action_pressed("interact"):
		if try_interact(_player.global_position):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		if handle_restart():
			get_viewport().set_input_as_handled()


func _begin_generation(seed_value: int, avoid_signature: String) -> void:
	_current_order = null
	_session = null
	_pending_generation = true
	_pending_seed = seed_value
	_avoid_signature = avoid_signature
	_nav_wait_frames = 0
	if _beacon != null:
		_beacon.visible = false
	if _hud != null:
		_hud.show_waiting("正在生成订单…")
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
				_activate_order(order)
				return
		seed_value += 1
	_pending_generation = false
	_hud.show_error("订单生成失败：没有可达的起点/商家/顾客组合，按 R 重试")


func _activate_order(order: DeliveryOrder) -> void:
	_current_order = order
	_order_seed = order.order_seed
	_session = OrderSession.new(order, _player.move_speed if _player != null else 5.0)
	_session.state_changed.connect(_on_session_state_changed)
	_session.finished.connect(_on_session_finished)
	_player.reset_to(order.start)
	_hud.show_active(order, _session)
	_update_beacon()
	_refresh_hud()
	order_started.emit(order)


func _restart_same_order() -> void:
	if _current_order == null:
		return
	_session = OrderSession.new(_current_order, _player.move_speed if _player != null else 5.0)
	_session.state_changed.connect(_on_session_state_changed)
	_session.finished.connect(_on_session_finished)
	_player.reset_to(_current_order.start)
	_hud.show_active(_current_order, _session)
	_update_beacon()
	_refresh_hud()
	order_started.emit(_current_order)


func _begin_next_order() -> void:
	var previous := _current_order
	var previous_signature := OrderGenerator.signature(previous)
	_begin_generation(_order_seed + 1, previous_signature)


func _on_session_state_changed(_state: int) -> void:
	_update_beacon()
	_refresh_hud()


func _on_session_finished(_success: bool) -> void:
	if _beacon != null:
		_beacon.visible = false
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


func _ensure_hud() -> void:
	if _hud != null:
		return
	_hud = OrderHUD.new()
	_hud.name = "OrderHUD"
	add_child(_hud)


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
