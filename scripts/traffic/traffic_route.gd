extends RefCounted
class_name TrafficRoute

## 汽车路线与车道偏移的纯数学部分。车辆不依赖导航代理，
## 只沿路网的车行道折线行驶；放在这里便于离树测试和保持确定性。

const STRAIGHT_DOT := 0.7
const STRAIGHT_CHANCE := 0.65
const DIRECTION_EPS := 0.000001


static func lane_offset(redline: float) -> float:
	## 右侧车道中心到道路中心线的距离。车行道为红线宽度的一部分，
	## 再取其中一半（单向一条车道）的中心。
	return redline * RoadNetwork.CARRIAGEWAY_RATIO * 0.25


static func right_of(direction: Vector2) -> Vector2:
	## 项目坐标中北为 (0, -1)，right(北) = 东。
	return Vector2(-direction.y, direction.x)


static func yaw_from_direction(direction: Vector2) -> float:
	if direction.length_squared() < DIRECTION_EPS:
		return 0.0
	return atan2(-direction.x, -direction.y)


static func build_adjacency(network: RoadNetwork) -> Array:
	var adjacency: Array = []
	if network == null:
		return adjacency
	adjacency.resize(network.nodes.size())
	for index in adjacency.size():
		adjacency[index] = []
	for edge_id in network.edges.size():
		var edge: Dictionary = network.edges[edge_id]
		adjacency[int(edge.a)].append(edge_id)
		adjacency[int(edge.b)].append(edge_id)
	return adjacency


static func other_node(edge: Dictionary, node_id: int) -> int:
	if int(edge.a) == node_id:
		return int(edge.b)
	if int(edge.b) == node_id:
		return int(edge.a)
	return -1


static func edge_lane(network: RoadNetwork, edge_id: int, from_node: int) -> Dictionary:
	## 返回从 from_node 驶向另一端的单向车道。start/end 已经带上右侧偏移。
	if network == null or edge_id < 0 or edge_id >= network.edges.size():
		return {}
	if from_node < 0 or from_node >= network.nodes.size():
		return {}
	var edge: Dictionary = network.edges[edge_id]
	var to_node := other_node(edge, from_node)
	if to_node < 0:
		return {}
	var start_node: Vector2 = network.nodes[from_node]
	var end_node: Vector2 = network.nodes[to_node]
	var offset := end_node - start_node
	var length := offset.length()
	if length <= DIRECTION_EPS:
		return {}
	var kind := int(edge.kind)
	if kind < RoadNetwork.MAIN or kind > RoadNetwork.LOCAL:
		return {}
	var direction := offset / length
	var right := right_of(direction)
	var lane := right * lane_offset(network.widths[kind])
	var start_xz := start_node + lane
	var end_xz := end_node + lane
	return {
		"edge_id": edge_id,
		"from": from_node,
		"to": to_node,
		"kind": kind,
		"direction": direction,
		"start": Vector3(start_xz.x, RoadNetwork.SURFACE_Y, start_xz.y),
		"end": Vector3(end_xz.x, RoadNetwork.SURFACE_Y, end_xz.y),
		"length": length,
	}


static func choose_next_edge(
	network: RoadNetwork,
	adjacency: Array,
	node_id: int,
	incoming_edge_id: int,
	incoming_direction: Vector2,
	rng: RandomNumberGenerator
) -> int:
	## 优先直行，其次随机转弯；只有无路可走时才原地掉头。
	if network == null or node_id < 0 or node_id >= adjacency.size():
		return -1
	var candidates: Array[int] = []
	var straight: Array[int] = []
	for raw_edge_id in adjacency[node_id]:
		var edge_id := int(raw_edge_id)
		if edge_id == incoming_edge_id:
			continue
		if edge_id < 0 or edge_id >= network.edges.size():
			continue
		var edge: Dictionary = network.edges[edge_id]
		var to_node := other_node(edge, node_id)
		if to_node < 0:
			continue
		var direction := (network.nodes[to_node] - network.nodes[node_id]).normalized()
		if direction.length_squared() < DIRECTION_EPS:
			continue
		candidates.append(edge_id)
		if direction.dot(incoming_direction) >= STRAIGHT_DOT:
			straight.append(edge_id)
	if candidates.is_empty():
		if incoming_edge_id >= 0 and incoming_edge_id < network.edges.size():
			return incoming_edge_id
		return -1
	if rng == null:
		return candidates[0]
	if not straight.is_empty() and rng.randf() < STRAIGHT_CHANCE:
		return straight[rng.randi_range(0, straight.size() - 1)]
	return candidates[rng.randi_range(0, candidates.size() - 1)]
