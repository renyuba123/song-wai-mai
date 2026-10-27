extends Node3D

@export_range(1200.0, 10000.0, 100.0) var map_width_m := 2400.0
@export_range(1200.0, 10000.0, 100.0) var map_height_m := 2400.0
@export var random_seed: int = 42
@export_range(0.0, 1.0, 0.05) var road_density := 0.5
@export_range(30.0, 50.0, 1.0) var main_redline_m := 40.0
@export_range(20.0, 40.0, 1.0) var secondary_redline_m := 30.0
@export_range(14.0, 24.0, 1.0) var local_redline_m := 18.0
@export var allow_difficult_entrance_exceptions := false

const ROAD_COLORS := [Color("d66752"), Color("e8b65b"), Color("6bbdb1")]
const CORRIDOR_COLOR := Color("3c4650")
const GROUND_COLOR := Color("669473")

var network: Dictionary
var report: Dictionary
var road_body: StaticBody3D

func _ready() -> void:
	regenerate()

func regenerate() -> void:
	for child in get_children():
		child.queue_free()
	network = RoadNetwork.generate(
		Vector2(map_width_m, map_height_m), random_seed, road_density,
		Vector3(main_redline_m, secondary_redline_m, local_redline_m),
		allow_difficult_entrance_exceptions
	)
	report = RoadNetwork.validate(network)
	_draw_network()
	_add_camera_and_light()
	_add_overlay()
	print("路网校验：", "通过" if report.valid else "失败", "；节点 ", report.nodes, "；路段 ", report.edges)
	for message in report.errors:
		push_error(message)
	for message in report.notes:
		print("说明：", message)

func _draw_network() -> void:
	road_body = StaticBody3D.new()
	road_body.name = "RoadCollision"
	add_child(road_body)
	var ground := _material(GROUND_COLOR)
	var corridor := _material(CORRIDOR_COLOR)
	var surface := []
	for color in ROAD_COLORS:
		surface.append(_material(color))
	_box(Vector3(map_width_m + 80.0, 0.15, map_height_m + 80.0), Vector3(0.0, -0.15, 0.0), ground, true)
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
		var carriageway: float = redline * 0.55
		var horizontal: bool = absf(a.x - b.x) > absf(a.y - b.y)
		var length: float = a.distance_to(b)
		var centre := Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5)
		var base_size := Vector3(length + 0.05, 0.08, redline) if horizontal else Vector3(redline, 0.08, length + 0.05)
		var lane_size := Vector3(length + 0.07, 0.09, carriageway) if horizontal else Vector3(carriageway, 0.09, length + 0.07)
		_box(base_size, centre + Vector3(0.0, 0.02, 0.0), corridor)
		_box(lane_size, centre + Vector3(0.0, 0.08, 0.0), surface[kind], true)
		for id in [edge.a, edge.b]:
			junction_widths[id] = maxf(junction_widths[id], redline)
			junction_kinds[id] = mini(junction_kinds[id], kind)
	for id in nodes.size():
		var position: Vector2 = nodes[id]
		var width: float = junction_widths[id]
		var kind: int = junction_kinds[id]
		var centre := Vector3(position.x, 0.0, position.y)
		_box(Vector3(width, 0.09, width), centre + Vector3(0.0, 0.03, 0.0), corridor)
		_box(Vector3(width * 0.55, 0.09, width * 0.55), centre + Vector3(0.0, 0.08, 0.0), surface[kind], true)

func _box(size: Vector3, position: Vector3, material: Material, collidable: bool = false) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	add_child(instance)
	if collidable:
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		shape_node.position = position
		road_body.add_child(shape_node)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material

func _add_camera_and_light() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(map_width_m, map_height_m) * 1.45
	camera.position = Vector3(0.0, maxf(map_width_m, map_height_m) * 0.9, maxf(map_width_m, map_height_m) * 0.6)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)

func _add_overlay() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var label := Label.new()
	label.position = Vector2(16.0, 16.0)
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.text = "大城市送外卖 · 3D 路网\n主干路：红　次干路：黄　支路：青\n种子 %d · 节点 %d · 路段 %d · 硬规则：%s" % [
		random_seed, report.nodes, report.edges, "通过" if report.valid else "失败"
	]
	ui.add_child(label)
