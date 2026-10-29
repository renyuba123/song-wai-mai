extends SceneTree

## 导出展览行为分析页用的城市底图。
##
## 用法（在仓库根目录）：
##   Godot --headless --path . --script res://tools/export_city_map.gd
##
## 默认导出展览演示用的种子 118：2400 × 2400 米、密度 0.5、红线 40/30/18 米，
## 输出 `exhibition/analytics/data/city-118.json`。游戏里每局的城市种子是随机的，
## 想把某局的本地记录画到对应的路网上，用 `-- --seed <种子> --out <路径>` 导出：
##
##   Godot --headless --path . --script res://tools/export_city_map.gd \
##     -- --seed 123456 --out res://exports/recordings/<会话 ID>/city-123456.json

const RoadGenerator = preload("res://scripts/world/road_generator.gd")
const CityGenerator = preload("res://scripts/world/city_generator.gd")
const OUTPUT := "res://exhibition/analytics/data/city-118.json"
const SEED := 118
const SIZE := Vector2(2400.0, 2400.0)
const DENSITY := 0.5
const WIDTHS := Vector3(40.0, 30.0, 18.0)


func _initialize() -> void:
	var seed_value := SEED
	var output := OUTPUT
	var args := OS.get_cmdline_user_args()
	var index := args.find("--seed")
	if index >= 0 and index + 1 < args.size():
		seed_value = maxi(args[index + 1].to_int(), 1)
	index = args.find("--out")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	var network: RoadNetwork = RoadGenerator.generate(SIZE, seed_value, DENSITY, WIDTHS)
	var city: CityContent = CityGenerator.generate(network)
	if network == null or not network.validate().valid or city == null:
		printerr("FAIL 城市生成失败")
		quit(1)
		return
	var data := {
		"seed": network.seed_value,
		"map": [snappedf(network.map_size.x, 0.1), snappedf(network.map_size.y, 0.1)],
		"widths": [
			snappedf(network.widths.x, 0.1),
			snappedf(network.widths.y, 0.1),
			snappedf(network.widths.z, 0.1),
		],
		"nodes": [],
		"edges": [],
		"sites": [],
		"starts": [],
	}
	for node in network.nodes:
		data.nodes.append([snappedf(node.x, 0.1), snappedf(node.y, 0.1)])
	for edge in network.edges:
		data.edges.append([int(edge.a), int(edge.b), int(edge.kind)])
	for site in city.sites:
		if site.spawn_point == null:
			continue
		data.sites.append({
			"id": String(site.id),
			"k": int(site.kind),
			"x": snappedf(site.spawn_point.position.x, 0.1),
			"z": snappedf(site.spawn_point.position.z, 0.1),
		})
	for start in city.player_starts:
		data.starts.append([
			snappedf(start.position.x, 0.1),
			snappedf(start.position.z, 0.1),
		])
	var directory := ProjectSettings.globalize_path(output.get_base_dir())
	var dir_error := DirAccess.make_dir_recursive_absolute(directory)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		printerr("FAIL 无法创建输出目录：", dir_error)
		quit(1)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("FAIL 无法写入 ", output, "：", FileAccess.get_open_error())
		quit(1)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	print(
		"PASS city map seed=%d nodes=%d edges=%d sites=%d starts=%d -> %s"
		% [
			seed_value, data.nodes.size(), data.edges.size(),
			data.sites.size(), data.starts.size(), output,
		]
	)
	quit(0)
