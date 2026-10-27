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

## 2026-10-27 16:47 新增各角色开发者使用指南

**本轮需求（原文）：** 顺手先加一个使用指南，详细写出各类型开发者的操作方法与注意事项。

**做了什么：**

- 新增 `docs/USER_GUIDE.md`，按建模手、世界与交通生成、玩家/物理/整合、导航、技术美术/资源整合分别写明职责目录、操作步骤、交付标准、协作边界和常见问题。
- 指南包含所有人共用的环境准备、分支与同步、场景文件规则、LFS 规则、提交前检查清单和故障排查。
- 建模部分写清 SketchUp/Rhino 导出 `.glb` 的单位、朝向、原点、三角化、变换、命名、面数、贴图和交付验收要求。
- 在 `README.md` 的目录结构和文档链接、`CONTRIBUTING.md` 开头补上使用指南入口。

**修改目录：** `docs/`、`README.md`、`CONTRIBUTING.md`。

**远端同步：** 开始本轮前监控到 `origin/main` 从 `2212daf` 前进到 `67bc997 Add LFS and scene overlap checks to CI`，已合并进 `refactor/modular-base`，合并提交为 `e2111bf`。

**校验：** 文档改动不涉及运行时代码，仍重新执行了两项检查：

```text
PASS seed=42 nodes=153 edges=220 kinds=[48, 108, 64]
PASS seed=1 nodes=27 edges=32 kinds=[8, 20, 4]
PASS seed=73 nodes=307 edges=466 kinds=[110, 196, 160]
PASS main scene nodes=153 nav_polygons=624
```

**提交：** `f7e73fe docs: add role-based developer guide`；本条日志单独提交。

**推送：** `refactor/modular-base` 已成功推送到 `origin`，并设置为跟踪 `origin/refactor/modular-base`。首次推送因远端 LFS locking API 返回 EOF 失败，按 Git LFS 提示在本仓库设置 `lfs.https://github.com/renyuba123/song-wai-mai.git/info/lfs.locksverify=false` 后成功；此前 GitHub 403 写权限问题已不再出现。

**PR：** 分支已推送，PR 创建入口为 <https://github.com/renyuba123/song-wai-mai/compare/main...refactor/modular-base?expand=1>。当前环境没有 `gh` CLI，自动模式也不允许提取 Git 凭据调用 GitHub API，因此 PR 尚未自动创建；安装并登录 `gh`，或由有权限的成员打开上述链接即可补建。
