extends RefCounted
class_name CityGenerator

## 从真实路段生成阶段一城市内容：地块、出入口、建筑、站点和玩家起点。
## 只读取 RoadNetwork，并把生成的出入口追加到 network.entrances。
## 同一城市种子总是得到相同结果；编号与数组下标一致。

const CITY_RNG_SALT := 0x5EEDC17
const EXTRA_START_RNG_SALT := 0x57A275
const MAX_PLAYER_STARTS := 12
const MAX_FRONTAGE_LOTS := 640
const MAX_LOTS := 1800
const MAX_LOTS_PER_SIDE := 5
const INFILL_ROWS := 2
const MIN_FRONTAGE := 18.0
const MAX_FRONTAGE := 40.0
const MIN_DEPTH := 18.0
const MAX_DEPTH := 28.0
const MIN_GAP := 2.0
const MAX_GAP := 6.0
const LOT_SETBACK := 2.0
const BUILDING_INSET := 3.0
const ENTRANCE_WIDTH := 6.0
const MAX_MERCHANTS := 12
const MAX_CUSTOMERS := 20


static func generate(network: RoadNetwork) -> CityContent:
	var city := CityContent.new()
	if network == null:
		return city
	city.seed_value = network.seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = network.seed_value ^ CITY_RNG_SALT

	var edge_ids := _eligible_edge_ids(network)
	_shuffle(edge_ids, rng)
	var used_edges := {}
	var entrance_sides := {}
	for edge_id in edge_ids:
		if city.lots.size() >= MAX_FRONTAGE_LOTS:
			break
		var edge_lots := _lots_for_edge(network, edge_id, rng)
		if edge_lots.is_empty():
			continue
		var remaining := MAX_FRONTAGE_LOTS - city.lots.size()
		if edge_lots.size() > remaining:
			edge_lots.resize(remaining)
		for lot in edge_lots:
			lot.id = city.lots.size()
			city.lots.append(lot)
		var entrance_lot: Dictionary = edge_lots[rng.randi_range(0, edge_lots.size() - 1)]
		var entrance_id := network.entrances.size()
		network.entrances.append({
			"edge_id": edge_id,
			"offset": float(entrance_lot.road_offset_m),
			"width": minf(ENTRANCE_WIDTH, float(entrance_lot.frontage_width_m) * 0.6),
			"facing_yaw": float(entrance_lot.facing_yaw),
			"lot_id": int(entrance_lot.id),
		})
		entrance_lot.entrance_id = entrance_id
		used_edges[edge_id] = true
		entrance_sides[edge_id] = int(entrance_lot.side)
		for lot in edge_lots:
			var building := _make_building(lot, rng)
			var building_id := city.buildings.size()
			building.id = building_id
			lot.building_id = building_id
			city.buildings.append(building)

	_add_infill_lots(network, city, rng)

	var entrance_lots := city.get_entrance_lots()
	if entrance_lots.size() < 2:
		push_error("城市入口地块不足，无法放置商家和顾客站点：%d" % entrance_lots.size())
		return city
	_shuffle(entrance_lots, rng)
	var capacity := entrance_lots.size()
	var merchant_count := clampi(roundi(float(capacity) * 0.4), 1, mini(MAX_MERCHANTS, capacity - 1))
	var customer_count := mini(clampi(capacity - merchant_count, 1, MAX_CUSTOMERS), capacity - merchant_count)
	var selected_count := merchant_count + customer_count
	var merchant_index := 0
	var customer_index := 0
	for index in selected_count:
		var lot: Dictionary = entrance_lots[index]
		var is_merchant := index < merchant_count
		var site_kind := CitySite.Kind.MERCHANT if is_merchant else CitySite.Kind.RESIDENTIAL
		var ordinal := merchant_index if is_merchant else customer_index
		var building: Dictionary = city.buildings[int(lot.building_id)]
		var site := _make_site(network, lot, site_kind, ordinal)
		site.position = Vector3(
			building.rect.get_center().x,
			RoadNetwork.SURFACE_Y,
			building.rect.get_center().y
		)
		city.sites.append(site)
		lot.site_id = site.id
		building.kind = site_kind
		building.site_id = site.id
		building.height_m = (
			rng.randf_range(5.0, 10.0) if is_merchant else rng.randf_range(8.0, 16.0)
		)
		if is_merchant:
			merchant_index += 1
		else:
			customer_index += 1

	var start_edge_ids := _start_edge_ids(network)
	city.player_start = _make_player_start(network, start_edge_ids, used_edges, entrance_sides, rng)
	if city.player_start == null:
		push_error("城市没有可用的玩家出生点")
		return city
	city.player_starts = _make_player_starts(
		network, start_edge_ids, used_edges, entrance_sides, city.player_start, city.buildings
	)
	if city.player_starts.size() < 2:
		push_error("城市可用的玩家出生点不足：%d" % city.player_starts.size())
	return city


static func _eligible_edge_ids(network: RoadNetwork) -> Array:
	## 所有路段两侧都可以生成地块，包括支路；支路两侧也有完整人行道。
	var result := []
	for edge_id in network.edges.size():
		result.append(edge_id)
	return result


static func _start_edge_ids(network: RoadNetwork) -> Array:
	## 玩家起点仍只放在主干路和次干路，避开支路的窄人行道。
	var result := []
	for edge_id in network.edges.size():
		if int(network.edges[edge_id].kind) != RoadNetwork.LOCAL:
			result.append(edge_id)
	return result


static func _lots_for_edge(network: RoadNetwork, edge_id: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var lots: Array[Dictionary] = []
	var edge: Dictionary = network.edges[edge_id]
	var a: Vector2 = network.nodes[edge.a]
	var b: Vector2 = network.nodes[edge.b]
	var length := a.distance_to(b)
	if length <= RoadNetwork.EPS:
		return lots
	var required := network.get_entrance_setback(edge_id)
	var start := required
	var finish := length - required
	if finish - start < MIN_FRONTAGE:
		return lots
	var redline: float = network.widths[int(edge.kind)]
	var direction := (b - a) / length
	var left := Vector2(direction.y, -direction.x)
	var front_offset := redline * 0.5 + LOT_SETBACK
	for side in [1, -1]:
		var sample := (
			a.lerp(b, 0.5)
			+ left * (float(side) * (front_offset + MAX_DEPTH * 0.5))
		)
		if not _inside_block(network, sample):
			continue
		var cursor := start
		var count := 0
		while count < MAX_LOTS_PER_SIDE:
			var available := finish - cursor
			if available < MIN_FRONTAGE:
				break
			var width := rng.randf_range(MIN_FRONTAGE, minf(MAX_FRONTAGE, available))
			var depth := rng.randf_range(MIN_DEPTH, MAX_DEPTH)
			var offset := cursor + width * 0.5
			var inward := left * float(side)
			lots.append({
				"id": -1,
				"rect": _lot_rect(a, b, length, offset, width, depth, front_offset, side, left),
				"road_edge_id": edge_id,
				"road_offset_m": offset,
				"frontage_width_m": width,
				"depth_m": depth,
				"facing_yaw": _yaw_from_dir(-inward),
				"side": side,
				"entrance_id": -1,
				"building_id": -1,
				"site_id": &"",
			})
			cursor += width + rng.randf_range(MIN_GAP, MAX_GAP)
			count += 1
	return lots


static func _add_infill_lots(
	network: RoadNetwork,
	city: CityContent,
	rng: RandomNumberGenerator
) -> void:
	## 沿临街地块再向街区内补两排建筑，避免只有一圈“贴街皮”和空荡的街区。
	## 补排地块没有出入口，也不参与站点选择；与已有地块相交时跳过。
	var frontage_count := city.lots.size()
	var occupied: Array = []
	for lot in city.lots:
		occupied.append(lot.rect)
	for index in frontage_count:
		if city.lots.size() >= MAX_LOTS:
			return
		var source: Dictionary = city.lots[index]
		var edge_id := int(source.road_edge_id)
		if edge_id < 0 or edge_id >= network.edges.size():
			continue
		var edge: Dictionary = network.edges[edge_id]
		var kind := int(edge.kind)
		if kind < RoadNetwork.MAIN or kind > RoadNetwork.LOCAL:
			continue
		var a: Vector2 = network.nodes[edge.a]
		var b: Vector2 = network.nodes[edge.b]
		var length := a.distance_to(b)
		if length <= RoadNetwork.EPS:
			continue
		var direction := (b - a) / length
		var left := Vector2(direction.y, -direction.x)
		var base_front := network.widths[kind] * 0.5 + LOT_SETBACK
		var front := base_front + float(source.depth_m) + rng.randf_range(MIN_GAP, MAX_GAP)
		for _row in INFILL_ROWS:
			if city.lots.size() >= MAX_LOTS:
				return
			var depth := rng.randf_range(MIN_DEPTH, MAX_DEPTH)
			var gap := rng.randf_range(MIN_GAP, MAX_GAP)
			var rect := _lot_rect(
				a, b, length, float(source.road_offset_m),
				float(source.frontage_width_m), depth, front,
				int(source.side), left
			)
			if not _overlaps_existing(rect, occupied):
				var lot := {
					"id": city.lots.size(),
					"rect": rect,
					"road_edge_id": edge_id,
					"road_offset_m": float(source.road_offset_m),
					"frontage_width_m": float(source.frontage_width_m),
					"depth_m": depth,
					"facing_yaw": float(source.facing_yaw),
					"side": int(source.side),
					"entrance_id": -1,
					"building_id": -1,
					"site_id": &"",
				}
				city.lots.append(lot)
				occupied.append(rect)
				var building := _make_building(lot, rng)
				building.id = city.buildings.size()
				lot.building_id = int(building.id)
				city.buildings.append(building)
			front += depth + gap


static func _overlaps_existing(rect: Rect2, occupied: Array) -> bool:
	for other in occupied:
		if rect.intersects(other):
			return true
	return false


static func _lot_rect(
	a: Vector2,
	b: Vector2,
	length: float,
	offset: float,
	width: float,
	depth: float,
	front_offset: float,
	side: int,
	left: Vector2
) -> Rect2:
	var half := width * 0.5
	var p0 := a.lerp(b, (offset - half) / length)
	var p1 := a.lerp(b, (offset + half) / length)
	var shift := left * float(side)
	var front0 := p0 + shift * front_offset
	var front1 := p1 + shift * front_offset
	var back0 := front0 + shift * depth
	var back1 := front1 + shift * depth
	var min_point := Vector2(
		minf(minf(front0.x, front1.x), minf(back0.x, back1.x)),
		minf(minf(front0.y, front1.y), minf(back0.y, back1.y))
	)
	var max_point := Vector2(
		maxf(maxf(front0.x, front1.x), maxf(back0.x, back1.x)),
		maxf(maxf(front0.y, front1.y), maxf(back0.y, back1.y))
	)
	return Rect2(min_point, max_point - min_point)


static func _make_building(lot: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var rect: Rect2 = lot.rect
	var inset := BUILDING_INSET
	var size := rect.size - Vector2(inset * 2.0, inset * 2.0)
	var building_rect := Rect2(rect.position + Vector2(inset, inset), size)
	var kind := CitySite.Kind.MERCHANT
	if rng.randf() >= 0.5:
		kind = CitySite.Kind.RESIDENTIAL
	return {
		"id": -1,
		"lot_id": int(lot.id),
		"rect": building_rect,
		"height_m": rng.randf_range(6.0, 12.0),
		"kind": kind,
		"entrance_id": int(lot.entrance_id),
		"site_id": &"",
	}


static func _make_site(network: RoadNetwork, lot: Dictionary, kind: CitySite.Kind, ordinal: int) -> CitySite:
	var site := CitySite.new()
	site.id = StringName(
		("merchant_%03d" % ordinal) if kind == CitySite.Kind.MERCHANT else ("customer_%03d" % ordinal)
	)
	site.kind = kind
	site.facing_yaw = float(lot.facing_yaw)
	site.lot_id = int(lot.id)
	var entrance_id := int(lot.entrance_id)
	var entrance: Dictionary = network.entrances[entrance_id]
	site.road_edge_id = int(entrance.edge_id)
	var edge: Dictionary = network.edges[site.road_edge_id]
	var a: Vector2 = network.nodes[edge.a]
	var b: Vector2 = network.nodes[edge.b]
	var length := a.distance_to(b)
	var direction := (b - a) / length
	var left := Vector2(direction.y, -direction.x)
	var lateral := RoadNetwork.sidewalk_offset(network.widths[int(edge.kind)])
	var side := int(lot.side)
	var signed_lateral := float(side) * lateral
	var point := a.lerp(b, float(entrance.offset) / length) + left * signed_lateral
	var spawn := SpawnPoint.new()
	spawn.kind = (
		SpawnPoint.Kind.MERCHANT if kind == CitySite.Kind.MERCHANT else SpawnPoint.Kind.CUSTOMER
	)
	spawn.site_id = site.id
	spawn.position = Vector3(point.x, RoadNetwork.SURFACE_Y, point.y)
	spawn.facing_yaw = _yaw_from_dir(left * float(side))
	spawn.road_edge_id = site.road_edge_id
	spawn.road_offset_m = float(entrance.offset)
	spawn.lateral_offset_m = signed_lateral
	site.spawn_point = spawn
	return site


static func _make_player_start(
	network: RoadNetwork,
	edge_ids: Array,
	used_edges: Dictionary,
	entrance_sides: Dictionary,
	rng: RandomNumberGenerator
) -> SpawnPoint:
	for require_unused in [true, false]:
		for edge_id in edge_ids:
			var is_used := used_edges.has(edge_id)
			if require_unused == is_used:
				continue
			var spawn := _make_start_on_edge(network, int(edge_id), is_used, entrance_sides, rng)
			if spawn != null:
				return spawn
	return null


static func _make_start_on_edge(
	network: RoadNetwork,
	edge_id: int,
	is_used: bool,
	entrance_sides: Dictionary,
	rng: RandomNumberGenerator
) -> SpawnPoint:
	var required := network.get_entrance_setback(edge_id)
	var edge: Dictionary = network.edges[edge_id]
	var a: Vector2 = network.nodes[edge.a]
	var b: Vector2 = network.nodes[edge.b]
	var length := a.distance_to(b)
	if length < required * 2.0 + 20.0:
		return null
	var redline: float = network.widths[int(edge.kind)]
	var direction := (b - a) / length
	var left := Vector2(direction.y, -direction.x)
	var sides := _block_sides(network, a, b, left, redline)
	if sides.is_empty():
		return null
	var side: int = sides[0]
	if is_used and entrance_sides.has(edge_id):
		var opposite := -int(entrance_sides[edge_id])
		if sides.has(opposite):
			side = opposite
	elif sides.size() > 1:
		side = sides[rng.randi_range(0, sides.size() - 1)]
	var lateral := RoadNetwork.sidewalk_offset(redline)
	var signed_lateral := float(side) * lateral
	var point := a.lerp(b, 0.5) + left * signed_lateral
	var spawn := SpawnPoint.new()
	spawn.kind = SpawnPoint.Kind.PLAYER_START
	spawn.position = Vector3(point.x, RoadNetwork.SURFACE_Y, point.y)
	spawn.facing_yaw = _yaw_from_dir(direction)
	spawn.road_edge_id = edge_id
	spawn.road_offset_m = length * 0.5
	spawn.lateral_offset_m = signed_lateral
	return spawn


static func _make_player_starts(
	network: RoadNetwork,
	edge_ids: Array,
	used_edges: Dictionary,
	entrance_sides: Dictionary,
	legacy: SpawnPoint,
	buildings: Array[Dictionary]
) -> Array[SpawnPoint]:
	var result: Array[SpawnPoint] = [legacy]
	var rng := RandomNumberGenerator.new()
	rng.seed = network.seed_value ^ EXTRA_START_RNG_SALT
	var candidates := edge_ids.duplicate()
	_shuffle(candidates, rng)
	for edge_id in candidates:
		if result.size() >= MAX_PLAYER_STARTS:
			break
		if int(edge_id) == legacy.road_edge_id:
			continue
		var spawn := _make_start_on_edge(
			network, int(edge_id), used_edges.has(edge_id), entrance_sides, rng
		)
		if spawn == null or not spawn.is_valid(network):
			continue
		if _point_in_buildings(Vector2(spawn.position.x, spawn.position.z), buildings):
			continue
		var duplicate := false
		for existing in result:
			var existing_xz := Vector2(existing.position.x, existing.position.z)
			if existing_xz.distance_to(Vector2(spawn.position.x, spawn.position.z)) < 0.5:
				duplicate = true
				break
		if duplicate:
			continue
		result.append(spawn)
	return result


static func _point_in_buildings(point: Vector2, buildings: Array[Dictionary]) -> bool:
	for building in buildings:
		if not building.has("rect"):
			continue
		var rect: Rect2 = building.rect
		if rect.has_point(point):
			return true
	return false


static func _block_sides(network: RoadNetwork, a: Vector2, b: Vector2, left: Vector2, redline: float) -> Array[int]:
	var sides: Array[int] = []
	var front_offset := redline * 0.5 + LOT_SETBACK
	for side in [1, -1]:
		var sample := (
			a.lerp(b, 0.5)
			+ left * (float(side) * (front_offset + MAX_DEPTH * 0.5))
		)
		if _inside_block(network, sample):
			sides.append(side)
	return sides


static func _inside_block(network: RoadNetwork, point: Vector2) -> bool:
	if network.x_axes.size() < 2 or network.y_axes.size() < 2:
		return false
	var min_x: float = network.x_axes[0].pos
	var max_x: float = network.x_axes[network.x_axes.size() - 1].pos
	var min_y: float = network.y_axes[0].pos
	var max_y: float = network.y_axes[network.y_axes.size() - 1].pos
	return (
		point.x > min_x + RoadNetwork.EPS
		and point.x < max_x - RoadNetwork.EPS
		and point.y > min_y + RoadNetwork.EPS
		and point.y < max_y - RoadNetwork.EPS
	)


static func _yaw_from_dir(direction: Vector2) -> float:
	## 0 朝向 -Z；方向向量位于 XZ 平面，Y 分量为世界 Z。
	return atan2(-direction.x, -direction.y)


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temp = values[index]
		values[index] = values[other]
		values[other] = temp
