<#PSScriptInfo
.VERSION 1.0.0
.GUID 7e38b9f1-8c62-4a53-9e14-d8c7f2a6b10d
.AUTHOR 埃博拉酱-机器人
.COMPANYNAME 一致行动党
.COPYRIGHT (c) 2026 一致行动党。MIT 许可证。
.TAGS PSGallery publish api key secure encrypt DPAPI PowerShell 发布 密钥 加密
.LICENSEURI https://opensource.org/licenses/MIT
.EXTERNALMODULEDEPENDENCIES Microsoft.PowerShell.PSResourceGet
.RELEASENOTES 初始版本。首次输入 API 密钥后自动加密保存（Windows DPAPI，仅本机当前用户可解密），以后无需输入。
#>

<#
.SYNOPSIS
    将 PowerShell 模块发布到 PowerShell Gallery，首次输入 API 密钥后自动加密保存，后续无需再次输入。
.DESCRIPTION
    使用 Export-Clixml 将 PSGallery API 密钥加密保存到本地文件（Windows DPAPI，仅本机当前用户可解密）。
    首次运行提示输入密钥并保存，后续运行自动读取，实现一键发布。密钥文件会自动加入 .gitignore。
.PARAMETER 模块路径
    要发布的模块所在文件夹路径（或 .psd1 清单文件路径）。默认在当前工作目录下查找。
.PARAMETER 自身
    指定此开关时，将 Gallery发布 脚本自身发布到 PowerShell Gallery。
.EXAMPLE
    .\Gallery发布.ps1
    在当前目录下查找模块并发布到 PSGallery。
.EXAMPLE
    .\Gallery发布.ps1 -模块路径 ".\GitHub加速"
    发布 GitHub加速 模块到 PSGallery。
.EXAMPLE
    .\Gallery发布.ps1 -自身
    将 Gallery发布 脚本自身发布到 PSGallery。
#>

[CmdletBinding(DefaultParameterSetName = "模块")]
param(
    [Parameter(Position = 0, ParameterSetName = "模块")]
    [string]$模块路径 = ".",

    [Parameter(Mandatory = $true, ParameterSetName = "自身")]
    [switch]$自身
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# 0. 确定要发布的对象和密钥文件位置
# ============================================================
if ($自身) {
    # 发布自身脚本
    $脚本文件 = $MyInvocation.MyCommand.Path
    if (-not $脚本文件) {
        throw "无法确定脚本文件路径。"
    }
    $脚本文件 = Resolve-Path $脚本文件
    $密钥目录 = Split-Path -Parent $脚本文件
    $发布目标 = "脚本"  # 标记，后续分支处理
}
else {
    # 发布模块
    if (Test-Path -LiteralPath $模块路径 -PathType Container) {
        $模块文件夹 = Resolve-Path $模块路径
    }
    elseif (Test-Path -LiteralPath $模块路径 -PathType Leaf) {
        $模块文件夹 = Split-Path -Parent (Resolve-Path $模块路径)
    }
    else {
        throw "模块路径不存在：$模块路径"
    }

    $清单文件 = Get-ChildItem -LiteralPath $模块文件夹 -Filter "*.psd1" | Select-Object -First 1
    if (-not $清单文件) {
        throw "在 $模块文件夹 中未找到 .psd1 清单文件。"
    }

    $模块信息 = Test-ModuleManifest -Path $清单文件.FullName
    $模块名称 = $模块信息.Name
    $版本 = $模块信息.Version
    $密钥目录 = $模块文件夹
    $发布目标 = "模块"
}

$密钥文件 = Join-Path $密钥目录 ".apikey"

# ============================================================
# 0a. 确保 .apikey 在 .gitignore 中
# ============================================================
$Git目录 = $密钥目录
$Git忽略文件 = $null
while ($Git目录 -and (Split-Path -Parent $Git目录) -ne $Git目录) {
    if (Test-Path -LiteralPath (Join-Path $Git目录 ".git")) {
        $Git忽略文件 = Join-Path $Git目录 ".gitignore"
        break
    }
    $Git目录 = Split-Path -Parent $Git目录
}

if ($Git忽略文件) {
    $已忽略 = $false
    if (Test-Path -LiteralPath $Git忽略文件) {
        $已有行 = Get-Content -LiteralPath $Git忽略文件 | ForEach-Object { $_.Trim() }
        $已忽略 = $已有行 -contains ".apikey"
    }
    if (-not $已忽略) {
        Add-Content -LiteralPath $Git忽略文件 -Value ".apikey"
        Write-Host "已将 .apikey 加入 $Git忽略文件" -ForegroundColor DarkGray
    }
}

# ============================================================
# 1. 尝试从加密文件读取 API 密钥
# ============================================================
$ApiKey = $null
if (Test-Path -LiteralPath $密钥文件) {
    try {
        $安全串 = Import-Clixml -LiteralPath $密钥文件
        $ApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($安全串)
        )
        if (-not $ApiKey) { throw "解密结果为空" }
        Write-Host "已从加密文件读取 API 密钥。" -ForegroundColor Green
    }
    catch {
        Write-Host "加密文件损坏或无法解密，将重新获取。($($_.Exception.Message))" -ForegroundColor Yellow
    }
}

# ============================================================
# 2. 若无密钥则交互输入
# ============================================================
if (-not $ApiKey) {
    Write-Host "请输入 PowerShell Gallery API 密钥：" -ForegroundColor Yellow
    Write-Host "  （获取方式：PowerShell Gallery 右上角 → API Keys → Create）" -ForegroundColor DarkGray
    $安全密钥 = Read-Host -AsSecureString
    $ApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($安全密钥)
    )
    if (-not $ApiKey) {
        throw "未提供 API 密钥，无法发布。"
    }

    # 用 Export-Clixml 保存，原生支持 SecureString DPAPI 加密
    $安全密钥 | Export-Clixml -LiteralPath $密钥文件
    Write-Host "已加密保存（仅本机当前用户可解密）。" -ForegroundColor Green
}

# ============================================================
# 3. 确保 PSResourceGet 已安装
# ============================================================
$新发布模块 = Get-Module -ListAvailable Microsoft.PowerShell.PSResourceGet
if (-not $新发布模块) {
    Write-Host "正在安装 Microsoft.PowerShell.PSResourceGet ..." -ForegroundColor Yellow
    Install-Module Microsoft.PowerShell.PSResourceGet -Repository PSGallery -Scope CurrentUser -Force
}

# ============================================================
# 4. 发布
# ============================================================
if ($自身) {
    Write-Host "正在发布 Gallery发布 脚本到 PSGallery ..."
    Publish-PSResource -Path $脚本文件 -ApiKey $ApiKey -Repository PSGallery
}
else {
    Write-Host "准备发布 $模块名称 v$版本 ..."
    Write-Host "正在发布到 PSGallery ..."
    Publish-PSResource -Path $模块文件夹 -ApiKey $ApiKey -Repository PSGallery
}

Write-Host "发布完成！" -ForegroundColor Green
