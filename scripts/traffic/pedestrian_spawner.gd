extends Node3D
class_name PedestrianSpawner

## 行人管理器：按城市种子在玩家附近的人行道上确定性生成行人，
## 远离后回收；行人自己沿人行道行走，到路口按概率横穿。
## 由 TrafficSpawner 在代码里创建，车辆逻辑不受影响。

const PED_RNG_SALT := 0x51D3A7
const DENSITY_M_PER_PEDESTRIAN := 120.0
const PED_END_MARGIN := 2.0
const MIN_USABLE_SIDEWALK_M := 12.0
const MIN_PLAYER_DISTANCE_M := 24.0
const MIN_AVOIDANCE_DISTANCE_M := 12.0
const PEDESTRIAN_SPACING_M := 6.0
const SPAWN_ATTEMPTS := 8
const VISIBLE_SPAWN_MIN_DISTANCE_M := 80.0
const DESPAWN_GRACE_M := 80.0
const MAX_PEDESTRIANS_PER_EDGE := [3, 2, 2]

@export var enable_pedestrians := true
@export_range(0, 100) var max_pedestrians := 24
@export_range(50.0, 1000.0) var spawn_radius := 220.0
@export_range(100.0, 1400.0) var despawn_radius := 320.0
@export_range(0.1, 2.0) var update_interval := 0.75
@export_range(0.5, 4.0) var walk_speed_mps := 1.4
@export_range(0.0, 1.0) var crossing_chance := 0.35

var network: RoadNetwork = null
var _pedestrians: Array[Pedestrian] = []
var _container: Node3D = null
var _adjacency: Array = []
var _avoidance: Array[Vector3] = []
var _player: Node3D = null
var _camera: Camera3D = null
var _focus := Vector3.ZERO
var _clock := 0.0
var _serial := 0
var _spawned := 0
var _recycled := 0


func build(
	source_network: RoadNetwork,
	adjacency: Array = [],
	source_city: CityContent = null,
	avoidance: Array = []
) -> void:
	_clear()
	network = source_network
	if (
		network == null
		or network.edges.is_empty()
		or max_pedestrians <= 0
		or not enable_pedestrians
	):
		return
	_adjacency = adjacency if not adjacency.is_empty() else TrafficRoute.build_adjacency(network)
	_avoidance.clear()
	if avoidance.is_empty():
		_avoidance = _collect_avoidance(source_city)
	else:
		for point in avoidance:
			_avoidance.append(point)
	_container = Node3D.new()
	_container.name = "Agents"
	add_child(_container)
	_focus = (
		source_city.player_start.position
		if source_city != null and source_city.player_start != null
		else Vector3.ZERO
	)
	if is_instance_valid(_player):
		_focus = _player.global_position
	update_pedestrians(_focus, true)


func set_player(player: Node3D) -> void:
	_player = player
	_camera = player.get_node_or_null("Camera3D") if player != null else null
	if player != null and network != null and _container != null:
		update_pedestrians(player.global_position, true)


func set_simulation_enabled(enabled: bool) -> void:
	set_physics_process(enabled)


func _physics_process(delta: float) -> void:
	if network == null or _container == null or not enable_pedestrians:
		return
	if is_instance_valid(_player):
		_focus = _player.global_position
	for pedestrian in _pedestrians:
		pedestrian.advance(pedestrian.speed_mps * delta)
	_clock += delta
	if _clock >= update_interval:
		_clock = 0.0
		update_pedestrians(_focus)


func update_pedestrians(position: Vector3, immediate := false) -> void:
	if network == null or _container == null:
		return
	_focus = position
	_recycle_distant(position)
	var scan := _scan_candidates(position)
	var candidates: Array = scan["candidates"]
	var target := mini(
		max_pedestrians,
		maxi(1, roundi(float(scan["weighted"]) / DENSITY_M_PER_PEDESTRIAN))
	)
	var budget := target if immediate else 2
	for candidate in candidates:
		if _pedestrians.size() >= target or budget <= 0:
			break
		var edge_id: int = int(candidate["id"])
		var kind := int(network.edges[edge_id].kind)
		if _count_on_edge(edge_id) >= int(MAX_PEDESTRIANS_PER_EDGE[kind]):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = network.seed_value ^ (edge_id * 65537) ^ (_serial * 131071) ^ PED_RNG_SALT
		var spawn := _pick_spawn(edge_id, rng, position)
		if spawn.is_empty():
			continue
		var pedestrian := Pedestrian.new()
		pedestrian.name = "Pedestrian%d" % _serial
		var ped_rng := RandomNumberGenerator.new()
		ped_rng.seed = rng.randi()
		pedestrian.setup(
			network,
			_adjacency,
			edge_id,
			int(spawn["from"]),
			float(spawn["offset"]),
			int(spawn["side"]),
			float(spawn["band_ratio"]),
			walk_speed_mps * rng.randf_range(0.9, 1.1),
			ped_rng,
			int(spawn["appearance"]),
			crossing_chance
		)
		_container.add_child(pedestrian)
		_pedestrians.append(pedestrian)
		_serial += 1
		_spawned += 1
		budget -= 1


func get_pedestrian_count() -> int:
	return _pedestrians.size()


func get_pedestrians() -> Array[Pedestrian]:
	return _pedestrians


func get_recycled_count() -> int:
	return _recycled


func get_spawned_count() -> int:
	return _spawned


func recycle_pedestrian(pedestrian: Pedestrian) -> void:
	if not _pedestrians.has(pedestrian):
		return
	_pedestrians.erase(pedestrian)
	if is_instance_valid(_container):
		_container.remove_child(pedestrian)
	pedestrian.free()
	_recycled += 1


func _recycle_distant(position: Vector3) -> void:
	var outer := maxf(despawn_radius, spawn_radius + 30.0)
	for pedestrian in _pedestrians.duplicate():
		var distance := Vector2(
			pedestrian.position.x - position.x,
			pedestrian.position.z - position.z
		).length()
		if (
			distance > outer
			and (distance > outer + DESPAWN_GRACE_M or not _visible(pedestrian.position))
		):
			recycle_pedestrian(pedestrian)


func _scan_candidates(position: Vector3) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var weighted := 0.0
	var focus_xz := Vector2(position.x, position.z)
	for edge_id in network.edges.size():
		var edge: Dictionary = network.edges[edge_id]
		var a: Vector2 = network.nodes[int(edge.a)]
		var b: Vector2 = network.nodes[int(edge.b)]
		var closest := Geometry2D.get_closest_point_to_segment(focus_xz, a, b)
		var distance := closest.distance_to(focus_xz)
		if distance > spawn_radius:
			continue
		var start_margin := Pedestrian.junction_half_width(network, int(edge.a))
		var end_margin := Pedestrian.junction_half_width(network, int(edge.b))
		var usable := a.distance_to(b) - start_margin - end_margin
		if usable < MIN_USABLE_SIDEWALK_M:
			continue
		var kind := int(edge.kind)
		var weight: float = [1.0, 0.7, 0.35][kind]
		weighted += minf(usable, spawn_radius * 2.0) * weight
		candidates.append({"id": edge_id, "score": distance / 100.0 + float(kind) * 0.6})
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_score := float(first["score"])
		var second_score := float(second["score"])
		if not is_equal_approx(first_score, second_score):
			return first_score < second_score
		return int(first["id"]) < int(second["id"])
	)
	return {"candidates": candidates, "weighted": weighted}


func _pick_spawn(
	edge_id: int, rng: RandomNumberGenerator, focus: Vector3
) -> Dictionary:
	var edge: Dictionary = network.edges[edge_id]
	var redline := float(network.widths[int(edge.kind)])
	for _attempt in SPAWN_ATTEMPTS:
		var from_node := int(edge.a) if rng.randf() < 0.5 else int(edge.b)
		var side := 1 if rng.randf() < 0.5 else -1
		var band_ratio := rng.randf_range(0.35, 0.65)
		var lateral := Pedestrian.lateral_for_band(redline, band_ratio)
		var lane := Pedestrian.sidewalk_lane(network, edge_id, from_node, side, lateral)
		if lane.is_empty() or float(lane.length) <= PED_END_MARGIN * 2.0:
			continue
		var offset := rng.randf_range(PED_END_MARGIN, float(lane.length) - PED_END_MARGIN)
		var direction: Vector2 = lane.direction
		var start: Vector3 = lane.start
		var spawn_position := start + Vector3(direction.x, 0.0, direction.y) * offset
		var distance := Vector2(
			spawn_position.x - focus.x, spawn_position.z - focus.z
		).length()
		if distance > spawn_radius or distance < MIN_PLAYER_DISTANCE_M:
			continue
		if _visible(spawn_position) and distance < VISIBLE_SPAWN_MIN_DISTANCE_M:
			continue
		if not _clear_of_avoidance(spawn_position):
			continue
		if not _clear_of_pedestrians(spawn_position):
			continue
		return {
			"from": from_node,
			"offset": offset,
			"side": side,
			"band_ratio": band_ratio,
			"appearance": rng.randi_range(0, Pedestrian.COLORS.size() - 1),
		}
	return {}


func _count_on_edge(edge_id: int) -> int:
	var count := 0
	for pedestrian in _pedestrians:
		if pedestrian.get_current_edge_id() == edge_id:
			count += 1
	return count


func _clear_of_avoidance(position: Vector3) -> bool:
	for point in _avoidance:
		if (
			Vector2(position.x, position.z).distance_to(Vector2(point.x, point.z))
			< MIN_AVOIDANCE_DISTANCE_M
		):
			return false
	return true


func _clear_of_pedestrians(position: Vector3) -> bool:
	for pedestrian in _pedestrians:
		if pedestrian.position.distance_to(position) < PEDESTRIAN_SPACING_M:
			return false
	return true


func _visible(position: Vector3) -> bool:
	return (
		is_instance_valid(_camera)
		and _camera.is_inside_tree()
		and _camera.is_position_in_frustum(position + Vector3.UP)
	)


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


func _clear() -> void:
	_pedestrians.clear()
	if is_instance_valid(_container):
		_container.free()
	_container = null
	_serial = 0
	_spawned = 0
	_recycled = 0
	_clock = 0.0
