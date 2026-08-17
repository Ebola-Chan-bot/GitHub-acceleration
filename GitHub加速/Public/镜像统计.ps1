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
		[string]$记录文件路径 = $script:默认记录路径
	)

	$镜像记录 = 读取-镜像记录 $记录文件路径

	if (@($镜像记录.镜像.PSObject.Properties).Count -eq 0) {
		Write-Host "暂无镜像使用记录。"
		return
	}

	$统计列表 = @()
	foreach ($属性 in $镜像记录.镜像.PSObject.Properties) {
		$统计 = 确保-镜像统计结构 $属性.Value
		$评分 = 计算-镜像评分 $统计
		$成功百分比 = [math]::Round($评分 * 100, 1)

		$统计列表 += [pscustomobject]@{
			镜像站    = $属性.Name
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
		[string]$记录文件路径 = $script:默认记录路径
	)

	if (Test-Path -LiteralPath $记录文件路径) {
		Remove-Item -LiteralPath $记录文件路径 -Force
		Write-Host "已删除镜像统计记录：$记录文件路径"
	}
	else {
		Write-Host "镜像统计记录文件不存在，无需重置。"
	}
}
