extends Resource
class_name RoadNetwork

## 路网数据。生成、道路绘制、碰撞和导航都读取同一份 RoadNetwork，
## 避免各模块各自维护一套道路数据。所有距离单位为米，1 个 Godot
## 世界单位 = 1 米。
##
## 字段冻结（阶段零）：下列字段的含义、单位和坐标约定已确认，只允许新增，
## 修改或删除前先通知 A、B、C 并补测试。nodes 的 XY 对应世界 XZ，Y 轴向上；
## edges 使用 {"a": int, "b": int, "kind": int}；entrances 使用
## {"edge_id": int, "offset": float}；x_axes / y_axes 使用
## {"kind": int, "pos": float}。

const MAIN := 0
const SECONDARY := 1
const LOCAL := 2
const NAMES := ["主干路", "次干路", "支路"]
const WIDTH_LIMITS := [Vector2(30.0, 50.0), Vector2(20.0, 40.0), Vector2(14.0, 24.0)]
const MIN_JUNCTION_SPACING := 150.0
const MIN_CROSSING_ANGLE := 45.0
const PREFERRED_CROSSING_ANGLE := 70.0
const MAIN_PREFERRED := Vector2(500.0, 800.0)
const SECONDARY_PREFERRED := Vector2(300.0, 400.0)
const LOCAL_PREFERRED := Vector2(150.0, 300.0)
const ENTRANCE_SETBACK := [100.0, 80.0, 50.0, 30.0]
const DIFFICULT_SETBACK := [80.0, 50.0]
const ENTRANCE_CLEARANCE := [100.0, 60.0, 30.0]
const DIFFICULT_CLEARANCE := [80.0, 50.0]
const EPS := 0.01

@export var nodes: Array[Vector2] = []
@export var edges: Array[Dictionary] = []
@export var entrances: Array[Dictionary] = []
@export var map_size: Vector2 = Vector2.ZERO
@export var seed_value: int = 0
@export var density: float = 0.0
@export var widths: Vector3 = Vector3.ZERO
@export var allow_difficult: bool = false
@export var arterial_step: float = 0.0
@export var x_axes: Array[Dictionary] = []
@export var y_axes: Array[Dictionary] = []


func find_route(start: int, destination: int) -> Array[int]:
	var route: Array[int] = []
	if start < 0 or destination < 0 or start >= nodes.size() or destination >= nodes.size():
		return route
	var adjacency: Array = []
	for _id in nodes.size():
		adjacency.append([])
	for edge in edges:
		adjacency[edge.a].append(edge.b)
		adjacency[edge.b].append(edge.a)
	var previous := {start: -1}
	var queue := [start]
	var cursor := 0
	while cursor < queue.size() and not previous.has(destination):
		var current: int = queue[cursor]
		cursor += 1
		for next_id in adjacency[current]:
			if not previous.has(next_id):
				previous[next_id] = current
				queue.append(next_id)
	if not previous.has(destination):
		return route
	var id := destination
	while id != -1:
		route.push_front(id)
		id = previous[id]
	return route


func validate() -> Dictionary:
	var errors: Array[String] = []
	var notes: Array[String] = []
	var adjacency: Array = []
	for _node_id in nodes.size():
		adjacency.append([])
	var kind_counts := [0, 0, 0]
	var short_edges := 0
	for edge in edges:
		var a: int = edge.a
		var b: int = edge.b
		var kind: int = edge.kind
		if kind < MAIN or kind > LOCAL:
			errors.append("存在无效的道路等级")
			continue
		kind_counts[kind] += 1
		if a == b or a < 0 or b < 0 or a >= nodes.size() or b >= nodes.size():
			errors.append("存在无效的路段端点")
			continue
		adjacency[a].append({"other": b, "kind": kind})
		adjacency[b].append({"other": a, "kind": kind})
		if nodes[a].distance_to(nodes[b]) < MIN_JUNCTION_SPACING - EPS:
			short_edges += 1
	if short_edges > 0:
		errors.append("%d 条路段短于 %.0f 米硬下限" % [short_edges, MIN_JUNCTION_SPACING])
	var unmerged_crossings := 0
	for i in range(edges.size()):
		var first: Dictionary = edges[i]
		for j in range(i + 1, edges.size()):
			var second: Dictionary = edges[j]
			if first.a == second.a or first.a == second.b or first.b == second.a or first.b == second.b:
				continue
			if _segments_touch_without_node(nodes[first.a], nodes[first.b], nodes[second.a], nodes[second.b]):
				unmerged_crossings += 1
	if unmerged_crossings > 0:
		errors.append("%d 处道路几何相交却没有共享交叉口节点" % unmerged_crossings)
	for kind in 3:
		var width: float = widths[kind]
		var limits: Vector2 = WIDTH_LIMITS[kind]
		if width < limits.x or width > limits.y:
			errors.append("%s红线宽度 %.1f 米不在 %.0f～%.0f 米范围内" % [NAMES[kind], width, limits.x, limits.y])
		if kind_counts[kind] == 0:
			errors.append("缺少%s" % NAMES[kind])
	var branch_main := 0
	var weak_angles := 0
	for id in nodes.size():
		var arms: Array = adjacency[id]
		if arms.size() > 4:
			errors.append("节点 %d 有 %d 条连接，超过 4 条" % [id, arms.size()])
		var has_main := false
		var has_local := false
		for arm in arms:
			has_main = has_main or arm.kind == MAIN
			has_local = has_local or arm.kind == LOCAL
		for i in range(arms.size()):
			var first: Vector2 = (nodes[arms[i].other] - nodes[id]).normalized()
			for j in range(i + 1, arms.size()):
				var second: Vector2 = (nodes[arms[j].other] - nodes[id]).normalized()
				var degrees := rad_to_deg(acos(clampf(first.dot(second), -1.0, 1.0)))
				if degrees < MIN_CROSSING_ANGLE - EPS:
					errors.append("节点 %d 的最小夹角 %.1f° 小于 %.0f°" % [id, degrees, MIN_CROSSING_ANGLE])
				elif degrees < PREFERRED_CROSSING_ANGLE - EPS:
					weak_angles += 1
		if has_main and has_local:
			branch_main += 1
	if branch_main > 0:
		errors.append("%d 处支路直接连接主干路" % branch_main)
	if weak_angles > 0:
		notes.append("%d 个夹角低于建议的 %.0f°" % [weak_angles, PREFERRED_CROSSING_ANGLE])
	if not nodes.is_empty():
		var seen := {0: true}
		var queue := [0]
		var cursor := 0
		while cursor < queue.size():
			var current: int = queue[cursor]
			cursor += 1
			for arm in adjacency[current]:
				if not seen.has(arm.other):
					seen[arm.other] = true
					queue.append(arm.other)
		if seen.size() != nodes.size():
			errors.append("路网不连通：%d / %d 个节点可达" % [seen.size(), nodes.size()])
	else:
		errors.append("路网没有节点")
	# Compare distances between successive intersection nodes along each
	# centreline. Road ends are checked for the 150 m hard limit above.
	var arterial_outliers := 0
	for axis in x_axes:
		if axis.kind == MAIN:
			var main_positions: Array[float] = []
			for cross in y_axes:
				if cross.kind == MAIN:
					main_positions.append(cross.pos)
			for i in range(main_positions.size() - 1):
				var gap: float = main_positions[i + 1] - main_positions[i]
				if gap < MAIN_PREFERRED.x - EPS or gap > MAIN_PREFERRED.y + EPS:
					arterial_outliers += 1
	for axis in y_axes:
		if axis.kind == MAIN:
			var main_positions: Array[float] = []
			for cross in x_axes:
				if cross.kind == MAIN:
					main_positions.append(cross.pos)
			for i in range(main_positions.size() - 1):
				var gap: float = main_positions[i + 1] - main_positions[i]
				if gap < MAIN_PREFERRED.x - EPS or gap > MAIN_PREFERRED.y + EPS:
					arterial_outliers += 1
	if arterial_outliers > 0:
		notes.append("%d 处主干路—主干路间距偏离 %.0f～%.0f 米建议范围" % [arterial_outliers, MAIN_PREFERRED.x, MAIN_PREFERRED.y])
	var secondary_short := 0
	for edge in edges:
		if edge.kind == SECONDARY and nodes[edge.a].distance_to(nodes[edge.b]) < SECONDARY_PREFERRED.x - EPS:
			secondary_short += 1
	if secondary_short > 0:
		notes.append("%d 段次干路交叉口间距低于建议的 %.0f 米；为连接支路保留，均满足 %.0f 米硬下限" % [secondary_short, SECONDARY_PREFERRED.x, MIN_JUNCTION_SPACING])
	errors.append_array(_validate_entrances(nodes, adjacency))
	if entrances.is_empty():
		notes.append("地块出入口规则：未适用（本演示未生成地块或出入口）")
	return {"valid": errors.is_empty(), "errors": errors, "notes": notes, "nodes": nodes.size(), "edges": edges.size(), "kinds": kind_counts}


static func _segments_touch_without_node(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var first_horizontal := absf(a.y - b.y) < EPS
	var second_horizontal := absf(c.y - d.y) < EPS
	if first_horizontal != second_horizontal:
		var h0: Vector2 = a if first_horizontal else c
		var h1: Vector2 = b if first_horizontal else d
		var v0: Vector2 = c if first_horizontal else a
		var v1: Vector2 = d if first_horizontal else b
		return (
			v0.x >= minf(h0.x, h1.x) - EPS
			and v0.x <= maxf(h0.x, h1.x) + EPS
			and h0.y >= minf(v0.y, v1.y) - EPS
			and h0.y <= maxf(v0.y, v1.y) + EPS
		)
	if first_horizontal:
		return absf(a.y - c.y) < EPS and maxf(minf(a.x, b.x), minf(c.x, d.x)) <= minf(maxf(a.x, b.x), maxf(c.x, d.x)) + EPS
	return absf(a.x - c.x) < EPS and maxf(minf(a.y, b.y), minf(c.y, d.y)) <= minf(maxf(a.y, b.y), maxf(c.y, d.y)) + EPS


func _validate_entrances(road_nodes: Array, adjacency: Array) -> Array[String]:
	var errors: Array[String] = []
	var grouped := {}
	for entrance in entrances:
		var edge_id: int = entrance.edge_id
		if edge_id < 0 or edge_id >= edges.size():
			errors.append("地块出入口引用了无效路段")
			continue
		var edge: Dictionary = edges[edge_id]
		var length: float = road_nodes[edge.a].distance_to(road_nodes[edge.b])
		var offset: float = entrance.offset
		if offset < 0.0 or offset > length:
			errors.append("地块出入口位于路段外")
			continue
		var kind: int = edge.kind
		var required: float = ENTRANCE_SETBACK[kind]
		if kind == LOCAL:
			var connects_higher := false
			for arm in adjacency[edge.a]:
				connects_higher = connects_higher or arm.kind < LOCAL
			for arm in adjacency[edge.b]:
				connects_higher = connects_higher or arm.kind < LOCAL
			required = ENTRANCE_SETBACK[2] if connects_higher else ENTRANCE_SETBACK[3]
		elif allow_difficult:
			required = DIFFICULT_SETBACK[kind]
		if minf(offset, length - offset) < required - EPS:
			errors.append("出入口距交叉口退让不足 %.0f 米" % required)
		if not grouped.has(edge_id):
			grouped[edge_id] = []
		grouped[edge_id].append(offset)
	for edge_id in grouped:
		var offsets: Array = grouped[edge_id]
		offsets.sort()
		var kind: int = edges[edge_id].kind
		var required: float = ENTRANCE_CLEARANCE[kind]
		if kind != LOCAL and allow_difficult:
			required = DIFFICULT_CLEARANCE[kind]
		for i in range(offsets.size() - 1):
			if offsets[i + 1] - offsets[i] < required - EPS:
				errors.append("相邻地块出入口净距不足 %.0f 米" % required)
	return errors
