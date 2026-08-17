# GitHub加速 - 通过多个 GitHub 镜像站点自动尝试 git fetch
# 按历史成功率智能排序，实现国内无障碍拉取 GitHub 仓库。

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# 模块常量
# ============================================================

# 内置镜像站前缀列表。各镜像地位平等、默认不区分先后，
# 实际执行时按各站历史成功率动态排序。
$script:镜像站前缀 = @(
	"https://gh-proxy.cn/",
	"https://gh-proxy.org/",
	"https://ghproxy.net/",
	"https://gh-proxy.com/",
	"https://gh.llkk.cc/",
	"https://ghfast.top/",
	"https://gh-proxy.net/",
	"https://hub.gitmirror.com/"
)

# 默认的镜像统计记录文件路径（推送代理设置也保存在此文件中）
$script:默认记录路径 = Join-Path $env:TEMP "镜像拉取记录.json"

# ============================================================
# 加载内部辅助函数与公开命令
# ============================================================

$模块根 = Split-Path -Parent $MyInvocation.MyCommand.Path

foreach ($目录 in "Internal", "Public") {
	foreach ($文件 in Get-ChildItem -LiteralPath (Join-Path $模块根 $目录) -Filter "*.ps1") {
		. $文件.FullName
	}
}

Write-Verbose "GitHub加速 模块已加载。使用 '拉取-GitHub镜像' 开始拉取。" -Verbose:$false
