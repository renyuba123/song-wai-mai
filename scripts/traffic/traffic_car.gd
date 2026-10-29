extends AnimatableBody3D
class_name TrafficCar

## 真实汽车模型沿 RoadNetwork 右侧车道行驶；命中与路线复用原接口。

signal player_entered(body: Node3D)

const Catalog = preload("res://scripts/traffic/traffic_model_catalog.gd")
const BODY_SIZE := Vector3(1.9, 0.7, 4.2)
const BODY_CENTER_Y := 0.65
const CABIN_SIZE := Vector3(1.6, 0.6, 2.0)
const CABIN_CENTER := Vector3(0.0, 1.3, 0.15)
const WHEEL_SIZE := Vector3(0.28, 0.62, 0.62)
const WHEEL_X := 0.84
const WHEEL_Y := 0.31
const WHEEL_Z := 1.35
const LIGHT_SIZE := Vector3(0.34, 0.18, 0.08)
const LIGHT_Y := 0.72
const LIGHT_FRONT_Z := -2.11
const LIGHT_BACK_Z := 2.11

const COLLISION_SIZE := Vector3(1.9, 1.5, 4.2)
const COLLISION_CENTER_Y := 0.75
const HIT_SIZE := Vector3(2.1, 1.6, 4.4)
const HIT_CENTER_Y := 0.8

const GLASS_COLOR := Color("27313a")
const WHEEL_COLOR := Color("20242a")
const HEADLIGHT_COLOR := Color("fff2c4")
const TAILLIGHT_COLOR := Color("ff4a3d")
const PRELOAD_ROUTE_SEGMENTS := 2
const MAX_ADVANCE_STEPS := 4096
const POINT_EPS := 0.0001
const MODEL_VISUAL_YAW := PI

var speed_mps := 8.0
var cruise_speed_mps := 8.0
var model_index := -1
var _model: Node3D = null
var _idle_seconds := 0.0

var _network: RoadNetwork = null
var _adjacency: Array = []
var _rng: RandomNumberGenerator = null
var _path: Array[Vector3] = []
var _path_cursor := 0
var _last_edge_id := -1
var _last_to_node := -1
var _last_direction := Vector2.ZERO
var _spawn_edge_id := -1
var _distance_travelled := 0.0
var _car_color := Color.WHITE
var _nodes_built := false
var _hit_area: Area3D = null


func _ready() -> void:
	_ensure_nodes()


func setup(
	source_network: RoadNetwork,
	adjacency: Array,
	edge_id: int,
	from_node: int,
	spawn_offset: float,
	speed: float,
	car_rng: RandomNumberGenerator,
	color: Color,
	choice: int = 0
) -> void:
	_network = source_network
	_adjacency = adjacency
	_rng = car_rng
	_car_color = color
	speed_mps = maxf(speed, 0.0)
	cruise_speed_mps = speed_mps
	_distance_travelled = 0.0
	_idle_seconds = 0.0
	_spawn_edge_id = edge_id
	_ensure_nodes()
	_set_model(choice)

	var lane := TrafficRoute.edge_lane(_network, edge_id, from_node)
	if lane.is_empty():
		return
	var lane_length := float(lane.length)
	var offset := clampf(spawn_offset, 0.0, lane_length)
	var direction: Vector2 = lane.direction
	var start: Vector3 = lane.start
	var end: Vector3 = lane.end
	var spawn_point := start + Vector3(direction.x, 0.0, direction.y) * offset
	## 车辆挂在 TrafficSpawner 的 Vehicles 容器下，容器保持在原点，
	## 因此本地坐标与世界坐标一致，也方便离树测试。
	position = spawn_point
	rotation = Vector3(0.0, TrafficRoute.yaw_from_direction(direction), 0.0)

	_path.clear()
	_path.append(spawn_point)
	_path.append(end)
	_path_cursor = 1
	_last_edge_id = edge_id
	_last_to_node = int(lane.to)
	_last_direction = direction
	for _step in PRELOAD_ROUTE_SEGMENTS:
		_extend_path()
	if is_inside_tree():
		reset_physics_interpolation()


func advance(distance: float) -> void:
	## 按弧长沿折线移动。公开给测试和固定步长模拟使用。
	if distance <= 0.0 or _network == null:
		return
	var remaining := distance
	var guard := 0
	while remaining > POINT_EPS and guard < MAX_ADVANCE_STEPS:
		guard += 1
		while _path_cursor >= _path.size() - 1:
			var before := _path.size()
			_extend_path()
			if _path.size() == before:
				return
		var target: Vector3 = _path[_path_cursor]
		var delta := target - position
		delta.y = 0.0
		var segment_length := delta.length()
		if segment_length <= POINT_EPS:
			_path_cursor += 1
			continue
		var direction := delta / segment_length
		var step_distance := minf(remaining, segment_length)
		position += direction * step_distance
		rotation.y = TrafficRoute.yaw_from_direction(
			Vector2(direction.x, direction.z)
		)
		_distance_travelled += step_distance
		remaining -= step_distance
		if step_distance >= segment_length - POINT_EPS:
			_path_cursor += 1


func set_simulation_enabled(enabled: bool) -> void:
	set_physics_process(enabled)


func get_next_junction() -> Vector3:
	return _path[_path_cursor] if _path_cursor < _path.size() else Vector3.INF

func is_turn_approaching() -> bool:
	if _path_cursor + 2 >= _path.size():
		return false
	var current := _path[_path_cursor] - position
	var after := _path[_path_cursor + 2] - _path[_path_cursor + 1]
	return current.length() < 30.0 and current.normalized().dot(after.normalized()) < 0.8

func get_forward() -> Vector2:
	return Vector2(-sin(rotation.y), -cos(rotation.y))


func get_spawn_edge_id() -> int:
	return _spawn_edge_id


func get_path_point_count() -> int:
	return _path.size()


func get_distance_travelled() -> float:
	return _distance_travelled


func get_car_color() -> Color:
	return _car_color


func get_hit_area() -> Area3D:
	return _hit_area


func _physics_process(delta: float) -> void:
	if speed_mps <= 0.0:
		return
	advance(speed_mps * delta)


func _extend_path() -> void:
	if _network == null or _last_to_node < 0 or _adjacency.is_empty():
		return
	var next_edge_id := TrafficRoute.choose_next_edge(
		_network, _adjacency, _last_to_node, _last_edge_id, _last_direction, _rng
	)
	if next_edge_id < 0:
		return
	var lane := TrafficRoute.edge_lane(_network, next_edge_id, _last_to_node)
	if lane.is_empty():
		return
	var lane_start: Vector3 = lane.start
	if _path.is_empty() or _path[_path.size() - 1].distance_to(lane_start) > 0.01:
		_path.append(lane_start)
	_path.append(lane.end)
	_last_edge_id = next_edge_id
	_last_to_node = int(lane.to)
	_last_direction = lane.direction


func _ensure_nodes() -> void:
	if _nodes_built:
		return
	_nodes_built = true
	collision_layer = CollisionLayers.VEHICLE
	collision_mask = CollisionLayers.PLAYER
	sync_to_physics = false
	_build_visuals()

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.position = Vector3(0.0, COLLISION_CENTER_Y, 0.0)
	var body_shape := BoxShape3D.new()
	body_shape.size = COLLISION_SIZE
	collision.shape = body_shape
	add_child(collision)

	_hit_area = Area3D.new()
	_hit_area.name = "HitBox"
	_hit_area.position = Vector3(0.0, HIT_CENTER_Y, 0.0)
	_hit_area.collision_layer = CollisionLayers.TRIGGER
	_hit_area.collision_mask = CollisionLayers.PLAYER
	_hit_area.monitoring = true
	_hit_area.monitorable = false
	var hit_collision := CollisionShape3D.new()
	hit_collision.name = "HitShape"
	var hit_shape := BoxShape3D.new()
	hit_shape.size = HIT_SIZE
	hit_collision.shape = hit_shape
	_hit_area.add_child(hit_collision)
	_hit_area.body_entered.connect(_on_hit_body_entered)
	add_child(_hit_area)


func _build_visuals() -> void:
	# Keep a minimal fallback mesh and the historical Body node for diagnostics.
	var body := _add_box("Body", BODY_SIZE, Vector3(0, BODY_CENTER_Y, 0), _car_color)
	body.visible = false


func _set_model(choice: int) -> void:
	var index := posmod(choice, Catalog.MODELS.size())
	if model_index == index and is_instance_valid(_model):
		return
	if is_instance_valid(_model):
		_model.free()
	model_index = index
	var info: Dictionary = Catalog.MODELS[index]
	var path: String = info.path
	var scene: PackedScene = load(path)
	_model = Node3D.new()
	_model.name = "CarModel"
	_model.add_child(scene.instantiate())
	var box: AABB = info.bounds
	# The source cars face +Z while road traffic uses Godot's -Z forward axis.
	var model_rotation := Basis(Vector3.UP, MODEL_VISUAL_YAW)
	var rotated_box := Transform3D(model_rotation, Vector3.ZERO) * box
	# Bounds include imported root transforms. Scale uniformly and rest the lowest vertex on the road.
	var factor := minf(1.9 / box.size.x, 4.2 / box.size.z) * 1.6
	var origin := -rotated_box.get_center() * factor
	origin.y = -rotated_box.position.y * factor + 0.025
	_model.transform = Transform3D(
		model_rotation.scaled(Vector3.ONE * factor),
		origin
	)
	add_child(_model)
	var collision: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if collision != null:
		var shape := BoxShape3D.new()
		shape.size = Vector3(box.size.x * factor, box.size.y * factor, box.size.z * factor)
		collision.shape = shape
		collision.position = Vector3(0, shape.size.y * 0.5 + 0.025, 0)
	var hit_shape: CollisionShape3D = get_node_or_null("HitBox/HitShape")
	if hit_shape != null:
		var trigger := BoxShape3D.new()
		trigger.size = Vector3(box.size.x * factor + 0.2, box.size.y * factor + 0.2, box.size.z * factor + 0.2)
		hit_shape.shape = trigger
		_hit_area.position.y = shape_y() * 0.5 + 0.025


func shape_y() -> float:
	var collision: CollisionShape3D = get_node("CollisionShape3D")
	return collision.shape.size.y


func update_speed(delta: float, target: float, acceleration: float, braking: float) -> void:
	var rate := acceleration if target >= speed_mps else braking
	speed_mps = move_toward(speed_mps, maxf(target, 0.0), rate * delta)
	advance(speed_mps * delta)


func _add_box(
	node_name: String,
	size: Vector3,
	offset: Vector3,
	color: Color,
	emission: Color = Color(0.0, 0.0, 0.0, 0.0)
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = offset
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	if emission.a > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.8
	instance.material_override = material
	add_child(instance)
	return instance


func _on_hit_body_entered(body: Node3D) -> void:
	var physics_body := body as PhysicsBody3D
	if physics_body == null:
		return
	if physics_body.collision_layer & CollisionLayers.PLAYER == 0:
		return
	player_entered.emit(body)
