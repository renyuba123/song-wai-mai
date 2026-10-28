@tool
extends Node3D
class_name CityStreaming
## Only visuals stream. Layout, navigation, task data and simple collisions stay resident.
@export_range(25, 400, 25) var chunk_size := 100.0
@export_range(0, 5) var load_radius := 2
@export_range(1, 8) var unload_radius := 3
@export_range(0.05, 2.0) var stream_update_interval := 0.2
@export var enable_streaming := true
@export_range(1, 20) var instances_per_frame := 2
@export_range(0.5, 20.0) var frame_budget_ms := 3.0
@export_enum("全城简化", "局部精细", "全城精细（昂贵）") var editor_preview := 0
@export var preview_position := Vector3.ZERO
@export_tool_button("刷新预览", "Reload") var refresh_action = refresh_preview
var layout: CityPopulationLayout
var loaded_chunks: Dictionary = {}
var pending: Array[int] = []
var resources: Dictionary = {}
var requested: Dictionary = {}
var failed: Dictionary = {}
var focus := Vector3.ZERO
var _elapsed := 0.0
var _builder: CityBuilder
var _player: Node3D
var _all_detail := false
var last_batch_ms := 0.0
var peak_batch_ms := 0.0

func refresh_preview() -> void:
	if is_inside_tree():
		get_parent().regenerate()

func configure(data: CityPopulationLayout, builder: CityBuilder, start: Vector3) -> void:
	clear_visuals()
	layout = data
	_builder = builder
	_player = get_parent().get_parent().get_node_or_null("Player")
	_all_detail = not enable_streaming
	if Engine.is_editor_hint():
		_all_detail = editor_preview == 2
		if editor_preview == 0:
			return
		start = preview_position
	update_focus(start)

func clear_visuals() -> void:
	pending.clear()
	for key in loaded_chunks.keys():
		unload_chunk(key)

func unload_chunk(key: Vector2i) -> void:
	var chunk: Node3D = loaded_chunks[key]
	for child in chunk.get_children():
		var id := int(child.get_meta("building_id", -1))
		if is_instance_valid(_builder) and id >= 0:
			_builder.set_detail_visible(id, false)
	remove_child(chunk)
	chunk.queue_free()
	loaded_chunks.erase(key)

func _process(delta: float) -> void:
	if layout == null or (Engine.is_editor_hint() and editor_preview == 0):
		return
	_elapsed += delta
	if _elapsed >= stream_update_interval:
		_elapsed = 0
		if not Engine.is_editor_hint() and is_instance_valid(_player):
			update_focus(get_parent().to_local(_player.global_position))
	process_pending()

func update_focus(position: Vector3) -> void:
	if layout == null:
		return
	focus = position
	var center := CityPopulationLayout.chunk_at(position, layout.chunk_size)
	var unload_distance := maxi(unload_radius, load_radius + 1)
	for key in loaded_chunks.keys():
		if not _all_detail and maxi(absi(key.x-center.x), absi(key.y-center.y)) > unload_distance:
			unload_chunk(key)
	for key in layout.chunks:
		if not _all_detail and maxi(absi(key.x-center.x), absi(key.y-center.y)) > load_radius:
			continue
		if loaded_chunks.has(key):
			continue
		var chunk := Node3D.new()
		chunk.name = "Chunk_%d_%d" % [key.x, key.y]
		add_child(chunk)
		loaded_chunks[key] = chunk
		for index in layout.chunks[key]:
			pending.append(index)
	pending = pending.filter(func(index): return loaded_chunks.has(layout.items[index].chunk))
	# Nearest tasks first; queue order never changes layout or model choice.
	pending.sort_custom(func(a, b): return layout.items[a].center.distance_squared_to(focus) < layout.items[b].center.distance_squared_to(focus))

func process_pending() -> void:
	var begin := Time.get_ticks_usec()
	var count := 0
	var attempts := pending.size()
	while not pending.is_empty() and count < instances_per_frame and attempts > 0:
		if (Time.get_ticks_usec() - begin) / 1000.0 >= frame_budget_ms:
			break
		attempts -= 1
		var index: int = pending.pop_front()
		var item: Dictionary = layout.items[index]
		var path: String = item.path
		if failed.has(path):
			continue # Keep the low-detail representation on resource failure.
		# Editor imports can overlap preview refreshes; load one cached resource on the main thread there.
		if Engine.is_editor_hint() and not resources.has(path):
			resources[path] = load(path)
		if not resources.has(path):
			if not requested.has(path):
				var error := ResourceLoader.load_threaded_request(path, "PackedScene")
				if error != OK:
					failed[path] = true
					push_error("City model request failed: " + path)
					continue
				requested[path] = true
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				resources[path] = ResourceLoader.load_threaded_get(path)
			elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				failed[path] = true
				push_error("City model load failed: " + path)
				continue
			else:
				pending.append(index)
				continue
		var holder := Node3D.new()
		holder.name = item.id
		holder.transform = item.transform
		holder.set_meta("building_id", item.building_id)
		var model: Node3D = resources[path].instantiate()
		holder.add_child(model)
		loaded_chunks[item.chunk].add_child(holder)
		if item.building_id >= 0:
			_builder.set_detail_visible(item.building_id, true)
		count += 1
	last_batch_ms = (Time.get_ticks_usec() - begin) / 1000.0
	peak_batch_ms = maxf(peak_batch_ms, last_batch_ms)

func instance_count() -> int:
	var count := 0
	for chunk in loaded_chunks.values():
		count += chunk.get_child_count()
	return count

func _exit_tree() -> void:
	# Finish outstanding resource requests before engine shutdown; no SceneTree work on workers.
	for path in requested:
		if not resources.has(path) and not failed.has(path):
			resources[path] = ResourceLoader.load_threaded_get(path)
