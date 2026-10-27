extends Node3D

## 主场景装配者：只负责把 World、玩家、导航、交通接到一起。
## 各模块不直接修改 main.tscn，避免多人同时改主场景。

@onready var world: WorldGenerator = $World
@onready var navigation: NavigationService = $NavigationSystem
@onready var traffic: TrafficSpawner = $TrafficSystem


func _ready() -> void:
	world.world_generated.connect(_on_world_generated)
	world.regenerate()


func _on_world_generated(network: RoadNetwork) -> void:
	navigation.build(network)
	traffic.build(network)
