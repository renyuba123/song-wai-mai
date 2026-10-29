extends RefCounted
class_name CollisionLayers

## 物理层与掩码的唯一来源。所有模块引用这里的常量，不再各自写魔法数字。

const WORLD_STATIC := 1 << 0
const PLAYER := 1 << 1
const VEHICLE := 1 << 2
const PEDESTRIAN := 1 << 3
const TRIGGER := 1 << 4
const NAVIGATION_OBSTACLE := 1 << 5

const PLAYER_MASK := WORLD_STATIC | VEHICLE
const VEHICLE_MASK := WORLD_STATIC | PLAYER | VEHICLE | PEDESTRIAN
const PEDESTRIAN_MASK := WORLD_STATIC | PLAYER | VEHICLE | PEDESTRIAN

## 静态碰撞体加入这个组，导航系统按组烘焙导航网格。
const NAVIGATION_SOURCE_GROUP := &"navigation_source"
