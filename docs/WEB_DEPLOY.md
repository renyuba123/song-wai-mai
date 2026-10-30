# 自动部署 Web 版到服务器

`main` 分支每次更新后，GitHub Actions 会自动导出 Web 版并上传到腾讯云 CloudBase 静态托管。
工作流文件是 [`.github/workflows/deploy-web.yml`](../.github/workflows/deploy-web.yml)。

线上地址：<https://passive-sailfish-d0e1nvt8175333a-1451076912.tcloudbaseapp.com/>

## 触发方式

| 方式 | 说明 |
| --- | --- |
| 推送 `main` | 合并 PR 后自动运行，构建 + 部署 + 页面探活 |
| 手动运行 | 仓库 **Actions → Deploy web build → Run workflow**，可指定分支 |

工作流只导出 `Web` 预设（单线程模板，普通静态托管即可运行），
同一时间只允许一个部署任务，新的推送会取消尚未完成的旧任务。

无论是否配置了部署凭据，工作流都会先构建并把 `build/web` 作为 artifact 保留 7 天；
没配置凭据时只在 Summary 里提示“本轮只构建不部署”，不会失败。

## 仓库需要配置的凭据

部署需要腾讯云账号的 **API 密钥**。密钥只放在 GitHub Secrets 里，
不要写进仓库、Issue、聊天记录或日志。

| 类型 | 名称 | 必填 | 内容 |
| --- | --- | --- | --- |
| Secret | `TCB_SECRET_ID` | 是 | 腾讯云 API 密钥的 SecretId |
| Secret | `TCB_SECRET_KEY` | 是 | 腾讯云 API 密钥的 SecretKey |
| Variable | `TCB_ENV_ID` | 否 | CloudBase 环境 ID，默认 `passive-sailfish-d0e1nvt8175333a` |
| Variable | `TCB_SITE_URL` | 否 | 线上地址，默认上面的默认域名 |

### 获取密钥

1. 登录腾讯云控制台，进入 **访问管理 CAM → 用户 → 用户列表 → 新建用户**，
   类型选“自定义创建”，访问方式勾选 **编程访问**。
2. 在权限策略里授予 CloudBase 相关权限。团队内部使用可以直接给预设策略
   `QcloudTCBFullAccess`；如果希望收窄权限，至少需要静态托管的上传、发布和
   文件校验权限，以及读取环境列表的权限。
3. 创建完成后会显示 **SecretId** 和 **SecretKey**，SecretKey 只显示一次，
   当场复制。密钥泄露时在 CAM 里直接禁用或删除该密钥，重新生成后再更新 Secret。

### 写入 GitHub

在仓库目录执行（需要已登录 `gh`）：

```bash
gh secret set TCB_SECRET_ID --body "<SecretId>"
gh secret set TCB_SECRET_KEY --body "<SecretKey>"
gh variable set TCB_ENV_ID --body "passive-sailfish-d0e1nvt8175333a"
gh variable set TCB_SITE_URL --body "https://passive-sailfish-d0e1nvt8175333a-1451076912.tcloudbaseapp.com"
```

也可以网页操作：**Settings → Secrets and variables → Actions**。
`gh secret list` 能列出已配置的 Secret 名称，但读不到内容。

改完凭据后不会自动重跑，下一次推送 `main` 或在 Actions 页面手动运行即可验证。

## 工作流做了什么

1. 带 LFS 检出仓库，并执行 `git lfs fsck --pointers` 确认资源不是指针文件。
2. 检查 `TCB_SECRET_ID` / `TCB_SECRET_KEY` 是否存在。
3. 下载标准版 Godot `4.7.2-stable`（非 .NET 版）和 `4.7.2.stable` Web 导出模板，
   缓存到 `.ci-godot/` 和 `~/.local/share/godot/export_templates/`。
4. `--headless --path . --import` 后执行 `--export-release "Web" build/web/index.html`，
   并检查 `index.html`、`index.wasm`、`index.pck` 都非空。
5. 上传构建产物 artifact。
6. 用 `tcb login --apiKeyId … --apiKey …` 非交互登录，再执行
   `tcb hosting deploy build/web / -e <环境 ID> --concurrency 5 --retry-count 5 --entry index.html`。
   入口文件 `index.html` 最后上传，避免页面先于资源出现。
   **不要加 `--safe --verify`**：CDN 尚未同步时它会误报所有文件 missing，
   然后按“安全回滚”把整站删到只剩 `.import` 文件（2026-10-29 实际发生过）。
7. 用 `curl` 访问线上地址，确认页面包含 Godot 标记，并且 `index.pck`、`index.wasm`
   都返回 200。

Web 使用 Compatibility 渲染器，没有 Forward+ 的法线缓冲。玩家相机在 Web
运行时会切换到 `assets/Shaders/edge_detection_web.gdshader`，用屏幕颜色梯度
近似描边，保留像素化、量化和抖动效果；桌面版继续使用原 shader。

`:8080` 之类的调试端口不需要开放，静态托管只需要普通 HTTPS 访问。

## 本地手动部署

CI 不可用时仍可在本地导出上传，步骤与展览文档一致：

```bash
# 1. 拉齐 LFS 资源
git lfs pull

# 2. 用标准版（非 mono）Godot 4.7.2 导出
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
Godot_v4.7.2-stable_win64_console.exe --headless --path . \
  --export-release "Web" "build/web/index.html"

# 3. 登录并发布
npm install -g @cloudbase/cli --registry=https://registry.npmmirror.com
tcb login
tcb hosting deploy build/web -e passive-sailfish-d0e1nvt8175333a \
  --concurrency 5 --retry-count 5 --entry index.html
```

同样不要加 `--safe --verify`，原因见上一节第 6 步。

.NET 版 Godot（`Godot_v4.7.2-stable_mono_win64`）不能导出 Web，必须用标准版。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| Summary 提示“本轮只构建不部署” | 仓库还没有 `TCB_SECRET_ID` / `TCB_SECRET_KEY`，按上面的步骤添加 |
| `tcb login` 报密钥错误 | 密钥被禁用或复制时多了空格；在 CAM 重新生成并更新 Secret |
| `git lfs fsck --pointers` 失败 | 有 LFS 文件没真正上传，本地执行 `git lfs push origin --all` 后重试 |
| 导出报模板缺失 | 工作流缓存里模板不完整，删掉 `godot-4.7.2-stable-web-templates` 缓存重跑 |
| 页面打不开或 404 | 确认 `-e` 的环境 ID 与 `TCB_SITE_URL` 指向同一个环境 |
| 部署日志报 `一致性校验失败：missing=...` 后整站 404 | `--safe --verify` 在 CDN 同步前误判并回滚。去掉这两个参数直接上传，入口文件用 `--entry index.html` 放最后；仓库已在 2026-10-29 修正工作流 |
| 页面能开但黑屏 | 打开浏览器控制台看 `index.wasm` 是否 404 或 MIME 类型不对；必要时在托管控制台检查文件名大小写 |

## 与展览二维码的关系

1 号二维码的链接写在 `exhibition/qr/links.json` 的 `game.url`。
线上地址没有变化时，自动部署不影响二维码；如果以后更换环境或域名，
更新 `links.json` 后按 `exhibition/README.md` 重新生成二维码。
