extends SceneTree

## 城市人口布局测试：种子 118 的动态布局，检查道路净距、模型重叠、
## 站点落位和入口步道。旧烘焙场景依赖正交路网，改为直接验证运行时布局。

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1


func clear_of_road(rect: Rect2, a: Vector2, b: Vector2, half_width: float) -> bool:
	var safe := rect.grow(half_width)
	if safe.has_point(a) or safe.has_point(b):
		return false
	var corners := [
		safe.position,
		Vector2(safe.end.x, safe.position.y),
		safe.end,
		Vector2(safe.position.x, safe.end.y),
	]
	for index in 4:
		if RoadNetwork._segments_touch_without_node(a, b, corners[index], corners[(index + 1) % 4]):
			return false
	return true


func run() -> void:
	var network := RoadGenerator.generate(Vector2(2400, 2400), 118, 0.5, Vector3(40, 30, 18), false)
	var city := CityGenerator.generate(network)
	var layout := CityPopulationLayout.generate(city)
	check(layout.buildings.size() == city.buildings.size(), "Missing buildings")
	check(layout.items.size() >= layout.buildings.size(), "Missing decorations")
	var footprint_buckets := {}
	for item in layout.items:
		var rect: Rect2 = item.footprint
		for edge in network.edges:
			var a: Vector2 = network.nodes[edge.a]
			var b: Vector2 = network.nodes[edge.b]
			check(
				clear_of_road(rect, a, b, network.widths[edge.kind] * 0.5),
				"Model occupies road/sidewalk/junction " + str(item.id)
			)
		var low := Vector2i(floori(rect.position.x / 50.0), floori(rect.position.y / 50.0))
		var high := Vector2i(floori(rect.end.x / 50.0), floori(rect.end.y / 50.0))
		for x in range(low.x, high.x + 1):
			for y in range(low.y, high.y + 1):
				var key := Vector2i(x, y)
				for previous in footprint_buckets.get(key, []):
					check(not rect.intersects(previous), "Overlapping model footprint " + str(item.id))
				if not footprint_buckets.has(key):
					footprint_buckets[key] = []
				footprint_buckets[key].append(rect)

	for site in city.sites:
		var item: Dictionary = layout.buildings[city.lots[site.lot_id].building_id]
		check(item.site_id == String(site.id), "Unpopulated delivery site " + String(site.id))
		var target := Vector2(item.target.x, item.target.z)
		for other in layout.items:
			check(
				not other.footprint.grow(1.0).has_point(target),
				"Blocked delivery trigger " + String(site.id)
			)
		var door := CityPopulationLayout.door_point(item.footprint, item.yaw)
		for step in range(10):
			var sample := target.lerp(door, float(step) / 10.0)
			for other in layout.items:
				check(
					not other.footprint.has_point(sample),
					"Obstructed delivery approach " + String(site.id)
				)

	var decoration_count := layout.items.size() - layout.buildings.size()
	print(
		"PASS population: %d sites, %d buildings, %d decorations; seed 118 layout" % [
			city.sites.size(), layout.buildings.size(), decoration_count
		]
	)
	quit(1 if failures > 0 else 0)
