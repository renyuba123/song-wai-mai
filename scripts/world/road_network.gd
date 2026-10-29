extends Resource
class_name RoadNetwork

## 路网数据。生成、道路绘制、碰撞和导航都读取同一份 RoadNetwork，
## 避免各模块各自维护一套道路数据。所有距离单位为米，1 个 Godot
## 世界单位 = 1 米。
##
## 字段冻结（阶段零）：下列字段的含义、单位和坐标约定已确认，只允许新增，
## 修改或删除前先通知 A、B、C 并补测试。nodes 的 XY 对应世界 XZ，Y 轴向上；
## edges 使用 {"a": int, "b": int, "kind": int}；entrances 使用
## {"edge_id": int, "offset": float}，阶段一可附带 "width": float、
## "facing_yaw": float、"lot_id": int；x_axes / y_axes 使用
## {"kind": int, "pos": float}。
##
## SURFACE_Y 是所有可走表面（地面、车行道、人行道）的统一顶面高度；
## 视觉网格可以略高于它，但碰撞体必须齐平，避免出现无法跨越的台阶。

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
const SURFACE_Y := 0.0
const CARRIAGEWAY_RATIO := 0.55

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


static func sidewalk_offset(redline: float) -> float:
	## 单侧人行道中心到道路中心线的横向距离。
	var carriageway := redline * CARRIAGEWAY_RATIO
	return carriageway * 0.5 + (redline - carriageway) * 0.25


func get_entrance_setback(edge_id: int) -> float:
	## 地块出入口和出生点共用的交叉口退让。无效路段返回 0，由调用方另行报错。
	if edge_id < 0 or edge_id >= edges.size():
		return 0.0
	var edge: Dictionary = edges[edge_id]
	var kind: int = edge.kind
	if kind < MAIN or kind > LOCAL:
		return 0.0
	if kind == LOCAL:
		var connects_higher := false
		var endpoints := [edge.a, edge.b]
		for other in edges:
			if other.kind >= LOCAL:
				continue
			if other.a in endpoints or other.b in endpoints:
				connects_higher = true
				break
		return ENTRANCE_SETBACK[2] if connects_higher else ENTRANCE_SETBACK[3]
	if allow_difficult:
		return DIFFICULT_SETBACK[kind]
	return ENTRANCE_SETBACK[kind]


func validate() -> Dictionary:
	var errors: Array[String] = []
	var notes: Array[String] = []
	var seen_edges := {}
	for point in nodes:
		if (
			not point.is_finite()
			or absf(point.x) > map_size.x * 0.5 + EPS
			or absf(point.y) > map_size.y * 0.5 + EPS
		):
			errors.append("节点超出地图边界或坐标无效")
	for edge in edges:
		if (
			not edge.has_all(["a", "b", "kind"])
			or int(edge.a) < 0
			or int(edge.b) < 0
			or int(edge.a) >= nodes.size()
			or int(edge.b) >= nodes.size()
		):
			errors.append("存在无效的路段端点或缺失字段")
			return {
				"valid": false,
				"errors": errors,
				"notes": notes,
				"nodes": nodes.size(),
				"edges": edges.size(),
				"kinds": [0, 0, 0],
			}
		var key := Vector2i(mini(edge.a, edge.b), maxi(edge.a, edge.b))
		if seen_edges.has(key):
			errors.append("存在重复路段")
		seen_edges[key] = true
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
	# 斜向生长后不再有全局轴线，按每条路段的推荐间距统计偏离。
	var outliers := [0, 0, 0]
	var preferred := [MAIN_PREFERRED, SECONDARY_PREFERRED, LOCAL_PREFERRED]
	for edge in edges:
		if edge.kind < MAIN or edge.kind > LOCAL:
			continue
		var length := nodes[edge.a].distance_to(nodes[edge.b])
		var limits: Vector2 = preferred[edge.kind]
		if length < limits.x - EPS or length > limits.y + EPS:
			outliers[edge.kind] += 1
	for kind in range(SECONDARY, LOCAL + 1):
		if outliers[kind] > 0:
			notes.append(
				"%s有 %d 段偏离推荐间距；边界裁切、街区接合和生长采样优先遵守 %.0f 米硬下限"
				% [NAMES[kind], outliers[kind], MIN_JUNCTION_SPACING]
			)
	if x_axes.is_empty() and y_axes.is_empty():
		notes.append("无主干路—主干路交叉口对：主干路推荐间距未适用；各段仍校验 %.0f 米硬下限" % MIN_JUNCTION_SPACING)
	errors.append_array(_validate_entrances(nodes))
	if entrances.is_empty():
		notes.append("地块出入口规则：未适用（本演示未生成地块或出入口）")
	return {"valid": errors.is_empty(), "errors": errors, "notes": notes, "nodes": nodes.size(), "edges": edges.size(), "kinds": kind_counts}


static func _segments_touch_without_node(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return true
	return (
		a.distance_to(Geometry2D.get_closest_point_to_segment(a, c, d)) <= EPS
		or b.distance_to(Geometry2D.get_closest_point_to_segment(b, c, d)) <= EPS
		or c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)) <= EPS
		or d.distance_to(Geometry2D.get_closest_point_to_segment(d, a, b)) <= EPS
	)


func _validate_entrances(road_nodes: Array) -> Array[String]:
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
		if entrance.has("width") and float(entrance.width) <= 0.0:
			errors.append("地块出入口宽度必须为正")
		if entrance.has("facing_yaw") and not is_finite(float(entrance.facing_yaw)):
			errors.append("地块出入口朝向无效")
		if entrance.has("lot_id") and int(entrance.lot_id) < 0:
			errors.append("地块出入口关联了无效地块")
		var required: float = get_entrance_setback(edge_id)
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
