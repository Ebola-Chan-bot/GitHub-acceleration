# 镜像统计记录的读写与评分相关的内部辅助函数

function 新建-镜像记录 {
	return [pscustomobject]@{
		版本   = 1
		最后更新 = ""
		代理   = ""
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
	确保-对象属性 $记录 "代理" ""
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
