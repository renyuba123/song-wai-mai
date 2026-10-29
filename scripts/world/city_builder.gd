@tool
extends Node3D
class_name CityBuilder

## 常驻城市表现：人行道、实际模型包围盒的低细节建筑、入口和站点标记。
## 人行道碰撞体加入 navigation_source，行人和玩家可以走人行道；
## 建筑碰撞体仍然不参与导航，导航网格不会铺进建筑内部。

const SIDEWALK_COLOR := Color("b7b9b5")
const MERCHANT_COLOR := Color("d98b4f")
const RESIDENTIAL_COLOR := Color("71859a")
const VACANT_COLOR := Color("8c8f91")
const MERCHANT_MARKER_COLOR := Color("f2c14e")
const CUSTOMER_MARKER_COLOR := Color("4fc3c8")
const GENERATED_META := &"world_generator_generated"

var _map_size: Vector2

var _sidewalk_body: StaticBody3D = null
var _building_body: StaticBody3D = null
var _materials := {}
var population_layout: CityPopulationLayout
var _lod_visuals := {}


func build(network: RoadNetwork, city: CityContent) -> void:
	_clear()
	if network == null or city == null:
		return
	_map_size = network.map_size
	if population_layout == null or population_layout.seed_value != city.seed_value:
		population_layout = CityPopulationLayout.generate(city)
	_materials = {
		"sidewalk": _material(SIDEWALK_COLOR),
		"merchant": _material(MERCHANT_COLOR),
		"residential": _material(RESIDENTIAL_COLOR),
		"vacant": _material(VACANT_COLOR),
		"merchant_marker": _marker_material(MERCHANT_MARKER_COLOR),
		"customer_marker": _marker_material(CUSTOMER_MARKER_COLOR),
	}
	_build_sidewalks(network)
	_build_buildings(city)
	_build_markers(city)


func _build_sidewalks(network: RoadNetwork) -> void:
	_sidewalk_body = StaticBody3D.new()
	_sidewalk_body.name = "SidewalkCollision"
	_sidewalk_body.collision_layer = CollisionLayers.WORLD_STATIC
	_sidewalk_body.collision_mask = 0
	_sidewalk_body.add_to_group(CollisionLayers.NAVIGATION_SOURCE_GROUP)
	_add_generated_child(_sidewalk_body)

	var nodes: Array = network.nodes
	var junction_widths: Array = []
	for _id in nodes.size():
		junction_widths.append(0.0)
	for edge in network.edges:
		var redline: float = network.widths[int(edge.kind)]
		for id in [edge.a, edge.b]:
			junction_widths[id] = maxf(junction_widths[id], redline)

	for edge_id in network.edges.size():
		var edge: Dictionary = network.edges[edge_id]
		var a: Vector2 = nodes[edge.a]
		var b: Vector2 = nodes[edge.b]
		var length := a.distance_to(b)
		if length <= RoadNetwork.EPS:
			continue
		var redline: float = network.widths[int(edge.kind)]
		var carriageway := redline * RoadNetwork.CARRIAGEWAY_RATIO
		var band_width := (redline - carriageway) * 0.5
		if band_width <= RoadNetwork.EPS:
			continue
		var start: float = float(junction_widths[edge.a]) * 0.5
		var finish: float = length - float(junction_widths[edge.b]) * 0.5
		if finish - start <= RoadNetwork.EPS:
			continue
		var direction := (b - a) / length
		var left := Vector2(direction.y, -direction.x)
		var yaw := -direction.angle()
		var centreline := a.lerp(b, (start + finish) * 0.5 / length)
		var usable_length := finish - start
		var visual_size := Vector3(usable_length, 0.01, band_width)
		var collision_size := Vector3(usable_length, 0.04, band_width)
		for side in [1, -1]:
			var lateral := RoadNetwork.sidewalk_offset(redline) * float(side)
			var point := centreline + left * lateral
			var centre := Vector3(point.x, 0.0, point.y)
			_visual_box(
				visual_size,
				centre + Vector3(0.0, RoadNetwork.SURFACE_Y + 0.007, 0.0),
				_materials.sidewalk,
				yaw
			)
			_collision_box(
				collision_size,
				centre + Vector3(0.0, RoadNetwork.SURFACE_Y - 0.02, 0.0),
				_sidewalk_body,
				yaw
			)


func _build_buildings(city: CityContent) -> void:
	_building_body = StaticBody3D.new()
	_building_body.name = "BuildingCollision"
	_building_body.collision_layer = CollisionLayers.WORLD_STATIC
	_building_body.collision_mask = 0
	_add_generated_child(_building_body)

	for building in city.buildings:
		var item: Dictionary = population_layout.buildings[int(building.id)]
		var material: Material = _materials.vacant
		if int(building.kind) == CitySite.Kind.MERCHANT:
			material = _materials.merchant
		elif int(building.kind) == CitySite.Kind.RESIDENTIAL:
			material = _materials.residential
		var visual := _visual_box(item.size, item.center, material)
		_lod_visuals[int(building.id)] = visual
		_collision_box(item.size, item.center, _building_body)
		if not item.site_id.is_empty():
			var rect: Rect2 = item.footprint
			var door := CityPopulationLayout.door_point(rect, item.yaw)
			var target: Vector3 = item.target
			var endpoint := Vector3(door.x, 0.025, door.y)
			_visual_box(
				Vector3(2, 0.015, target.distance_to(endpoint)),
				(target + endpoint) * 0.5 + Vector3(0, 0.02, 0),
				_materials.sidewalk,
				item.yaw
			)

func set_detail_visible(id: int, detailed: bool) -> void:
	if _lod_visuals.has(id) and is_instance_valid(_lod_visuals[id]):
		_lod_visuals[id].visible = not detailed


func _build_markers(city: CityContent) -> void:
	for site in city.sites:
		if site == null or site.spawn_point == null:
			continue
		var marker := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.7
		mesh.bottom_radius = 0.7
		mesh.height = 2.0
		marker.mesh = mesh
		marker.material_override = (
			_materials.merchant_marker
			if site.kind == CitySite.Kind.MERCHANT
			else _materials.customer_marker
		)
		marker.position = site.spawn_point.position + Vector3(0.0, 1.0, 0.0)
		_add_generated_child(marker)


func _clear() -> void:
	for child in get_children():
		if bool(child.get_meta(GENERATED_META, false)):
			child.free()
	_sidewalk_body = null
	_building_body = null
	_materials = {}
	_lod_visuals.clear()


func _add_generated_child(child: Node) -> void:
	child.set_meta(GENERATED_META, true)
	add_child(child)


func _visual_box(size: Vector3, position: Vector3, material: Material, yaw: float = 0.0) -> MeshInstance3D:
	var polygon := RoadBuilder.clipped_footprint(size, position, yaw, _map_size)
	if not polygon.is_empty():
		var clipped := MeshInstance3D.new()
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(1, polygon.size() - 1):
			for vertex in [polygon[0], polygon[index + 1], polygon[index]]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(Vector3(vertex.x, position.y + size.y * 0.5, vertex.y))
		clipped.mesh = surface.commit()
		clipped.material_override = material
		_add_generated_child(clipped)
		return clipped
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation.y = yaw
	_add_generated_child(instance)
	return instance


func _collision_box(size: Vector3, position: Vector3, body: StaticBody3D, yaw: float = 0.0) -> void:
	var polygon := RoadBuilder.clipped_footprint(size, position, yaw, _map_size)
	if not polygon.is_empty():
		var clipped_node := CollisionShape3D.new()
		var clipped_shape := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for vertex in polygon:
			points.append(Vector3(vertex.x, position.y - size.y * 0.5, vertex.y))
			points.append(Vector3(vertex.x, position.y + size.y * 0.5, vertex.y))
		clipped_shape.points = points
		clipped_node.shape = clipped_shape
		body.add_child(clipped_node)
		return
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	shape_node.position = position
	shape_node.rotation.y = yaw
	body.add_child(shape_node)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _marker_material(color: Color) -> StandardMaterial3D:
	var material := _material(color)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.4
	return material
