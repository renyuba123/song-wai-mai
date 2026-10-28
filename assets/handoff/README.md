# 交接包归档

本目录原样保存 2026-10-28 收到的手工交接包（来源：`E:\Project\Game Work Team\交接包接收\`）。文件只做归档，没有拆分、转换或接入场景；`.gdignore` 让 Godot 跳过整个目录，因此运行或导入项目时不会把这些 FBX 当成可导入资源。

## 目录内容

| 目录 | 内容 |
|---|---|
| `取外卖可用模型/` | 7 个商家建筑 FBX：Bakery、Coffee、Confectionery、Mall、Mini Market、Pizza、Restaurant |
| `收外卖可用模型/` | 7 个顾客设施 FBX：Bank、Bar、Book Shop、Cinema、Gym、Hotel、School |
| `城市/` | `卡通城市建筑设施.fbx`，约 34 MB 的组合城市模型，需要先拆分才能单独使用 |
| `previews/` | 4 份 DeepSeek 3D 预览 HTML：城市地标、临街商铺 12 变体、低识别度背景商铺、八类临街外卖建筑 |

14 个店铺 FBX 在仓库中已有对应的 `.glb` 版本，位于 `assets/models/取外卖可用模型/` 和 `assets/models/收外卖可用模型/`；本目录保留 FBX 源文件，方便后续重新导出或核对。

## 使用约定

- 组合城市模型由建模同事完成拆分并通知后，再导入 Godot 和替换占位建筑；在此之前不要直接引用本目录。
- 预览 HTML 用浏览器直接打开，只作为美术方向参考，不是游戏运行时资源。
- 需要重新导入某个模型时，先把单个 FBX 复制到 `assets/models/` 下的正式目录，再在 Godot 中设置导入参数；不要移动或改写本目录里的归档文件。

相关记录见 `docs/DEVELOPMENT_LOG.md` 的 2026-10-28 交接包条目。
