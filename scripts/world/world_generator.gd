@tool
extends Node3D
class_name WorldGenerator

## 世界生成入口：读取参数、生成 RoadNetwork 和 CityContent，交给
## RoadBuilder / CityBuilder 绘制，然后把同一份路网通过 world_generated
## 信号交给导航和交通模块。

signal world_generated(network: RoadNetwork)

@export var seed: int = 42:
	set(value):
		if seed == value:
			return
		seed = value
		_queue_editor_regeneration()

var map_width_m := 2400.0
var map_height_m := 2400.0
var road_density := 0.5
var main_redline_m := 40.0
var secondary_redline_m := 30.0
var local_redline_m := 18.0
var allow_difficult_entrance_exceptions := false

@onready var road_builder: RoadBuilder = $RoadBuilder
@onready var city_builder: CityBuilder = $CityBuilder

var network: RoadNetwork = null
var city: CityContent = null
var report: Dictionary = {}
var city_report: Dictionary = {}
var _editor_regeneration_queued := false


func _ready() -> void:
	if Engine.is_editor_hint():
		_queue_editor_regeneration()


func _queue_editor_regeneration() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or _editor_regeneration_queued:
		return
	_editor_regeneration_queued = true
	call_deferred("_regenerate_editor_preview")


func _regenerate_editor_preview() -> void:
	_editor_regeneration_queued = false
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	regenerate()


func regenerate() -> void:
	network = RoadGenerator.generate(
		Vector2(map_width_m, map_height_m), seed, road_density,
		Vector3(main_redline_m, secondary_redline_m, local_redline_m),
		allow_difficult_entrance_exceptions
	)
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
