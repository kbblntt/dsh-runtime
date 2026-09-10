# DSH 独立运行时(已脱离 npx)

本目录是 `@deepseek-ai/dsh` 0.1.2-rc.1 的完整独立安装,从 npx 缓存
(`%LOCALAPPDATA%\npm-cache\_npx\1e7f6d9597241db0`)完整复制而来,
不依赖 npx / npm 缓存即可运行。

## 使用

    dsh web              # 启动 Web UI(等价于原来的 npx @deepseek-ai/dsh web)
    dsh --help           # 查看启动器帮助
    dsh web --help       # 查看 web 应用参数(--host/--port/--no-open/--trusted-host)

`dsh` 命令来自本目录的 dsh.cmd / dsh.ps1 / dsh(本目录已加入用户 PATH;
已开的终端需要重开才能生效)。

也可以不经 PATH 直接运行:

    F:\dsh-runtime\dsh.cmd web
    node F:\dsh-runtime\node_modules\@deepseek-ai\dsh\lib\bin.js web

## 机制说明

- `~\.dsh\profiles\node_modules\@deepseek-ai\*` 的 junction 在每次启动时由
  dsh 的 `healProfilesModuleFallback` 自动指向"当前运行安装"的依赖闭包;
  从本目录启动后它们会自动重指向 F:\dsh-runtime,此后删除 npx 缓存不影响运行。
- 当前正在运行的旧实例(从 npx 缓存启动的)不受影响,退出后即可全部切换到本目录。
- 数据(会话、设置、凭据)仍在 `%USERPROFILE%\.dsh`,与安装位置无关。

## 升级

    npx @deepseek-ai/dsh --version     # 先用 npx 装新版进缓存
    robocopy "%LOCALAPPDATA%\npm-cache\_npx\<新版哈希>\node_modules" "F:\dsh-runtime\node_modules" /E /MIR