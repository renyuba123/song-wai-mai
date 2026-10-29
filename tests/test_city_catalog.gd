extends SceneTree

## 检查城市模型目录：每个条目都能加载、包围盒有效、分类目录正确，
## 并且同一城市种子下实际用到的建筑模型有足够多样性。

const Catalog = preload("res://scripts/world/city_model_catalog.gd")

var failures := 0


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var seen := {}
	for category in Catalog.MODELS:
		var entries: Array = Catalog.MODELS[category]
		check(not entries.is_empty(), "Empty catalog category: " + category)
		for model in entries:
			var path := String(model.get("path", ""))
			check(not path.is_empty(), "Catalog entry without path in " + category)
			check(ResourceLoader.exists(path), "Missing model: " + path)
			check(not seen.has(path), "Duplicate catalog path: " + path)
			seen[path] = true
			var box: AABB = model.get("bounds", AABB())
			check(box.size.x > 0.01 and box.size.y > 0.01 and box.size.z > 0.01,
				"Invalid bounds: " + path)

	check(Catalog.MODELS["other"].size() >= 40,
		"Expected at least 40 curated buildings, got %d" % Catalog.MODELS["other"].size())
	check(Catalog.MODELS["pickup"].size() >= 7,
		"Expected at least 7 pickup shops, got %d" % Catalog.MODELS["pickup"].size())
	check(Catalog.MODELS["delivery"].size() >= 7,
		"Expected at least 7 delivery sites, got %d" % Catalog.MODELS["delivery"].size())

	var network := RoadGenerator.generate(Vector2(2400, 2400), 118, 0.5, Vector3(40, 30, 18), false)
	var city := CityGenerator.generate(network)
	var layout := CityPopulationLayout.generate(city)
	var used := {}
	for item in layout.buildings:
		var path := String(item.path)
		check(seen.has(path), "Layout used a model outside the catalog: " + path)
		used[path] = true
	check(used.size() >= 40,
		"Seed 118 used only %d distinct building models" % used.size())
	check(layout.signature() == CityPopulationLayout.generate(city).signature(),
		"Catalog layout is not deterministic")

	if failures > 0:
		printerr("FAIL city catalog count=%d" % failures)
		quit(1)
		return
	print("PASS city catalog models=%d distinct_in_seed_118=%d buildings=%d" % [
		seen.size(), used.size(), layout.buildings.size()
	])
	quit(0)
