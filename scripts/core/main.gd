extends Node3D

## 主场景装配者：只负责把 World、玩家、导航、交通接到一起。
## 各模块不直接修改 main.tscn，避免多人同时改主场景。

@onready var world: WorldGenerator = $World
@onready var navigation: NavigationService = $NavigationSystem
@onready var traffic: TrafficSpawner = $TrafficSystem
@onready var player: PlayerController = $Player
@onready var orders: OrderManager = $OrderSystem

var _pause_menu: PauseController = null
var _telemetry: TelemetryClient = null


func _ready() -> void:
	world.world_generated.connect(_on_world_generated)
	traffic.player_hit.connect(_on_traffic_player_hit)
	world.regenerate()
	_place_player()
	traffic.set_player(player)
	orders.setup(world, navigation, player)
	_setup_pause_menu()
	_setup_touch_controls()
	_setup_telemetry()
	_setup_test_god_view()


func _on_world_generated(network: RoadNetwork) -> void:
	navigation.build(network)
	traffic.build(network, world.city)


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
	_pause_menu.setup(orders, player)


func get_pause_menu() -> PauseController:
	return _pause_menu


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
