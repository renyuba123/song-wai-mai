extends Node3D
class_name WorldGenerator

## 世界生成入口：读取参数、生成 RoadNetwork、交给 RoadBuilder 绘制，
## 然后把同一份数据通过 world_generated 信号交给导航和交通模块。

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

@onready var road_builder: RoadBuilder = $RoadBuilder

var network: RoadNetwork = null
var report: Dictionary = {}


func _ready() -> void:
	if generate_on_ready:
		regenerate()


func regenerate() -> void:
	network = RoadGenerator.generate(
		Vector2(map_width_m, map_height_m), random_seed, road_density,
		Vector3(main_redline_m, secondary_redline_m, local_redline_m),
		allow_difficult_entrance_exceptions
	)
	report = network.validate()
	road_builder.build(network)
	_print_report()
	world_generated.emit(network)


func _print_report() -> void:
	print("路网校验：", "通过" if report.valid else "失败", "；节点 ", report.nodes, "；路段 ", report.edges)
	for message in report.errors:
		push_error(message)
	for message in report.notes:
		print("说明：", message)
