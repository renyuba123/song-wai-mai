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
