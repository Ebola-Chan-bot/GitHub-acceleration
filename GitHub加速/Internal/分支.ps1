# 远端分支名的查询与补全
#
# 设计要点：
# - 本地已有 refs/remotes/* 缓存时直接用缓存（离线、最快）。
# - 全新克隆等无缓存场景下，按镜像评分排序用 ls-remote 联网查询分支列表，结果写入会话缓存，避免连续按 TAB 反复联网。
# - 补全只读、不写镜像统计；分支名不存在是「用户输入错误」，在真正拉取时精确匹配校验并立刻中止，不继续尝试其它镜像，也不写入镜像统计。

# 会话级分支列表缓存：键为远端 HTTPS 地址，值为该地址的分支名数组。仅缓存查询成功的结果；失败不缓存，网络恢复后再次按 TAB 会重试。
$script:分支补全缓存 = @{}

<#
.SYNOPSIS
	列出当前仓库已缓存的远端分支名（不含远程名前缀）。
.DESCRIPTION
	读取 refs/remotes/<远程名>/* 的本地跟踪引用，离线即可补全。必须在仓库目录内调用。无缓存时返回空数组。
#>
function 列出-远端分支名 {
	param(
		[Parameter(Mandatory = $true)]
		[string]$远程名
	)

	$引用行 = @(git for-each-ref --format='%(refname)' "refs/remotes/$远程名/" 2>$null)
	if ($LASTEXITCODE -ne 0 -or $引用行.Count -eq 0) {
		return @()
	}

	$前缀 = "refs/remotes/$远程名/"
	$分支列表 = @()
	foreach ($行 in $引用行) {
		$名称 = "$行".Trim()
		if (-not $名称.StartsWith($前缀)) {
			continue
		}

		$分支 = $名称.Substring($前缀.Length)
		# 过滤 <远程>/HEAD 这种伪引用
		if ($分支 -eq 'HEAD') {
			continue
		}

		$分支列表 += $分支
	}

	return @($分支列表 | Select-Object -Unique | Sort-Object)
}

<#
.SYNOPSIS
	向指定镜像地址查询远端分支列表（ls-remote），返回分支名数组。
.DESCRIPTION
	不写入任何镜像统计；这是用户输入校验，不是镜像可用性探测。查询失败（网络不通、认证失败等）返回 $null，由调用方决定是否回退重试其它镜像。
#>
function 查询-远端分支列表 {
	param(
		[Parameter(Mandatory = $true)]
		[string]$镜像地址
	)

	# 补全在后台触发，绝不能弹出任何凭据框或等待输入。
	# 关键：用 `-c credential.helper=` 把凭据助手彻底清空——光禁交互不够，只要 git 还去调 credential helper（含 VS Code 扩展注册的提供者），就会触发认证弹窗。补全只读公开分支，无需任何凭据；私有仓库查不到就返回空，由真正拉取时再处理认证。
	$原终端提示 = $env:GIT_TERMINAL_PROMPT
	$原GCM交互 = $env:GCM_INTERACTIVE
	$原GIT_ASKPASS = $env:GIT_ASKPASS
	$原SSH_ASKPASS = $env:SSH_ASKPASS
	$env:GIT_TERMINAL_PROMPT = '0'
	$env:GCM_INTERACTIVE = 'Never'
	$env:GIT_ASKPASS = ''
	$env:SSH_ASKPASS = ''
	try {
		$行 = @(git -c credential.helper= -c core.askpass= ls-remote --heads $镜像地址 2>$null)
		if ($LASTEXITCODE -ne 0) {
			return $null
		}

		$分支列表 = @()
		foreach ($文本行 in $行) {
			$文本 = "$文本行".Trim()
			if ($文本 -match '\s+refs/heads/(.+)$') {
				$分支列表 += $Matches[1].Trim()
			}
		}

		return @($分支列表 | Select-Object -Unique | Sort-Object)
	}
	finally {
		$env:GIT_TERMINAL_PROMPT = $原终端提示
		$env:GCM_INTERACTIVE = $原GCM交互
		$env:GIT_ASKPASS = $原GIT_ASKPASS
		$env:SSH_ASKPASS = $原SSH_ASKPASS
	}
}

<#
.SYNOPSIS
	获取 -分支 补全候选：本地缓存优先，无缓存时联网查询。
.DESCRIPTION
	已有仓库且存在 refs/remotes/* 缓存时直接返回缓存（离线）。否则确定远端 HTTPS 地址（克隆用 -仓库地址，拉取用现有仓库的 remote URL），按镜像评分排序逐个 ls-remote，第一个能连上的镜像的结果即返回并写入会话缓存。全部失败返回空数组（不缓存失败）。
#>
function 获取-分支补全候选 {
	param(
		[Parameter()]
		[string]$仓库目录 = ".",

		[Parameter()]
		[string]$远程名 = "origin",

		[Parameter()]
		[AllowEmptyString()]
		[string]$仓库地址 = ""
	)

	# 优先级：显式 -仓库地址 > 本地缓存 > 联网。传了 -仓库地址（克隆另一个仓库）时，绝不能拿当前目录的本地缓存充数——那属于当前仓库而非目标仓库。此时只按目标地址走会话缓存/联网。
	$显式地址 = -not [string]::IsNullOrWhiteSpace($仓库地址)
	$本地有效 = Test-Path -LiteralPath (Join-Path $仓库目录 '.git')

	# 1) 本地缓存（仅在未显式指定仓库地址时使用）
	if (-not $显式地址 -and $本地有效) {
		$本地 = @()
		Push-Location -LiteralPath $仓库目录
		try {
			$本地 = @(列出-远端分支名 $远程名)
		}
		finally {
			Pop-Location
		}
		if ($本地.Count -gt 0) {
			return $本地
		}
	}

	# 2) 确定远端 HTTPS 地址
	$HTTPS = ""
	if ($显式地址) {
		$HTTPS = 转换为-HTTPS仓库地址 $仓库地址
	}
	elseif ($本地有效) {
		Push-Location -LiteralPath $仓库目录
		try {
			$HTTPS = 转换为-HTTPS仓库地址 (尝试读取-Git文本 @('remote', 'get-url', $远程名))
		}
		finally {
			Pop-Location
		}
	}
	if ([string]::IsNullOrWhiteSpace($HTTPS)) {
		return @()
	}

	# 3) 会话缓存
	if ($script:分支补全缓存.ContainsKey($HTTPS)) {
		return $script:分支补全缓存[$HTTPS]
	}

	# 4) 联网：按镜像评分排序，逐个 ls-remote，首个成功即返回并缓存
	$镜像记录 = 读取-镜像记录 $script:默认记录路径
	$条目 = 排序-镜像候选 $镜像记录 $script:镜像站前缀 $HTTPS
	foreach ($镜像条目 in $条目) {
		$分支 = 查询-远端分支列表 $镜像条目.地址
		if ($null -ne $分支) {
			$script:分支补全缓存[$HTTPS] = $分支
			return $分支
		}
	}

	return @()
}

<#
.SYNOPSIS
	为 -分支 参数注册 TAB 补全。
.DESCRIPTION
	本地缓存优先，无缓存（如全新克隆）时联网 ls-remote；候选按已输入前缀过滤。
#>
function 注册-分支参数补全 {
	$补全脚本 = {
		param($命令名, $参数名, $输入前缀, $命令Ast, $绑定参数)

		$仓库目录 = "."
		if ($绑定参数.ContainsKey('仓库目录') -and -not [string]::IsNullOrWhiteSpace("$($绑定参数['仓库目录'])")) {
			$仓库目录 = "$($绑定参数['仓库目录'])"
		}

		$远程名 = "origin"
		if ($绑定参数.ContainsKey('远程名') -and -not [string]::IsNullOrWhiteSpace("$($绑定参数['远程名'])")) {
			$远程名 = "$($绑定参数['远程名'])"
		}

		$仓库地址 = ""
		if ($绑定参数.ContainsKey('仓库地址')) {
			$仓库地址 = "$($绑定参数['仓库地址'])"
		}

		$分支列表 = @(获取-分支补全候选 -仓库目录 $仓库目录 -远程名 $远程名 -仓库地址 $仓库地址)

		foreach ($分支 in $分支列表) {
			if ($分支.StartsWith($输入前缀, [System.StringComparison]::OrdinalIgnoreCase)) {
				[System.Management.Automation.CompletionResult]::new($分支, $分支, 'ParameterValue', $分支)
			}
		}
	}

	foreach ($函数名 in @('拉取-GitHub镜像', '克隆-GitHub镜像')) {
		Register-ArgumentCompleter -CommandName $函数名 -ParameterName 分支 -ScriptBlock $补全脚本
	}
}

注册-分支参数补全
