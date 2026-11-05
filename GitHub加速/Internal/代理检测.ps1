# 本机可用代理的自动检测
#
# 仅在「用户未显式指定 -代理、且没有已记住的代理」时调用。唯一来源是 Windows 系统代理（注册表 IE 设置，即「设置→网络→代理→手动设置代理」），这是系统定义的标准位置，属确定性读取、不靠猜。读到的候选用 git ls-remote 实际验证连通性（禁凭据，绝不弹认证框）。

<#
.SYNOPSIS
	用 git ls-remote 实测某代理能否连上 GitHub。
.DESCRIPTION
	通过 -c http.proxy/https.proxy 注入候选代理，并彻底禁凭据（credential.helper= 等），避免触发 VS Code 认证弹窗。目标用公开仓库（GitHub 官方 octocat/Hello-World），仅验证「经此代理能否建立到 GitHub 的 HTTPS 连接」，不写镜像统计。低速超时防止挂死连接拖慢检测。
#>
function 测试-代理连通 {
	param(
		[Parameter(Mandatory = $true)]
		[string]$代理,

		[Parameter()]
		[int]$超时秒 = 6
	)

	$原终端提示 = $env:GIT_TERMINAL_PROMPT
	$原GCM交互 = $env:GCM_INTERACTIVE
	$原GIT_ASKPASS = $env:GIT_ASKPASS
	$原SSH_ASKPASS = $env:SSH_ASKPASS
	$原低速限额 = $env:GIT_HTTP_LOW_SPEED_LIMIT
	$原低速时间 = $env:GIT_HTTP_LOW_SPEED_TIME
	$env:GIT_TERMINAL_PROMPT = '0'
	$env:GCM_INTERACTIVE = 'Never'
	$env:GIT_ASKPASS = ''
	$env:SSH_ASKPASS = ''
	$env:GIT_HTTP_LOW_SPEED_LIMIT = '1'
	$env:GIT_HTTP_LOW_SPEED_TIME = "$超时秒"
	try {
		# 吞掉 git 的 stderr：检测失败的候选属正常情况，不应把NativeCommandError打到控制台（EAP=Stop 下 git 非零退出会触发）。
		$原错误策略 = $ErrorActionPreference
		$ErrorActionPreference = 'Continue'
		git -c credential.helper= -c core.askpass= `
			-c "http.proxy=$代理" -c "https.proxy=$代理" `
			ls-remote --heads https://github.com/octocat/Hello-World.git 2>$null | Out-Null
		$退出码 = $LASTEXITCODE
		$ErrorActionPreference = $原错误策略
		return ($退出码 -eq 0)
	}
	finally {
		$env:GIT_TERMINAL_PROMPT = $原终端提示
		$env:GCM_INTERACTIVE = $原GCM交互
		$env:GIT_ASKPASS = $原GIT_ASKPASS
		$env:SSH_ASKPASS = $原SSH_ASKPASS
		$env:GIT_HTTP_LOW_SPEED_LIMIT = $原低速限额
		$env:GIT_HTTP_LOW_SPEED_TIME = $原低速时间
	}
}

<#
.SYNOPSIS
	读取 Windows 系统代理设置（确定性来源，无猜测）。
.DESCRIPTION
	只读注册表 IE 代理：HKCU\...\Internet Settings 的 ProxyEnable/ProxyServer。这是 Windows「设置 → 网络和 Internet → 代理 → 手动设置代理」对应的确切位置，键名与取值都是系统契约，不靠猜。未启用（ProxyEnable≠1）或无地址时返回空串。分协议形式（http=...;https=...）优先取 https，其次 http，否则整串视为 host:port。
#>
function 收集-代理候选 {
	try {
		$键 = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
		if ($键.ProxyEnable -ne 1) {
			return @()
		}
		if ([string]::IsNullOrWhiteSpace($键.ProxyServer)) {
			return @()
		}

		$服务器 = "$($键.ProxyServer)".Trim()
		if ($服务器 -match 'https=([^;]+)') {
			return @("http://$($Matches[1])")
		}
		elseif ($服务器 -match 'http=([^;]+)') {
			return @("http://$($Matches[1])")
		}
		elseif ($服务器 -notmatch '=') {
			return @("http://$服务器")
		}
	}
	catch { }

	return @()
}

<#
.SYNOPSIS
	自动检测当前可用的代理地址。
.DESCRIPTION
	逐个测试候选的 GitHub 连通性，返回第一个实测可用的代理地址；全部不可用则返回空串。仅做只读检测，不修改任何配置、不写镜像统计、不弹认证框。
#>
function 检测-可用代理 {
	$候选 = @(收集-代理候选)
	if ($候选.Count -eq 0) {
		return ""
	}

	foreach ($代理 in $候选) {
		Write-Host "检测代理候选：$代理" -ForegroundColor DarkGray
		if (测试-代理连通 $代理) {
			return $代理
		}
	}

	return ""
}
