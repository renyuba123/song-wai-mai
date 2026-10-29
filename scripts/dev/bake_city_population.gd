extends SceneTree
## Rebuild the committed seed-118 scene; model bounds are normalized, never edited.
const DEST = "res://scenes/city/city_population.tscn"
const PICKUP = ["bakery", "coffee", "Pizza", "Resturant", "mini_market", "confectionery"]
const DELIVERY = ["hotel", "school", "bank", "book_shop", "gym", "cinema", "bar"]
const FILL = ["公寓楼", "Asset_0002", "Asset_0011"]
var cache := {}
var occupied: Array[Rect2] = []
var population: Node3D
var manifest: Array = []

func _initialize() -> void:
	call_deferred("bake")

func bounds(node: Node, transform := Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	if node is Node3D:
		transform = transform * node.transform
	if node is MeshInstance3D and node.mesh:
		result = transform * node.mesh.get_aabb()
	for child in node.get_children():
		var child_bounds := bounds(child, transform)
		if child_bounds.size.length() > 0.0:
			result = child_bounds if result.size.length() == 0.0 else result.merge(child_bounds)
	return result

func asset(path: String) -> Dictionary:
	if not cache.has(path):
		var scene: PackedScene = load(path)
		var node := scene.instantiate()
		cache[path] = {"scene": scene, "bounds": bounds(node)}
		node.free()
	return cache[path]

func owned(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = population

func place(parent: Node3D, path: String, rect: Rect2, yaw: float, height: float, title: String, solid: bool) -> Node3D:
	var info := asset(path)
	var source: AABB = info.bounds
	var basis := Basis(Vector3.UP, yaw + PI)
	var rotated := Transform3D(basis, Vector3.ZERO) * source
	var factor := minf(rect.size.x / rotated.size.x, rect.size.y / rotated.size.z)
	factor = minf(factor, height / source.size.y)
	var size := rotated.size * factor
	var center := rect.get_center()
	if solid:
		var front := Vector2(-sin(yaw), -cos(yaw))
		center += front * (rect.size - Vector2(size.x, size.z)) * 0.5
	var actual := Rect2(center - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))
	assert(rect.grow(0.01).encloses(actual))
	for previous in occupied:
		assert(not actual.intersects(previous), "Overlapping placement: " + title)
	occupied.append(actual)
	var holder := Node3D.new()
	holder.name = title
	owned(parent, holder)
	var model: Node3D = info.scene.instantiate()
	model.name = "Model"
	model.transform = Transform3D(basis.scaled(Vector3.ONE * factor), Vector3.ZERO)
	model.position = Vector3(center.x, 0.03, center.y) - (basis * source.get_center()) * factor
	model.position.y += size.y * 0.5
	owned(holder, model)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = CollisionLayers.WORLD_STATIC
		body.collision_mask = 0
		owned(holder, body)
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		collision.shape = box
		collision.position = Vector3(center.x, size.y * 0.5 + 0.03, center.y)
		owned(body, collision)
	holder.set_meta("footprint", actual)
	holder.set_meta("asset", path)
	return holder

func bake() -> void:
	var network := RoadGenerator.generate(Vector2(2400, 2400), 118, 0.5, Vector3(40, 30, 18), false)
	var city := CityGenerator.generate(network)
	population = Node3D.new()
	population.name = "CityPopulation"
	population.set_meta("city_seed", 118)
	root.add_child(population)
	var buildings := Node3D.new()
	buildings.name = "GeneratedBuildings"
	owned(population, buildings)
	var decorations := Node3D.new()
	decorations.name = "GeneratedDecorations"
	owned(population, decorations)
	var sites := {}
	var focus_edges := {}
	for site in city.sites:
		sites[site.lot_id] = site
		focus_edges[site.road_edge_id] = true
	# Prioritize the actual first delivery, using the same navigation and order seed as Main.
	var preview: Node3D = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(preview)
	await physics_frame
	await physics_frame
	var navigation: NavigationService = preview.get_node("NavigationSystem")
	var first_order := OrderGenerator.generate(city, network, navigation, 1)
	assert(first_order != null)
	var route := navigation.find_path(first_order.start.position, first_order.merchant.spawn_point.position)
	route.append_array(navigation.find_path(first_order.merchant.spawn_point.position, first_order.customer.spawn_point.position))
	print("FIRST ROUTE ", first_order.merchant.id, " -> ", first_order.customer.id, " points=", route.size())
	var route_lots := {}
	for lot in city.lots:
		var center: Vector2 = lot.rect.get_center()
		for i in range(route.size() - 1):
			var a := Vector2(route[i].x, route[i].z)
			var b := Vector2(route[i+1].x, route[i+1].z)
			if center.distance_to(Geometry2D.get_closest_point_to_segment(center, a, b)) < 85.0:
				route_lots[lot.id] = true
				focus_edges[lot.road_edge_id] = true
	preview.free()
	var candidates: Array = city.buildings.duplicate()
	candidates.sort_custom(func(a, b):
		var la = city.lots[a.lot_id]
		var lb = city.lots[b.lot_id]
		var pa = 0 if sites.has(a.lot_id) else (1 if route_lots.has(a.lot_id) else (2 if focus_edges.has(la.road_edge_id) and a.id < CityGenerator.MAX_FRONTAGE_LOTS else 3))
		var pb = 0 if sites.has(b.lot_id) else (1 if route_lots.has(b.lot_id) else (2 if focus_edges.has(lb.road_edge_id) and b.id < CityGenerator.MAX_FRONTAGE_LOTS else 3))
		return pa < pb if pa != pb else a.id < b.id)
	var ids := PackedInt32Array()
	for building in candidates:
		var lot: Dictionary = city.lots[building.lot_id]
		if ids.size() >= 240 and not sites.has(building.lot_id):
			continue
		# Frontage only: preserve distant inexpensive silhouettes.
		if lot.rect.get_center().distance_to(building.rect.get_center()) > 1.0:
			continue
		var path: String
		var title := "Building_%04d" % building.id
		if sites.has(building.lot_id):
			var site: CitySite = sites[building.lot_id]
			var choices = PICKUP if site.kind == CitySite.Kind.MERCHANT else DELIVERY
			var category = "取外卖可用模型" if site.kind == CitySite.Kind.MERCHANT else "收外卖可用模型"
			path = "res://assets/models/%s/%s.glb" % [category, choices[int(String(site.id).get_slice("_", 1)) % choices.size()]]
			title = String(site.id)
			manifest.append({"site": title, "model": path, "trigger": [site.spawn_point.position.x, 0, site.spawn_point.position.z], "building_id": building.id})
		else:
			path = "res://assets/models/其他建筑模型/%s.glb" % FILL[int(building.id) % FILL.size()]
		var instance := place(buildings, path, building.rect, lot.facing_yaw, 16.0 if sites.has(building.lot_id) else 30.0, title, true)
		if sites.has(building.lot_id):
			var site: CitySite = sites[building.lot_id]
			var footprint: Rect2 = instance.get_meta("footprint")
			var target := Vector2(site.spawn_point.position.x, site.spawn_point.position.z)
			var door := CityPopulationLayout.door_point(footprint, lot.facing_yaw)
			var approach := MeshInstance3D.new()
			approach.name = "EntryApproach"
			var paving := BoxMesh.new()
			var length := target.distance_to(door)
			paving.size = Vector3(2.0, 0.015, length)
			approach.mesh = paving
			approach.position = Vector3((target.x + door.x) * 0.5, 0.025, (target.y + door.y) * 0.5)
			approach.rotation.y = lot.facing_yaw
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("d7c8ad")
			approach.material_override = material
			owned(instance, approach)
			var label := Label3D.new()
			label.name = "DeliveryAddress"
			label.text = ("取餐 " if site.kind == CitySite.Kind.MERCHANT else "送达 ") + String(site.id)
			label.font_size = 40
			label.pixel_size = 0.015
			label.position = site.spawn_point.position + Vector3(0, 2.8, 0)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.visibility_range_end = 70.0
			owned(instance, label)
		instance.set_meta("building_id", building.id)
		ids.append(building.id)
		# Two small trees in the lot's side margins; keep the central entry clear.
		if sites.has(building.lot_id) or (focus_edges.has(lot.road_edge_id) and building.id % 4 == 0):
			var rect: Rect2 = building.rect
			for side in [-1, 1]:
				var p := Vector2(rect.position.x - 1.5 if side < 0 else rect.end.x + 1.5, rect.get_center().y)
				if absf(sin(lot.facing_yaw)) > 0.5:
					p = Vector2(rect.get_center().x, rect.position.y - 1.5 if side < 0 else rect.end.y + 1.5)
				var tree_rect := Rect2(p - Vector2.ONE * 0.65, Vector2.ONE * 1.3)
				if lot.rect.encloses(tree_rect):
					place(decorations, "res://assets/models/装饰模型/Asset_0004.glb", tree_rect, 0, 4.0, "Tree_%d_%d" % [building.id, side], false)
	population.set_meta("building_ids", ids)
	var packed := PackedScene.new()
	assert(packed.pack(population) == OK)
	assert(ResourceSaver.save(packed, DEST) == OK)
	var file := FileAccess.open("res://scenes/city/delivery_sites.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("BAKED buildings=", ids.size(), " sites=", manifest.size(), " decorations=", decorations.get_child_count())
	quit()
