#requires -Version 5.1
<#
dsh-upgrade.ps1 — 安全升级 @deepseek-ai/dsh 运行时(补丁层 + 插件层三重保障)

用法(在 F:\DSH\dsh-runtime 目录下):
    .\dsh-upgrade.ps1 -VerifyOnly            # 只做校验,不安装
    .\dsh-upgrade.ps1                        # 保持现版本,重跑 npm install(重放补丁)+ 全量校验
    .\dsh-upgrade.ps1 -Version 0.1.6-rc.1    # 改 package.json 版本号后再安装

流程:
    [1/4] 备份当前 10 个补丁目标文件 + patches/ 到 ~\.dsh\upgrade-backups\<时间戳>\
    [2/4] npm install —— postinstall 的 patch-package 自动重放 patches/;
          补丁与新代码冲突时 patch-package 响亮报错并中止,绝不静默丢补丁
    [3/4] 逐文件验证 10 个补丁特征串(任一缺失 = 补丁未生效,立即失败)
    [4/4] 验证 6 个插件仍在 web profile 登记(目录 + link 依赖 + bundles)

警告: 严禁用 robocopy /MIR 覆盖 node_modules 的方式升级 —— 那会抹掉整个补丁层。
回滚: 把 ~\.dsh\upgrade-backups\<时间戳>\ 里的文件复制回运行时目录,再重跑本脚本 -VerifyOnly。
#>
[CmdletBinding()]
param(
    [string]$Version,
    [switch]$VerifyOnly,
    [string]$BackupRoot = $(if ($env:DSH_UPGRADE_BACKUP_ROOT) { $env:DSH_UPGRADE_BACKUP_ROOT } else { Join-Path $env:USERPROFILE '.dsh\upgrade-backups' })
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not (Test-Path (Join-Path $root 'package.json'))) { throw "请在运行时目录(F:\DSH\dsh-runtime)下运行本脚本" }
if (-not (Test-Path (Join-Path $root 'patches'))) { throw "patches/ 目录缺失 —— 补丁层不存在,拒绝继续,否则全部稳健性修复会丢失" }

# 10 个补丁目标文件及其特征串(来自 patches/*.patch 的新增行)
$patchTargets = @(
    @{ file = 'node_modules/@deepseek-ai/dsh-api-gateway/lib/client.js';                markers = @('reconnect flap') },
    @{ file = 'node_modules/@deepseek-ai/dsh-api-session-controller/lib/client.js';     markers = @('STREAM_RETRY_BLOCKED_CODES') },
    @{ file = 'node_modules/@deepseek-ai/dsh-api-session-controller/lib/index.js';      markers = @('sourceCursor') },
    @{ file = 'node_modules/@deepseek-ai/dsh-client-modules/lib/index.js';              markers = @('validatedArtifact') },
    @{ file = 'node_modules/@deepseek-ai/dsh-client-modules/lib/client.js';             markers = @('manifestRefresh') },
    @{ file = 'node_modules/@deepseek-ai/dsh-client-ui-chat/lib/client.js';             markers = @('noteAssistantDiagnostic') },
    @{ file = 'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js';     markers = @('locationIndex.snapshot') },
    @{ file = 'node_modules/@deepseek-ai/dsh-client-ui-settings-general/lib/client.js'; markers = @('min(1120px', 'IconArchiveOutline20') },
    @{ file = 'node_modules/@deepseek-ai/dsh-client-ui-settings-models/lib/client.js';  markers = @('probeOutcomeLine') },
    @{ file = 'node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js';                   markers = @('max_model_len') }
)
$plugins = 'dsh-user-system-prompt', 'dsh-notification-sounds', 'dsh-custom-background', 'dsh-model-probe', 'dsh-key-rotation', 'dsh-session-archive'

# [1/4] 备份
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $BackupRoot $stamp
New-Item -ItemType Directory -Force $backupRoot | Out-Null
foreach ($t in $patchTargets) {
    $src = Join-Path $root ($t.file.Replace('/', '\'))
    if (Test-Path $src) {
        $dst = Join-Path $backupRoot ($t.file.Replace('/', '\'))
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item $src $dst -Force
    }
}
Copy-Item (Join-Path $root 'patches') (Join-Path $backupRoot 'patches') -Recurse -Force
Write-Host "[1/4] 已备份补丁目标与 patches/ -> $backupRoot"

# [2/4] 安装(可选)
if (-not $VerifyOnly) {
    if ($Version) {
        $pkgPath = Join-Path $root 'package.json'
        $raw = Get-Content $pkgPath -Raw
        $new = [regex]::Replace($raw, '("@deepseek-ai/dsh"\s*:\s*")[^"]+(")', ('$1^' + $Version + '$2'))
        if ($new -eq $raw) { throw "未能改写 package.json 中的 @deepseek-ai/dsh 版本号,请手工修改后重跑" }
        Set-Content -Path $pkgPath -Value $new -Encoding UTF8 -NoNewline
        Write-Host "[2/4] package.json 版本 -> ^$Version"
    }
    Push-Location $root
    try {
        & npm.cmd install --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) {
            throw "npm install 失败(exit $LASTEXITCODE)—— 通常是补丁与新代码冲突而响亮报错。安装未完成 = 旧状态完好无损;按 F:\DSH\dsh-migration\patches-inventory.md 的映射表把修复移植到新代码,再重跑本脚本。"
        }
    } finally { Pop-Location }
    Write-Host "[2/4] npm install 完成(patch-package 已重放 patches/)"
} else {
    Write-Host "[2/4] 跳过安装(-VerifyOnly)"
}

# [3/4] 补丁特征校验
$fail = 0
foreach ($t in $patchTargets) {
    $p = Join-Path $root ($t.file.Replace('/', '\'))
    if (-not (Test-Path $p)) {
        Write-Host ("  [FAIL] {0} : 文件不存在" -f $t.file); $fail++; continue
    }
    $content = Get-Content $p -Raw
    foreach ($m in $t.markers) {
        if ($content.Contains($m)) {
            Write-Host ("  [OK]   {0} : '{1}'" -f $t.file, $m)
        } else {
            Write-Host ("  [FAIL] {0} : 缺特征 '{1}' —— 该补丁未生效" -f $t.file, $m); $fail++
        }
    }
}
if ($fail -gt 0) { throw "[3/4] 校验失败: $fail 处补丁特征缺失,请勿使用本次安装;参照 patches-inventory.md 重新移植后重跑本脚本" }
Write-Host "[3/4] 10 个补丁文件特征全部命中"

# [4/4] 插件层校验
$profPkg = Join-Path $env:USERPROFILE '.dsh\profiles\web\package.json'
if (-not (Test-Path $profPkg)) { throw "[4/4] 找不到 web profile: $profPkg" }
$prof = Get-Content $profPkg -Raw | ConvertFrom-Json
$missing = @()
foreach ($plug in $plugins) {
    if (-not (Test-Path (Join-Path $env:USERPROFILE (".dsh\profiles\web\plugins\" + $plug)))) { $missing += "$plug(插件目录缺失)" }
    $deps = @($prof.dependencies.PSObject.Properties.Name)
    if ($deps -notcontains $plug) { $missing += "$plug(未登记为 link 依赖)" }
    $bundles = @($prof.dsh.profile.bundles)
    if ($bundles -notcontains $plug) { $missing += "$plug(不在 dsh.profile.bundles)" }
}
if ($missing.Count -gt 0) { throw "[4/4] 插件层异常: " + ($missing -join '; ') }
Write-Host "[4/4] 6 个插件登记完好(目录 + 依赖 + bundles)"

Write-Host ""
Write-Host "全部通过。冒烟: dsh web --no-open 后检查设置里的自建分区(系统提示词/提示音/背景/归档)与模型页每行的'测试连接'按钮。"
