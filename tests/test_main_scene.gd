extends SceneTree

## 主场景冒烟测试：实例化 main.tscn，确认世界生成和导航烘焙都完成。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		printerr("FAIL could not load main scene")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var world := main.get_node_or_null("World") as WorldGenerator
	var region := main.get_node_or_null("NavigationSystem/NavigationRegion3D") as NavigationRegion3D
	var ok := (
		world != null
		and world.network != null
		and region != null
		and region.navigation_mesh != null
		and region.navigation_mesh.get_polygon_count() > 0
	)
	if ok:
		print("PASS main scene nodes=", world.network.nodes.size(), " nav_polygons=", region.navigation_mesh.get_polygon_count())
	else:
		printerr("FAIL main scene world=", world != null, " network=", world != null and world.network != null,
			" nav_mesh=", region != null and region.navigation_mesh != null)
	quit(0 if ok else 1)
