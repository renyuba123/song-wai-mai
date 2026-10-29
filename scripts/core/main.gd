extends Node3D

## 主场景装配者：只负责把 World、玩家、导航、交通接到一起。
## 各模块不直接修改 main.tscn，避免多人同时改主场景。

@onready var world: WorldGenerator = $World
@onready var navigation: NavigationService = $NavigationSystem
@onready var traffic: TrafficSpawner = $TrafficSystem
@onready var player: PlayerController = $Player


func _ready() -> void:
	world.world_generated.connect(_on_world_generated)
	world.regenerate()
	_place_player()
	_setup_test_god_view()
	var orders := get_node_or_null("OrderSystem") as OrderManager
	if orders == null:
		orders = OrderManager.new()
		orders.name = "OrderSystem"
		add_child(orders)
	var phone := player.get_node_or_null("MeshInstance3D") as PhoneOrderScreen
	if phone == null:
		phone = player.get_node_or_null("电鸡模型/Empty/MeshInstance3D") as PhoneOrderScreen
	if phone != null:
		phone.bind_order_manager(orders)
	orders.setup(world, navigation, player)


func _on_world_generated(network: RoadNetwork) -> void:
	navigation.build(network)
	traffic.build(network)


func _place_player() -> void:
	if world.city == null or world.city.player_start == null:
		return
	var start := world.city.player_start
	player.global_position = start.position
	player.rotation.y = start.facing_yaw
	player.velocity = Vector3.ZERO


func _setup_test_god_view() -> void:
	## 只在调试/测试构建中创建；正式导出不会出现 F3 上帝视角。
	if not TestGodView.is_test_only_enabled():
		return
	var god_view := TestGodView.new()
	god_view.name = "TestGodView"
	god_view.setup(player, Vector2(world.map_width_m, world.map_height_m))
	add_child(god_view)
