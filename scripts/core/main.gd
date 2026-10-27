extends Node3D

## 主场景装配者：只负责把 World、玩家、导航、交通接到一起。
## 各模块不直接修改 main.tscn，避免多人同时改主场景。

@onready var world: WorldGenerator = $World
@onready var navigation: NavigationService = $NavigationSystem
@onready var traffic: TrafficSpawner = $TrafficSystem
@onready var player: PlayerController = $Player
@onready var orders: OrderManager = $OrderSystem


func _ready() -> void:
	world.world_generated.connect(_on_world_generated)
	world.regenerate()
	_place_player()
	orders.setup(world, navigation, player)
	_setup_test_god_view()


func _on_world_generated(network: RoadNetwork) -> void:
	navigation.build(network)
	traffic.build(network)


func _place_player() -> void:
	if world.city == null or world.city.player_start == null:
		return
	player.reset_to(world.city.player_start)


func _setup_test_god_view() -> void:
	## 只在调试/测试构建中创建；正式导出不会出现 F3 上帝视角。
	if not TestGodView.is_test_only_enabled():
		return
	var god_view := TestGodView.new()
	god_view.name = "TestGodView"
	god_view.setup(player, Vector2(world.map_width_m, world.map_height_m))
	add_child(god_view)
