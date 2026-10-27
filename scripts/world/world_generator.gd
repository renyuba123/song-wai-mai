extends Node3D
class_name WorldGenerator

## 世界生成入口：读取参数、生成 RoadNetwork 和 CityContent，交给
## RoadBuilder / CityBuilder 绘制，然后把同一份路网通过 world_generated
## 信号交给导航和交通模块。

signal world_generated(network: RoadNetwork)

@export_group("Map")
@export_range(1200.0, 10000.0, 100.0) var map_width_m := 2400.0
@export_range(1200.0, 10000.0, 100.0) var map_height_m := 2400.0
@export var random_seed := 42
@export_range(0.0, 1.0, 0.05) var road_density := 0.5
@export_range(30.0, 50.0, 1.0) var main_redline_m := 40.0
@export_range(20.0, 40.0, 1.0) var secondary_redline_m := 30.0
@export_range(14.0, 24.0, 1.0) var local_redline_m := 18.0
@export var allow_difficult_entrance_exceptions := false
@export var generate_on_ready := true
@export var generate_city := true

@onready var road_builder: RoadBuilder = $RoadBuilder
@onready var city_builder: CityBuilder = $CityBuilder

var network: RoadNetwork = null
var city: CityContent = null
var report: Dictionary = {}
var city_report: Dictionary = {}


func _ready() -> void:
	if generate_on_ready:
		regenerate()


func regenerate() -> void:
	network = RoadGenerator.generate(
		Vector2(map_width_m, map_height_m), random_seed, road_density,
		Vector3(main_redline_m, secondary_redline_m, local_redline_m),
		allow_difficult_entrance_exceptions
	)
	city = null
	city_report = {}
	if generate_city:
		city = CityGenerator.generate(network)
		var city_errors := city.validate(network)
		city_report = {
			"valid": city_errors.is_empty(),
			"errors": city_errors,
			"lots": city.lots.size(),
			"buildings": city.buildings.size(),
			"sites": city.sites.size(),
			"entrances": network.entrances.size(),
		}
	report = network.validate()
	road_builder.build(network)
	city_builder.build(network, city)
	_print_report()
	world_generated.emit(network)


func _print_report() -> void:
	print("路网校验：", "通过" if report.valid else "失败", "；节点 ", report.nodes, "；路段 ", report.edges)
	for message in report.errors:
		push_error(message)
	for message in report.notes:
		print("说明：", message)
	if not city_report.is_empty():
		print(
			"城市生成：", "通过" if city_report.valid else "失败",
			"；地块 ", city_report.lots, "；建筑 ", city_report.buildings,
			"；站点 ", city_report.sites, "；出入口 ", city_report.entrances
		)
		for message in city_report.errors:
			push_error("城市：" + message)
