extends Node3D
class_name TrafficSpawner

## 交通生成入口：按路网确定性生成占位汽车，并沿右侧车道行驶。
## 行人尚未接入；max_pedestrians 保留给后续人物模型。

signal traffic_ready
signal player_hit(car: TrafficCar, player_position: Vector3)

const RNG_SALT := 0x7A4FF1C
const MIN_EDGE_MARGIN_M := 20.0
const MIN_SPAWN_CLEARANCE_M := 15.0
const SPAWN_ATTEMPTS := 8
const SPEEDS := [13.0, 10.0, 7.0]
const COLORS := [
	Color("c94f4f"),
	Color("3f7fbf"),
	Color("e0c15a"),
	Color("e8e8e8"),
	Color("555e66"),
]

@export var max_vehicles := 16
@export var max_pedestrians := 0

var network: RoadNetwork = null

var _cars: Array[TrafficCar] = []
var _vehicles: Node3D = null


func build(source_network: RoadNetwork, source_city: CityContent = null) -> void:
	network = source_network
	_clear_vehicles()
	if network == null or network.edges.is_empty() or max_vehicles <= 0:
		print("交通系统：生成 0 辆汽车（上限 ", max_vehicles, "）")
		traffic_ready.emit()
		return

	_vehicles = Node3D.new()
	_vehicles.name = "Vehicles"
	add_child(_vehicles)

	var rng := RandomNumberGenerator.new()
	rng.seed = network.seed_value ^ RNG_SALT
	var adjacency := TrafficRoute.build_adjacency(network)
	var edge_ids: Array[int] = []
	for edge_id in network.edges.size():
		edge_ids.append(edge_id)
	_shuffle(edge_ids, rng)
	var avoidance := _collect_avoidance(source_city)
	var target := mini(max_vehicles, edge_ids.size())

	for edge_id in edge_ids:
		if _cars.size() >= target:
			break
		var spawn := _pick_spawn(edge_id, avoidance, rng)
		if spawn.is_empty():
			continue
		var car := TrafficCar.new()
		car.name = "Vehicle%d" % _cars.size()
		var car_rng := RandomNumberGenerator.new()
		car_rng.seed = rng.randi()
		var kind := clampi(int(network.edges[edge_id].kind), 0, SPEEDS.size() - 1)
		var speed := float(SPEEDS[kind]) * rng.randf_range(0.9, 1.1)
		var color: Color = COLORS[rng.randi_range(0, COLORS.size() - 1)]
		car.setup(
			network, adjacency, edge_id, int(spawn.from),
			float(spawn.offset), speed, car_rng, color
		)
		car.player_entered.connect(_on_car_player_entered.bind(car))
		_vehicles.add_child(car)
		_cars.append(car)

	print(
		"交通系统：生成 ", _cars.size(), " 辆汽车（上限 ",
		max_vehicles, "）"
	)
	traffic_ready.emit()


func get_vehicle_count() -> int:
	return _cars.size()


func get_cars() -> Array[TrafficCar]:
	return _cars


func _pick_spawn(
	edge_id: int,
	avoidance: Array[Vector3],
	rng: RandomNumberGenerator
) -> Dictionary:
	var edge: Dictionary = network.edges[edge_id]
	var endpoint_a: Vector2 = network.nodes[int(edge.a)]
	var endpoint_b: Vector2 = network.nodes[int(edge.b)]
	var length := endpoint_a.distance_to(endpoint_b)
	if length <= MIN_EDGE_MARGIN_M * 2.0:
		return {}
	for _attempt in SPAWN_ATTEMPTS:
		var from_node := int(edge.a) if rng.randf() < 0.5 else int(edge.b)
		var lane := TrafficRoute.edge_lane(network, edge_id, from_node)
		if lane.is_empty():
			continue
		var max_offset := float(lane.length) - MIN_EDGE_MARGIN_M
		if max_offset < MIN_EDGE_MARGIN_M:
			continue
		var offset := rng.randf_range(MIN_EDGE_MARGIN_M, max_offset)
		var direction: Vector2 = lane.direction
		var start: Vector3 = lane.start
		var position := start + Vector3(direction.x, 0.0, direction.y) * offset
		if _has_clearance(position, avoidance):
			return {"from": from_node, "offset": offset}
	return {}


func _has_clearance(position: Vector3, avoidance: Array[Vector3]) -> bool:
	var point := Vector2(position.x, position.z)
	for other in avoidance:
		if point.distance_to(Vector2(other.x, other.z)) < MIN_SPAWN_CLEARANCE_M:
			return false
	return true


func _collect_avoidance(city: CityContent) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if city == null:
		return result
	if city.player_start != null:
		result.append(city.player_start.position)
	for start in city.player_starts:
		if start != null:
			result.append(start.position)
	for site in city.sites:
		if site != null and site.spawn_point != null:
			result.append(site.spawn_point.position)
	return result


func _shuffle(values: Array[int], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temp := values[index]
		values[index] = values[swap_index]
		values[swap_index] = temp


func _on_car_player_entered(body: Node3D, car: TrafficCar) -> void:
	if body == null:
		return
	var physics_body := body as PhysicsBody3D
	if physics_body == null:
		return
	if physics_body.collision_layer & CollisionLayers.PLAYER == 0:
		return
	player_hit.emit(car, body.global_position)


func _clear_vehicles() -> void:
	_cars.clear()
	if _vehicles != null and is_instance_valid(_vehicles):
		if _vehicles.get_parent() == self:
			remove_child(_vehicles)
		_vehicles.free()
	_vehicles = null
