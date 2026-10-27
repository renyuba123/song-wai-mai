extends SceneTree

## 导航查询接口测试：未就绪行为、主场景路径查询和路径长度计算。

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_empty_service()
	await _check_main_scene()
	_check_path_length()
	if _failed:
		printerr("FAIL navigation queries")
	else:
		print("PASS navigation queries")
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL ", message)


func _check_empty_service() -> void:
	var packed := load("res://scenes/navigation/navigation_system.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载导航场景")
		return
	var service := packed.instantiate() as NavigationService
	root.add_child(service)
	await process_frame
	_expect(not service.is_ready(), "未烘焙的导航服务不应就绪")
	_expect(service.find_path(Vector3.ZERO, Vector3(10.0, 0.0, 0.0)).is_empty(), "未就绪时路径应为空")
	_expect(not service.is_reachable(Vector3.ZERO, Vector3(10.0, 0.0, 0.0)), "未就绪时不应报告可达")
	_expect(service.get_closest_point(Vector3.ZERO) == Vector3.INF, "未就绪时最近点应为 Vector3.INF")
	service.queue_free()
	await process_frame


func _check_main_scene() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载主场景")
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	var navigation := main.get_node_or_null("NavigationSystem") as NavigationService
	var world := main.get_node_or_null("World") as WorldGenerator
	if navigation == null or world == null or world.network == null:
		_expect(false, "主场景缺少导航服务或世界数据")
		main.queue_free()
		await process_frame
		return
	var ready := navigation.is_ready()
	for _frame in 10:
		if ready:
			break
		await physics_frame
		ready = navigation.is_ready()
	_expect(ready, "导航在 10 个物理帧内未就绪")
	if not ready:
		main.queue_free()
		await process_frame
		return
	var nodes := world.network.nodes
	var from := Vector3(nodes[0].x, 0.0, nodes[0].y)
	var to := Vector3(nodes[nodes.size() - 1].x, 0.0, nodes[nodes.size() - 1].y)
	var snapped_from := navigation.get_closest_point(from)
	var snapped_to := navigation.get_closest_point(to)
	_expect(snapped_from.is_finite() and snapped_to.is_finite(), "最近可导航点不是有限值")
	var path := navigation.find_path(snapped_from, snapped_to)
	_expect(path.size() >= 2, "路径为空或只有一点：%d" % path.size())
	_expect(navigation.is_reachable(snapped_from, snapped_to), "路网两端应可达")
	_expect(NavigationService.get_path_length(path) > 0.0, "路径长度应大于 0")
	var far_point := navigation.get_closest_point(Vector3(9000.0, 100.0, 9000.0))
	_expect(far_point.is_finite(), "远离网格的最近点应返回有限值")
	main.queue_free()
	await process_frame


func _check_path_length() -> void:
	var diagonal := PackedVector3Array([Vector3.ZERO, Vector3(3.0, 0.0, 4.0)])
	_expect(is_equal_approx(NavigationService.get_path_length(diagonal), 5.0), "3-4-5 路径长度应为 5 米")
	_expect(NavigationService.get_path_length(PackedVector3Array()) == 0.0, "空路径长度应为 0")
	_expect(
		NavigationService.get_path_length(PackedVector3Array([Vector3.ONE])) == 0.0,
		"单点路径长度应为 0"
	)
