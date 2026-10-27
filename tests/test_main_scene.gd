extends SceneTree

## 主场景冒烟测试：实例化 main.tscn，确认世界生成和导航就绪。

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
	var world := main.get_node_or_null("World") as WorldGenerator
	var navigation := main.get_node_or_null("NavigationSystem") as NavigationService
	var ok := world != null and world.network != null and navigation != null
	if ok:
		for _frame in 10:
			if navigation.is_ready():
				break
			await physics_frame
		ok = navigation.is_ready()
	if ok:
		print("PASS main scene nodes=", world.network.nodes.size())
	else:
		printerr("FAIL main scene world=", world != null, " network=", world != null and world.network != null,
			" navigation_ready=", navigation != null and navigation.is_ready())
	main.queue_free()
	quit(0 if ok else 1)
