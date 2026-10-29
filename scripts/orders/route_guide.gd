extends MeshInstance3D
class_name RouteGuide

## 地面路线指引：把 NavigationService.find_path() 的结果画成贴地条带。
## 重算只在 update_route() 判定需要时发生（目标变化、传送、玩家沿路线前进、
## 明显偏航、节流窗口到期），不在每个物理帧调用 A*。
## 坐标约定：顶点直接写世界坐标，因此节点 top_level = true。

const ROUTE_WIDTH := 0.8
## 车行道视觉顶面在 SURFACE_Y + 0.01，条带只抬高 1.5 厘米，避免看起来悬空。
const ROUTE_LIFT_M := 0.015
## 约 5 Hz；玩家每前进 1 米就重算一次，让路线跟随当前位置。
const RECOMPUTE_INTERVAL_S := 0.2

## 玩家偏离当前路线超过该距离才认为“明显偏航”。
const DEVIATION_THRESHOLD_M := 6.0

## 单次更新位移超过该距离视为传送或重开，立即重算，不受节流限制。
const TELEPORT_THRESHOLD_M := 12.0

## 目标点移动超过该距离视为换目标。
const TARGET_MOVE_EPS_M := 0.5

## 过短的重复路径段会产生零长度切线，构建条带前剔除。
const MIN_SEGMENT_LENGTH_M := 0.05

## 玩家相对上次重算位置前进该距离后重算，避免静止时反复寻路。
const MIN_REBUILD_TRAVEL_M := 1.0

const ROUTE_COLOR := Color(1.0, 0.72, 0.28, 1.0)

var _navigation: NavigationService = null
var _mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null

var _path := PackedVector3Array()
var _target := Vector3.INF
var _active := false
var _last_player_position := Vector3.INF
var _last_rebuild_player := Vector3.INF
var _time_since_rebuild := RECOMPUTE_INTERVAL_S
var _rebuild_count := 0
var _vertex_count := 0


func _ready() -> void:
	_ensure_visuals()


func setup(navigation: NavigationService) -> void:
	_navigation = navigation
	_ensure_visuals()
	hide_route()


func update_route(
	player_position: Vector3,
	target_position: Vector3,
	delta: float,
	force: bool = false
) -> void:
	## 每帧调用只做廉价的距离判断；只有需要时才重建网格并寻路一次。
	_ensure_visuals()
	if (
		_navigation == null
		or not player_position.is_finite()
		or not target_position.is_finite()
	):
		hide_route()
		return

	_time_since_rebuild += maxf(delta, 0.0)

	var target_changed := (
		not _target.is_finite()
		or _target.distance_to(target_position) > TARGET_MOVE_EPS_M
	)
	var teleported := (
		_last_player_position.is_finite()
		and _distance_xz(_last_player_position, player_position) > TELEPORT_THRESHOLD_M
	)
	var needs_rebuild := force or target_changed or teleported
	var interval_ok := _time_since_rebuild >= RECOMPUTE_INTERVAL_S

	if not needs_rebuild and interval_ok:
		if _path.size() < 2:
			# 导航刚就绪或上次寻路为空，按节流间隔重试。
			needs_rebuild = true
		elif (
			_last_rebuild_player.is_finite()
			and _distance_xz(_last_rebuild_player, player_position) >= MIN_REBUILD_TRAVEL_M
		):
			# 玩家沿路线前进后从当前位置重新寻路，路线随移动实时更新。
			needs_rebuild = true
		elif distance_to_path_xz(player_position, _path) > DEVIATION_THRESHOLD_M:
			# 被推到路线外但位移不大时，也按节流间隔纠正。
			needs_rebuild = true

	_last_player_position = player_position
	if needs_rebuild:
		_rebuild(player_position, target_position)


func hide_route() -> void:
	_active = false
	visible = false
	_path = PackedVector3Array()
	_target = Vector3.INF
	_last_player_position = Vector3.INF
	_last_rebuild_player = Vector3.INF
	_time_since_rebuild = RECOMPUTE_INTERVAL_S
	_vertex_count = 0
	if _mesh != null:
		_mesh.clear_surfaces()


func is_route_visible() -> bool:
	return visible and _active and _path.size() >= 2


func get_route_path() -> PackedVector3Array:
	return _path.duplicate()


func get_point_count() -> int:
	return _path.size()


func get_vertex_count() -> int:
	return _vertex_count


func get_rebuild_count() -> int:
	return _rebuild_count


func get_target() -> Vector3:
	return _target


static func distance_to_path_xz(point: Vector3, path: PackedVector3Array) -> float:
	## 只比较水平距离，供偏航判断和测试使用。
	if path.is_empty():
		return INF
	var flat_point := Vector2(point.x, point.z)
	if path.size() == 1:
		return flat_point.distance_to(Vector2(path[0].x, path[0].z))
	var best := INF
	for index in range(1, path.size()):
		var a := Vector2(path[index - 1].x, path[index - 1].z)
		var b := Vector2(path[index].x, path[index].z)
		best = minf(best, _point_segment_distance(flat_point, a, b))
	return best


static func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)


static func _distance_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _ensure_visuals() -> void:
	if _mesh != null:
		return
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = ROUTE_COLOR
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.disable_receive_shadows = true
	material_override = _material
	visible = false


func _rebuild(player_position: Vector3, target_position: Vector3) -> void:
	_time_since_rebuild = 0.0
	_rebuild_count += 1
	_target = target_position
	_last_rebuild_player = player_position
	_path = _clean_path(_navigation.find_path(player_position, target_position))
	if _path.size() < 2:
		_active = false
		visible = false
		_vertex_count = 0
		_mesh.clear_surfaces()
		return
	_build_ribbon()


func _clean_path(raw: PackedVector3Array) -> PackedVector3Array:
	var clean := PackedVector3Array()
	for point in raw:
		if not point.is_finite():
			continue
		if (
			clean.size() > 0
			and clean[clean.size() - 1].distance_to(point) < MIN_SEGMENT_LENGTH_M
		):
			continue
		clean.append(point)
	return clean


func _build_ribbon() -> void:
	_mesh.clear_surfaces()
	_vertex_count = 0
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for index in _path.size():
		var tangent := _tangent_at(index)
		var side := Vector3(-tangent.z, 0.0, tangent.x) * (ROUTE_WIDTH * 0.5)
		var point := _path[index]
		# 导航网格与道路都在 SURFACE_Y；固定贴路面，不跟随导航点高度悬空。
		var y := RoadNetwork.SURFACE_Y + ROUTE_LIFT_M
		_mesh.surface_add_vertex(Vector3(point.x + side.x, y, point.z + side.z))
		_mesh.surface_add_vertex(Vector3(point.x - side.x, y, point.z - side.z))
		_vertex_count += 2
	_mesh.surface_end()
	_active = true
	visible = true


func _tangent_at(index: int) -> Vector3:
	var forward := Vector3.ZERO
	var backward := Vector3.ZERO
	if index + 1 < _path.size():
		forward = _path[index + 1] - _path[index]
	if index > 0:
		backward = _path[index] - _path[index - 1]
	var combined := forward + backward
	var tangent := Vector3(combined.x, 0.0, combined.z)
	if tangent.length_squared() < 0.000001:
		tangent = Vector3(forward.x, 0.0, forward.z)
	if tangent.length_squared() < 0.000001:
		tangent = Vector3(backward.x, 0.0, backward.z)
	if tangent.length_squared() < 0.000001:
		return Vector3.RIGHT
	return tangent.normalized()
