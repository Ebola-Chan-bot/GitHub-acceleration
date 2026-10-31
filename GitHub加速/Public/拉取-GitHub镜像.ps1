<#
.SYNOPSIS
	通过多个 GitHub 镜像站点自动尝试 git fetch，按历史成功率智能排序，并自动切换到拉取的分支。
.DESCRIPTION
	自动检测指定仓库的远程地址，通过多个镜像代理站点依次尝试 git fetch，
	并根据历史成功/失败记录智能排序，优先使用成功率最高的镜像。
	拉取目标分支（不指定则为与本地当前分支同名的远端分支）的最新提交，
	成功后自动切换到该分支（本地无此分支时自动创建）并执行快进合并（--ff-only），而不是停留在当前分支。
	若快进合并失败（如本地与远程历史分叉），会交互式询问是否强行用远程版本覆盖本地分支（默认否）。
	拉取成功后自动刷新远程跟踪引用并为该分支建立对远程的跟踪关系（利用 FETCH_HEAD 更新，
	不需要直连 GitHub），以后即可直接使用 git pull/push。
.PARAMETER 仓库目录
	本地仓库目录，默认为当前工作目录。
.PARAMETER 镜像站前缀
	镜像站地址前缀列表，默认内置多个国内常用镜像站，并保留各网络环境下都可能可用的新老镜像。
.PARAMETER 分支
	可选。要拉取的分支名，不指定则拉取与本地当前分支同名的远端分支（当前处于分离 HEAD 状态时必须指定）。拉取成功后自动切换到该分支。
	支持 TAB 补全：本地已有远端引用缓存时用缓存，无缓存时按镜像评分排序联网查询分支列表（结果会话内缓存）。分支名不存在属用户输入错误，会立即中止，不尝试其它镜像、不计入镜像统计。
.PARAMETER 远程名
	Git 远程名称，默认为 "origin"。
.PARAMETER 记录文件路径
	镜像统计记录文件的保存路径，默认为 "$env:TEMP\镜像拉取记录.json"。
.EXAMPLE
	拉取-GitHub镜像
	拉取 origin 上与本地当前分支同名的远端分支并快进合并。
.EXAMPLE
	拉取-GitHub镜像 "D:\Repo\my-project"
	对指定仓库目录拉取与当前分支同名的远端分支。
.EXAMPLE
	拉取-GitHub镜像 -分支 "release-7.5"
	拉取 release-7.5 分支并自动切换到它。
.EXAMPLE
	拉取-GitHub镜像 -镜像站前缀 "https://gh-proxy.cn/", "https://gh-proxy.org/"
	仅使用指定的两个镜像站。
.EXAMPLE
	拉取-GitHub镜像 -远程名 "upstream"
	从 upstream 远程拉取与本地当前分支同名的远端分支。
#>
function 拉取-GitHub镜像 {
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[string]$仓库目录 = ".",

		[Parameter(Position = 1)]
		[string[]]$镜像站前缀 = $script:镜像站前缀,

		[Parameter()]
		[string]$分支,

		[Parameter()]
		[string]$远程名 = "origin",

		[Parameter()]
		[string]$记录文件路径 = $script:默认记录路径
	)

	if (-not (Test-Path -LiteralPath $仓库目录 -PathType Container)) {
		throw "仓库目录不存在：$仓库目录"
	}

	Push-Location -LiteralPath $仓库目录
	try {
		$源仓库地址 = 读取-Git文本 @("remote", "get-url", $远程名)
		$HTTPS仓库地址 = 转换为-HTTPS仓库地址 $源仓库地址

		# 指定分支时取该分支，否则取与本地当前分支同名的远端分支；分离 HEAD 状态没有分支名，必须显式指定
		$目标分支 = $分支
		if ([string]::IsNullOrWhiteSpace($目标分支)) {
			$目标分支 = 尝试读取-Git文本 @("branch", "--show-current")
			if ([string]::IsNullOrWhiteSpace($目标分支)) {
				throw "当前处于分离 HEAD 状态，无法确定同名远端分支，请用 -分支 指定要拉取的分支。"
			}
			$拉取描述 = "与本地当前分支同名的远端分支 $目标分支"
		}
		else {
			$拉取描述 = "分支 $目标分支"
		}
		$抓取引用 = "refs/heads/$目标分支"

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
			$结果 = Git执行并区分取消 @("fetch", $镜像地址, $抓取引用)
			$耗时毫秒 = [int]((Get-Date) - $开始时间).TotalMilliseconds

			if ($结果.用户取消) {
				# 用户主动取消身份验证等操作：不是镜像的问题，不记录成败、不尝试下一个
				throw "检测到用户取消操作，已停止（不计入镜像统计）。"
			}

			if ($结果.分支不存在) {
				# 分支名写错或该分支确实不存在：换任何镜像结果都一样，属用户输入错误，立即中止，不继续尝试、不记镜像统计
				throw "远端不存在分支「$目标分支」，已停止（不计入镜像统计）。请核实分支名（可按 TAB 补全），或用 -分支 指定其它分支。"
			}

			$拉取成功 = $结果.成功
			记录-镜像尝试 $镜像记录 $镜像条目.站点 $拉取成功 $耗时毫秒
			保存-镜像记录 $镜像记录 $记录文件路径

			if ($拉取成功) {
				$成功镜像地址 = $镜像地址
				break
			}

			Write-Host "该镜像不可用，继续尝试下一个。"
		}

		if ([string]::IsNullOrWhiteSpace($成功镜像地址)) {
			throw "所有镜像站都未能获取 $拉取描述。"
		}

		# $目标分支 已在拉取前确定（指定分支或本地当前分支名），无需再解析远端默认分支；
		# 镜像 fetch 不会生成 remote-tracking 引用，这里直接用 FETCH_HEAD
		# 刷新引用，免去再直连 GitHub。必须无条件刷新：否则已建立跟踪的分支
		# 会拿陈旧的引用与 HEAD 比较，显示与远程有提交差异待同步。
		$现有规范 = 尝试读取-Git文本 @("config", "--get-all", "remote.$远程名.fetch")
		if ([string]::IsNullOrWhiteSpace($现有规范)) {
			执行-Git命令 @("config", "remote.$远程名.fetch", "+refs/heads/*:refs/remotes/$远程名/*")
		}
		执行-Git命令 @("update-ref", "refs/remotes/$远程名/$目标分支", "FETCH_HEAD")

		# 自动切换到刚拉取的分支（本地无此分支时自动创建），而不是停留在当前分支
		$当前分支 = 尝试读取-Git文本 @("branch", "--show-current")
		$本地有分支 = 尝试-Git命令 @("show-ref", "--verify", "--quiet", "refs/heads/$目标分支")

		if (-not $本地有分支) {
			Write-Host "本地无分支 $目标分支，从拉取结果创建并切换..."
			执行-Git命令 @("checkout", "-b", $目标分支, "FETCH_HEAD")
		}
		else {
			if ($当前分支 -ne $目标分支) {
				Write-Host "切换到分支 $目标分支..."
				执行-Git命令 @("checkout", $目标分支)
			}

			Write-Host "将分支 $目标分支 快进到镜像中的最新提交..."
			$快进成功 = 尝试-Git命令 @("merge", "--ff-only", "FETCH_HEAD")

			if (-not $快进成功) {
				Write-Host "快进合并失败（常见原因：本地与远程历史分叉、存在未解决的合并冲突或未提交修改）。" -ForegroundColor Yellow
				$选择 = $null
				while ($null -eq $选择 -or $选择 -notmatch "^[yYnN]$") {
					$输入 = Read-Host "是否强行用远程版本覆盖本地？（本地提交及未提交修改将丢失，未跟踪文件保留）[y/N]"
					if ([string]::IsNullOrWhiteSpace($输入)) { $选择 = "n" }
					else { $选择 = $输入.Substring(0, 1) }
				}

				if ($选择 -match "^[yY]$") {
					Write-Host "正在用远程版本覆盖本地分支..."
					执行-Git命令 @("reset", "--hard", "FETCH_HEAD")
					Write-Host "提示：未跟踪文件仍保留在工作区，如不需要请自行清理。" -ForegroundColor DarkGray
				}
				else {
					throw "已取消覆盖，本地分支未发生变化。"
				}
			}
		}

		# 为拉取的分支建立跟踪关系（引用已在上方刷新为 FETCH_HEAD）
		$上游 = 尝试读取-Git文本 @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
		if ([string]::IsNullOrWhiteSpace($上游)) {
			Write-Host "为分支 $目标分支 建立跟踪关系：$目标分支 -> $远程名/$目标分支 ..."
			执行-Git命令 @("branch", "--set-upstream-to=$远程名/$目标分支", $目标分支)
			Write-Host "已建立跟踪，以后可直接使用 git pull/push。"
		}
		elseif ($上游 -ne "$远程名/$目标分支") {
			Write-Host "提示：分支 $目标分支 跟踪的是 $上游，本次从 $远程名 拉取。git status 中相对 $上游 的提交差异是真实差异，如需改为与 $远程名/$目标分支 比较可运行：git branch -u $远程名/$目标分支" -ForegroundColor DarkGray
		}

		$最新提交 = 读取-Git文本 @("log", "-1", "--pretty=format:%h %s")
		Write-Host "完成。当前最新提交：$最新提交"
	}
	finally {
		Pop-Location
	}
}
