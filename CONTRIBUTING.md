# 协作规则

本文件是团队日常开发的约定。改代码之前先确认自己负责的目录和场景文件，避免多人同时改同一个 `.tscn`。各角色从环境准备到交付的具体步骤见 [docs/USER_GUIDE.md](docs/USER_GUIDE.md)。

## 分支管理

### 基本原则

- `main` 是集成分支，只接受通过 PR 的改动；不直接向 `main` 提交或推送。
- `road` 保留为改造前的路网原型历史分支，不再作为开发主线。
- 所有开发从最新 `main` 拉短生命周期分支，完成一件事就合并并删除，不长期挂着。
- 一个分支只做一件事、只有一个负责人；不要往别人的功能分支上追加提交，需要协作时先沟通。
- 分支名统一为 `<type>/<github-id>-<topic>`，避免多人重名：
  - `feature/jzy-worldgen-blocks`
  - `fix/lisi-player-capsule`
  - `docs/wang-user-guide`
  - `chore/zhao-ci-cleanup`
  - `refactor/chen-navigation-api`
- 类型只使用 `feature`、`fix`、`docs`、`chore`、`refactor`；主题用小写英文和连字符。
- 开始开发前先同步 `main`，分支落后时及时合并最新 `main`；不要在过期分支上攒大量改动。
- 只对自己的分支使用 `rebase` / `force-with-lease`；共享分支不要强推。
- PR 合并后删除对应的本地和远端分支；同一件事不要反复复用已经合并的分支名。

### 本地保护

首次克隆或换电脑后，在仓库根目录执行：

```bash
sh scripts/dev/setup-git-hooks.sh
```

它会把 Git hooks 指向 `.githooks/`，阻止直接在 `main` 上提交和推送。hook 只是本地提醒，不能替代 GitHub 的远端保护；确实需要绕过时使用 `--no-verify`，但不要在 `main` 上绕过。

清理已经合并的本地分支：

```bash
sh scripts/dev/cleanup-merged-branches.sh
```

脚本会先确认工作区干净，然后同步 `main`、删除已合并到 `main` 的本地分支，并提示远端分支需要单独确认后删除。

### 远端保护（仓库 owner）

GitHub 仓库需要由 owner 配置，普通协作者没有权限修改：

- **Settings → General → Pull Requests**：启用 “Automatically delete head branches”，PR 合并后自动删除远端分支。
- **Settings → Branches → Branch protection rules**：为 `main` 添加规则：
  - Require a pull request before merging
  - Require approvals（至少 1 人）
  - Require status checks to pass（选择 `integrity`）
  - Require conversation resolution before merging
  - Block force pushes
  - Restrict deletions
  - 可选：Require linear history
- 如果团队使用 GitHub Team/Enterprise，可进一步限制谁可以推送到 `main`；免费仓库至少应启用上面的 PR 和状态检查要求。

### 远端分支清理

PR 合并后，由创建者或整合者确认没有未合并提交，再删除远端分支：

```bash
git push origin --delete <branch-name>
```

不要删除仍在开发中的分支，也不要删除 `main` 或 `road`。如果 owner 已启用自动删除，PR 合并时 GitHub 会处理，不需要手动执行。

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
- 合并前确认：路网和城市测试通过、主场景能启动、没有调试残留（临时 `print`、临时改数值、`@tool` 调试节点）。
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
| 玩家、物理与整合 | B | `scripts/player/`、`scripts/core/`、`scripts/orders/`、`scenes/player/`、`scenes/main/main.tscn`、`project.godot` | 世界生成、导航内部实现、`SpawnPoint` / `CitySite` 字段 |
| 导航 | C | `scripts/navigation/`、`scenes/navigation/` | 车辆/行人场景、玩家场景 |
| 建模 | 美术 | `assets/models/`、`assets/textures/` 中交付的 `.glb` | 任何 `.tscn` |

共享文件（`scenes/main/main.tscn`、`project.godot`、`scripts/core/collision_layers.gd`、`.gitattributes`、`.gitignore`）由整合者统一修改；其他人需要变更时先提出，不要直接改。

共享契约的维护责任：

- `RoadNetwork` 字段和 `SpawnPoint`、`CitySite` 由 A 维护。
- `CityContent` 及 `CityGenerator` 生成的地块、建筑、站点和玩家起点数据由 A 维护；阶段二新增的 `player_starts` 是共享契约，修改前通知 B、C。
- `RoadNetwork.entrances` 的 `width`、`facing_yaw`、`lot_id` 属于共享契约；修改含义或校验规则前先通知 B、C，并同步更新 `tests/test_contracts.gd` 和 `tests/test_city.gd`。
- `DeliveryOrder` 由 B 维护。
- 输入动作和 `project.godot` 由 B 维护。
- `NavigationService` 查询接口由 C 维护。

契约字段只做新增；修改或删除现有字段、改变单位或坐标约定前，先通知相关模块负责人并补测试。世界数据契约改变后，订单、导航和玩家模块必须能继续通过 `tests/test_contracts.gd`。

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
sh scripts/dev/setup-git-hooks.sh
```

`gdmerge` 版本固定为 0.3.6。没有 Rust 工具链的成员可以使用官方 Release 的 Windows 预编译包，但团队内保持同一版本。
