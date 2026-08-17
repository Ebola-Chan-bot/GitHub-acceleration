<#
.SYNOPSIS
	通过多个 GitHub 镜像站点自动尝试 git fetch，按历史成功率智能排序。
.DESCRIPTION
	自动检测当前仓库的 origin 远程和当前分支，通过多个镜像代理站点依次尝试 git fetch，
	并根据历史成功/失败记录智能排序，优先使用成功率最高的镜像。拉取成功后自动执行快进合并（--ff-only）。
.PARAMETER 镜像站前缀
	镜像站地址前缀列表，默认内置多个国内常用镜像站，并保留各网络环境下都可能可用的新老镜像。
.PARAMETER 远程名
	Git 远程名称，默认为 "origin"。
.PARAMETER 记录文件路径
	镜像统计记录文件的保存路径，默认为 "$env:TEMP\镜像拉取记录.json"。
.EXAMPLE
	拉取-GitHub镜像
	从 origin 拉取当前分支，使用默认镜像站列表，快进合并。
.EXAMPLE
	拉取-GitHub镜像 -镜像站前缀 "https://gh-proxy.cn/", "https://gh-proxy.org/"
	仅使用指定的两个镜像站。
.EXAMPLE
	拉取-GitHub镜像 -远程名 "upstream"
	从 upstream 远程拉取当前分支。
#>
function 拉取-GitHub镜像 {
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[string[]]$镜像站前缀 = $script:镜像站前缀,

		[Parameter()]
		[string]$远程名 = "origin",

		[Parameter()]
		[string]$记录文件路径 = $script:默认记录路径
	)

	$分支 = 读取-Git文本 @("branch", "--show-current")
	if ([string]::IsNullOrWhiteSpace($分支)) {
		throw "当前处于分离 HEAD 状态，无法执行加速拉取。"
	}

	$源仓库地址 = 读取-Git文本 @("remote", "get-url", $远程名)
	$HTTPS仓库地址 = 转换为-HTTPS仓库地址 $源仓库地址

	$镜像记录 = 读取-镜像记录 $记录文件路径

	# 统计按镜像站（前缀）记录，与具体仓库无关，可跨仓库共享历史经验；
	# 候选条目按各站历史成功率排序
	$候选镜像条目 = 排序-镜像候选 $镜像记录 $镜像站前缀 $HTTPS仓库地址

	$成功镜像地址 = ""
	foreach ($镜像条目 in $候选镜像条目) {
		$镜像地址 = $镜像条目.地址
		$显示评分 = [math]::Round($镜像条目.评分 * 100, 1)
		Write-Host "尝试从镜像拉取（成功率 $显示评分%）：$镜像地址"

		$开始时间 = Get-Date
		$拉取成功 = 尝试-Git命令 @("fetch", $镜像地址, $分支)
		$耗时毫秒 = [int]((Get-Date) - $开始时间).TotalMilliseconds
		记录-镜像尝试 $镜像记录 $镜像条目.站点 $拉取成功 $耗时毫秒
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
