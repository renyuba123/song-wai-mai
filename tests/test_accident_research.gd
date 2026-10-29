extends SceneTree

## Hidden developer accident panel grouping and visibility behavior.

var _failed := false
var _panel: AccidentResearchPanel = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_panel = AccidentResearchPanel.new()
	_panel.write_jsonl = false
	root.add_child(_panel)
	await process_frame
	_check_records()
	if _failed:
		printerr("FAIL accident research")
	else:
		print("PASS accident research")
	if _panel != null:
		_panel.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL accident research: ", message)


func _check_records() -> void:
	_expect(not _panel.is_panel_visible(), "研究面板初始应隐藏")
	_panel.record_death(
		"rear_vehicle_collision",
		{
			"context": "evading_pedestrian",
			"speed_mps": 8.4,
			"impact_speed_mps": 11.2,
			"source": "Vehicle_03",
			"position": Vector3(3.0, 0.0, -5.0),
		}
	)
	_panel.record_death(
		"building_collision",
		{
			"context": "normal_riding",
			"speed_mps": 6.1,
			"source": "building",
			"position": Vector3(-4.0, 0.0, 2.0),
		}
	)
	_expect(_panel.get_total_deaths() == 2, "总死亡数统计错误")
	_expect(_panel.get_cause_count("rear_vehicle_collision") == 1, "后方来车统计错误")
	_expect(_panel.get_cause_count("building_collision") == 1, "建筑碰撞统计错误")
	_expect(_panel.get_context_count("evading_pedestrian") == 1, "避让行人情境统计错误")
	_expect(_panel.get_context_count("normal_riding") == 1, "普通骑行情境统计错误")
	var records := _panel.get_records()
	_expect(records.size() == 2, "事故明细条数错误")
	if not records.is_empty():
		_expect(records[0].get("position", []).size() == 3, "事故位置没有序列化为数组")
	_panel.toggle_panel()
	_expect(_panel.is_panel_visible(), "切换后研究面板应显示")
	_expect(_panel.get_summary_text().contains("总死亡 2"), "研究摘要缺少总死亡数")
	_panel.toggle_panel()
	_expect(not _panel.is_panel_visible(), "再次切换后研究面板应隐藏")
