extends SceneTree

## 测试用上帝视角：确认调试构建创建节点、切换相机与玩家状态，
## 并且正式构建不会创建该节点。

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载主场景")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var player := main.get_node_or_null("Player") as PlayerController
	var god_view := main.get_node_or_null("TestGodView") as TestGodView
	var debug_build := OS.is_debug_build()
	_expect(player != null, "主场景缺少玩家")
	_expect(god_view != null or not debug_build, "调试构建应创建上帝视角节点")
	_expect(god_view == null or debug_build, "正式构建不应创建上帝视角节点")

	if debug_build and god_view != null and player != null:
		await _check_god_view(god_view, player)

	if _failed:
		printerr("FAIL god view")
	else:
		print("PASS god view debug=", debug_build)
	main.queue_free()
	quit(1 if _failed else 0)


func _check_god_view(god_view: TestGodView, player: PlayerController) -> void:
	var camera := god_view.camera
	_expect(camera != null, "上帝视角缺少相机")
	_expect(not god_view.is_active(), "上帝视角默认应关闭")
	if camera == null:
		return
	_expect(not camera.current, "未启用时上帝视角相机不应为当前相机")
	_expect(player.camera != null and player.camera.current, "未启用时应保持玩家相机")
	_expect(player.is_physics_processing(), "未启用时玩家应正常移动")

	god_view.set_active(true)
	await process_frame
	_expect(god_view.is_active(), "set_active(true) 后应启用")
	_expect(camera.current, "启用后上帝视角相机应为当前相机")
	_expect(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "上帝视角应为正交相机")
	_expect(camera.size > 0.0, "上帝视角尺寸应为正")
	_expect(camera.position.y > 0.0, "上帝视角应位于地图上方")
	_expect(player.camera != null and not player.camera.current, "启用后玩家相机不应为当前相机")
	_expect(not player.is_physics_processing(), "启用后应暂停玩家物理移动")
	_expect(player.velocity == Vector3.ZERO, "启用后应清零玩家速度")
	_expect(player.global_position.y >= RoadNetwork.SURFACE_Y, "玩家不应被上帝视角移动到地下")

	god_view.set_active(false)
	await process_frame
	_expect(not god_view.is_active(), "set_active(false) 后应关闭")
	_expect(not camera.current, "关闭后上帝视角相机不应为当前相机")
	_expect(player.camera != null and player.camera.current, "关闭后应恢复玩家相机")
	_expect(player.is_physics_processing(), "关闭后应恢复玩家物理移动")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL ", message)
