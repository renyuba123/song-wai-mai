extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL streaming: ", message)
func _initialize() -> void:
	call_deferred("run")

func spatial(layout: CityPopulationLayout, network: RoadNetwork, city: CityContent) -> void:
	var buckets := {}
	for item in layout.items:
		var rect: Rect2 = item.footprint
		for edge in network.edges:
			var a: Vector2 = network.nodes[edge.a]
			var b: Vector2 = network.nodes[edge.b]
			check(not rect.intersects(Rect2(a.min(b), (a-b).abs()).grow(network.widths[edge.kind]*0.5)), "road encroachment " + item.id)
		var low := Vector2i(floori(rect.position.x / 50), floori(rect.position.y / 50))
		var high := Vector2i(floori(rect.end.x / 50), floori(rect.end.y / 50))
		for x in range(low.x, high.x+1):
			for y in range(low.y, high.y+1):
				var key := Vector2i(x,y)
				for other in buckets.get(key, []):
					check(not rect.intersects(other), "model overlap " + item.id)
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(rect)
	for site in city.sites:
		var item: Dictionary = layout.buildings[city.lots[site.lot_id].building_id]
		check(item.site_id == String(site.id), "site identity")
		var rect: Rect2 = item.footprint
		var target := Vector2(item.target.x, item.target.z)
		var door := rect.get_center() + Vector2(-sin(item.yaw), -cos(item.yaw)) * rect.size * 0.5
		for other in layout.items:
			check(not other.footprint.grow(1).has_point(target), "trigger clearance")
			for step in range(10):
				check(not other.footprint.has_point(target.lerp(door, step/10.0)), "entry approach")

func drain(stream: CityStreaming) -> void:
	for frame in 2400:
		stream.process_pending()
		if stream.pending.is_empty():
			break
		await process_frame
	check(stream.pending.is_empty(), "loading timed out")
	check(stream.failed.is_empty(), "resource loading failed")

func run() -> void:
	var signatures := {}
	for seed_value in [118, 1, 42, 2026]:
		var begin := Time.get_ticks_msec()
		var network := RoadGenerator.generate(Vector2(2400,2400), seed_value, 0.5, Vector3(40,30,18), false)
		var city := CityGenerator.generate(network)
		var layout := CityPopulationLayout.generate(city)
		var elapsed := Time.get_ticks_msec() - begin
		check(layout.buildings.size() == city.buildings.size(), "incomplete city")
		check(layout.signature() == CityPopulationLayout.generate(city).signature(), "same seed differs")
		check(not signatures.has(layout.signature()), "different seeds identical")
		signatures[layout.signature()] = true
		spatial(layout, network, city)
		print("LAYOUT seed=", seed_value, " buildings=", layout.buildings.size(), " props=", layout.items.size()-layout.buildings.size(), " chunks=", layout.chunks.size(), " generation_ms=", elapsed)
		var main = load("res://scenes/main/main.tscn").instantiate()
		main.get_node("World").seed = seed_value
		root.add_child(main)
		await physics_frame
		var world: WorldGenerator = main.get_node("World")
		var stream: CityStreaming = world.streaming
		stream.set_process(false)
		var nav: NavigationService = main.get_node("NavigationSystem")
		var order := OrderGenerator.generate(world.city, world.network, nav, 1)
		for wait_frame in 120:
			if order != null:
				break
			await physics_frame
			await process_frame
			order = OrderGenerator.generate(world.city, world.network, nav, 1)
		check(order != null, "order generation")
		if order == null:
			main.free()
			continue
		var session := OrderSession.new(order, 5)
		var before := stream.layout.signature()
		stream.update_focus(order.merchant.spawn_point.position)
		await drain(stream)
		var initial_count := stream.instance_count()
		var merchant_item: Dictionary = stream.layout.buildings[world.city.lots[order.merchant.lot_id].building_id]
		check(stream.loaded_chunks.has(merchant_item.chunk), "merchant chunk missing")
		var first_transform: Transform3D = stream.loaded_chunks[merchant_item.chunk].get_node(merchant_item.id).transform
		check(session.try_interact(order.merchant.spawn_point.position), "pickup")
		stream.update_focus(Vector3(10000,0,10000))
		await process_frame
		check(stream.instance_count() == 0 and stream.loaded_chunks.is_empty(), "far chunks retained")
		check(session.state == OrderSession.State.TO_CUSTOMER, "unload corrupted order")
		stream.update_focus(order.customer.spawn_point.position)
		await drain(stream)
		check(session.try_interact(order.customer.spawn_point.position), "delivery")
		check(session.state == OrderSession.State.DELIVERED, "delivery did not finish")
		stream.update_focus(Vector3(10000,0,10000))
		stream.update_focus(order.merchant.spawn_point.position)
		stream.pending.reverse() # Deliberately change load order on revisit.
		await drain(stream)
		check(stream.instance_count() == initial_count, "resident count grows after revisit")
		check(stream.loaded_chunks[merchant_item.chunk].get_node(merchant_item.id).transform == first_transform, "revisit changed transform")
		check(stream.layout.signature() == before, "streaming changed layout")
		# Boundary hysteresis: already loaded chunks remain until beyond the outer radius.
		var center := CityPopulationLayout.chunk_at(order.merchant.spawn_point.position, stream.chunk_size)
		var retained := stream.loaded_chunks.keys()
		stream.update_focus(Vector3((center.x+1)*100+0.1,0,center.y*100+0.1))
		for key in retained:
			check(stream.loaded_chunks.has(key), "boundary thrashing")
		for step in range(12):
			var position := Vector3(-1000 + step * 180, 0, -800 + (step % 4) * 450)
			stream.update_focus(position)
			var count_before := stream.instance_count()
			stream.process_pending()
			check(stream.instance_count() - count_before <= stream.instances_per_frame, "unbounded frame batch")
			var bound := 0
			for key in stream.loaded_chunks:
				bound += stream.layout.chunks[key].size()
			check(stream.instance_count() <= bound, "resident count exceeds selected chunks")
			check(stream.loaded_chunks.size() <= 49, "exploration retains distant chunks")
			await process_frame
		stream.update_focus(Vector3(10000,0,10000))
		await process_frame
		check(stream.pending.is_empty() and stream.instance_count() == 0, "stale exploration queue")
		print("STREAM seed=", seed_value, " near_instances=", initial_count, " cached_models=", stream.resources.size(), " peak_batch_ms=", stream.peak_batch_ms)
		main.free()
		await process_frame
	print("PASS city streaming" if failures == 0 else "FAIL city streaming count=%d" % failures)
	quit(0 if failures == 0 else 1)
