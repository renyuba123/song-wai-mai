extends Node3D

## 路网演示入口：只负责相机、灯光和调试 UI，生成与绘制交给 World。

@onready var world: WorldGenerator = $World

var _overlay: Label


func _ready() -> void:
	_add_camera_and_light()
	_add_overlay()
	world.world_generated.connect(_on_world_generated)
	world.regenerate()


func _on_world_generated(_network: RoadNetwork) -> void:
	_update_overlay()


func _add_camera_and_light() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(world.map_width_m, world.map_height_m) * 1.45
	camera.position = Vector3(0.0, maxf(world.map_width_m, world.map_height_m) * 0.9, maxf(world.map_width_m, world.map_height_m) * 0.6)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)


func _add_overlay() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	_overlay = Label.new()
	_overlay.position = Vector2(16.0, 16.0)
	_overlay.add_theme_font_size_override("font_size", 19)
	_overlay.add_theme_color_override("font_color", Color.WHITE)
	_overlay.add_theme_color_override("font_shadow_color", Color.BLACK)
	_overlay.add_theme_constant_override("shadow_offset_x", 2)
	_overlay.add_theme_constant_override("shadow_offset_y", 2)
	_overlay.text = "大城市送外卖 · 3D 路网\n生成中……"
	ui.add_child(_overlay)


func _update_overlay() -> void:
	if _overlay == null or world.report.is_empty():
		return
	var city_line := "城市：未生成"
	if not world.city_report.is_empty():
		city_line = "地块 %d · 建筑 %d · 站点 %d · 出入口 %d · 城市规则：%s" % [
			world.city_report.lots, world.city_report.buildings,
			world.city_report.sites, world.city_report.entrances,
			"通过" if world.city_report.valid else "失败"
		]
	_overlay.text = "大城市送外卖 · 3D 路网\n主干路：红　次干路：黄　支路：青\n种子 %d · 节点 %d · 路段 %d · 硬规则：%s\n%s" % [
		world.seed, world.report.nodes, world.report.edges,
		"通过" if world.report.valid else "失败", city_line
	]
