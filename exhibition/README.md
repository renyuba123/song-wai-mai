# 展览二维码

展览需要三个二维码：

| 编号 | 文件 | 用途 | 当前链接 |
| --- | --- | --- | --- |
| 1 | `qr/output/qr-1-game.png` | 打开游戏本体 | 待部署后替换 |
| 2 | `qr/output/qr-2-video.png` | 打开游戏演示视频 | 占位 |
| 3 | `qr/output/qr-3-analytics.png` | 打开用户行为分析数据 | 占位 |

二维码是纯黑白 PNG，尺寸 720×720，纠错等级 H，四周保留 4 个模块的静区。
打印时建议边长不小于 5 厘米；展板排版时不要裁掉白边。

## 重新生成

链接集中在 `qr/links.json`，改完运行：

```bash
cd exhibition/qr
python generate_qr.py
```

依赖 Python 的 `qrcode` 和 `Pillow`（`python -m pip install "qrcode[pil]"`）。
生成结果覆盖 `qr/output/` 下的三张图，文件名固定。

## 游戏 Web 版

游戏用 Godot 4.7.2 导出 Web 版。注意：.NET 版 Godot 不能导出 Web，
本项目是纯 GDScript，必须用标准版（非 mono）编辑器。

- 导出预设：仓库根目录 `export_presets.cfg`，平台 `Web`，单线程模板
  （不依赖 SharedArrayBuffer，普通静态托管即可运行）。
- 导出模板：`4.7.2.stable` 的 `web_nothreads_release.zip` 和
  `web_nothreads_debug.zip`，放在
  `%APPDATA%/Godot/export_templates/4.7.2.stable/`。
- 导出命令：

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . \
  --export-release "Web" "build/web/index.html"
```

产物在 `build/web/`，约 66 MB，其中 `index.wasm` 约 38 MB、`index.pck` 约 28 MB。
`build/` 不提交。

导出前先拉齐 LFS 资源，否则城市模型会变成指针文件：

```bash
git lfs pull
```

### 手机操作

Web 版在手机浏览器里会启用触屏层 `scripts/ui/touch_controls.gd`：

- 左下摇杆移动；
- 右半屏拖动转视角；
- 右下 `E` 取餐/送达、`R` 重新开始、`Ⅱ` 暂停。

开始菜单、接单和结算仍用界面按钮。触屏层只在配送进行中显示。
桌面端不创建触屏层，仍用 WASD、鼠标和快捷键。

### 中文字体

Web 构建没有系统字体，项目通过 `project.godot` 的
`gui/theme/custom_font` 使用 `assets/fonts/NotoSansSC-Regular.ttf`
（Noto Sans SC，SIL Open Font License 1.1，授权文本见同目录 `OFL.txt`）。
字体随仓库用 Git LFS 保存。

## 部署

国内静态托管需要账号登录。已验证 EdgeOne Pages 单个文件上限 25 MiB，
放不下 38 MB 的 `index.wasm`；CloudBase 静态托管命令行上传没有这个限制，
所以走腾讯云 CloudBase。

```bash
npm install -g @cloudbase/cli --registry=https://registry.npmmirror.com
tcb login
tcb env:list
tcb hosting deploy build/web / -e <环境 ID>
```

部署后默认域名形如 `https://<环境 ID>.tcloudbaseapp.com/`。
把正式地址填入 `qr/links.json` 的 `game.url`，再把 `placeholder` 改成 `false`，
重新运行生成脚本即可得到 1 号二维码的正式版本。

## 行为数据

3 号二维码背后的参观行为记录保存在 CloudBase PostgreSQL 的
`behavior_events` 表里。取数、导成 CSV 和常用查询见
[docs/BEHAVIOR_DATA_EXPORT.md](../docs/BEHAVIOR_DATA_EXPORT.md)。

## 行为分析页

`analytics/` 是 3 号二维码的静态页面，不需要构建，直接打开
`analytics/index.html` 就能看：

- 城市路网底图和本单的起点、取餐点、送达点；
- 玩家轨迹，按采样时的速度着色，热力直接叠在轨迹上；
- 每 30 秒一个计时点及玩家当时的位置；
- 玩家经过路段的 NPC 拥挤度（每百米车辆数）。

页面默认载入 `analytics/data/sample-data.js` 里的演示轨迹，顶部标着
“示例数据”，不是真实访客。真实数据先用 `tools/export_behavior_data.py`
导出 CSV，再用 `tools/build_behavior_page_data.py` 转成页面 JSON，
在页面上点「载入数据」打开；完整步骤见
[docs/BEHAVIOR_DATA_EXPORT.md](../docs/BEHAVIOR_DATA_EXPORT.md#生成分析页数据)。

部署时把整个 `exhibition/analytics/` 目录作为静态站点上传（CloudBase 静态托管），
再把正式地址填进 `qr/links.json` 的 `analytics.url`、把 `placeholder`
改成 `false`，重新生成 3 号二维码。页面上的下载按钮导出的 JSON、CSV 和
PNG 属于内部资料，不要提交进仓库或贴到公开群。

## 待办

- 1 号码等 CloudBase 部署完成后替换链接。
- 2 号码等演示视频上传后替换链接。
- 3 号码等分析页部署到静态托管后替换链接。
