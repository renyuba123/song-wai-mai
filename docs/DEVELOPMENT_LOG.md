# 开发日志

本文件按轮次追加。每轮记录需求、改动、校验结果和对应提交，规则见 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 2026-10-27 16:36 模块化改造与协作规则

**本轮需求（原文）：** 执行改造操作，同时新增规则：编写log，每轮对话完成后编写，简要说明修改，并同步提交并推送；定期提交推送与PR，时机自行确认；监控远端，出现新的更新时拉取更新。

**做了什么：**

- 从 `road` 分支建立 `refactor/modular-base`，合并 `main` 的最新基础提交，保留路网原型并解决删除/修改冲突。
- 将 `scripts/road_network.gd` 从静态工具类改为 `RoadNetwork` Resource，作为生成、绘制、碰撞和导航共享的数据。
- 新增 `RoadGenerator`（只生成数据）、`RoadBuilder`（只绘制道路和碰撞）、`WorldGenerator`（参数入口与信号）。
- 新增 `scenes/main/main.tscn`、`scenes/world/world.tscn`，主场景负责装配世界、玩家、导航和交通。
- 新增第一人称玩家骨架 `scripts/player/player_controller.gd` 和 `scenes/player/player.tscn`。
- 新增导航模块 `scripts/navigation/navigation_service.gd`，从静态道路碰撞体烘焙导航网格；车辆/行人入口 `scripts/traffic/traffic_spawner.gd` 暂为占位。
- 新增碰撞层常量和层名，统一玩家、车辆、行人、静态几何等掩码。
- 路网演示移到 `scenes/demo/city_road_demo.tscn`，保持按 F6 可运行。
- 新增 `CONTRIBUTING.md`，写明分支、每轮日志、提交推送、PR、远端同步和文件所有权规则。
- 更新 `README.md`，补充目录结构、运行方式和测试命令。

**修改目录：** `scripts/core/`、`scripts/world/`、`scripts/player/`、`scripts/navigation/`、`scripts/traffic/`、`scripts/demo/`、`scenes/main/`、`scenes/world/`、`scenes/player/`、`scenes/navigation/`、`scenes/traffic/`、`scenes/demo/`、`tests/`、`docs/`、`project.godot`、`README.md`、`CONTRIBUTING.md`。

**校验：**

- 路网测试通过：

```text
PASS seed=42 nodes=153 edges=220 kinds=[48, 108, 64]
PASS seed=1 nodes=27 edges=32 kinds=[8, 20, 4]
PASS seed=73 nodes=307 edges=466 kinds=[110, 196, 160]
```

- 主场景冒烟测试通过：`PASS main scene nodes=153 nav_polygons=624`。
- 导航烘焙一度因默认体素过细触发 Godot 崩溃保护，改为 4 米体素，并把地面从导航源中分离后通过。

**提交：** `ec9e9e5 refactor: split road prototype into modular world skeleton`

**远端同步：** 准备推送时发现 `origin/road` 新增 `fd164ad Add LFS and Godot scene integrity checks`，已合并进本分支并解决 `README.md` 冲突；新增的 `.github/workflows/repository-integrity.yml` 已纳入。

**推送：** 尝试 `git push -u origin refactor/modular-base` 失败，GitHub 返回 `Permission to renyuba123/song-wai-mai.git denied to jzy070407`（403）。本地提交已就绪，需要仓库 owner 把 `jzy070407` 加为 collaborator，或切换到有写权限的账号后重新推送并创建 PR。

**下一步：** 获得推送权限后推送 `refactor/modular-base` 并创建 PR；之后按 A（世界与交通）、B（玩家/物理/整合）、C（导航）划分目录继续开发，先补地块和订单起点/终点选择。
