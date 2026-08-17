# 镜像地址合成、候选排序与推送辅助相关的内部函数

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

function 获取-已存代理 {
	param(
		[Parameter(Mandatory = $true)]
		[pscustomobject]$记录
	)

	if ($null -eq $记录.PSObject.Properties["代理"]) {
		return ""
	}

	if ($null -eq $记录.代理) {
		return ""
	}

	return [string]$记录.代理
}

function 解析-推送远程名 {
	$远程列表 = @()
	foreach ($行 in ((读取-Git文本 @("remote")) -split "`n")) {
		$行 = $行.Trim()
		if (-not [string]::IsNullOrWhiteSpace($行)) {
			$远程列表 += $行
		}
	}

	if ($远程列表.Count -eq 0) {
		throw "当前仓库没有配置任何远程，无法推送。"
	}

	if ($远程列表 -contains "origin") {
		return "origin"
	}

	if ($远程列表.Count -eq 1) {
		return $远程列表[0]
	}

	throw "当前仓库没有 origin 且存在多个远程（$($远程列表 -join '、')），请通过 -远程名 指定要推送的远程。"
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

function 排序-镜像候选 {
	param(
		[Parameter(Mandatory = $true)]
		[pscustomobject]$记录,

		[Parameter(Mandatory = $true)]
		[string[]]$镜像站前缀,

		[Parameter(Mandatory = $true)]
		[string]$仓库地址
	)

	# 统计按镜像站（前缀）记录，与具体仓库无关，可跨仓库共享历史经验
	$已加入站点 = @()
	$候选条目 = @()
	foreach ($镜像站 in $镜像站前缀) {
		if ([string]::IsNullOrWhiteSpace($镜像站)) {
			continue
		}

		$站点 = $镜像站.TrimEnd("/")
		if ($已加入站点 -contains $站点) {
			continue
		}
		$已加入站点 += $站点

		$候选条目 += [pscustomobject]@{
			站点 = $站点
			地址 = 合成-镜像仓库地址 $镜像站 $仓库地址
			评分 = 计算-镜像评分 (读取-镜像统计 $记录 $站点)
		}
	}

	if ($候选条目.Count -eq 0) {
		throw "没有可用的镜像站地址，请检查 -镜像站前缀 参数。"
	}

	return @($候选条目 | Sort-Object -Property 评分 -Descending)
}
