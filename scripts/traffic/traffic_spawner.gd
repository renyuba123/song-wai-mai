extends Node3D
class_name TrafficSpawner
## The original RoadNetwork/TrafficRoute car system, active only around the player.
signal traffic_ready
signal player_hit(car: TrafficCar, player_position: Vector3)
const RNG_SALT := 0x7A4FF1C
const MIN_EDGE_MARGIN_M := 20.0
const MIN_SPAWN_CLEARANCE_M := 15.0
const SPAWN_ATTEMPTS := 12
const NEARBY_PLACEMENT_STEP_M := 8.0
const MIN_NEARBY_VEHICLES := 4
const NEARBY_VEHICLE_TARGET := MIN_NEARBY_VEHICLES + 2
const NEARBY_VEHICLE_RADIUS_M := 120.0
const NEARBY_VEHICLE_MIN_DISTANCE_M := 22.0
const REGULAR_SPAWN_BUDGET := 6
const EDGE_CAPACITY_MAIN := 9
const EDGE_CAPACITY_SECONDARY := 7
const EDGE_CAPACITY_LOCAL := 4
const SPEEDS := [18.0, 13.5, 10.5]
const COLORS := [Color("c94f4f"), Color("3f7fbf"), Color("e0c15a"), Color("e8e8e8"), Color("555e66")]
const HORN_STREAM := preload("res://assets/audio/traffic_horn.ogg")
const HORN_COOLDOWN_MIN_S := 3.0
const HORN_COOLDOWN_MAX_S := 5.0
const HORN_PROBE_INTERVAL_S := 0.45
const HORN_TRIGGER_CHANCE := 0.42
const HORN_ACTIVE_GUARD_S := 1.4
const HORN_WRONG_WAY_RADIUS_M := 24.0
const HORN_RED_LIGHT_RADIUS_M := 26.0
const HORN_NEAR_MISS_MIN_M := 4.5
const HORN_NEAR_MISS_MAX_M := 14.0
const HORN_NEAR_MISS_MAX_LATERAL_M := 3.2
@export var enable_traffic := true
@export_range(0.1, 3.0) var traffic_density := 3.0
@export_range(1, 160) var max_vehicles := 120
@export_range(0, 100) var max_pedestrians := 24
@export_range(50.0, 1000.0) var traffic_spawn_radius := 320.0
@export_range(100.0, 1400.0) var traffic_despawn_radius := 420.0
@export_range(0.1, 2.0) var traffic_update_interval := 0.25
@export_range(5.0, 80.0) var min_vehicle_spacing := 18.0
@export_range(0.0, 100.0) var min_speed_kmh := 25.0
@export_range(1.0, 120.0) var max_speed_kmh := 72.0
@export_range(0.1, 10.0) var acceleration_mps2 := 3.2
@export_range(0.1, 20.0) var braking_mps2 := 7.0
@export var show_traffic_debug := false
var network: RoadNetwork = null
var _cars: Array[TrafficCar] = []
var _pool: Array[TrafficCar] = []
var _vehicles: Node3D = null
var _pedestrians: PedestrianSpawner = null
var _signals: TrafficSignals = null
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
var _horn_player: AudioStreamPlayer3D = null
var _horn_cooldown := 0.0
var _horn_active_seconds := 0.0
var _horn_probe_clock := 0.0
var _horn_count := 0
var _horn_last_reason := &""
var _horn_rng := RandomNumberGenerator.new()

func set_player(player: Node3D) -> void:
	_player = player
	_camera = player.get_node_or_null("Camera3D") if player != null else null
	if is_instance_valid(_pedestrians):
		_pedestrians.set_player(player)
	if is_instance_valid(_signals):
		_signals.set_player(player)
	if player != null and network != null:
		update_traffic(player.global_position, true)

func build(source_network: RoadNetwork, source_city: CityContent = null) -> void:
	_clear_vehicles()
	_clear_pedestrians()
	_clear_signals()
	network = source_network
	if network == null or network.edges.is_empty() or not enable_traffic:
		traffic_ready.emit()
		return
	_adjacency = TrafficRoute.build_adjacency(network)
	_edge_ids.clear()
	for edge_id in network.edges.size():
		_edge_ids.append(edge_id)
	_avoidance = _collect_avoidance(source_city)
	_focus = source_city.player_start.position if source_city != null and source_city.player_start != null else Vector3.ZERO
	if is_instance_valid(_player):
		_focus = _player.global_position

	_signals = TrafficSignals.new()
	_signals.name = "Signals"
	add_child(_signals)
	_signals.build(network)
	_ensure_horn_player()
	_horn_rng.seed = network.seed_value ^ RNG_SALT ^ 0x48B0A2D
	if is_instance_valid(_player):
		_signals.set_player(_player)

	if max_vehicles <= 0:
		traffic_ready.emit()
		return

	_vehicles = Node3D.new()
	_vehicles.name = "Vehicles"
	add_child(_vehicles)
	update_traffic(_focus, true)
	if max_pedestrians > 0:
		_pedestrians = PedestrianSpawner.new()
		_pedestrians.name = "Pedestrians"
		_pedestrians.max_pedestrians = max_pedestrians
		_pedestrians.spawn_radius = traffic_spawn_radius
		_pedestrians.despawn_radius = traffic_despawn_radius
		_pedestrians.set_traffic_signals(_signals)
		add_child(_pedestrians)
		_pedestrians.build(network, _adjacency, source_city, _avoidance)
		if is_instance_valid(_player):
			_pedestrians.set_player(_player)
	traffic_ready.emit()

func get_vehicle_count() -> int:
	return _cars.size()
func get_cars() -> Array[TrafficCar]:
	return _cars
func get_nearby_vehicle_count(
	center: Vector3,
	radius := NEARBY_VEHICLE_RADIUS_M
) -> int:
	return _count_nearby_vehicles(center, radius)
func get_edge_capacity(kind: int) -> int:
	return _edge_capacity(kind)
func get_active_road_count() -> int:
	return _active_roads
func get_recycled_count() -> int:
	return _recycled
func get_pool_count() -> int:
	return _pool.size()
func get_pedestrian_spawner() -> PedestrianSpawner:
	return _pedestrians
func get_traffic_signals() -> TrafficSignals:
	return _signals
func get_pedestrian_count() -> int:
	return _pedestrians.get_pedestrian_count() if is_instance_valid(_pedestrians) else 0
func get_pedestrians() -> Array[Pedestrian]:
	if is_instance_valid(_pedestrians):
		return _pedestrians.get_pedestrians()
	var empty: Array[Pedestrian] = []
	return empty
func get_horn_count() -> int:
	return _horn_count
func is_horn_playing() -> bool:
	return (
		_horn_active_seconds > 0.0
		or (
			is_instance_valid(_horn_player)
			and _horn_player.is_playing()
		)
	)
func get_last_horn_reason() -> StringName:
	return _horn_last_reason
func get_horn_player() -> AudioStreamPlayer3D:
	return _horn_player
func detect_horn_reason() -> StringName:
	var event := _detect_horn_event()
	return StringName(event.get("reason", &""))

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
		# Signalized junctions use the shared phase; the old nearest-approach
		# fairness rule remains only at junctions without a signal.
		var junction := car.get_next_junction()
		var signalized := false
		if is_instance_valid(_signals) and junction.is_finite():
			var signal_node := _signals.find_signal_node(
				junction,
				TrafficSignals.VEHICLE_APPROACH_DISTANCE_M
			)
			if signal_node >= 0:
				signalized = true
				var forward_3d := Vector3(forward.x, 0.0, forward.y)
				# A car beyond the junction center must clear the box even if
				# the light changes, so it never stops across traffic lanes.
				var already_inside := (
					(car.position - junction).dot(forward_3d) > -0.35
				)
				if _signals.should_vehicle_stop(
					signal_node,
					forward,
					car.position.distance_to(junction),
					already_inside
				):
					target = 0.0
		if (
			not signalized
			and junction.is_finite()
			and car.position.distance_to(junction) < 25.0
		):
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
	_update_horn(delta)
	_update_clock += delta
	_debug_clock += delta
	if _update_clock >= traffic_update_interval:
		_update_clock = 0.0
		update_traffic(_focus)
	if show_traffic_debug and _debug_clock >= 2.0:
		_debug_clock = 0.0
		print(
			"交通：active=", _cars.size(),
			" roads=", _active_roads,
			" signals=", _signals.get_visible_signal_count() if is_instance_valid(_signals) else 0,
			" spawned=", _spawned,
			" recycled=", _recycled,
			" pool=", _pool.size()
		)

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
		candidates.append({
			"id": edge_id,
			"distance": distance,
			"score": distance / 100.0 + float(kind) * 0.6,
		})
	_active_roads = candidates.size()
	candidates.sort_custom(func(a, b): return a.score < b.score)
	var target := mini(max_vehicles, maxi(1, roundi(weighted_length * traffic_density / 85.0)))
	var budget := target if immediate else REGULAR_SPAWN_BUDGET
	for candidate in candidates:
		if _cars.size() >= target or budget <= 0:
			break
		var edge_id: int = candidate.id
		var kind: int = network.edges[edge_id].kind
		if kind == RoadNetwork.LOCAL and (_serial + edge_id) % 4 != 0:
			continue
		if _try_spawn_vehicle(edge_id, position, false, false, false):
			budget -= 1
	_ensure_nearby_vehicles(position, candidates)

func _ensure_nearby_vehicles(position: Vector3, candidates: Array[Dictionary]) -> void:
	# Keep two spare cars beyond the four-car hard floor so movement between
	# update ticks does not briefly leave the player under the configured floor.
	var missing := NEARBY_VEHICLE_TARGET - _count_nearby_vehicles(position)
	if missing <= 0:
		return
	var nearby_candidates := candidates.duplicate()
	nearby_candidates.sort_custom(func(a, b): return a.distance < b.distance)
	# Prefer off-screen placements; the in-view fallback preserves the floor in
	# tight road layouts while still keeping every car beyond the minimum gap.
	var occupied_edges := {}
	for car in _cars:
		occupied_edges[car.get_spawn_edge_id()] = true
	# A long edge can carry more than one nearby car. Repeat the candidate scan
	# so isolated road sections still reach the floor instead of stopping at one
	# car per edge.
	for pass_index in 5:
		var reject_occupied := pass_index == 0
		var allow_visible := pass_index >= 2
		for candidate in nearby_candidates:
			if missing <= 0:
				return
			if float(candidate.distance) > NEARBY_VEHICLE_RADIUS_M:
				break
			var edge_id := int(candidate.id)
			if reject_occupied and occupied_edges.has(edge_id):
				continue
			if _try_spawn_vehicle(edge_id, position, true, allow_visible, true):
				occupied_edges[edge_id] = true
				missing -= 1

func _make_room_for_nearby_vehicle(position: Vector3) -> bool:
	if _cars.size() < max_vehicles:
		return true
	var farthest: TrafficCar = null
	var farthest_distance := NEARBY_VEHICLE_RADIUS_M * NEARBY_VEHICLE_RADIUS_M
	for car in _cars:
		var delta := Vector2(car.position.x - position.x, car.position.z - position.z)
		var distance_squared := delta.length_squared()
		if distance_squared > farthest_distance:
			farthest = car
			farthest_distance = distance_squared
	if farthest == null:
		return false
	recycle_car(farthest)
	return true

func _try_spawn_vehicle(
	edge_id: int,
	focus: Vector3,
	nearby_only: bool,
	allow_visible: bool,
	ignore_capacity: bool
) -> bool:
	var kind: int = network.edges[edge_id].kind
	if not ignore_capacity:
		var on_edge := 0
		for car in _cars:
			if car.get_spawn_edge_id() == edge_id:
				on_edge += 1
		if on_edge >= _edge_capacity(kind):
			return false
	var rng := RandomNumberGenerator.new()
	rng.seed = network.seed_value ^ (edge_id * 65537) ^ (_serial * 131071) ^ RNG_SALT
	var spawn := _pick_spawn(edge_id, _avoidance, rng, focus, nearby_only, allow_visible)
	if spawn.is_empty():
		return false
	if _cars.size() >= max_vehicles:
		if not nearby_only or not _make_room_for_nearby_vehicle(focus):
			return false
	var car := _take_car(int(spawn.model))
	var car_rng := RandomNumberGenerator.new()
	car_rng.seed = rng.randi()
	var speed := clampf(
		SPEEDS[kind] * rng.randf_range(0.9, 1.1),
		min_speed_kmh / 3.6,
		max_speed_kmh / 3.6
	)
	car.setup(
		network,
		_adjacency,
		edge_id,
		int(spawn.from),
		float(spawn.offset),
		speed,
		car_rng,
		COLORS[rng.randi_range(0, COLORS.size() - 1)],
		int(spawn.model)
	)
	car.speed_mps = 0.0
	car.set_simulation_enabled(false)
	_vehicles.add_child(car)
	_cars.append(car)
	_serial += 1
	_spawned += 1
	return true

func _edge_capacity(kind: int) -> int:
	if kind == RoadNetwork.MAIN:
		return EDGE_CAPACITY_MAIN
	if kind == RoadNetwork.SECONDARY:
		return EDGE_CAPACITY_SECONDARY
	return EDGE_CAPACITY_LOCAL

func _count_nearby_vehicles(center: Vector3, radius := NEARBY_VEHICLE_RADIUS_M) -> int:
	var count := 0
	var radius_squared := radius * radius
	for car in _cars:
		var delta := Vector2(car.position.x - center.x, car.position.z - center.z)
		if delta.length_squared() <= radius_squared:
			count += 1
	return count

func _pick_spawn(
	edge_id: int,
	avoidance: Array[Vector3],
	rng: RandomNumberGenerator,
	focus: Vector3,
	nearby_only := false,
	allow_visible := false
) -> Dictionary:
	if nearby_only:
		return _pick_nearby_spawn(edge_id, avoidance, rng, focus, allow_visible)
	var edge: Dictionary = network.edges[edge_id]
	for attempt in SPAWN_ATTEMPTS:
		var from_node := int(edge.a) if rng.randf() < 0.5 else int(edge.b)
		var lane := TrafficRoute.edge_lane(network, edge_id, from_node)
		if lane.is_empty() or lane.length <= MIN_EDGE_MARGIN_M * 2.0:
			continue
		var offset := rng.randf_range(MIN_EDGE_MARGIN_M, lane.length - MIN_EDGE_MARGIN_M)
		var position: Vector3 = lane.start + Vector3(lane.direction.x, 0, lane.direction.y) * offset
		var distance := Vector2(position.x - focus.x, position.z - focus.z).length()
		if distance > traffic_spawn_radius or distance < 48.0:
			continue
		if not _spawn_position_is_clear(position, avoidance):
			continue
		return {"from": from_node, "offset": offset, "model": rng.randi_range(0, TrafficCar.Catalog.MODELS.size()-1)}
	return {}

func _pick_nearby_spawn(
	edge_id: int,
	avoidance: Array[Vector3],
	rng: RandomNumberGenerator,
	focus: Vector3,
	allow_visible: bool
) -> Dictionary:
	var edge: Dictionary = network.edges[edge_id]
	var from_nodes: Array[int] = [int(edge.a), int(edge.b)]
	if rng.randf() < 0.5:
		from_nodes.reverse()
	var candidates: Array[Dictionary] = []
	var max_distance := minf(traffic_spawn_radius, NEARBY_VEHICLE_RADIUS_M)
	for from_node in from_nodes:
		var lane := TrafficRoute.edge_lane(network, edge_id, from_node)
		if lane.is_empty() or lane.length <= MIN_EDGE_MARGIN_M * 2.0:
			continue
		for interval in _nearby_lane_offset_intervals(
			lane,
			focus,
			NEARBY_VEHICLE_MIN_DISTANCE_M,
			max_distance
		):
			var span := interval.y - interval.x
			var steps := maxi(1, ceili(span / NEARBY_PLACEMENT_STEP_M))
			for index in steps + 1:
				var offset := lerpf(interval.x, interval.y, float(index) / float(steps))
				var position: Vector3 = (
					lane.start
					+ Vector3(lane.direction.x, 0, lane.direction.y) * offset
				)
				var distance := Vector2(
					position.x - focus.x,
					position.z - focus.z
				).length()
				candidates.append({
					"from": from_node,
					"offset": offset,
					"position": position,
					"distance": distance,
					"model": rng.randi_range(0, TrafficCar.Catalog.MODELS.size() - 1),
				})
	candidates.sort_custom(func(a, b): return a.distance < b.distance)
	for candidate in candidates:
		var position: Vector3 = candidate.position
		if not allow_visible and _visible(position):
			continue
		if _spawn_position_is_clear(position, avoidance):
			return candidate
	return {}

func _spawn_position_is_clear(position: Vector3, avoidance: Array[Vector3]) -> bool:
	if not _has_clearance(position, avoidance):
		return false
	for car in _cars:
		if car.position.distance_to(position) < min_vehicle_spacing:
			return false
	return true

func _nearby_lane_offset_intervals(
	lane: Dictionary,
	focus: Vector3,
	min_distance: float,
	max_distance: float
) -> Array[Vector2]:
	var start := Vector2(lane.start.x, lane.start.z)
	var direction: Vector2 = lane.direction
	var delta := Vector2(focus.x, focus.z) - start
	var perpendicular := absf(delta.cross(direction))
	if perpendicular > max_distance:
		return []
	var projection := delta.dot(direction)
	var outer := sqrt(maxf(max_distance * max_distance - perpendicular * perpendicular, 0.0))
	var inner := 0.0
	if min_distance > perpendicular:
		inner = sqrt(maxf(min_distance * min_distance - perpendicular * perpendicular, 0.0))
	var intervals: Array[Vector2] = []
	var total_weight := 0.0
	for bounds in [
		Vector2(projection - outer, projection - inner),
		Vector2(projection + inner, projection + outer),
	]:
		var low := maxf(float(bounds.x), MIN_EDGE_MARGIN_M)
		var high := minf(float(bounds.y), float(lane.length) - MIN_EDGE_MARGIN_M)
		if high < low:
			continue
		intervals.append(Vector2(low, high))
	return intervals

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


func _ensure_horn_player() -> void:
	if is_instance_valid(_horn_player):
		return
	_horn_player = AudioStreamPlayer3D.new()
	_horn_player.name = "TrafficHorn"
	_horn_player.stream = HORN_STREAM
	_horn_player.volume_db = -3.0
	_horn_player.unit_size = 16.0
	_horn_player.max_distance = 100.0
	add_child(_horn_player)


func _update_horn(delta: float) -> void:
	_horn_cooldown = maxf(_horn_cooldown - delta, 0.0)
	_horn_active_seconds = maxf(_horn_active_seconds - delta, 0.0)
	if _horn_cooldown > 0.0 or is_horn_playing():
		return
	_horn_probe_clock += delta
	if _horn_probe_clock < HORN_PROBE_INTERVAL_S:
		return
	_horn_probe_clock = 0.0
	var event := _detect_horn_event()
	if event.is_empty():
		return
	if _horn_rng.randf() > HORN_TRIGGER_CHANCE:
		return
	_play_horn(
		StringName(event.get("reason", &"")),
		event.get("position", _player.global_position)
	)


func _detect_horn_event() -> Dictionary:
	if (
		not is_instance_valid(_player)
		or not _player.is_inside_tree()
		or not is_instance_valid(_signals)
		or network == null
	):
		return {}
	var player := _player as PlayerController
	if player == null or not player.controls_enabled:
		return {}
	var player_velocity := player.get_planar_velocity()
	var player_speed := player_velocity.length()
	if player_speed < 3.0:
		return {}
	var player_direction := player_velocity / player_speed

	var wrong_way := _find_wrong_way_horn(player_direction)
	if not wrong_way.is_empty():
		return wrong_way

	var red_light := _find_red_light_horn(player_direction)
	if not red_light.is_empty():
		return red_light

	var near_miss := _find_near_miss_horn(player_direction, player_speed)
	if not near_miss.is_empty():
		return near_miss
	return {}


func _find_wrong_way_horn(player_direction: Vector2) -> Dictionary:
	var closest_car: TrafficCar = null
	var closest_distance := HORN_WRONG_WAY_RADIUS_M
	for car in _cars:
		if car.speed_mps < 0.5:
			continue
		var delta := Vector2(
			car.position.x - _player.global_position.x,
			car.position.z - _player.global_position.z
		)
		var distance := delta.length()
		if distance > closest_distance:
			continue
		if car.get_forward().dot(player_direction) > -0.65:
			continue
		closest_car = car
		closest_distance = distance
	if closest_car == null:
		return {}
	return {
		"reason": &"wrong_way",
		"position": closest_car.global_position,
	}


func _find_red_light_horn(player_direction: Vector2) -> Dictionary:
	var signal_node := _signals.find_signal_node(
		_player.global_position,
		HORN_RED_LIGHT_RADIUS_M
	)
	if signal_node < 0:
		return {}
	if (
		_signals.get_vehicle_state(signal_node, player_direction)
		!= TrafficSignals.VehicleState.RED
	):
		return {}
	var sound_position := _signals.get_junction_position(signal_node)
	var closest_car: TrafficCar = null
	var closest_distance := 55.0
	for car in _cars:
		var distance := car.global_position.distance_to(sound_position)
		if distance < closest_distance:
			closest_car = car
			closest_distance = distance
	if closest_car != null:
		sound_position = closest_car.global_position
	return {
		"reason": &"red_light",
		"position": sound_position,
	}


func _find_near_miss_horn(player_direction: Vector2, player_speed: float) -> Dictionary:
	var closest_car: TrafficCar = null
	var closest_distance := INF
	for car in _cars:
		if car.speed_mps < 2.0 or player_speed < car.speed_mps + 2.5:
			continue
		var forward := car.get_forward()
		if forward.dot(player_direction) < 0.25:
			continue
		var delta := Vector2(
			car.position.x - _player.global_position.x,
			car.position.z - _player.global_position.z
		)
		var distance := delta.length()
		if distance < HORN_NEAR_MISS_MIN_M or distance > HORN_NEAR_MISS_MAX_M:
			continue
		var lateral := absf(delta.cross(forward))
		if lateral > HORN_NEAR_MISS_MAX_LATERAL_M:
			continue
		if distance < closest_distance:
			closest_car = car
			closest_distance = distance
	if closest_car == null:
		return {}
	return {
		"reason": &"near_miss",
		"position": closest_car.global_position,
	}


func _play_horn(reason: StringName, sound_position: Vector3) -> bool:
	if _horn_cooldown > 0.0 or is_horn_playing():
		return false
	_ensure_horn_player()
	if not is_instance_valid(_horn_player):
		return false
	if _horn_player.is_inside_tree():
		_horn_player.global_position = sound_position
	else:
		_horn_player.position = sound_position
	if _horn_player.is_inside_tree():
		_horn_player.play()
	_horn_count += 1
	_horn_last_reason = reason
	_horn_active_seconds = HORN_ACTIVE_GUARD_S
	_horn_cooldown = _horn_rng.randf_range(
		HORN_COOLDOWN_MIN_S,
		HORN_COOLDOWN_MAX_S
	)
	_horn_probe_clock = 0.0
	return true


func _reset_horn_state() -> void:
	if is_instance_valid(_horn_player):
		_horn_player.stop()
	_horn_cooldown = 0.0
	_horn_active_seconds = 0.0
	_horn_probe_clock = 0.0
	_horn_count = 0
	_horn_last_reason = &""


func _clear_vehicles() -> void:
	_reset_horn_state()
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

func _clear_pedestrians() -> void:
	if is_instance_valid(_pedestrians):
		_pedestrians.free()
	_pedestrians = null


func _clear_signals() -> void:
	if is_instance_valid(_signals):
		_signals.free()
	_signals = null


func _exit_tree() -> void:
	# Pooled cars are detached nodes, so the normal child cleanup cannot release them.
	for car in _pool:
		car.free()
	_pool.clear()
	_clear_signals()
