extends Node3D

## 主场景装配者：只负责把 World、玩家、导航、交通接到一起。
## 各模块不直接修改 main.tscn，避免多人同时改主场景。

@onready var world: WorldGenerator = $World
@onready var navigation: NavigationService = $NavigationSystem
@onready var traffic: TrafficSpawner = $TrafficSystem
@onready var player: PlayerController = $Player
@onready var orders: OrderManager = $OrderSystem
const MINI_MAP_SCRIPT := preload("res://scripts/ui/mini_map.gd")

var _pause_menu: PauseController = null
var _telemetry: TelemetryClient = null
var _mini_map: Control = null
var _settings: GameSettings = null
var _economy: EconomyHUD = null
var _input_activation: InputActivationOverlay = null
var _input_diagnostics: InputDiagnosticsHUD = null


func _ready() -> void:
	_setup_settings()
	_setup_input_layers()
	world.world_generated.connect(_on_world_generated)
	traffic.player_hit.connect(_on_traffic_player_hit)
	# 每局换一座城市；测试和录制脚本会通过 GameSeeds.pin() 固定种子。
	world.seed = GameSeeds.city_seed()
	world.allow_seed_retry = GameSeeds.is_city_random()
	world.regenerate()
	_place_player()
	traffic.set_player(player)
	_setup_economy()
	orders.setup(world, navigation, player)
	_setup_pause_menu()
	_setup_touch_controls()
	_setup_telemetry()
	_setup_test_god_view()
	_setup_mini_map()
	# 把本局种子打到日志里；需要复现时用 --city-seed / --order-seed 传回去。
	print("[种子] 城市 %d · 订单 %d" % [world.seed, orders.get_order_seed()])


func _setup_settings() -> void:
	_settings = GameSettings.new()
	_settings.name = "GameSettings"
	add_child(_settings)
	_settings.load_settings()
	_settings.apply_to(player, traffic)


func _on_world_generated(network: RoadNetwork) -> void:
	navigation.build(network)
	traffic.build(network, world.city)
	if _settings != null:
		_settings.apply_to(player, traffic)
	if _mini_map != null:
		_mini_map.call("set_network", network)


func _on_traffic_player_hit(_car: TrafficCar, position: Vector3) -> void:
	orders.notify_player_hit(position)


func _place_player() -> void:
	if world.city == null or world.city.player_start == null:
		return
	player.reset_to(world.city.player_start)


func _setup_pause_menu() -> void:
	## 暂停层由代码创建，避免把 UI 节点写进共享的 main.tscn。
	_pause_menu = PauseController.new()
	_pause_menu.name = "PauseMenu"
	add_child(_pause_menu)
	_pause_menu.setup(orders, player, _settings, traffic)


func get_pause_menu() -> PauseController:
	return _pause_menu


func get_game_settings() -> GameSettings:
	return _settings


func get_economy_hud() -> EconomyHUD:
	return _economy


func get_input_diagnostics() -> InputDiagnosticsHUD:
	return _input_diagnostics


func _setup_input_layers() -> void:
	## 浏览器/桌面窗口丢失焦点时先点一下画面，键盘才会交回游戏；自检面板常驻右上角。
	_input_activation = InputActivationOverlay.new()
	_input_activation.name = "InputActivation"
	add_child(_input_activation)
	_input_diagnostics = InputDiagnosticsHUD.new()
	_input_diagnostics.name = "InputDiagnostics"
	add_child(_input_diagnostics)
	_input_diagnostics.setup(player, _input_activation)


func _setup_economy() -> void:
	_economy = EconomyHUD.new()
	_economy.name = "EconomyHUD"
	add_child(_economy)
	player.pedestrian_hit.connect(_on_player_pedestrian_hit)
	orders.game_started.connect(_on_game_started)
	orders.order_started.connect(_on_order_started)
	orders.order_finished.connect(_on_order_finished)


func _on_game_started() -> void:
	## 从主菜单重新开始时账户归位；后续订单在同一局里累加。
	if _economy != null:
		_economy.reset_economy()


func _on_order_started(_order: DeliveryOrder) -> void:
	if _economy != null:
		_economy.begin_order()


func _on_order_finished(success: bool) -> void:
	## 送达按预估路程和剩余时间入账；撞车、超时和撞行人不加收入。
	if not success or _economy == null:
		return
	var order := orders.get_current_order()
	var session := orders.get_session()
	if order == null or session == null:
		return
	var distance := order.pickup_path_length_m + order.delivery_path_length_m
	_economy.record_successful_delivery(distance, session.time_remaining)


func _on_player_pedestrian_hit(
	_pedestrian: Pedestrian,
	compensation: int
) -> void:
	if _economy != null:
		_economy.add_compensation(compensation)
	if orders != null and orders.get_hud() != null:
		orders.get_hud().show_toast("撞到行人，赔偿 %d 元" % compensation)


func _setup_touch_controls() -> void:
	## 手机浏览器没有键盘鼠标，用触屏层代替；桌面端不创建。
	if not TouchControls.is_touch_device():
		return
	var controls := TouchControls.new()
	controls.name = "TouchControls"
	add_child(controls)
	controls.setup(player)


func _setup_telemetry() -> void:
	## 行为采集随主场景创建；是否真正联网由 TelemetryClient 按 Web 导出判断。
	_telemetry = TelemetryClient.new()
	_telemetry.name = "Telemetry"
	add_child(_telemetry)
	_telemetry.setup(orders, player)


func get_telemetry() -> TelemetryClient:
	return _telemetry


func _setup_test_god_view() -> void:
	## 只在调试/测试构建中创建；正式导出不会出现 F3 上帝视角。
	if not TestGodView.is_test_only_enabled():
		return
	var god_view := TestGodView.new()
	god_view.name = "TestGodView"
	god_view.setup(player, Vector2(world.map_width_m, world.map_height_m))
	add_child(god_view)


func _setup_mini_map() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MiniMapLayer"
	layer.layer = 8
	add_child(layer)
	_mini_map = MINI_MAP_SCRIPT.new() as Control
	_mini_map.name = "MiniMap"
	layer.add_child(_mini_map)
	_mini_map.anchor_top = 1.0
	_mini_map.anchor_bottom = 1.0
	_mini_map.offset_left = 22.0
	_mini_map.offset_right = 230.0
	var touch_offset := 244.0 if TouchControls.is_touch_device() else 0.0
	_mini_map.offset_top = -236.0 - touch_offset
	_mini_map.offset_bottom = -28.0 - touch_offset
	_mini_map.call("setup", player, world.network, navigation, orders)
