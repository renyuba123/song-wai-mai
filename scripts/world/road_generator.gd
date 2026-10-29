extends RefCounted
class_name RoadGenerator

## Hierarchy-first deterministic growth, transactional intersections, spatial grid.
const MAIN := RoadNetwork.MAIN
const SECONDARY := RoadNetwork.SECONDARY
const LOCAL := RoadNetwork.LOCAL
const MIN_JUNCTION_SPACING := RoadNetwork.MIN_JUNCTION_SPACING
const STEP_SIZE := 220.0
const HASH_SIZE := 300.0
const SNAP_DISTANCE := 165.0
const CLEARANCE := 55.0
const MAX_FRONTS := 2048
const OCTAVES := 4
const ROUGHNESS := 0.55
const LACUNARITY := 2.3731
const TURN_SCALE := 1100.0
const TURN_FREQUENCY := 0.8
const TURN_STRENGTH := [0.0, 0.06, 0.09]
const FIELD_ANGLE := 0.46
const FIELD_BLEND := 0.24
const MAX_TURN := 0.10

class Front:
	var position: Vector2
	var direction: Vector2
	var road_id: int
	var road_kind: int
	var spline_distance := 0.0
	var distance_since_split := 0.0
	var is_growing := true
	var node_id: int
	var target_heading: float

var network: RoadNetwork
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var node_grid := {}
var edge_grid := {}
var adjacency: Array = []
var fronts: Array[Front] = []
var base_heading := 0.0
var phase := 0.0

static func generate(map_size: Vector2, seed_value: int, density: float, widths: Vector3, allow_difficult: bool = false) -> RoadNetwork:
	return RoadGenerator.new()._generate(map_size, seed_value, density, widths, allow_difficult)

func _generate(size: Vector2, seed_value: int, density: float, widths: Vector3, difficult: bool) -> RoadNetwork:
	network = RoadNetwork.new()
	network.map_size = size
	network.seed_value = seed_value
	network.density = density
	network.widths = widths
	network.allow_difficult = difficult
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	base_heading = rng.randf_range(-0.30, 0.30)
	phase = rng.randf_range(-PI, PI)
	# Legacy axis fields remain available but are empty: no global axis grid.
	network.arterial_step = lerpf(460.0, 380.0, clampf(density, 0.0, 1.0))
	if minf(size.x, size.y) < MIN_JUNCTION_SPACING * 4.0:
		return network # Explicit validation failure for unsupported small maps.
	var axis := Vector2.from_angle(base_heading)
	var first := _clip(Vector2.ZERO, -axis * size.length())
	var last := _clip(Vector2.ZERO, axis * size.length())
	var count := maxi(3, floori(first.distance_to(last) / network.arterial_step))
	for index in count + 1:
		_add_node(first.lerp(last, float(index) / count))
		if index > 0:
			_add_edge(index - 1, index, MAIN)
	for index in range(1, count):
		var heading := base_heading + clampf(_field(network.nodes[index]), -0.30, 0.30)
		for side in [-1.0, 1.0]:
			_front(index, Vector2.from_angle(heading + side * PI * 0.5), SECONDARY)
	# Collectors establish join targets first; locals then close blocks.
	var collector_count := fronts.size()
	for index in collector_count:
		_grow(fronts[index])
	var local_count := fronts.size()
	for index in range(collector_count, local_count):
		_grow(fronts[index])
	# Infill perpendicular streets from local interior nodes closes smaller
	# Manhattan cells. Only one infill generation prevents recursive trees.
	var infill_start := fronts.size()
	for node in network.nodes.size():
		if adjacency[node].size() != 2 or rng.randf() > 0.55 + 0.45 * clampf(density, 0.0, 1.0):
			continue
		var edge: Dictionary = network.edges[adjacency[node][0]]
		if edge.kind != LOCAL or network.edges[adjacency[node][1]].kind != LOCAL:
			continue
		var other: int = edge.b if edge.a == node else edge.a
		var direction := (network.nodes[other] - network.nodes[node]).normalized()
		for side in [-1.0, 1.0]:
			_front(node, direction.rotated(side * PI * 0.5), LOCAL)
	var infill_end := fronts.size()
	for index in range(infill_start, infill_end):
		_grow(fronts[index])
	_prune_local_stubs()
	return network

func _front(node: int, direction: Vector2, kind: int) -> void:
	if fronts.size() >= MAX_FRONTS:
		return
	var front := Front.new()
	front.position = network.nodes[node]
	front.node_id = node
	front.direction = direction
	front.target_heading = direction.angle()
	front.road_kind = kind
	front.road_id = fronts.size()
	fronts.append(front)

func _field(point: Vector2) -> float:
	var local := point.rotated(-base_heading)
	return FIELD_ANGLE * sin(local.x / network.map_size.x * TAU + phase) + 0.08 * noise.get_noise_2d(local.x / TURN_SCALE, local.y / TURN_SCALE)

func _fractal(front: Front) -> float:
	var sample := Vector2(front.road_id * 1.2572, front.spline_distance / TURN_SCALE)
	var amplitude := 1.0
	var value := 0.0
	for octave in OCTAVES:
		sample = (sample + Vector2(5.2612, 1.6783)) * LACUNARITY
		value += noise.get_noise_2dv(sample) * amplitude
		amplitude *= pow(ROUGHNESS, LACUNARITY)
	return signf(value) * maxf(0.0, absf(value) - (1.0 - TURN_FREQUENCY))

func _grow(front: Front) -> void:
	var max_length := network.map_size.length() if front.road_kind == SECONDARY else network.arterial_step * 2.5
	while front.is_growing and front.spline_distance < max_length:
		var desired := base_heading + _field(front.position)
		desired += roundf((front.target_heading - desired) / (PI * 0.5)) * PI * 0.5
		var turn := wrapf(desired - front.direction.angle(), -PI, PI) * FIELD_BLEND
		turn += _fractal(front) * TURN_STRENGTH[front.road_kind]
		var direction := front.direction.rotated(clampf(turn, -MAX_TURN, MAX_TURN))
		var proposed := front.position + direction * minf(STEP_SIZE, max_length - front.spline_distance)
		var end := _clip(front.position, proposed)
		var boundary := end.distance_to(proposed) > RoadNetwork.EPS
		var result := _insert(front.node_id, end, front.road_kind)
		if result.is_empty():
			front.is_growing = false
			break
		var node: int = result.node
		var next: Vector2 = network.nodes[node]
		var distance := next.distance_to(front.position)
		front.direction = (next - front.position).normalized()
		front.position = next
		front.node_id = node
		front.spline_distance += distance
		front.distance_since_split += distance
		front.is_growing = not boundary and not result.joined
		if front.road_kind == SECONDARY and front.is_growing and front.distance_since_split >= STEP_SIZE - RoadNetwork.EPS:
			if rng.randf() <= lerpf(0.65, 1.0, clampf(network.density, 0.0, 1.0)):
				for side in [-1.0, 1.0]:
					_front(node, front.direction.rotated(side * PI * 0.5), LOCAL)
				front.distance_since_split = 0.0

func _clip(start: Vector2, end: Vector2) -> Vector2:
	var half := network.map_size * 0.5
	var delta := end - start
	var t := 1.0
	for axis in 2:
		if delta[axis] > 0.0:
			t = minf(t, (half[axis] - start[axis]) / delta[axis])
		elif delta[axis] < 0.0:
			t = minf(t, (-half[axis] - start[axis]) / delta[axis])
	return (start + delta * clampf(t, 0.0, 1.0)).clamp(-half, half)

func _cells(a: Vector2, b: Vector2, margin: float = 0.0) -> Array[Vector2i]:
	var lo := Vector2i(floori((minf(a.x, b.x) - margin) / HASH_SIZE), floori((minf(a.y, b.y) - margin) / HASH_SIZE))
	var hi := Vector2i(floori((maxf(a.x, b.x) + margin) / HASH_SIZE), floori((maxf(a.y, b.y) + margin) / HASH_SIZE))
	var result: Array[Vector2i] = []
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			result.append(Vector2i(x, y))
	return result

func _query(grid: Dictionary, a: Vector2, b: Vector2, margin: float) -> Array:
	var found := {}
	for cell in _cells(a, b, margin):
		for id in grid.get(cell, []):
			found[id] = true
	var result := found.keys()
	result.sort()
	return result

func _add_node(point: Vector2) -> int:
	var id := network.nodes.size()
	network.nodes.append(point)
	adjacency.append([])
	var cell: Vector2i = _cells(point, point)[0]
	if not node_grid.has(cell):
		node_grid[cell] = []
	node_grid[cell].append(id)
	return id

func _add_edge(a: int, b: int, kind: int) -> void:
	var id := network.edges.size()
	network.edges.append({"a": a, "b": b, "kind": kind})
	_index_edge(id)

func _index_edge(id: int) -> void:
	var edge: Dictionary = network.edges[id]
	adjacency[edge.a].append(id)
	adjacency[edge.b].append(id)
	for cell in _cells(network.nodes[edge.a], network.nodes[edge.b]):
		if not edge_grid.has(cell):
			edge_grid[cell] = []
		edge_grid[cell].append(id)

func _legal_arm(node: int, point: Vector2, kind: int) -> bool:
	if adjacency[node].size() >= 4:
		return false
	var direction := (point - network.nodes[node]).normalized()
	for id in adjacency[node]:
		var edge: Dictionary = network.edges[id]
		if (kind == LOCAL and edge.kind == MAIN) or (kind == MAIN and edge.kind == LOCAL):
			return false
		var other: int = edge.b if edge.a == node else edge.a
		var arm := (network.nodes[other] - network.nodes[node]).normalized()
		if rad_to_deg(acos(clampf(direction.dot(arm), -1.0, 1.0))) < RoadNetwork.MIN_CROSSING_ANGLE:
			return false
	return true

func _insert(source: int, proposed: Vector2, kind: int) -> Dictionary:
	var start: Vector2 = network.nodes[source]
	var end := proposed
	var target := -1
	var split := -1
	var nearest := SNAP_DISTANCE
	for id in _query(node_grid, end, end, SNAP_DISTANCE):
		if id == source:
			continue
		var distance := end.distance_to(network.nodes[id])
		if distance < nearest and start.distance_to(network.nodes[id]) >= MIN_JUNCTION_SPACING and _legal_arm(id, start, kind):
			nearest = distance
			target = id
	if target >= 0:
		end = network.nodes[target]
	var closest := 1.0
	for id in _query(edge_grid, start, end, RoadNetwork.EPS):
		var edge: Dictionary = network.edges[id]
		if source == edge.a or source == edge.b:
			continue
		var hit: Variant = Geometry2D.segment_intersects_segment(start, end, network.nodes[edge.a], network.nodes[edge.b])
		if hit == null:
			continue
		var fraction: float = start.distance_to(hit) / maxf(start.distance_to(end), RoadNetwork.EPS)
		if fraction < closest - 0.00001:
			closest = fraction
			split = id
			target = -1
			proposed = hit
	if split >= 0:
		end = proposed
		var edge: Dictionary = network.edges[split]
		for id in [edge.a, edge.b]:
			if end.distance_to(network.nodes[id]) < RoadNetwork.EPS:
				target = id
				split = -1
				end = network.nodes[id]
				break
	if start.distance_to(end) < MIN_JUNCTION_SPACING or not _legal_arm(source, end, kind):
		return {}
	if target >= 0 and not _legal_arm(target, start, kind):
		return {}
	if split >= 0:
		var edge: Dictionary = network.edges[split]
		if (kind == LOCAL and edge.kind == MAIN) or (kind == MAIN and edge.kind == LOCAL):
			return {}
		for id in [edge.a, edge.b]:
			if end.distance_to(network.nodes[id]) < MIN_JUNCTION_SPACING:
				return {}
			var angle := absf((start - end).angle_to(network.nodes[id] - end))
			if rad_to_deg(angle) < RoadNetwork.MIN_CROSSING_ANGLE:
				return {}
	# Recheck snapped geometry before any mutation.
	for id in _query(edge_grid, start, end, CLEARANCE):
		var edge: Dictionary = network.edges[id]
		if id == split or source in [edge.a, edge.b] or target in [edge.a, edge.b]:
			continue
		var a: Vector2 = network.nodes[edge.a]
		var b: Vector2 = network.nodes[edge.b]
		if RoadNetwork._segments_touch_without_node(start, end, a, b):
			return {}
		if end.distance_to(Geometry2D.get_closest_point_to_segment(end, a, b)) < CLEARANCE:
			return {}
		if a.distance_to(Geometry2D.get_closest_point_to_segment(a, start, end)) < CLEARANCE or b.distance_to(Geometry2D.get_closest_point_to_segment(b, start, end)) < CLEARANCE:
			return {}
	var joined := target >= 0 or split >= 0
	if target < 0:
		target = _add_node(end)
	if split >= 0:
		var old: Dictionary = network.edges[split].duplicate()
		for cell in _cells(network.nodes[old.a], network.nodes[old.b]):
			edge_grid[cell].erase(split)
		adjacency[old.a].erase(split)
		adjacency[old.b].erase(split)
		network.edges[split] = {"a": old.a, "b": target, "kind": old.kind}
		_index_edge(split)
		_add_edge(target, old.b, old.kind)
	_add_edge(source, target, kind)
	return {"node": target, "joined": joined}

func _prune_local_stubs() -> void:
	var removed := {}
	var changed := true
	while changed:
		changed = false
		for node in adjacency.size():
			var active: Array = adjacency[node].filter(func(id: int) -> bool: return not removed.has(id))
			if active.size() == 1 and network.edges[active[0]].kind == LOCAL:
				removed[active[0]] = true
				changed = true
	var kept: Array[Dictionary] = []
	var used := {}
	for id in network.edges.size():
		if not removed.has(id):
			var edge: Dictionary = network.edges[id]
			kept.append(edge)
			used[edge.a] = true
			used[edge.b] = true
	var points: Array[Vector2] = []
	var mapping := {}
	for id in network.nodes.size():
		if used.has(id):
			mapping[id] = points.size()
			points.append(network.nodes[id])
	for edge in kept:
		edge.a = mapping[edge.a]
		edge.b = mapping[edge.b]
	network.nodes = points
	network.edges = kept
