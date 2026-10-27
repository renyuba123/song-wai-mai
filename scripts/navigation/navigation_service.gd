extends Node3D
class_name NavigationService

## 导航模块入口：从 RoadNetwork 和静态碰撞体烘焙导航网格。
## 车辆、行人通过本模块提供的导航区域寻路，不直接改道路场景。

signal navigation_baked

@onready var region: NavigationRegion3D = $NavigationRegion3D

## 城市级地图的导航烘焙体素。默认 2400 米地图使用 4 米体素，
## 否则默认 0.25 米体素会触发 Godot 的烘焙崩溃保护。
@export var cell_size := 4.0
@export var cell_height := 1.0
@export var agent_radius := 4.0
@export var agent_height := 4.0
@export var agent_max_climb := 1.0
@export var agent_max_slope := 45.0

var network: RoadNetwork = null


func build(source_network: RoadNetwork) -> void:
	network = source_network
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = cell_size
	nav_mesh.cell_height = cell_height
	nav_mesh.agent_radius = agent_radius
	nav_mesh.agent_height = agent_height
	nav_mesh.agent_max_climb = agent_max_climb
	nav_mesh.agent_max_slope = agent_max_slope
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = CollisionLayers.WORLD_STATIC
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = CollisionLayers.NAVIGATION_SOURCE_GROUP
	region.navigation_mesh = nav_mesh
	region.bake_navigation_mesh(false)
	navigation_baked.emit()
