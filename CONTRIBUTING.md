# 协作规则

本文件是团队日常开发的约定。改代码之前先确认自己负责的目录和场景文件，避免多人同时改同一个 `.tscn`。各角色从环境准备到交付的具体步骤见 [docs/USER_GUIDE.md](docs/USER_GUIDE.md)。

## 分支

- `main` 是集成分支，只接受通过 PR 的改动。
- 功能开发从最新 `main` 拉短生命周期分支，例如 `feature/worldgen`、`feature/navigation`、`fix/player-collision`。
- 一个分支只做一件事；完成后尽快提交 PR，不长期挂着。
- `road` 保留为改造前的路网原型历史分支，不再作为开发主线。

## 每轮开发日志

每轮对话或开发工作结束后，在 [docs/DEVELOPMENT_LOG.md](docs/DEVELOPMENT_LOG.md) 末尾追加一条记录，至少包含：

- 日期和本地时间
- 这一轮做了什么、为什么
- 修改了哪些目录或文件
- 运行了哪些校验、结果如何
- 对应的提交（commit）

日志用自然中文记录，保留原始需求措辞，不要只写一句“优化代码”。写完日志后，与代码一起提交并推送到当前功能分支。

## 提交与 PR

- 每轮工作结束都提交并推送当前分支；提交信息说明“改了什么”，不要只写“更新”。
- 一个模块或一个完整修复通过校验后，及时创建 PR，不要等所有功能都做完。
- PR 描述写清楚：改了什么、怎么验证、影响哪些模块、是否改了共享文件。
- 合并前确认：路网测试通过、主场景能启动、没有调试残留（临时 `print`、临时改数值、`@tool` 调试节点）。
- 不直接往 `main` 推送；紧急修复也走 PR。

## 远端同步

- 开始一轮工作前执行 `git fetch origin --prune`，确认远端有没有新提交。
- 本地工作区干净时，如果 `main` 有更新，执行 `git pull --rebase`；有未提交改动时先提交或暂存，再同步。
- 同步后如果出现冲突，尤其是 `.tscn` / `.tres` 冲突，先停下来确认冲突节点和双方意图，不要盲目选择一边。
- 长时间不操作后重新开始，也先检查远端，再继续开发。

## 文件所有权

| 模块 | 负责人 | 主要文件 | 不修改 |
|---|---|---|---|
| 世界与交通生成 | A | `scripts/world/`、`scripts/traffic/`、`scenes/world/`、`scenes/traffic/` | 玩家、导航、`main.tscn` |
| 玩家、物理与整合 | B | `scripts/player/`、`scripts/core/`、`scenes/player/`、`scenes/main/main.tscn`、`project.godot` | 世界生成、导航内部实现 |
| 导航 | C | `scripts/navigation/`、`scenes/navigation/` | 车辆/行人场景、玩家场景 |
| 建模 | 美术 | `assets/models/`、`assets/textures/` 中交付的 `.glb` | 任何 `.tscn` |

共享文件（`scenes/main/main.tscn`、`project.godot`、`scripts/core/collision_layers.gd`、`.gitattributes`、`.gitignore`）由整合者统一修改；其他人需要变更时先提出，不要直接改。

## 场景与资产规则

- 同一个 `.tscn` 同一时间只允许一个人编辑；按模块拆分场景所有权。
- 不直接编辑导入的 `.glb` 原始场景；在实例化它的上层场景里加碰撞、脚本、灯光和材质覆盖。
- 建模交付 `.glb` 前统一单位（米）、三角化、应用变换；保留组件实例，不随意炸开。
- 二进制资源必须走 Git LFS；新增文件类型先确认 `.gitattributes` 已覆盖。
- 调试用的临时场景放在 `scenes/dev/<名字>/`，不要混进共享场景。

## 环境准备

```powershell
git lfs install --local
gdmerge git-install
```

`gdmerge` 版本固定为 0.3.6。没有 Rust 工具链的成员可以使用官方 Release 的 Windows 预编译包，但团队内保持同一版本。
