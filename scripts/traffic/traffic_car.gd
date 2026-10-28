extends AnimatableBody3D
class_name TrafficCar

## 占位汽车：车身、车厢和轮子都由 BoxMesh 在代码里生成，
## 沿右侧车道折线行驶。等正式汽车模型拆分完成后，只需替换
## _build_visuals()，路线、碰撞和命中逻辑可以继续复用。

signal player_entered(body: Node3D)

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

var speed_mps := 8.0

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
	color: Color
) -> void:
	_network = source_network
	_adjacency = adjacency
	_rng = car_rng
	_car_color = color
	speed_mps = maxf(speed, 0.0)
	_spawn_edge_id = edge_id
	_ensure_nodes()

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
	sync_to_physics = true
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
	_add_box("Body", BODY_SIZE, Vector3(0.0, BODY_CENTER_Y, 0.0), _car_color)
	_add_box("Cabin", CABIN_SIZE, CABIN_CENTER, GLASS_COLOR)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			_add_box(
				"Wheel", WHEEL_SIZE,
				Vector3(WHEEL_X * side, WHEEL_Y, WHEEL_Z * end),
				WHEEL_COLOR
			)
		_add_box(
			"Headlight", LIGHT_SIZE,
			Vector3(0.55 * side, LIGHT_Y, LIGHT_FRONT_Z),
			HEADLIGHT_COLOR, HEADLIGHT_COLOR
		)
		_add_box(
			"Taillight", LIGHT_SIZE,
			Vector3(0.55 * side, LIGHT_Y, LIGHT_BACK_Z),
			TAILLIGHT_COLOR, TAILLIGHT_COLOR
		)


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
