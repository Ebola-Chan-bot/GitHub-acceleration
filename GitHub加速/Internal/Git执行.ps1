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
