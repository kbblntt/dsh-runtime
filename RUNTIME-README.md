# DSH 独立运行时（0.1.5-rc.1，插件化架构）

本目录是 `@deepseek-ai/dsh` 的独立安装（最初从 npx 缓存复制，2026-09-10 起改为 npm 管理并升级到 0.1.5-rc.1）。
你的全部自定义修改已**脱离 node_modules**，分为两层：

1. **功能层 = 6 个 dsh 插件**（在 `~/.dsh/profiles/web/plugins/`，快照在 `F:\DSH\dsh-migration\plugins-snapshot\`）：
   | 插件 | 功能 |
   |---|---|
   | `dsh-user-system-prompt` | 自定义系统提示词（设置→系统提示词） |
   | `dsh-notification-sounds` | 任务完成/报错/提权提示音（设置→提示音） |
   | `dsh-custom-background` | 自定义背景壁纸（设置→背景） |
   | `dsh-model-probe` | 模型连通性探测 + 已存 key 读回 + 伴生 key 池（设置→模型探测） |
   | `dsh-key-rotation` | `<ref>_2`…`<ref>_9` 多 key 逐请求轮换（无 UI，宿主面） |
   | `dsh-session-archive` | 归档会话恢复/永久删除（设置→归档） |
2. **稳健性修复层 = 8 个 patch-package 补丁**（在本目录 `patches/`，`npm install` 后由 postinstall 自动重放）：
   api-gateway 重试退避、api-session-controller seq 容忍+resync+**usage 页游标钳制**、client-modules 撕裂重建+boot 图自愈、client-ui-chat 防闪烁、client-ui-conversation timeline healing+压缩按钮、client-ui-settings-general 面板宽度+导航图标、client-ui-settings-models 模型页整页（行级探测/key 读回/伴生池/**使用统计**）、llm-pi-ai 上下文解析增强。

   使用统计与 0.1.5 会话格式迁移的兼容修复（2026-09-11）：v0 旧日志迁移后 seq 重编号、投影缓存降级为 asOfSeq=-1，
   导致 page RPC 对旧会话返回空页、历史用量静默归零。修复 = controller 把 -1/越界游标钳制到日志末尾 +
   usage 缓存升 v4 强制全量重折 + delta 守卫。细节见 `patches-inventory.md` 第三轮附录。

数据（会话/设置/凭据）仍在 `%USERPROFILE%\.dsh`，与安装位置无关。

## 使用

    dsh web              # 启动 Web UI
    dsh --help           # 启动器帮助

`dsh` 命令来自本目录的 dsh / dsh.ps1（本目录已加入用户 PATH）。

## 升级（正常升级，不再覆盖你的修改）

1. 改 `package.json` 里 `@deepseek-ai/dsh` 的版本（或 `npm i @deepseek-ai/dsh@<新版本>`）。
2. `npm install` —— postinstall 会自动跑 `patch-package` 重放 `patches/` 里的补丁。
   - 补丁与新版代码冲突时 patch-package 会**响亮报错**（不会静默丢失）：按
     `F:\DSH\dsh-migration\patches-inventory.md` 的映射表把该修复移植到新代码，
     再 `npx patch-package <包名>` 重新生成补丁。
3. 插件不受升级影响（它们在 `~/.dsh` 里）。若某个插件依赖的官方内部结构在新版变了，
   插件会自检失败并报错（如 dsh-session-archive 的 registry 断言），按 inventory 适配即可。
4. 冒烟：`dsh web --no-open`，打开设置确认六个分区仍在。

**不要再使用 robocopy /MIR 覆盖 node_modules 的旧升级法**——那会抹掉 patch-package 补丁。

## 插件管理

    dsh plugin --profile web add <插件绝对路径>     # 接入（pnpm link + 自动加入 bundles）
    dsh plugin --profile web remove <包名>          # 移除

改插件代码后需重启 `dsh web`（客户端 bundle 在服务端启动时组装）。

## 排障

- 设置里某个自建分区空白：多为该插件 client face 渲染异常（React 边界静默吞错）。
  用 `F:\DSH\dsh-migration\render-sounds-test.js` 同款方法在 Node 里渲染定位。
- Web UI 401：token 一次性，用 `dsh web` 打印的带 token URL 重新打开。
- 完整迁移档案：`F:\DSH\dsh-migration\`（双基线 tarball、37 个原始 diff、清单、组装脚本）。
- 升级前锚点快照：本目录 git 仓库（`git log` 可见 0.1.2 补丁态与 0.1.5 迁移态）。
