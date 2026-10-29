
@tool
extends Node3D
class_name RoadBuilder

## 把 RoadNetwork 绘制成 3D 道路，并生成静态碰撞体。
## 只读取数据，不修改 RoadNetwork。

const ROAD_COLORS := [Color("d66752"), Color("e8b65b"), Color("6bbdb1")]
const CORRIDOR_COLOR := Color("3c4650")
# The grass map needs extra brightness under the pixel-art screen effect.
const GROUND_COLOR := Color(1.7, 1.9, 1.5)
const GENERATED_META := &"world_generator_generated"
const ROAD_TEXTURE := preload("res://assets/textures/road_asphalt_02_diff_1k.jpg")
const GRASS_TEXTURE := preload("res://assets/textures/grass004_color_1k.jpg")

# 新增：草地纹理饱和度
# 1.0 = 原始饱和度，0.7 = 降低饱和度，0.0 = 黑白
const GRASS_SATURATION := 0.5

# 新增：缓存处理后的草地纹理
var _grass_texture_cache: Texture2D = null

var _map_size: Vector2

var road_body: StaticBody3D
var ground_body: StaticBody3D


func build(network: RoadNetwork) -> void:
	_clear()
	_map_size = network.map_size
	road_body = StaticBody3D.new()
	road_body.name = "RoadCollision"
	road_body.collision_layer = CollisionLayers.WORLD_STATIC
	road_body.collision_mask = 0
	road_body.add_to_group(CollisionLayers.NAVIGATION_SOURCE_GROUP)
	_add_generated_child(road_body)

	# 地面参与玩家碰撞，但不参与导航烘焙；导航网格只覆盖道路。
	ground_body = StaticBody3D.new()
	ground_body.name = "GroundCollision"
	ground_body.collision_layer = CollisionLayers.WORLD_STATIC
	ground_body.collision_mask = 0
	_add_generated_child(ground_body)

	var ground := _ground_material()
	var corridor := _material(CORRIDOR_COLOR)
	var surface := []
	for color in ROAD_COLORS:
		surface.append(_road_material(color))
	var ground_size := Vector3(network.map_size.x, 0.5, network.map_size.y)
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
		var yaw := - (b - a).angle()
		var length: float = a.distance_to(b)
		var centre := Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5)
		var corridor_size := Vector3(length + 0.05, 0.01, redline)
		var lane_size := Vector3(length + 0.07, 0.01, carriageway)
		var lane_collision_size := Vector3(length + 0.07, 0.04, carriageway)
		_visual_box(corridor_size, centre + Vector3(0.0, RoadNetwork.SURFACE_Y, 0.0), corridor, yaw)
		_visual_box(lane_size, centre + Vector3(0.0, RoadNetwork.SURFACE_Y + 0.005, 0.0), surface[kind], yaw)
		_collision_box(lane_collision_size, centre + Vector3(0.0, RoadNetwork.SURFACE_Y - 0.02, 0.0), road_body, yaw)
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
		if bool(child.get_meta(GENERATED_META, false)):
			child.free()
	road_body = null
	ground_body = null


func _add_generated_child(child: Node) -> void:
	child.set_meta(GENERATED_META, true)
	add_child(child)


func _visual_box(size: Vector3, position: Vector3, material: Material, yaw: float = 0.0) -> void:
	var polygon := clipped_footprint(size, position, yaw, _map_size)
	if not polygon.is_empty():
		var instance := MeshInstance3D.new()
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(1, polygon.size() - 1):
			for vertex in [polygon[0], polygon[index + 1], polygon[index]]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(Vector3(vertex.x, position.y + size.y * 0.5, vertex.y))
		instance.mesh = surface.commit()
		instance.material_override = material
		_add_generated_child(instance)
		return
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation.y = yaw
	_add_generated_child(instance)


func _collision_box(size: Vector3, position: Vector3, body: StaticBody3D, yaw: float = 0.0) -> void:
	var polygon := clipped_footprint(size, position, yaw, _map_size)
	if not polygon.is_empty():
		var shape_node := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for vertex in polygon:
			points.append(Vector3(vertex.x, position.y - size.y * 0.5, vertex.y))
			points.append(Vector3(vertex.x, position.y + size.y * 0.5, vertex.y))
		shape.points = points
		shape_node.shape = shape
		body.add_child(shape_node)
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


func _road_material(color: Color) -> StandardMaterial3D:
	var material := _material(color.lerp(Color.WHITE, 0.72))
	material.albedo_texture = ROAD_TEXTURE
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.08, 0.08, 0.08)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


func _ground_material() -> StandardMaterial3D:
	var material := _material(GROUND_COLOR)

	# 新增：只在第一次使用时处理草地纹理
	if _grass_texture_cache == null:
		var image: Image = GRASS_TEXTURE.get_image()

		if image != null and not image.is_empty():
			# 压缩图像必须先解压才能修改饱和度
			if image.is_compressed():
				var err: Error = image.decompress()
				if err != OK:
					push_warning("Grass texture decompression failed")

			if not image.is_compressed():
				# 亮度、对比度、饱和度
				image.adjust_bcs(1.0, 1.0, GRASS_SATURATION)
				image.generate_mipmaps()
				_grass_texture_cache = ImageTexture.create_from_image(image)

		# 处理失败时回退到原始纹理
		if _grass_texture_cache == null:
			_grass_texture_cache = GRASS_TEXTURE

	material.albedo_texture = _grass_texture_cache
	material.uv1_triplanar = true
	# Grass004 covers about 1.4 m. Tile gently to keep the detail visible
	# from street level without turning distant greenery into noisy pixels.
	material.uv1_scale = Vector3(0.4, 0.4, 0.4)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


static func clipped_footprint(size: Vector3, centre: Vector3, yaw: float, map_size: Vector2) -> PackedVector2Array:
	var half := map_size * 0.5
	var corners := PackedVector2Array()
	var outside := false
	for sign_vector in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var point: Vector2 = (sign_vector * Vector2(size.x, size.z) * 0.5).rotated(-yaw) + Vector2(centre.x, centre.z)
		corners.append(point)
		outside = outside or absf(point.x) > half.x or absf(point.y) > half.y
	if not outside:
		return PackedVector2Array()
	var bounds := PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	var clipped := Geometry2D.intersect_polygons(corners, bounds)
	if clipped.is_empty():
		return PackedVector2Array()
	var polygon: PackedVector2Array = clipped[0]
	# 只擦到地图边缘的薄片会退化成近零面积，凸包碰撞体和导航烘焙
	# 都会因此不稳定；这种情况直接按未裁切处理。
	if polygon.size() < 3:
		return PackedVector2Array()
	var twice_area := 0.0
	for index in polygon.size():
		twice_area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	if absf(twice_area) < 0.02:
		return PackedVector2Array()
	return polygon
