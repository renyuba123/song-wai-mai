extends Resource
class_name CitySite

## 城市站点。position 是建筑或地块锚点，spawn_point.position 是安全的
## 可走位置。站点只保存纯数据，不保存 Node 引用。

enum Kind { MERCHANT, RESIDENTIAL }

@export var id: StringName = &""
@export var kind: Kind = Kind.MERCHANT
@export var position: Vector3 = Vector3.ZERO
@export var facing_yaw: float = 0.0
@export var lot_id: int = -1
@export var road_edge_id: int = -1
@export var spawn_point: SpawnPoint = null


func validate(network: RoadNetwork = null) -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("站点缺少编号")
	if kind < Kind.MERCHANT or kind > Kind.RESIDENTIAL:
		errors.append("站点类型无效")
	if not position.is_finite():
		errors.append("站点位置无效")
	if not is_finite(facing_yaw):
		errors.append("站点朝向无效")
	if lot_id < 0 and road_edge_id < 0:
		errors.append("站点必须关联地块或路段")
	if spawn_point == null:
		errors.append("站点缺少出生点")
		return errors
	var expected_kind: SpawnPoint.Kind = (
		SpawnPoint.Kind.MERCHANT if kind == Kind.MERCHANT else SpawnPoint.Kind.CUSTOMER
	)
	if spawn_point.kind != expected_kind:
		errors.append("站点出生点类型不匹配")
	if spawn_point.site_id != id:
		errors.append("站点出生点的站点编号不匹配")
	errors.append_array(spawn_point.validate(network))
	return errors


func is_valid(network: RoadNetwork = null) -> bool:
	return validate(network).is_empty()
