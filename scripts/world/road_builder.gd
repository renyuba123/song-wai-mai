extends Node3D
class_name RoadBuilder

## 把 RoadNetwork 绘制成 3D 道路，并生成静态碰撞体。
## 只读取数据，不修改 RoadNetwork。

const ROAD_COLORS := [Color("d66752"), Color("e8b65b"), Color("6bbdb1")]
const CORRIDOR_COLOR := Color("3c4650")
const GROUND_COLOR := Color("669473")

var road_body: StaticBody3D
var ground_body: StaticBody3D


func build(network: RoadNetwork) -> void:
	_clear()
	road_body = StaticBody3D.new()
	road_body.name = "RoadCollision"
	road_body.collision_layer = CollisionLayers.WORLD_STATIC
	road_body.collision_mask = 0
	road_body.add_to_group(CollisionLayers.NAVIGATION_SOURCE_GROUP)
	add_child(road_body)

	# 地面参与玩家碰撞，但不参与导航烘焙；导航网格只覆盖道路。
	ground_body = StaticBody3D.new()
	ground_body.name = "GroundCollision"
	ground_body.collision_layer = CollisionLayers.WORLD_STATIC
	ground_body.collision_mask = 0
	add_child(ground_body)

	var ground := _material(GROUND_COLOR)
	var corridor := _material(CORRIDOR_COLOR)
	var surface := []
	for color in ROAD_COLORS:
		surface.append(_material(color))
	var ground_size := Vector3(network.map_size.x + 80.0, 0.5, network.map_size.y + 80.0)
	var ground_position := Vector3(0.0, RoadNetwork.SURFACE_Y - 0.25, 0.0)
	_visual_box(ground_size, ground_position, ground)
	_collision_box(ground_size, ground_position, ground_body)

	var nodes: Array = network.nodes
	var junction_widths: Array = []
	var junction_kinds: Array = []
	for _id in nodes.size():
		junction_widths.append(0.0)
		junction_kinds.append(RoadNetwork.LOCAL)
	for edge in network.edges:
		var a: Vector2 = nodes[edge.a]
		var b: Vector2 = nodes[edge.b]
		var kind: int = edge.kind
		var redline: float = network.widths[kind]
		var carriageway: float = redline * RoadNetwork.CARRIAGEWAY_RATIO
		var horizontal: bool = absf(a.x - b.x) > absf(a.y - b.y)
		var length: float = a.distance_to(b)
		var centre := Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5)
		var corridor_size := Vector3(length + 0.05, 0.01, redline) if horizontal else Vector3(redline, 0.01, length + 0.05)
		var lane_size := Vector3(length + 0.07, 0.01, carriageway) if horizontal else Vector3(carriageway, 0.01, length + 0.07)
		var lane_collision_size := Vector3(length + 0.07, 0.04, carriageway) if horizontal else Vector3(carriageway, 0.04, length + 0.07)
		_visual_box(corridor_size, centre + Vector3(0.0, RoadNetwork.SURFACE_Y, 0.0), corridor)
		_visual_box(lane_size, centre + Vector3(0.0, RoadNetwork.SURFACE_Y + 0.005, 0.0), surface[kind])
		_collision_box(lane_collision_size, centre + Vector3(0.0, RoadNetwork.SURFACE_Y - 0.02, 0.0), road_body)
		for id in [edge.a, edge.b]:
			junction_widths[id] = maxf(junction_widths[id], redline)
			junction_kinds[id] = mini(junction_kinds[id], kind)
	for id in nodes.size():
		var position: Vector2 = nodes[id]
		var width: float = junction_widths[id]
		var kind: int = junction_kinds[id]
		var centre := Vector3(position.x, 0.0, position.y)
		var carriageway: float = width * RoadNetwork.CARRIAGEWAY_RATIO
		_visual_box(Vector3(width, 0.01, width), centre + Vector3(0.0, RoadNetwork.SURFACE_Y, 0.0), corridor)
		_visual_box(Vector3(carriageway, 0.01, carriageway), centre + Vector3(0.0, RoadNetwork.SURFACE_Y + 0.005, 0.0), surface[kind])
		_collision_box(Vector3(carriageway, 0.04, carriageway), centre + Vector3(0.0, RoadNetwork.SURFACE_Y - 0.02, 0.0), road_body)


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _visual_box(size: Vector3, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	add_child(instance)


func _collision_box(size: Vector3, position: Vector3, body: StaticBody3D) -> void:
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	shape_node.position = position
	body.add_child(shape_node)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
