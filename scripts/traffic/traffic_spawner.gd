extends Node3D
class_name TrafficSpawner

## 车辆、行人模块入口。当前只接收路网并输出占位信息；
## 接入车辆/行人 .glb 后，从这里按路网出生点生成实例。

signal traffic_ready

@export var max_vehicles := 0
@export var max_pedestrians := 0

var network: RoadNetwork = null


func build(source_network: RoadNetwork) -> void:
	network = source_network
	print("交通系统：已接入路网（节点 ", network.nodes.size(), "，路段 ", network.edges.size(), "）；等待车辆/行人资产")
	traffic_ready.emit()
