extends Node3D
class_name NavigationService

## 导航模块入口：从 RoadNetwork 和静态碰撞体烘焙导航网格，并提供查询接口。
## 车辆、行人和订单系统通过本模块查询导航，不直接操作 NavigationRegion3D。
## 坐标约定：所有查询参数和返回值都是世界坐标，单位米，Y 轴向上。

signal navigation_baked

@onready var _region: NavigationRegion3D = $NavigationRegion3D

## 城市级地图的导航烘焙体素。2400 米地图不能用默认 0.25 米体素，
## 否则会触发 Godot 的烘焙崩溃保护；2 米体素足以保留人行道宽度。
## 导航代理按玩家尺寸设置，不再沿用 4 米的车辆尺寸。
@export var cell_size := 2.0
@export var cell_height := 1.0
@export var agent_radius := 0.5
@export var agent_height := 1.8
@export var agent_max_climb := 1.0
@export var agent_max_slope := 45.0

var network: RoadNetwork = null
var _baked := false


func build(source_network: RoadNetwork) -> void:
	network = source_network
	_baked = false
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
	_region.navigation_mesh = nav_mesh
	_region.bake_navigation_mesh(false)
	NavigationServer3D.map_force_update(_region.get_navigation_map())
	_baked = _region.navigation_mesh != null and _region.navigation_mesh.get_polygon_count() > 0
	navigation_baked.emit()


func is_ready() -> bool:
	if not _baked or _region == null or not _region.is_inside_tree():
		return false
	var map_rid := _region.get_navigation_map()
	if not NavigationServer3D.map_is_active(map_rid):
		return false
	# 烘焙发生在主场景 _ready 内，导航地图可能要到下一个物理帧才同步。
	# 查询前强制同步一次，避免刚就绪时拿到空路径。
	NavigationServer3D.map_force_update(map_rid)
	return true


func get_closest_point(world_position: Vector3) -> Vector3:
	if not is_ready():
		return Vector3.INF
	return NavigationServer3D.map_get_closest_point(_region.get_navigation_map(), world_position)


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not is_ready():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(_region.get_navigation_map(), from, to, true)


func is_reachable(from: Vector3, to: Vector3) -> bool:
	return find_path(from, to).size() >= 2


static func get_path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += path[index - 1].distance_to(path[index])
	return total
