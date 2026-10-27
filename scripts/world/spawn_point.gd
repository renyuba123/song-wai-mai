extends Resource
class_name SpawnPoint

## 可复现的安全出生点。位置单位为米，Y 轴向上；facing_yaw 为弧度，
## 0 表示朝向 -Z。商家和顾客点通过 site_id 关联 CitySite，玩家起点可以
## 不关联站点。

enum Kind { PLAYER_START, MERCHANT, CUSTOMER }

@export var kind: Kind = Kind.PLAYER_START
@export var site_id: StringName = &""
@export var position: Vector3 = Vector3.ZERO
@export var facing_yaw: float = 0.0
@export var road_edge_id: int = -1
@export var road_offset_m: float = 0.0


func validate(network: RoadNetwork = null) -> Array[String]:
	var errors: Array[String] = []
	if not position.is_finite():
		errors.append("出生点位置无效")
	if not is_finite(facing_yaw):
		errors.append("出生点朝向无效")
	if kind < Kind.PLAYER_START or kind > Kind.CUSTOMER:
		errors.append("出生点类型无效")
	if kind != Kind.PLAYER_START and site_id == &"":
		errors.append("商家或顾客出生点缺少站点编号")
	if network == null:
		return errors
	if road_edge_id < 0 or road_edge_id >= network.edges.size():
		errors.append("出生点引用了无效路段")
		return errors
	var edge: Dictionary = network.edges[road_edge_id]
	var road_kind: int = edge.kind
	if road_kind < RoadNetwork.MAIN or road_kind > RoadNetwork.LOCAL:
		errors.append("出生点路段的道路等级无效")
		return errors
	var a: Vector2 = network.nodes[edge.a]
	var b: Vector2 = network.nodes[edge.b]
	var length: float = a.distance_to(b)
	if road_offset_m < 0.0 or road_offset_m > length:
		errors.append("出生点偏移超出路段范围")
		return errors
	var required: float = RoadNetwork.ENTRANCE_SETBACK[road_kind]
	if minf(road_offset_m, length - road_offset_m) < required - RoadNetwork.EPS:
		errors.append("出生点距交叉口退让不足 %.0f 米" % required)
	var half_x: float = network.map_size.x * 0.5
	var half_z: float = network.map_size.y * 0.5
	if absf(position.x) > half_x + RoadNetwork.EPS or absf(position.z) > half_z + RoadNetwork.EPS:
		errors.append("出生点超出地图范围")
	return errors


func is_valid(network: RoadNetwork = null) -> bool:
	return validate(network).is_empty()
