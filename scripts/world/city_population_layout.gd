extends RefCounted
class_name CityPopulationLayout
## Pure placement data: no SceneTree, model loading, or player-dependent random state.
const Catalog = preload("res://scripts/world/city_model_catalog.gd")
var seed_value: int
var chunk_size: float
var buildings: Array[Dictionary] = []
var items: Array[Dictionary] = []
var chunks: Dictionary = {}

static func chunk_at(position: Vector3, size: float) -> Vector2i:
	return Vector2i(floori(position.x / size), floori(position.z / size))

static func fit(model: Dictionary, rect: Rect2, yaw: float, height: float, align_front: bool) -> Dictionary:
	var source: AABB = model.bounds
	var basis := Basis(Vector3.UP, yaw + PI)
	var rotated := Transform3D(basis, Vector3.ZERO) * source
	var factor := minf(minf(rect.size.x / rotated.size.x, rect.size.y / rotated.size.z), height / source.size.y)
	var size := rotated.size * factor
	var center := rect.get_center()
	if align_front:
		center += Vector2(-sin(yaw), -cos(yaw)) * (rect.size - Vector2(size.x, size.z)) * 0.5
	var origin := Vector3(center.x, 0.03 + size.y * 0.5, center.y) - basis * source.get_center() * factor
	return {"path": model.path, "transform": Transform3D(basis.scaled(Vector3.ONE * factor), origin),
		"footprint": Rect2(center - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)),
		"size": size, "center": Vector3(center.x, 0.03 + size.y * 0.5, center.y)}

static func generate(city: CityContent, size := 100.0) -> CityPopulationLayout:
	var result := CityPopulationLayout.new()
	result.seed_value = city.seed_value
	result.chunk_size = maxf(size, 25.0)
	var sites := {}
	for site in city.sites:
		sites[site.lot_id] = site
	for building in city.buildings:
		var lot: Dictionary = city.lots[building.lot_id]
		var site: CitySite = sites.get(building.lot_id)
		var category := "other" if site == null else ("pickup" if site.kind == CitySite.Kind.MERCHANT else "delivery")
		var choices: Array = Catalog.MODELS[category]
		var rng := RandomNumberGenerator.new()
		rng.seed = city.seed_value ^ (int(building.id) * 104729) ^ 0xC17
		var item := fit(choices[rng.randi_range(0, choices.size()-1)], building.rect, lot.facing_yaw, 16.0 if site else 30.0, true)
		item.id = "building_%d" % building.id
		item.building_id = int(building.id)
		item.site_id = String(site.id) if site else ""
		item.target = site.spawn_point.position if site else Vector3.INF
		item.yaw = float(lot.facing_yaw)
		result.buildings.append(item)
		result.add_item(item)
		# Side margins of each lot; never the central entrance or sidewalk.
		var rect: Rect2 = building.rect
		for side in [-1, 1]:
			var point := Vector2(rect.position.x - 1.5 if side < 0 else rect.end.x + 1.5, rect.get_center().y)
			if absf(sin(lot.facing_yaw)) > 0.5:
				point = Vector2(rect.get_center().x, rect.position.y - 1.5 if side < 0 else rect.end.y + 1.5)
			var slot := Rect2(point - Vector2.ONE * 0.65, Vector2.ONE * 1.3)
			if not lot.rect.encloses(slot):
				continue
			var kind := "lamp" if side == 1 and int(building.id) % 3 == 0 else "tree"
			var prop := fit(Catalog.MODELS[kind][0], slot, lot.facing_yaw, 5.0 if kind == "lamp" else 4.0, false)
			prop.id = "%s_%d_%d" % [kind, building.id, side]
			prop.building_id = -1
			prop.site_id = ""
			result.add_item(prop)
	return result

func add_item(item: Dictionary) -> void:
	item.chunk = chunk_at(item.center, chunk_size)
	if not chunks.has(item.chunk):
		chunks[item.chunk] = []
	chunks[item.chunk].append(items.size())
	items.append(item)

func signature() -> String:
	return var_to_bytes(items).hex_encode().sha256_text()
