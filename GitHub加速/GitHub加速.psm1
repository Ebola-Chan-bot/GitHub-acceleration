# GitHub加速 - 通过多个 GitHub 镜像站点自动尝试 git fetch
# 按历史成功率智能排序，实现国内无障碍拉取 GitHub 仓库。

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# 内部辅助函数
# ============================================================

function 执行-Git命令 {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$参数
    )

    & git @参数
    if ($LASTEXITCODE -ne 0) {
        throw "git $($参数 -join ' ') 执行失败。"
    }
}

function 尝试-Git命令 {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$参数
    )

    & git @参数
    return $LASTEXITCODE -eq 0
}

function 读取-Git文本 {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$参数
    )

    $输出 = & git @参数
    if ($LASTEXITCODE -ne 0) {
        throw "git $($参数 -join ' ') 执行失败。"
    }

    return ($输出 -join "`n").Trim()
}

function 新建-镜像记录 {
    return [pscustomobject]@{
        版本   = 1
        最后更新 = ""
        镜像   = [pscustomobject]@{}
    }
}

function 确保-对象属性 {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$对象,

        [Parameter(Mandatory = $true)]
        [string]$属性名,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $默认值
    )

    if ($null -eq $对象.PSObject.Properties[$属性名]) {
        $对象 | Add-Member -NotePropertyName $属性名 -NotePropertyValue $默认值
    }
}

function 确保-记录结构 {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$记录
    )

    确保-对象属性 $记录 "版本" 1
    确保-对象属性 $记录 "最后更新" ""
    确保-对象属性 $记录 "镜像" ([pscustomobject]@{})

    if ($null -eq $记录.镜像) {
        $记录.镜像 = [pscustomobject]@{}
    }

    return $记录
}

function 确保-镜像统计结构 {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$统计
    )

    确保-对象属性 $统计 "成功次数" 0
    确保-对象属性 $统计 "失败次数" 0
    确保-对象属性 $统计 "最近结果" ""
    确保-对象属性 $统计 "最近耗时毫秒" $null
    确保-对象属性 $统计 "最后尝试时间" ""
    确保-对象属性 $统计 "最后成功时间" ""
    确保-对象属性 $统计 "最后失败时间" ""

    return $统计
}

function 读取-镜像记录 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$路径
    )

    if (-not (Test-Path -LiteralPath $路径)) {
        return 新建-镜像记录
    }

    $内容 = Get-Content -Raw -LiteralPath $路径
    if ([string]::IsNullOrWhiteSpace($内容)) {
        return 新建-镜像记录
    }

    $记录 = $内容 | ConvertFrom-Json
    return 确保-记录结构 $记录
}

function 保存-镜像记录 {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$记录,

        [Parameter(Mandatory = $true)]
        [string]$路径
    )

    $目录 = Split-Path -Parent $路径
    if (-not [string]::IsNullOrWhiteSpace($目录) -and -not (Test-Path -LiteralPath $目录)) {
        New-Item -ItemType Directory -Path $目录 | Out-Null
    }

    $记录.最后更新 = (Get-Date).ToString("o")
    $记录 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $路径 -Encoding UTF8
}

function 读取-镜像统计 {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$记录,

        [Parameter(Mandatory = $true)]
        [string]$镜像地址
    )

    $镜像属性 = $记录.镜像.PSObject.Properties[$镜像地址]
    if ($null -eq $镜像属性) {
        $统计 = [pscustomobject]@{}
        $记录.镜像 | Add-Member -NotePropertyName $镜像地址 -NotePropertyValue $统计
        return 确保-镜像统计结构 $统计
    }

    return 确保-镜像统计结构 $镜像属性.Value
}

function 计算-镜像评分 {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$统计
    )

    # 无记录的镜像视为成功失败各 1 次（初始评分 0.5）
    $成功次数 = [int]$统计.成功次数
    $失败次数 = [int]$统计.失败次数
    $总次数 = $成功次数 + $失败次数

    if ($总次数 -gt 0) {
        return [double]$成功次数 / [double]$总次数
    }
    else {
        return 0.5
    }
}

function 记录-镜像尝试 {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$记录,

        [Parameter(Mandatory = $true)]
        [string]$镜像地址,

        [Parameter(Mandatory = $true)]
        [bool]$成功,

        [Parameter(Mandatory = $true)]
        [int]$耗时毫秒
    )

    $统计 = 读取-镜像统计 $记录 $镜像地址
    $当前时间 = (Get-Date).ToString("o")
    $统计.最后尝试时间 = $当前时间
    $统计.最近耗时毫秒 = $耗时毫秒

    if ($成功) {
        $统计.成功次数 = [int]$统计.成功次数 + 1
        $统计.最近结果 = "成功"
        $统计.最后成功时间 = $当前时间
    }
    else {
        $统计.失败次数 = [int]$统计.失败次数 + 1
        $统计.最近结果 = "失败"
        $统计.最后失败时间 = $当前时间
    }
}

function 转换为-HTTPS仓库地址 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$仓库地址
    )

    if ($仓库地址 -match "^git@github\.com:(.+)$") {
        return "https://github.com/$($Matches[1])"
    }

    if ($仓库地址 -match "^ssh://git@github\.com/(.+)$") {
        return "https://github.com/$($Matches[1])"
    }

    return $仓库地址
}

function 合成-镜像仓库地址 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$镜像站,

        [Parameter(Mandatory = $true)]
        [string]$仓库地址
    )

    return "$($镜像站.TrimEnd('/'))/$仓库地址"
}

# ============================================================
# 公开函数
# ============================================================

<#
.SYNOPSIS
    通过多个 GitHub 镜像站点自动尝试 git fetch，按历史成功率智能排序。
.DESCRIPTION
    自动检测当前仓库的 origin 远程和当前分支，通过多个镜像代理站点依次尝试 git fetch，
    并根据历史成功/失败记录智能排序，优先使用成功率最高的镜像。拉取成功后自动执行快进合并（--ff-only）。
.PARAMETER 镜像站前缀
    镜像站地址前缀列表，默认内置 5 个国内常用镜像站。
.PARAMETER 远程名
    Git 远程名称，默认为 "origin"。
.PARAMETER 记录文件路径
    镜像统计记录文件的保存路径，默认为 "$env:TEMP\镜像拉取记录.json"。
.EXAMPLE
    拉取-GitHub镜像
    从 origin 拉取当前分支，使用默认镜像站列表，快进合并。
.EXAMPLE
    拉取-GitHub镜像 -镜像站前缀 "https://gh.llkk.cc/", "https://gh-proxy.com/"
    仅使用指定的两个镜像站。
.EXAMPLE
    拉取-GitHub镜像 -远程名 "upstream"
    从 upstream 远程拉取当前分支。
#>
function 拉取-GitHub镜像 {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]$镜像站前缀 = @(
            "https://gh.llkk.cc/",
            "https://gh-proxy.com/",
            "https://ghfast.top/",
            "https://gh-proxy.net/",
            "https://hub.gitmirror.com/"
        ),

        [Parameter()]
        [string]$远程名 = "origin",

        [Parameter()]
        [string]$记录文件路径 = (Join-Path $env:TEMP "镜像拉取记录.json")
    )

    $分支 = 读取-Git文本 @("branch", "--show-current")
    if ([string]::IsNullOrWhiteSpace($分支)) {
        throw "当前处于分离 HEAD 状态，无法执行加速拉取。"
    }

    $源仓库地址 = 读取-Git文本 @("remote", "get-url", $远程名)
    $HTTPS仓库地址 = 转换为-HTTPS仓库地址 $源仓库地址

    $候选镜像地址 = @()
    foreach ($镜像站 in $镜像站前缀) {
        if (-not [string]::IsNullOrWhiteSpace($镜像站)) {
            $候选镜像地址 += 合成-镜像仓库地址 $镜像站 $HTTPS仓库地址
        }
    }

    $候选镜像地址 = @($候选镜像地址 | Select-Object -Unique)
    if ($候选镜像地址.Count -eq 0) {
        throw "没有可用的镜像站地址，请检查 -镜像站前缀 参数。"
    }

    $镜像记录 = 读取-镜像记录 $记录文件路径

    $候选镜像条目 = @()
    $原始序号 = 0
    foreach ($镜像地址 in $候选镜像地址) {
        $统计 = 读取-镜像统计 $镜像记录 $镜像地址
        $评分 = 计算-镜像评分 $统计
        $候选镜像条目 += [pscustomobject]@{
            地址  = $镜像地址
            评分  = $评分
            排序值 = ($评分 * 1000000) - $原始序号
        }
        $原始序号 += 1
    }

    $候选镜像条目 = @($候选镜像条目 | Sort-Object -Property 排序值 -Descending)

    $成功镜像地址 = ""
    foreach ($镜像条目 in $候选镜像条目) {
        $镜像地址 = $镜像条目.地址
        $显示评分 = [math]::Round($镜像条目.评分 * 100, 1)
        Write-Host "尝试从镜像拉取（成功率 $显示评分%）：$镜像地址"

        $开始时间 = Get-Date
        $拉取成功 = 尝试-Git命令 @("fetch", $镜像地址, $分支)
        $耗时毫秒 = [int]((Get-Date) - $开始时间).TotalMilliseconds
        记录-镜像尝试 $镜像记录 $镜像地址 $拉取成功 $耗时毫秒
        保存-镜像记录 $镜像记录 $记录文件路径

        if ($拉取成功) {
            $成功镜像地址 = $镜像地址
            break
        }

        Write-Host "该镜像不可用，继续尝试下一个。"
    }

    if ([string]::IsNullOrWhiteSpace($成功镜像地址)) {
        throw "所有镜像站都未能获取 $分支。"
    }

    Write-Host "将当前分支快进到镜像中的 $分支..."
    执行-Git命令 @("merge", "--ff-only", "FETCH_HEAD")

    $最新提交 = 读取-Git文本 @("log", "-1", "--pretty=format:%h %s")
    Write-Host "完成。当前最新提交：$最新提交"
}

<#
.SYNOPSIS
    通过镜像站点克隆 GitHub 仓库，仅获取默认分支的最新提交（浅克隆）。
.DESCRIPTION
    接受仓库远程地址和本地路径作为参数，使用与拉取相同的动态镜像排序策略，
    依次尝试克隆，成功后记录镜像统计。仅克隆默认分支（--single-branch）且
    只获取最新一次提交（--depth 1），适合快速获取大型仓库的最新代码。
.PARAMETER 仓库地址
    GitHub 仓库的 HTTPS 或 SSH 地址，如 https://github.com/用户/仓库.git 或 git@github.com:用户/仓库.git。
.PARAMETER 本地路径
    克隆到的本地目标路径。若已存在则报错退出。
.PARAMETER 镜像站前缀
    镜像站地址前缀列表，默认内置 5 个国内常用镜像站。
.PARAMETER 记录文件路径
    镜像统计记录文件的保存路径，默认为 "$env:TEMP\镜像拉取记录.json"。
.EXAMPLE
    克隆-GitHub镜像 -仓库地址 "https://github.com/PowerShell/PowerShell.git" -本地路径 "D:\PowerShell"
    通过镜像站克隆 PowerShell 仓库到本地 D:\PowerShell。
.EXAMPLE
    克隆-GitHub镜像 "https://github.com/torvalds/linux.git" "D:\linux" -镜像站前缀 "https://gh.llkk.cc/"
    仅使用指定镜像站克隆 Linux 内核仓库。
#>
function 克隆-GitHub镜像 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$仓库地址,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$本地路径,

        [Parameter(Position = 2)]
        [string[]]$镜像站前缀 = @(
            "https://gh.llkk.cc/",
            "https://gh-proxy.com/",
            "https://ghfast.top/",
            "https://gh-proxy.net/",
            "https://hub.gitmirror.com/"
        ),

        [Parameter()]
        [string]$记录文件路径 = (Join-Path $env:TEMP "镜像拉取记录.json")
    )

    if (Test-Path -LiteralPath $本地路径) {
        throw "目标路径已存在：$本地路径"
    }

    $HTTPS仓库地址 = 转换为-HTTPS仓库地址 $仓库地址

    $候选镜像地址 = @()
    foreach ($镜像站 in $镜像站前缀) {
        if (-not [string]::IsNullOrWhiteSpace($镜像站)) {
            $候选镜像地址 += 合成-镜像仓库地址 $镜像站 $HTTPS仓库地址
        }
    }

    $候选镜像地址 = @($候选镜像地址 | Select-Object -Unique)
    if ($候选镜像地址.Count -eq 0) {
        throw "没有可用的镜像站地址，请检查 -镜像站前缀 参数。"
    }

    $镜像记录 = 读取-镜像记录 $记录文件路径

    $候选镜像条目 = @()
    $原始序号 = 0
    foreach ($镜像地址 in $候选镜像地址) {
        $统计 = 读取-镜像统计 $镜像记录 $镜像地址
        $评分 = 计算-镜像评分 $统计
        $候选镜像条目 += [pscustomobject]@{
            地址  = $镜像地址
            评分  = $评分
            排序值 = ($评分 * 1000000) - $原始序号
        }
        $原始序号 += 1
    }

    $候选镜像条目 = @($候选镜像条目 | Sort-Object -Property 排序值 -Descending)

    $成功镜像地址 = ""
    foreach ($镜像条目 in $候选镜像条目) {
        $镜像地址 = $镜像条目.地址
        $显示评分 = [math]::Round($镜像条目.评分 * 100, 1)
        Write-Host "尝试从镜像克隆（成功率 $显示评分%）：$镜像地址"

        $开始时间 = Get-Date
        $克隆成功 = 尝试-Git命令 @("clone", "--depth", "1", "--single-branch", $镜像地址, $本地路径)
        $耗时毫秒 = [int]((Get-Date) - $开始时间).TotalMilliseconds
        记录-镜像尝试 $镜像记录 $镜像地址 $克隆成功 $耗时毫秒
        保存-镜像记录 $镜像记录 $记录文件路径

        if ($克隆成功) {
            $成功镜像地址 = $镜像地址
            break
        }

        Write-Host "该镜像不可用，继续尝试下一个。"

        # 克隆失败会残留空目录，清理之
        if (Test-Path -LiteralPath $本地路径) {
            Remove-Item -LiteralPath $本地路径 -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ([string]::IsNullOrWhiteSpace($成功镜像地址)) {
        throw "所有镜像站都未能克隆仓库：$仓库地址"
    }

    Push-Location $本地路径
    try {
        $最新提交 = 读取-Git文本 @("log", "-1", "--pretty=format:%h %s")
        Write-Host "克隆完成。当前最新提交：$最新提交"
    }
    finally {
        Pop-Location
    }
}

<#
.SYNOPSIS
    查看所有镜像站的历史成功率统计。
.DESCRIPTION
    读取本地镜像拉取记录，按评分高低列出所有镜像站的成功次数、失败次数、成功率和最后尝试时间。
.PARAMETER 记录文件路径
    镜像统计记录文件的保存路径，默认为 "$env:TEMP\镜像拉取记录.json"。
.EXAMPLE
    查看-镜像统计
    查看默认记录文件中的镜像统计。
.EXAMPLE
    查看-镜像统计 -记录文件路径 "D:\MyData\镜像记录.json"
    查看指定记录文件中的镜像统计。
#>
function 查看-镜像统计 {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$记录文件路径 = (Join-Path $env:TEMP "镜像拉取记录.json")
    )

    $镜像记录 = 读取-镜像记录 $记录文件路径

    if ($镜像记录.镜像.PSObject.Properties.Count -eq 0) {
        Write-Host "暂无镜像使用记录。"
        return
    }

    $统计列表 = @()
    foreach ($属性 in $镜像记录.镜像.PSObject.Properties) {
        $统计 = 确保-镜像统计结构 $属性.Value
        $评分 = 计算-镜像评分 $统计
        成功百分比 = [math]::Round($评分 * 100, 1)

        $统计列表 += [pscustomobject]@{
            镜像地址   = $属性.Name
            成功次数   = [int]$统计.成功次数
            失败次数   = [int]$统计.失败次数
            成功率     = "$成功百分比%"
            最近耗时毫秒 = $统计.最近耗时毫秒
            最后尝试   = $统计.最后尝试时间
        }
    }

    $统计列表 | Sort-Object -Property { [double]($_.成功率 -replace '%', '') } -Descending | Format-Table -AutoSize
}

<#
.SYNOPSIS
    重置所有镜像站的历史统计记录。
.DESCRIPTION
    删除本地镜像拉取记录文件，下次运行时将从零开始统计各镜像站的成功率。
.PARAMETER 记录文件路径
    镜像统计记录文件的保存路径，默认为 "$env:TEMP\镜像拉取记录.json"。
.EXAMPLE
    重置-镜像统计
    重置默认记录文件。
#>
function 重置-镜像统计 {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$记录文件路径 = (Join-Path $env:TEMP "镜像拉取记录.json")
    )

    if (Test-Path -LiteralPath $记录文件路径) {
        Remove-Item -LiteralPath $记录文件路径 -Force
        Write-Host "已删除镜像统计记录：$记录文件路径"
    }
    else {
        Write-Host "镜像统计记录文件不存在，无需重置。"
    }
}

# ============================================================
# 模块初始化：加载时输出提示
# ============================================================

Write-Verbose "GitHub加速 模块已加载。使用 '拉取-GitHub镜像' 开始拉取。" -Verbose:$false
