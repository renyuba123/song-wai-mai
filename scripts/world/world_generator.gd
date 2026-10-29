@tool
extends Node3D
class_name WorldGenerator

## 世界生成入口：读取参数、生成 RoadNetwork 和 CityContent，交给
## RoadBuilder / CityBuilder 绘制，然后把同一份路网通过 world_generated
## 信号交给导航和交通模块。

signal world_generated(network: RoadNetwork)

@export var seed: int = 42
@export_tool_button("重新生成城市", "Reload") var regenerate_action = regenerate

var map_width_m := 2400.0
var map_height_m := 2400.0
var road_density := 0.5
var main_redline_m := 40.0
var secondary_redline_m := 30.0
var local_redline_m := 18.0
var allow_difficult_entrance_exceptions := false

@onready var road_builder: RoadBuilder = $RoadBuilder
@onready var streaming: CityStreaming = $CityStreaming
@onready var city_builder: CityBuilder = $CityBuilder

var network: RoadNetwork = null
var city: CityContent = null
var report: Dictionary = {}
var city_report: Dictionary = {}
var site_signage: SiteSignage = null
var _editor_regeneration_queued := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		# 店名牌只是运行时视觉提示；编辑器预览不创建，避免把节点写进主场景。
		site_signage = _ensure_site_signage()
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
	var layout := CityPopulationLayout.generate(city, streaming.chunk_size)
	SiteNaming.apply(city, layout)
	city_builder.population_layout = layout
	city_builder.build(network, city)
	streaming.configure(layout, city_builder, city.player_start.position)
	if site_signage != null:
		site_signage.build(city)
	_print_report()
	world_generated.emit(network)


func get_site_signage() -> SiteSignage:
	## 订单管理器用它高亮当前目标；编辑器预览里为 null。
	return site_signage


func _ensure_site_signage() -> SiteSignage:
	var node := get_node_or_null("SiteSignage") as SiteSignage
	if node == null:
		node = SiteSignage.new()
		node.name = "SiteSignage"
		add_child(node)
	return node


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
