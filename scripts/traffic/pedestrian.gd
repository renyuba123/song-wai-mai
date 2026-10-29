extends AnimatableBody3D
class_name Pedestrian

## 行人：GLB 人形视觉 + 胶囊碰撞，沿人行道折线行走，
## 到路口按概率横穿到对侧，结束后继续沿对侧人行道走。
## 路径推进与 TrafficCar.advance() 同构，便于离树测试和固定步长模拟。

const CAPSULE_RADIUS := 0.28
const CAPSULE_HEIGHT := 1.7
const PEDESTRIAN_MODEL_PATH := "res://assets/models/人物模型/zsky_stylized_character.glb"
const PEDESTRIAN_MODEL_SCALE := 0.11
## 模型轴心在身体中部。脚底在原始骨架坐标的 7.85 处，乘以缩放后上移贴地。
const PEDESTRIAN_MODEL_OFFSET_Y := 0.8635
const PEDESTRIAN_MODEL_YAW_DEGREES := 180.0
const PEDESTRIAN_WALK_ANIMATION := "Armature|Walk"
const PEDESTRIAN_IDLE_ANIMATION := "Armature|Iddle"
const PEDESTRIAN_REFERENCE_SPEED := 1.8
const PEDESTRIAN_ACCELERATION_MPS2 := 2.4
const PEDESTRIAN_BRAKING_MPS2 := 4.8
const MOTION_SPEED_EPS := 0.02
const COLORS := [
	Color("c95f4f"),
	Color("4f7fbf"),
	Color("d9c35a"),
	Color("e6e6e6"),
	Color("5f6b75"),
	Color("7c9a66"),
]
const PRELOAD_SEGMENTS := 2
const MAX_ADVANCE_STEPS := 2048
const POINT_EPS := 0.0001

var speed_mps := 1.8
var crossing_chance := 0.35

var _current_speed_mps := 0.0
var _network: RoadNetwork = null
var _adjacency: Array = []
var _rng: RandomNumberGenerator = null
var _spawn_edge_id := -1
var _band_ratio := 0.5
var _plan_side := 1
var _last_edge_id := -1
var _last_from_node := -1
var _last_to_node := -1
var _last_direction := Vector2.ZERO
var _path: Array[Vector3] = []
var _path_cursor := 0
var _path_crossing: Array[bool] = []
var _path_junction_nodes: Array[int] = []
var _path_sides: Array[int] = []
var _path_edges: Array[int] = []
var _active_crossing_node := -1
var _distance_travelled := 0.0
var _appearance := 0
var _color := Color.WHITE
var _nodes_built := false
var _animation_player: AnimationPlayer = null


static func sidewalk_band(redline: float) -> Vector2:
	## 人行道在道路中心线两侧的合法横向区间（内侧到外侧）。
	var carriageway := redline * RoadNetwork.CARRIAGEWAY_RATIO
	return Vector2(carriageway * 0.5, redline * 0.5)


static func lateral_for_band(redline: float, band_ratio: float) -> float:
	## 把 0..1 的比例映射到人行道带内的横向距离；0.5 即人行道中心。
	var band := sidewalk_band(redline)
	return lerpf(band.x, band.y, clampf(band_ratio, 0.0, 1.0))


static func junction_half_width(network: RoadNetwork, node_id: int) -> float:
	## 交叉口沿路方向的半宽：节点连接道路的最大红线宽度的一半。
	if network == null:
		return 0.0
	var widest := 0.0
	for edge in network.edges:
		if int(edge.a) == node_id or int(edge.b) == node_id:
			widest = maxf(widest, float(network.widths[int(edge.kind)]))
	return widest * 0.5


static func sidewalk_lane(
	network: RoadNetwork, edge_id: int, from_node: int, side: int, lateral: float
) -> Dictionary:
	## 从 from_node 出发一侧的人行道段。start/end 已带横向偏移，
	## length 是避开两端路口后真正铺装的人行道长度。
	if network == null or edge_id < 0 or edge_id >= network.edges.size():
		return {}
	if from_node < 0 or from_node >= network.nodes.size():
		return {}
	var edge: Dictionary = network.edges[edge_id]
	var to_node := TrafficRoute.other_node(edge, from_node)
	if to_node < 0:
		return {}
	var start_node: Vector2 = network.nodes[from_node]
	var end_node: Vector2 = network.nodes[to_node]
	var offset := end_node - start_node
	var total := offset.length()
	if total <= RoadNetwork.EPS:
		return {}
	var kind := int(edge.kind)
	if kind < RoadNetwork.MAIN or kind > RoadNetwork.LOCAL:
		return {}
	var direction := offset / total
	var left := Vector2(direction.y, -direction.x)
	var start_along := junction_half_width(network, from_node)
	var end_along := total - junction_half_width(network, to_node)
	var usable := end_along - start_along
	if usable <= 0.0:
		return {}
	var lane := left * (float(side) * lateral)
	var start_xz := start_node + direction * start_along + lane
	var end_xz := start_node + direction * end_along + lane
	return {
		"edge_id": edge_id,
		"from": from_node,
		"to": to_node,
		"kind": kind,
		"direction": direction,
		"left": left,
		"start": Vector3(start_xz.x, RoadNetwork.SURFACE_Y, start_xz.y),
		"end": Vector3(end_xz.x, RoadNetwork.SURFACE_Y, end_xz.y),
		"start_along": start_along,
		"end_along": end_along,
		"length": usable,
		"lateral": lateral,
		"side": side,
	}


func _ready() -> void:
	_ensure_nodes()


func setup(
	source_network: RoadNetwork,
	adjacency: Array,
	edge_id: int,
	from_node: int,
	spawn_offset: float,
	side: int,
	band_ratio: float,
	speed: float,
	ped_rng: RandomNumberGenerator,
	appearance: int,
	cross_chance: float
) -> void:
	_network = source_network
	_adjacency = adjacency
	_rng = ped_rng
	_spawn_edge_id = edge_id
	_last_edge_id = edge_id
	_last_from_node = from_node
	_band_ratio = clampf(band_ratio, 0.0, 1.0)
	_plan_side = 1 if side >= 0 else -1
	speed_mps = maxf(speed, 0.1)
	_current_speed_mps = speed_mps * 0.35
	crossing_chance = clampf(cross_chance, 0.0, 1.0)
	_appearance = appearance
	_color = COLORS[posmod(appearance, COLORS.size())]
	_distance_travelled = 0.0
	_ensure_nodes()
	_apply_color()

	_path.clear()
	_path_crossing.clear()
	_path_junction_nodes.clear()
	_path_sides.clear()
	_path_edges.clear()
	_path_cursor = 0
	_active_crossing_node = -1

	var lane := _lane_for(edge_id, from_node, _plan_side)
	if lane.is_empty():
		return
	var direction: Vector2 = lane.direction
	var start: Vector3 = lane.start
	var offset := clampf(spawn_offset, 0.0, float(lane.length))
	var spawn_point := start + Vector3(direction.x, 0.0, direction.y) * offset
	## 行人挂在 PedestrianSpawner 的容器下，容器保持在原点，
	## 因此本地坐标与世界坐标一致，也方便离树测试。
	position = spawn_point
	rotation = Vector3(0.0, TrafficRoute.yaw_from_direction(direction), 0.0)
	_last_to_node = int(lane.to)
	_last_direction = direction

	_append(spawn_point, _plan_side, edge_id, false)
	_append(lane.end, _plan_side, edge_id, false)
	_path_cursor = 1
	for _step in PRELOAD_SEGMENTS:
		_extend_path()
	if is_inside_tree():
		reset_physics_interpolation()
	_update_animation()


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
			_finish_current_segment()
			continue
		var direction := delta / segment_length
		var step_distance := minf(remaining, segment_length)
		position += direction * step_distance
		rotation.y = TrafficRoute.yaw_from_direction(Vector2(direction.x, direction.z))
		_distance_travelled += step_distance
		remaining -= step_distance
		if step_distance >= segment_length - POINT_EPS:
			_finish_current_segment()


func advance_motion(delta: float, may_walk: bool) -> void:
	## 将路口等待、起步和停车接到平滑速度上，路径数学仍复用 advance()。
	if delta <= 0.0 or _network == null:
		return
	var can_walk := may_walk or _active_crossing_node >= 0
	var target_speed := speed_mps if can_walk else 0.0
	var rate := (
		PEDESTRIAN_ACCELERATION_MPS2
		if target_speed >= _current_speed_mps
		else PEDESTRIAN_BRAKING_MPS2
	)
	_current_speed_mps = move_toward(
		_current_speed_mps,
		target_speed,
		rate * delta
	)
	if _current_speed_mps > MOTION_SPEED_EPS:
		advance(_current_speed_mps * delta)
	_update_animation()


func get_spawn_edge_id() -> int:
	return _spawn_edge_id


func get_current_edge_id() -> int:
	if _path_cursor >= 0 and _path_cursor < _path_edges.size():
		return _path_edges[_path_cursor]
	return _spawn_edge_id


func is_crossing() -> bool:
	if _active_crossing_node >= 0:
		return true
	return (
		_path_cursor >= 0
		and _path_cursor < _path_crossing.size()
		and _path_crossing[_path_cursor]
	)


func get_pending_crossing_node() -> int:
	if _active_crossing_node >= 0:
		return -1
	if (
		_path_cursor < 0
		or _path_cursor >= _path_crossing.size()
		or not _path_crossing[_path_cursor]
		or _path_cursor >= _path_junction_nodes.size()
	):
		return -1
	return _path_junction_nodes[_path_cursor]


func needs_crossing_permission() -> bool:
	return get_pending_crossing_node() >= 0


func commit_crossing() -> int:
	var node_id := get_pending_crossing_node()
	if node_id >= 0:
		_active_crossing_node = node_id
	return node_id


func get_active_crossing_node() -> int:
	return _active_crossing_node


func get_side() -> int:
	if _path_cursor >= 0 and _path_cursor < _path_sides.size():
		return _path_sides[_path_cursor]
	return _plan_side


func get_lateral_offset() -> float:
	## 相对当前路段中心线的带符号横向距离（非横穿时即人行道偏移）。
	var edge_id := get_current_edge_id()
	if _network == null or edge_id < 0 or edge_id >= _network.edges.size():
		return 0.0
	var edge: Dictionary = _network.edges[edge_id]
	var a: Vector2 = _network.nodes[int(edge.a)]
	var b: Vector2 = _network.nodes[int(edge.b)]
	var direction := (b - a).normalized()
	if direction.length_squared() <= POINT_EPS:
		return 0.0
	var left := Vector2(direction.y, -direction.x)
	return (Vector2(position.x, position.z) - a).dot(left)


func get_speed_mps() -> float:
	return speed_mps


func get_current_speed_mps() -> float:
	return _current_speed_mps


func get_distance_travelled() -> float:
	return _distance_travelled


func get_pedestrian_color() -> Color:
	return _color


func get_signature() -> String:
	return "%d|%d|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%s" % [
		_spawn_edge_id,
		get_side(),
		position.x,
		position.y,
		position.z,
		rotation.y,
		speed_mps,
		_current_speed_mps,
		_distance_travelled,
		str(_color),
	]


func _extend_path() -> void:
	if _network == null or _last_edge_id < 0 or _last_from_node < 0 or _last_to_node < 0:
		return
	var current_lane := _lane_for(_last_edge_id, _last_from_node, _plan_side)
	if current_lane.is_empty():
		return
	var walking_side := _plan_side
	var crossing := _rng != null and _rng.randf() < crossing_chance
	if crossing:
		# 在当前路段尽头从本侧横移到对侧，横穿段朝对侧移动。
		var lateral := float(current_lane.lateral)
		var left: Vector2 = current_lane.left
		var opposite_end: Vector3 = (
			current_lane.end
			+ Vector3(left.x, 0.0, left.y) * (-2.0 * lateral * float(walking_side))
		)
		_append(
			opposite_end,
			walking_side,
			_last_edge_id,
			true,
			_last_to_node
		)
		_plan_side = -walking_side

	var next_edge := TrafficRoute.choose_next_edge(
		_network, _adjacency, _last_to_node, _last_edge_id, _last_direction, _rng
	)
	if next_edge < 0:
		return
	var next_lane := _lane_for(next_edge, _last_to_node, _plan_side)
	if next_lane.is_empty():
		return
	# 路口转角连接段：从横穿终点/本侧尽头走到下一段人行道起点。
	_append(next_lane.start, _plan_side, next_edge, false)
	_append(next_lane.end, _plan_side, next_edge, false)
	_last_edge_id = next_edge
	_last_from_node = _last_to_node
	_last_to_node = int(next_lane.to)
	_last_direction = next_lane.direction


func _lane_for(edge_id: int, from_node: int, side: int) -> Dictionary:
	if _network == null or edge_id < 0 or edge_id >= _network.edges.size():
		return {}
	var redline := float(_network.widths[int(_network.edges[edge_id].kind)])
	var lateral := lateral_for_band(redline, _band_ratio)
	return sidewalk_lane(_network, edge_id, from_node, side, lateral)


func _append(
	point: Vector3,
	side: int,
	edge_id: int,
	is_crossing: bool,
	junction_node := -1
) -> void:
	_path.append(point)
	_path_crossing.append(is_crossing)
	_path_junction_nodes.append(junction_node)
	_path_sides.append(side)
	_path_edges.append(edge_id)


func _finish_current_segment() -> void:
	if (
		_path_cursor >= 0
		and _path_cursor < _path_crossing.size()
		and _path_crossing[_path_cursor]
		and _path_cursor < _path_junction_nodes.size()
		and _path_junction_nodes[_path_cursor] == _active_crossing_node
	):
		_active_crossing_node = -1
	_path_cursor += 1


func _ensure_nodes() -> void:
	if _nodes_built:
		return
	_nodes_built = true
	collision_layer = CollisionLayers.PEDESTRIAN
	collision_mask = 0
	sync_to_physics = false
	_build_visuals()

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.position = Vector3(0.0, CAPSULE_HEIGHT * 0.5, 0.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	collision.shape = capsule
	add_child(collision)


func _build_visuals() -> void:
	var visual := Node3D.new()
	visual.name = "PedestrianModel"

	if ResourceLoader.exists(PEDESTRIAN_MODEL_PATH):
		var scene := load(PEDESTRIAN_MODEL_PATH) as PackedScene
		if scene != null:
			var character := scene.instantiate() as Node3D
			if character != null:
				character.name = "Character"
				character.position = Vector3(0.0, PEDESTRIAN_MODEL_OFFSET_Y, 0.0)
				character.rotation_degrees.y = PEDESTRIAN_MODEL_YAW_DEGREES
				character.scale = Vector3.ONE * PEDESTRIAN_MODEL_SCALE
				visual.add_child(character)
				_start_walk_animation(character)
				add_child(visual)
				return

	_build_fallback_visual(visual)
	add_child(visual)


func _build_fallback_visual(visual: Node3D) -> void:
	var fallback := MeshInstance3D.new()
	fallback.name = "FallbackCapsule"
	fallback.position = Vector3(0.0, CAPSULE_HEIGHT * 0.5, 0.0)
	var capsule := CapsuleMesh.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	fallback.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = _color
	material.roughness = 0.8
	fallback.material_override = material
	visual.add_child(fallback)


func _start_walk_animation(character: Node3D) -> void:
	_animation_player = character.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _animation_player == null:
		return
	var animation_name := StringName(PEDESTRIAN_WALK_ANIMATION)
	if not _animation_player.has_animation(animation_name):
		animation_name = StringName(PEDESTRIAN_IDLE_ANIMATION)
	if not _animation_player.has_animation(animation_name):
		return
	_animation_player.speed_scale = _animation_speed_scale()
	_animation_player.play(animation_name)


func _update_animation() -> void:
	if not is_instance_valid(_animation_player):
		return
	var moving := _current_speed_mps > MOTION_SPEED_EPS
	var preferred := (
		StringName(PEDESTRIAN_WALK_ANIMATION)
		if moving
		else StringName(PEDESTRIAN_IDLE_ANIMATION)
	)
	if (
		_animation_player.current_animation != preferred
		and _animation_player.has_animation(preferred)
	):
		_animation_player.play(preferred)
	_animation_player.speed_scale = _animation_speed_scale()


func _animation_speed_scale() -> float:
	if _current_speed_mps <= MOTION_SPEED_EPS:
		return 0.2
	return clampf(_current_speed_mps / PEDESTRIAN_REFERENCE_SPEED, 0.35, 1.5)


func _apply_color() -> void:
	var fallback := get_node_or_null("PedestrianModel/FallbackCapsule") as MeshInstance3D
	if fallback == null:
		return
	var material := fallback.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = _color
