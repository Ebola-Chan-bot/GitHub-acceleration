# Git 命令执行相关的内部辅助函数

function 组成-Git参数 {
	param(
		[Parameter(Mandatory = $true)]
		[string[]]$参数,

		[Parameter()]
		[AllowEmptyString()]
		[string]$代理 = ""
	)

	# 代理仅通过 -c 命令行参数注入本次进程（不写入任何 git 配置文件），
	# 因此不影响用户手动执行 git。
	$完整参数 = @()
	if (-not [string]::IsNullOrWhiteSpace($代理)) {
		$完整参数 += @("-c", "http.proxy=$代理", "-c", "https.proxy=$代理")
	}
	$完整参数 += $参数
	return $完整参数
}

function 执行-Git命令 {
	param(
		[Parameter(Mandatory = $true)]
		[string[]]$参数,

		[Parameter()]
		[AllowEmptyString()]
		[string]$代理 = ""
	)

	& git @(组成-Git参数 $参数 $代理)
	if ($LASTEXITCODE -ne 0) {
		throw "git $($参数 -join ' ') 执行失败。"
	}
}

function 尝试-Git命令 {
	param(
		[Parameter(Mandatory = $true)]
		[string[]]$参数,

		[Parameter()]
		[AllowEmptyString()]
		[string]$代理 = ""
	)

	& git @(组成-Git参数 $参数 $代理)
	return $LASTEXITCODE -eq 0
}

<#
.SYNOPSIS
	执行 git 命令，输出实时显示到控制台并同时收集，用于区分「用户取消」与普通失败。
.DESCRIPTION
	返回对象包含 成功（退出码是否为 0）和 用户取消（输出中是否出现用户取消身份验证对话框的特征文本）。调用方在 用户取消 为真时应中止流程且不记录镜像成败。注意：输出经管道收集后 git 不再显示 \r 进度刷新（stderr 非终端时 git 自动省略进度），但 "fatal:" 等以换行结束的错误信息会逐行实时显示。
#>
function Git执行并区分取消 {
	param(
		[Parameter(Mandatory = $true)]
		[string[]]$参数,

		[Parameter()]
		[AllowEmptyString()]
		[string]$代理 = ""
	)

	$输出行 = [System.Collections.Generic.List[string]]::new()
	$原错误策略 = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	& git @(组成-Git参数 $参数 $代理) 2>&1 | ForEach-Object {
		$行 = "$_"
		$输出行.Add($行)
		if (-not [string]::IsNullOrWhiteSpace($行)) {
			Write-Host $行
		}
	}
	$退出码 = $LASTEXITCODE
	$ErrorActionPreference = $原错误策略

	# GCM 取消对话框会输出 "fatal: User cancelled dialog."，随后 git 报"fatal: Authentication failed for ..."。只把「用户取消对话框」这一确切特征视为取消，单独的 Authentication failed 可能来自镜像限流，仍按镜像失败处理。
	$已取消 = $输出行 | Where-Object {
		$_ -match '(?i)user cancell'
	}

	return [pscustomobject]@{
		成功   = ($退出码 -eq 0)
		用户取消 = [bool]$已取消
	}
}

function 读取-Git文本 {
	param(
		[Parameter(Mandatory = $true)]
		[string[]]$参数,

		[Parameter()]
		[AllowEmptyString()]
		[string]$代理 = ""
	)

	$输出 = & git @(组成-Git参数 $参数 $代理)
	if ($LASTEXITCODE -ne 0) {
		throw "git $($参数 -join ' ') 执行失败。"
	}

	return ($输出 -join "`n").Trim()
}

<#
.SYNOPSIS
	执行只读的 git 命令并返回输出，失败时返回空字符串而非抛错。
	合并 stderr 并用 try/catch 兜底，确保在 EAP=Stop 下绝不影响调用者。
#>
function 尝试读取-Git文本 {
	param(
		[Parameter(Mandatory = $true)]
		[string[]]$参数,

		[Parameter()]
		[AllowEmptyString()]
		[string]$代理 = ""
	)

	try {
		$输出 = & git @(组成-Git参数 $参数 $代理) 2>&1
		if ($LASTEXITCODE -ne 0) {
			return ""
		}

		return (($输出 | ForEach-Object { "$_" }) -join "`n").Trim()
	}
	catch {
		return ""
	}
}
