extends Resource
class_name CityContent

## 阶段一的城市内容：地块、建筑、站点、玩家起点和出入口交叉引用。
## 所有位置都是纯数据；rect 的 X 对应世界 X，Y 对应世界 Z。
## lots / buildings 的 id 是数组下标，sites 通过 lot_id 关联地块。

const LOT_KEYS := [
	"id",
	"rect",
	"road_edge_id",
	"road_offset_m",
	"frontage_width_m",
	"depth_m",
	"facing_yaw",
	"side",
	"entrance_id",
	"building_id",
	"site_id",
]
const BUILDING_KEYS := [
	"id",
	"lot_id",
	"rect",
	"height_m",
	"kind",
	"entrance_id",
	"site_id",
]
const ENTRANCE_KEYS := ["edge_id", "offset", "width", "facing_yaw", "lot_id"]

@export var seed_value: int = 0
@export var lots: Array[Dictionary] = []
@export var buildings: Array[Dictionary] = []
@export var sites: Array[CitySite] = []
@export var player_start: SpawnPoint = null


func get_available_player_starts() -> Array[SpawnPoint]:
	## 兼容旧版 CityContent：当前项目只保存一个确定性出生点。
	var result: Array[SpawnPoint] = []
	if player_start != null:
		result.append(player_start)
	return result


func validate(network: RoadNetwork = null) -> Array[String]:
	var errors: Array[String] = []
	if network == null:
		errors.append("城市内容缺少路网")
		return errors
	if seed_value != network.seed_value:
		errors.append("城市种子与路网种子不一致")
	if lots.is_empty():
		errors.append("城市没有地块")
	if buildings.is_empty():
		errors.append("城市没有建筑")

	var lot_rects: Array[Dictionary] = []
	for index in lots.size():
		var lot: Dictionary = lots[index]
		if not _has_keys(lot, LOT_KEYS):
			errors.append("地块 %d 字段不完整" % index)
			continue
		if int(lot.id) != index:
			errors.append("地块编号 %d 与数组下标不一致" % int(lot.id))
		var rect: Rect2 = lot.rect
		if not _finite_rect(rect):
			errors.append("地块 %d 的矩形无效" % index)
		else:
			lot_rects.append({"id": index, "rect": rect})
		if int(lot.side) != 1 and int(lot.side) != -1:
			errors.append("地块 %d 的临街侧无效" % index)
		if float(lot.frontage_width_m) <= RoadNetwork.EPS:
			errors.append("地块 %d 的临街宽度无效" % index)
		if float(lot.depth_m) <= RoadNetwork.EPS:
			errors.append("地块 %d 的进深无效" % index)
		if not is_finite(float(lot.facing_yaw)):
			errors.append("地块 %d 的朝向无效" % index)
		var edge_id := int(lot.road_edge_id)
		if edge_id < 0 or edge_id >= network.edges.size():
			errors.append("地块 %d 引用了无效路段" % index)
		else:
			var edge: Dictionary = network.edges[edge_id]
			var a: Vector2 = network.nodes[edge.a]
			var b: Vector2 = network.nodes[edge.b]
			var length := a.distance_to(b)
			var offset := float(lot.road_offset_m)
			if length <= RoadNetwork.EPS or offset < -RoadNetwork.EPS or offset > length + RoadNetwork.EPS:
				errors.append("地块 %d 的临街偏移无效" % index)
			else:
				var required := network.get_entrance_setback(edge_id)
				if minf(offset, length - offset) < required - RoadNetwork.EPS:
					errors.append("地块 %d 距交叉口退让不足 %.0f 米" % [index, required])
		var entrance_id := int(lot.entrance_id)
		if entrance_id < -1 or entrance_id >= network.entrances.size():
			errors.append("地块 %d 引用了无效出入口" % index)
		var building_id := int(lot.building_id)
		if building_id < -1 or building_id >= buildings.size():
			errors.append("地块 %d 引用了无效建筑" % index)

	for i in lot_rects.size():
		for j in range(i + 1, lot_rects.size()):
			if lot_rects[i].rect.intersects(lot_rects[j].rect):
				errors.append("地块 %d 与地块 %d 重叠" % [lot_rects[i].id, lot_rects[j].id])

	var building_lots := {}
	for index in buildings.size():
		var building: Dictionary = buildings[index]
		if not _has_keys(building, BUILDING_KEYS):
			errors.append("建筑 %d 字段不完整" % index)
			continue
		if int(building.id) != index:
			errors.append("建筑编号 %d 与数组下标不一致" % int(building.id))
		var rect: Rect2 = building.rect
		if not _finite_rect(rect):
			errors.append("建筑 %d 的矩形无效" % index)
		if float(building.height_m) <= RoadNetwork.EPS:
			errors.append("建筑 %d 的高度无效" % index)
		if int(building.kind) < CitySite.Kind.MERCHANT or int(building.kind) > CitySite.Kind.RESIDENTIAL:
			errors.append("建筑 %d 的类型无效" % index)
		var lot_id := int(building.lot_id)
		if lot_id < 0 or lot_id >= lots.size():
			errors.append("建筑 %d 引用了无效地块" % index)
		else:
			if building_lots.has(lot_id):
				errors.append("地块 %d 有多栋建筑" % lot_id)
			building_lots[lot_id] = index
			var lot: Dictionary = lots[lot_id]
			if not _finite_rect(rect) or not _finite_rect(lot.rect) or not lot.rect.encloses(rect):
				errors.append("建筑 %d 超出所属地块" % index)
			if int(lot.building_id) != index:
				errors.append("地块 %d 与建筑 %d 的引用不一致" % [lot_id, index])
			if int(lot.entrance_id) != int(building.entrance_id):
				errors.append("建筑 %d 与地块 %d 的出入口不一致" % [index, lot_id])
			if StringName(lot.site_id) != StringName(building.site_id):
				errors.append("建筑 %d 与地块 %d 的站点不一致" % [index, lot_id])
			if int(building.entrance_id) >= 0 and int(building.entrance_id) < network.entrances.size():
				if int(network.entrances[int(building.entrance_id)].get("lot_id", -1)) != lot_id:
					errors.append("建筑 %d 的出入口未关联所属地块" % index)
		var entrance_id := int(building.entrance_id)
		if entrance_id < -1 or entrance_id >= network.entrances.size():
			errors.append("建筑 %d 引用了无效出入口" % index)

	var entrance_edges := {}
	for index in network.entrances.size():
		var entrance: Dictionary = network.entrances[index]
		if not _has_keys(entrance, ENTRANCE_KEYS):
			errors.append("出入口 %d 缺少宽度、朝向或地块关联" % index)
			continue
		var edge_id := int(entrance.edge_id)
		if edge_id < 0 or edge_id >= network.edges.size():
			errors.append("出入口 %d 引用了无效路段" % index)
			continue
		if entrance_edges.has(edge_id):
			errors.append("路段 %d 有多个出入口" % edge_id)
		entrance_edges[edge_id] = true
		var edge: Dictionary = network.edges[edge_id]
		var length: float = network.nodes[edge.a].distance_to(network.nodes[edge.b])
		var offset := float(entrance.offset)
		if offset < 0.0 or offset > length:
			errors.append("出入口 %d 位于路段外" % index)
		else:
			var required := network.get_entrance_setback(edge_id)
			if minf(offset, length - offset) < required - RoadNetwork.EPS:
				errors.append("出入口 %d 距交叉口退让不足 %.0f 米" % [index, required])
		if float(entrance.width) <= RoadNetwork.EPS:
			errors.append("出入口 %d 的宽度无效" % index)
		if not is_finite(float(entrance.facing_yaw)):
			errors.append("出入口 %d 的朝向无效" % index)
		var lot_id := int(entrance.lot_id)
		if lot_id < 0 or lot_id >= lots.size():
			errors.append("出入口 %d 引用了无效地块" % index)
			continue
		var lot: Dictionary = lots[lot_id]
		if int(lot.entrance_id) != index:
			errors.append("地块 %d 与出入口 %d 的引用不一致" % [lot_id, index])
		if int(lot.road_edge_id) != edge_id:
			errors.append("出入口 %d 与地块 %d 的路段不一致" % [index, lot_id])
		if absf(float(lot.road_offset_m) - offset) > 0.1:
			errors.append("出入口 %d 与地块 %d 的偏移不一致" % [index, lot_id])
		if int(lot.building_id) < 0 or int(lot.building_id) >= buildings.size():
			errors.append("出入口地块 %d 没有建筑" % lot_id)

	if not lots.is_empty() and get_entrance_lots().is_empty():
		errors.append("城市没有可用的地块出入口")

	var site_ids := {}
	var merchant_count := 0
	var customer_count := 0
	for site in sites:
		if site == null:
			errors.append("站点列表包含空值")
			continue
		if site_ids.has(site.id):
			errors.append("站点编号 %s 重复" % site.id)
		site_ids[site.id] = true
		if site.kind == CitySite.Kind.MERCHANT:
			merchant_count += 1
		elif site.kind == CitySite.Kind.RESIDENTIAL:
			customer_count += 1
		errors.append_array(site.validate(network))
		if site.lot_id < 0 or site.lot_id >= lots.size():
			errors.append("站点 %s 引用了无效地块" % site.id)
			continue
		var lot: Dictionary = lots[site.lot_id]
		if not _has_keys(lot, LOT_KEYS):
			continue
		if StringName(lot.site_id) != site.id:
			errors.append("地块 %d 与站点 %s 的引用不一致" % [site.lot_id, site.id])
		if not lot.rect.has_point(Vector2(site.position.x, site.position.z)):
			errors.append("站点 %s 不在所属地块内" % site.id)
		var entrance_id := int(lot.entrance_id)
		if entrance_id < 0 or entrance_id >= network.entrances.size():
			errors.append("站点 %s 的地块没有出入口" % site.id)
			continue
		var entrance: Dictionary = network.entrances[entrance_id]
		if int(entrance.get("lot_id", -1)) != site.lot_id:
			errors.append("站点 %s 的出入口未关联所属地块" % site.id)
		if site.road_edge_id != int(entrance.get("edge_id", -1)):
			errors.append("站点 %s 与出入口的路段不一致" % site.id)
		var building_id := int(lot.building_id)
		if building_id < 0 or building_id >= buildings.size():
			errors.append("站点 %s 的地块没有建筑" % site.id)
		elif int(buildings[building_id].kind) != site.kind:
			errors.append("站点 %s 与建筑类型不一致" % site.id)
		if site.spawn_point != null:
			if site.spawn_point.road_edge_id != int(entrance.get("edge_id", -1)):
				errors.append("站点 %s 的出生点路段不一致" % site.id)
			var entrance_offset := float(entrance.get("offset", -1.0))
			if absf(site.spawn_point.road_offset_m - entrance_offset) > 0.1:
				errors.append("站点 %s 的出生点偏移不一致" % site.id)
			if absf(site.spawn_point.lateral_offset_m) <= RoadNetwork.EPS:
				errors.append("站点 %s 的出生点位于道路中心" % site.id)
			if _point_in_building(Vector2(site.spawn_point.position.x, site.spawn_point.position.z)):
				errors.append("站点 %s 的出生点落在建筑内" % site.id)
	if merchant_count == 0:
		errors.append("城市没有商家站点")
	if customer_count == 0:
		errors.append("城市没有顾客站点")

	for lot in lots:
		if not _has_keys(lot, LOT_KEYS):
			continue
		var lot_site_id := StringName(lot.site_id)
		if lot_site_id != &"" and not site_ids.has(lot_site_id):
			errors.append("地块 %d 引用了不存在的站点 %s" % [int(lot.id), lot_site_id])

	if player_start == null:
		errors.append("城市没有玩家出生点")
	else:
		errors.append_array(player_start.validate(network))
		if player_start.kind != SpawnPoint.Kind.PLAYER_START:
			errors.append("玩家出生点类型无效")
		if player_start.site_id != &"":
			errors.append("玩家出生点不应关联站点")
		if absf(player_start.lateral_offset_m) <= RoadNetwork.EPS:
			errors.append("玩家出生点位于道路中心")
		if _point_in_building(Vector2(player_start.position.x, player_start.position.z)):
			errors.append("玩家出生点落在建筑内")
	return errors


func is_valid(network: RoadNetwork = null) -> bool:
	return validate(network).is_empty()


func get_entrance_lots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for lot in lots:
		if lot.has("entrance_id") and int(lot.entrance_id) >= 0:
			result.append(lot)
	return result


func _point_in_building(point: Vector2) -> bool:
	for building in buildings:
		if not building.has("rect"):
			continue
		var rect: Rect2 = building.rect
		if rect.has_point(point):
			return true
	return false


func _finite_rect(rect: Rect2) -> bool:
	return (
		rect.position.is_finite()
		and rect.size.is_finite()
		and rect.size.x > RoadNetwork.EPS
		and rect.size.y > RoadNetwork.EPS
	)


func _has_keys(data: Dictionary, keys: Array) -> bool:
	for key in keys:
		if not data.has(key):
			return false
	return true
