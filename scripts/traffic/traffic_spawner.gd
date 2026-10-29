extends Node3D
class_name TrafficSpawner
## The original RoadNetwork/TrafficRoute car system, active only around the player.
signal traffic_ready
signal player_hit(car: TrafficCar, player_position: Vector3)
const RNG_SALT := 0x7A4FF1C
const MIN_EDGE_MARGIN_M := 20.0
const MIN_SPAWN_CLEARANCE_M := 15.0
const SPAWN_ATTEMPTS := 12
const SPEEDS := [12.0, 9.0, 7.0]
const COLORS := [Color("c94f4f"), Color("3f7fbf"), Color("e0c15a"), Color("e8e8e8"), Color("555e66")]
@export var enable_traffic := true
@export_range(0.1, 3.0) var traffic_density := 1.0
@export_range(1, 100) var max_vehicles := 30
@export var max_pedestrians := 0
@export_range(50.0, 1000.0) var traffic_spawn_radius := 220.0
@export_range(100.0, 1400.0) var traffic_despawn_radius := 320.0
@export_range(0.1, 2.0) var traffic_update_interval := 0.5
@export_range(5.0, 80.0) var min_vehicle_spacing := 24.0
@export_range(0.0, 100.0) var min_speed_kmh := 25.0
@export_range(1.0, 120.0) var max_speed_kmh := 45.0
@export_range(0.1, 10.0) var acceleration_mps2 := 2.2
@export_range(0.1, 20.0) var braking_mps2 := 5.0
@export var show_traffic_debug := false
var network: RoadNetwork = null
var _cars: Array[TrafficCar] = []
var _pool: Array[TrafficCar] = []
var _vehicles: Node3D = null
var _adjacency: Array = []
var _edge_ids: Array[int] = []
var _avoidance: Array[Vector3] = []
var _player: Node3D = null
var _camera: Camera3D = null
var _focus := Vector3.ZERO
var _update_clock := 0.0
var _debug_clock := 0.0
var _serial := 0
var _spawned := 0
var _recycled := 0
var _active_roads := 0

func set_player(player: Node3D) -> void:
	_player = player
	_camera = player.get_node_or_null("Camera3D") if player != null else null
	if player != null and network != null:
		update_traffic(player.global_position, true)

func build(source_network: RoadNetwork, source_city: CityContent = null) -> void:
	_clear_vehicles()
	network = source_network
	if network == null or network.edges.is_empty() or max_vehicles <= 0 or not enable_traffic:
		traffic_ready.emit()
		return
	_vehicles = Node3D.new()
	_vehicles.name = "Vehicles"
	add_child(_vehicles)
	_adjacency = TrafficRoute.build_adjacency(network)
	_edge_ids.clear()
	for edge_id in network.edges.size():
		_edge_ids.append(edge_id)
	_avoidance = _collect_avoidance(source_city)
	_focus = source_city.player_start.position if source_city != null and source_city.player_start != null else Vector3.ZERO
	if is_instance_valid(_player):
		_focus = _player.global_position
	update_traffic(_focus, true)
	traffic_ready.emit()

func get_vehicle_count() -> int:
	return _cars.size()
func get_cars() -> Array[TrafficCar]:
	return _cars
func get_active_road_count() -> int:
	return _active_roads
func get_recycled_count() -> int:
	return _recycled
func get_pool_count() -> int:
	return _pool.size()

func _physics_process(delta: float) -> void:
	if network == null or not enable_traffic:
		return
	if is_instance_valid(_player):
		_focus = _player.global_position
	for car in _cars:
		var target := car.cruise_speed_mps
		var forward := car.get_forward()
		if car.is_turn_approaching():
			target = minf(target, car.cruise_speed_mps * 0.55)
		var closest := INF
		for other in _cars:
			if car == other:
				continue
			var difference := Vector2(other.position.x - car.position.x, other.position.z - car.position.z)
			var ahead := difference.dot(forward)
			if ahead <= 0 or ahead >= 45.0 or absf(difference.cross(forward)) > 2.4:
				continue
			closest = minf(closest, ahead)
		if closest < min_vehicle_spacing:
			target = 0.0 if closest < min_vehicle_spacing * 0.6 else minf(target, (closest - min_vehicle_spacing * 0.6) * 0.9)
		elif closest < min_vehicle_spacing * 1.7:
			target = minf(target, car.cruise_speed_mps * (closest - min_vehicle_spacing) / maxf(min_vehicle_spacing * 0.7, 1.0))
		# Basic unsignalled-junction yielding: the nearest approach proceeds first.
		var junction := car.get_next_junction()
		if junction.is_finite() and car.position.distance_to(junction) < 25.0:
			for other in _cars:
				if car == other or other.get_forward().dot(forward) > 0.8:
					continue
				var other_junction := other.get_next_junction()
				if other_junction.is_finite() and other_junction.distance_to(junction) < 15.0 and other.position.distance_to(junction) < 18.0:
					if other.position.distance_to(junction) < car.position.distance_to(junction) or (absf(other.position.distance_to(junction) - car.position.distance_to(junction)) < 1.0 and other.get_instance_id() < car.get_instance_id()):
						target = 0.0
		if is_instance_valid(_player):
			var player_delta := Vector2(_player.global_position.x - car.position.x, _player.global_position.z - car.position.z)
			if player_delta.dot(forward) > 0 and absf(player_delta.cross(forward)) < 2.5 and player_delta.length() < min_vehicle_spacing:
				target = 0.0
		var old_distance := car.get_distance_travelled()
		car.update_speed(delta, target, acceleration_mps2, braking_mps2)
		if car.get_distance_travelled() <= old_distance + 0.001 and car.speed_mps > 0.5 and closest >= min_vehicle_spacing:
			car._idle_seconds += delta
		else:
			car._idle_seconds = 0.0
	_update_clock += delta
	_debug_clock += delta
	if _update_clock >= traffic_update_interval:
		_update_clock = 0.0
		update_traffic(_focus)
	if show_traffic_debug and _debug_clock >= 2.0:
		_debug_clock = 0.0
		print("交通：active=", _cars.size(), " roads=", _active_roads, " spawned=", _spawned, " recycled=", _recycled, " pool=", _pool.size())

func update_traffic(position: Vector3, immediate := false) -> void:
	if network == null or _vehicles == null or not enable_traffic:
		return
	_focus = position
	var outer := maxf(traffic_despawn_radius, traffic_spawn_radius + 30.0)
	for car in _cars.duplicate():
		var distance := Vector2(car.position.x - position.x, car.position.z - position.z).length()
		if car._idle_seconds > 4.0 or (distance > outer and (distance > outer + 100.0 or not _visible(car.position))):
			recycle_car(car)
	var candidates: Array[Dictionary] = []
	var weighted_length := 0.0
	for edge_id in _edge_ids:
		var edge: Dictionary = network.edges[edge_id]
		var a: Vector2 = network.nodes[edge.a]
		var b: Vector2 = network.nodes[edge.b]
		var point := Geometry2D.get_closest_point_to_segment(Vector2(position.x, position.z), a, b)
		var distance := point.distance_to(Vector2(position.x, position.z))
		if distance > traffic_spawn_radius:
			continue
		var length := a.distance_to(b)
		if length < MIN_EDGE_MARGIN_M * 2.0:
			continue
		var kind: int = edge.kind
		var weight: float = [1.0, 0.6, 0.2][kind]
		weighted_length += minf(length, traffic_spawn_radius * 2.0) * weight
		candidates.append({"id": edge_id, "score": distance / 100.0 + float(kind) * 0.6})
	_active_roads = candidates.size()
	candidates.sort_custom(func(a, b): return a.score < b.score)
	var target := mini(max_vehicles, maxi(1, roundi(weighted_length * traffic_density / 85.0)))
	var budget := target if immediate else 2
	for candidate in candidates:
		if _cars.size() >= target or budget <= 0:
			break
		var edge_id: int = candidate.id
		var kind: int = network.edges[edge_id].kind
		if kind == RoadNetwork.LOCAL and (_serial + edge_id) % 4 != 0:
			continue
		var on_edge := 0
		for car in _cars:
			if car.get_spawn_edge_id() == edge_id:
				on_edge += 1
		if on_edge >= (1 if max_vehicles <= 8 else (3 if kind == RoadNetwork.MAIN else 2)):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = network.seed_value ^ (edge_id * 65537) ^ (_serial * 131071) ^ RNG_SALT
		var spawn := _pick_spawn(edge_id, _avoidance, rng, position)
		if spawn.is_empty():
			continue
		var car := _take_car(int(spawn.model))
		var car_rng := RandomNumberGenerator.new()
		car_rng.seed = rng.randi()
		var speed := clampf(SPEEDS[kind] * rng.randf_range(0.9, 1.1), min_speed_kmh / 3.6, max_speed_kmh / 3.6)
		car.setup(network, _adjacency, edge_id, int(spawn.from), float(spawn.offset), speed, car_rng, COLORS[rng.randi_range(0, COLORS.size()-1)], int(spawn.model))
		car.speed_mps = 0.0
		car.set_simulation_enabled(false)
		_vehicles.add_child(car)
		_cars.append(car)
		_serial += 1
		_spawned += 1
		budget -= 1

func _pick_spawn(edge_id: int, avoidance: Array[Vector3], rng: RandomNumberGenerator, focus: Vector3) -> Dictionary:
	var edge: Dictionary = network.edges[edge_id]
	for attempt in SPAWN_ATTEMPTS:
		var from_node := int(edge.a) if rng.randf() < 0.5 else int(edge.b)
		var lane := TrafficRoute.edge_lane(network, edge_id, from_node)
		if lane.is_empty() or lane.length <= MIN_EDGE_MARGIN_M * 2.0:
			continue
		var offset := rng.randf_range(MIN_EDGE_MARGIN_M, lane.length - MIN_EDGE_MARGIN_M)
		var position: Vector3 = lane.start + Vector3(lane.direction.x, 0, lane.direction.y) * offset
		var distance := Vector2(position.x - focus.x, position.z - focus.z).length()
		if distance > traffic_spawn_radius or distance < 48.0 or _visible(position):
			continue
		if not _has_clearance(position, avoidance):
			continue
		var clear := true
		for car in _cars:
			if car.position.distance_to(position) < min_vehicle_spacing:
				clear = false
				break
		if clear:
			return {"from": from_node, "offset": offset, "model": rng.randi_range(0, TrafficCar.Catalog.MODELS.size()-1)}
	return {}

func _visible(position: Vector3) -> bool:
	return is_instance_valid(_camera) and _camera.is_inside_tree() and _camera.is_position_in_frustum(position + Vector3.UP)

func _has_clearance(position: Vector3, avoidance: Array[Vector3]) -> bool:
	for other in avoidance:
		if Vector2(position.x, position.z).distance_to(Vector2(other.x, other.z)) < MIN_SPAWN_CLEARANCE_M:
			return false
	return true

func _take_car(model_index: int) -> TrafficCar:
	for car in _pool:
		if car.model_index == model_index:
			_pool.erase(car)
			return car
	var car := TrafficCar.new()
	car.name = "Vehicle%d" % _serial
	car.player_entered.connect(_on_car_player_entered.bind(car))
	return car

func recycle_car(car: TrafficCar) -> void:
	if not _cars.has(car):
		return
	_cars.erase(car)
	_vehicles.remove_child(car)
	car.set_simulation_enabled(false)
	if _pool.size() < max_vehicles:
		_pool.append(car)
	else:
		car.free()
	_recycled += 1

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

func _on_car_player_entered(body: Node3D, car: TrafficCar) -> void:
	if body is PhysicsBody3D and body.collision_layer & CollisionLayers.PLAYER != 0:
		player_hit.emit(car, body.global_position)

func _clear_vehicles() -> void:
	_cars.clear()
	for car in _pool:
		car.free()
	_pool.clear()
	if is_instance_valid(_vehicles):
		_vehicles.free()
	_vehicles = null
	_serial = 0
	_spawned = 0
	_recycled = 0

func _exit_tree() -> void:
	# Pooled cars are detached nodes, so the normal child cleanup cannot release them.
	for car in _pool:
		car.free()
	_pool.clear()
