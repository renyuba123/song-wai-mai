extends SceneTree

## 用游戏本体自动跑一单，导出行为分析页能直接打开的示例。
##
## 用法（在仓库根目录，桌面窗口可见）：
##   Godot --path . --rendering-method gl_compatibility \
##     --script res://tools/record_sample_session.gd
##
## 脚本加载正式的 main.tscn，走真实的导航、订单状态机、交通和
## TelemetryClient：自动接单、沿寻路结果骑行、在商家和顾客处按交互，
## 跑完后把内存里待上报的事件写成页面 JSON，复制一份分析页到
## `exports/game-sample/preview/` 并用默认浏览器打开。
##
## 输出目录在 `exports/`（已被 .gitignore 忽略），不会提交真实运行数据；
## 桌面构建不会联网，事件只留在本机队列里。

const MAIN_SCENE := "res://scenes/main/main.tscn"
const OUT_DIR := "res://exports/game-sample"
const PAGE_DIR := "res://exhibition/analytics"
const CITY_JSON := "res://exhibition/analytics/data/city-118.json"
const TIME_SCALE := 8.0
const MAX_GAME_SECONDS := 900.0
const INTERACT_AT_M := 3.0
const ARRIVE_PAUSE_S := 1.0
const MAX_WAIT_FRAMES := 900

var _main: Node3D = null
var _world: WorldGenerator = null
var _navigation: NavigationService = null
var _player: PlayerController = null
var _orders: OrderManager = null
var _telemetry: TelemetryClient = null
var _session: OrderSession = null

var _path := PackedVector3Array()
var _path_index := 0
var _target_state := -1
var _speed := 0.0
var _pause := 0.0
var _game_elapsed := 0.0
var _last_usec := 0
var _finish_sec := 0.0
var _failed := false


func _initialize() -> void:
	Engine.time_scale = TIME_SCALE
	Engine.max_fps = 60
	_last_usec = Time.get_ticks_usec()
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		_fail("无法加载主场景 %s" % MAIN_SCENE)
		return
	_main = scene.instantiate() as Node3D
	if _main == null:
		_fail("主场景根节点不是 Node3D")
		return
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_world = _main.get_node_or_null("World") as WorldGenerator
	_navigation = _main.get_node_or_null("NavigationSystem") as NavigationService
	_player = _main.get_node_or_null("Player") as PlayerController
	_orders = _main.get_node_or_null("OrderSystem") as OrderManager
	_telemetry = _main.get_node_or_null("Telemetry") as TelemetryClient
	if _world == null or _navigation == null or _player == null or _orders == null:
		_fail("主场景缺少 World / NavigationSystem / Player / OrderSystem")
		return
	if _telemetry == null:
		_fail("主场景没有创建 Telemetry 节点")
		return

	# 桌面构建默认不采集；这里改成 active，让 TelemetryClient 按真实节奏
	# 记录位置、计时点、速度和道路 NPC 数量。HTTPRequest 只在 Web 构建里
	# 创建，所以 flush() 不会把示例发到服务器。
	_telemetry.active = true

	if not _orders.start_game():
		_fail("订单系统没有进入生成流程")
		return
	if not await _wait_for_offer():
		_fail("等待订单生成或接单超时")
		return

	_session = _orders.get_session()
	if _session == null or not _session.is_active():
		_fail("接单后没有活动会话")
		return
	# 自动驾驶自己写位置和速度；关掉玩家物理后，订单管理器不再推进计时，
	# 由本脚本调用 session.advance()，避免同一帧计时两次。
	_player.set_physics_process(false)
	# 自动录像会贴着车流穿过路口，关掉玩家碰撞层避免交通模块反复报“被撞”；
	# 道路上的 NPC 数量仍按位置统计，拥挤度数据不受影响。
	_player.collision_layer = 0
	_player.collision_mask = 0

	_last_usec = Time.get_ticks_usec()
	await _drive()

	var events := _telemetry.get_pending_events()
	if events.is_empty():
		_fail("没有采到任何事件")
		return
	_write_output(events)
	if _failed:
		return
	_open_preview()
	quit(0)


func _wait_for_offer() -> bool:
	for _frame in MAX_WAIT_FRAMES:
		var order := _orders.get_current_order()
		if order != null and _orders.accept_order():
			return true
		await process_frame
	return false


## 沿 NavigationService 给出的路径骑行；到商家/顾客 3 米内调用订单交互。
func _drive() -> void:
	while _game_elapsed < MAX_GAME_SECONDS:
		var delta := _frame_delta()
		_game_elapsed += delta
		if _session == null or not _session.is_active():
			break
		_session.advance(delta)
		if _session.is_finished():
			break
		_tick_drive(delta)
		await process_frame
	# 留几帧给 TelemetryClient 的 _process 记录 pickup/finish 等状态事件。
	for _frame in 4:
		await process_frame


func _tick_drive(delta: float) -> void:
	if _pause > 0.0:
		_pause = maxf(0.0, _pause - delta)
		_player.velocity = Vector3.ZERO
		return

	var position := _player.global_position
	var target := _session.get_target_position()
	var flat := Vector2(target.x - position.x, target.z - position.z)
	var distance := flat.length()
	if distance <= INTERACT_AT_M:
		_player.velocity = Vector3.ZERO
		_speed = 0.0
		if _orders.try_interact(position) and _session.is_active():
			_pause = ARRIVE_PAUSE_S
			_target_state = -1
		return

	if _target_state != _session.state or _path.is_empty():
		_target_state = _session.state
		_path = _navigation.find_path(position, target)
		_path_index = 0
		if _path.is_empty():
			_path.append(target)
		_path_index = _advance_path_index(position)

	var waypoint := _path[mini(_path_index, _path.size() - 1)]
	var to_waypoint := Vector3(waypoint.x - position.x, 0.0, waypoint.z - position.z)
	if to_waypoint.length() < 0.8:
		_path_index += 1
		if _path_index >= _path.size():
			waypoint = target
			to_waypoint = Vector3(target.x - position.x, 0.0, target.z - position.z)
		else:
			waypoint = _path[_path_index]
			to_waypoint = Vector3(waypoint.x - position.x, 0.0, waypoint.z - position.z)
	if to_waypoint.length() < 0.01:
		return

	var direction := to_waypoint.normalized()
	var desired := _desired_speed(distance)
	_speed = move_toward(_speed, desired, 5.5 * delta)
	_speed = clampf(_speed, 0.0, _player.move_speed)

	var step := minf(_speed * delta, to_waypoint.length())
	var next := position + direction * step
	_player.global_position = Vector3(next.x, position.y, next.z)
	_player.velocity = direction * _speed
	_player.rotation.y = atan2(-direction.x, -direction.z)


## 速度不是匀速：接近目标、转弯前减速，骑行途中缓慢起伏，热力轨迹更像真人。
func _desired_speed(distance_to_target: float) -> float:
	var base := _player.move_speed * (
		0.78
		+ 0.16 * sin(_game_elapsed * 0.6)
		+ 0.06 * sin(_game_elapsed * 0.17)
	)
	var slow := clampf(distance_to_target / 18.0, 0.35, 1.0)
	if _path_index + 1 < _path.size():
		var here := _player.global_position
		var current := Vector2(_path[_path_index].x - here.x, _path[_path_index].z - here.z)
		var following := Vector2(
			_path[_path_index + 1].x - _path[_path_index].x,
			_path[_path_index + 1].z - _path[_path_index].z
		)
		if current.length() > 0.1 and following.length() > 0.1 and current.length() < 12.0:
			var turn := absf(current.normalized().angle_to(following.normalized()))
			if turn > deg_to_rad(25.0):
				slow *= 0.6
	return maxf(2.0, base * slow)


func _advance_path_index(position: Vector3) -> int:
	var index := 0
	while index < _path.size() - 1:
		var node := _path[index]
		if Vector2(node.x - position.x, node.z - position.z).length() < 0.8:
			index += 1
		else:
			break
	return index


func _frame_delta() -> float:
	var now := Time.get_ticks_usec()
	var delta := float(now - _last_usec) / 1_000_000.0 * Engine.time_scale
	_last_usec = now
	return clampf(delta, 0.0, 1.0)


func _write_output(events: Array) -> void:
	var first_t := int(events[0].get("t", 0))
	var last_t := int(events[events.size() - 1].get("t", 0))
	for event in events:
		if event.get("n", "") == "finish":
			_finish_sec = float(event.get("p", {}).get("sec", 0.0))
	# 自动录像用了时间加速，事件里的 t 是真实毫秒；页面按游戏内用时展示，
	# 这里线性换算到同一根时间轴，保证耗时、计时点和轨迹对得上。
	var game_ms := _finish_sec * 1000.0
	var real_ms := maxf(1.0, float(last_t - first_t))
	if _finish_sec > 0.0:
		for event in events:
			var offset := float(int(event.get("t", 0)) - first_t)
			event["t"] = roundi(offset * game_ms / real_ms)

	var sample := {
		"meta": {
			"label": "游戏本体自动录制示例（自动驾驶，不是真实访客）",
			"city": 118,
			"demo": true,
			"generated_at": Time.get_datetime_string_from_system(),
		},
		"sessions": [{
			"id": _telemetry.session_id,
			"started_at": Time.get_datetime_string_from_system(),
			"events": events,
			"summary": {
				"seconds": roundi(_finish_sec),
				"result": "ok" if _finish_sec > 0.0 else "unknown",
			},
		}],
	}
	var sample_text := JSON.stringify(sample, "  ")
	if not _write_text(OUT_DIR + "/analytics.json", sample_text):
		return
	_make_preview(sample)


func _make_preview(sample: Dictionary) -> void:
	var preview := OUT_DIR + "/preview"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(preview + "/data"))
	_copy(PAGE_DIR + "/index.html", preview + "/index.html")
	_copy(PAGE_DIR + "/analytics.css", preview + "/analytics.css")
	_copy(PAGE_DIR + "/analytics.js", preview + "/analytics.js")
	var city_text := FileAccess.get_file_as_string(CITY_JSON)
	if city_text.is_empty():
		_fail("读不到城市底图 %s" % CITY_JSON)
		return
	var script := (
		"/* 由 tools/record_sample_session.gd 生成，请勿手工修改。 */\n"
		+ "window.SWM_CITY = " + city_text + ";\n"
		+ "window.SWM_SAMPLE = " + JSON.stringify(sample) + ";\n"
	)
	if not _write_text(preview + "/data/sample-data.js", script):
		return
	var paths := 0
	for event in sample["sessions"][0]["events"]:
		if event.get("n", "") == "pos":
			paths += 1
	print(
		"PASS 游戏本体示例：事件 %d 条，位置采样 %d 个，用时 %d 秒，输出 %s"
		% [sample["sessions"][0]["events"].size(), paths, roundi(_finish_sec), OUT_DIR]
	)


func _open_preview() -> void:
	var path := ProjectSettings.globalize_path(OUT_DIR + "/preview/index.html")
	var uri := "file:///" + path.replace("\\", "/")
	print("OPEN " + path)
	var error := OS.shell_open(uri)
	if error != OK:
		print("WARN 无法自动打开浏览器（%d），请手动打开上面的路径" % error)


func _copy(from: String, to: String) -> void:
	var text := FileAccess.get_file_as_string(from)
	if text.is_empty():
		_fail("复制失败，读不到 %s" % from)
		return
	_write_text(to, text)


func _write_text(path: String, text: String) -> bool:
	var directory := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("无法写入 %s：%s" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	return true


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	printerr("FAIL " + message)
	quit(1)
