<#
.SYNOPSIS
	将本地 Git 仓库中指定提交的一个文件恢复到指定路径。
.DESCRIPTION
	直接读取指定提交中的文件对象，不切换分支、不修改暂存区，也不改动工作区中的其它文件。
	普通文件按 Git 中保存的原始字节恢复，不经过文本编码或换行转换；Git LFS 指针文件会自动通过 git lfs smudge 还原为真实内容，并按指针中的 SHA-256 和大小校验。
	指定提交及其文件对象必须已存在于本地仓库；LFS 真实内容不在本地缓存时，git-lfs 会按仓库现有配置自动下载。
	目标路径可以是绝对路径，也可以是相对仓库根目录的路径；父目录不存在时自动创建。目标文件已存在时会被替换，恢复或校验失败不会替换原文件。
.PARAMETER 仓库目录
	本地仓库目录或其子目录，默认为当前工作目录。
.PARAMETER 提交
	要读取的提交，可使用完整或缩写提交哈希，也可使用能解析为提交的分支、标签或修订表达式。
.PARAMETER 文件路径
	要恢复的文件在指定提交中的路径，相对仓库根目录，可使用正斜杠或反斜杠。
.PARAMETER 目标路径
	恢复文件的保存位置。相对路径以仓库根目录为基准；源文件路径与目标路径可以不同。
.EXAMPLE
	恢复-GitHub文件 -仓库目录 "C:\Users\vhtmf\Documents\MATLAB\Transfer-learning" -提交 "ab6381f3b26d3f28b8fbbd470aa14ee147c3f09a" -文件路径 "英文论文/图3.svg" -目标路径 "英文论文\旧图3.svg"
	将指定提交中的 LFS 文件 图3.svg 还原为真实 SVG 内容，保存到仓库根目录下的 英文论文\旧图3.svg。
.EXAMPLE
	恢复-GitHub文件 "D:\Repo" "v1.2.0" "config/app.json" "备份\app-v1.2.0.json"
	将 v1.2.0 标签所指向提交中的普通文件恢复到指定备份路径。
#>
function 恢复-GitHub文件 {
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[string]$仓库目录 = ".",

		[Parameter(Mandatory = $true, Position = 1)]
		[ValidateNotNullOrEmpty()]
		[string]$提交,

		[Parameter(Mandatory = $true, Position = 2)]
		[ValidateNotNullOrEmpty()]
		[string]$文件路径,

		[Parameter(Mandatory = $true, Position = 3)]
		[ValidateNotNullOrEmpty()]
		[string]$目标路径
	)

	if (-not (Test-Path -LiteralPath $仓库目录 -PathType Container)) {
		throw "仓库目录不存在或不是目录：$仓库目录"
	}
	$仓库目录 = (Resolve-Path -LiteralPath $仓库目录).Path
	$仓库根 = 读取-Git文本 @("-C", $仓库目录, "rev-parse", "--show-toplevel")
	if ([string]::IsNullOrWhiteSpace($仓库根)) {
		throw "无法确定仓库根目录：$仓库目录"
	}

	if ([System.IO.Path]::IsPathRooted($文件路径)) {
		throw "文件路径必须是相对仓库根目录的路径：$文件路径"
	}
	$文件路径 = $文件路径.Replace("\", "/")

	if ([System.IO.Path]::IsPathRooted($目标路径)) {
		$目标完整路径 = [System.IO.Path]::GetFullPath($目标路径)
	}
	else {
		$目标完整路径 = [System.IO.Path]::GetFullPath((Join-Path $仓库根 $目标路径))
	}
	if (Test-Path -LiteralPath $目标完整路径 -PathType Container) {
		throw "目标路径是目录，不是文件：$目标完整路径"
	}

	# 先固定为完整提交哈希，再合成 <提交>:<路径> 对象名，避免把用户提供的修订表达式误当作对象名语法的一部分。
	$提交哈希 = 读取-Git文本 @("-C", $仓库根, "rev-parse", "--verify", "$提交^{commit}")
	$对象名 = "${提交哈希}:$文件路径"
	$对象类型 = 读取-Git文本 @("-C", $仓库根, "cat-file", "-t", $对象名)
	if ($对象类型 -ne "blob") {
		throw "指定对象不是文件（对象类型为 $对象类型）：$对象名"
	}

	$目标父目录 = [System.IO.Path]::GetDirectoryName($目标完整路径)
	[void][System.IO.Directory]::CreateDirectory($目标父目录)
	$临时标记 = [guid]::NewGuid().ToString("N")
	$对象临时路径 = Join-Path $目标父目录 ".$([System.IO.Path]::GetFileName($目标完整路径)).$临时标记.对象.tmp"
	$还原临时路径 = Join-Path $目标父目录 ".$([System.IO.Path]::GetFileName($目标完整路径)).$临时标记.还原.tmp"
	$备份临时路径 = Join-Path $目标父目录 ".$([System.IO.Path]::GetFileName($目标完整路径)).$临时标记.备份.tmp"

	try {
		执行-Git二进制命令 -参数 @("cat-file", "blob", $对象名) -输出路径 $对象临时路径 -工作目录 $仓库根
		$LFS指针 = 读取-LFS指针信息 -路径 $对象临时路径
		if ($null -eq $LFS指针) {
			$待保存路径 = $对象临时路径
			$文件类型 = "普通文件"
		}
		else {
			Write-Host "检测到 Git LFS 指针，正在还原真实内容（本地无缓存时会自动下载）..."
			执行-Git二进制命令 -参数 @("lfs", "smudge") -输入路径 $对象临时路径 -输出路径 $还原临时路径 -工作目录 $仓库根
			校验-LFS恢复结果 -路径 $还原临时路径 -指针 $LFS指针
			$待保存路径 = $还原临时路径
			$文件类型 = "LFS 文件"
		}

		# 内容完整落盘且 LFS 校验通过后才替换目标，失败时原目标文件保持不变。
		if (Test-Path -LiteralPath $目标完整路径) {
			[System.IO.File]::Replace($待保存路径, $目标完整路径, $备份临时路径)
		}
		else {
			[System.IO.File]::Move($待保存路径, $目标完整路径)
		}

		Write-Host "恢复完成（$文件类型）：$对象名"
		Write-Host "保存位置：$目标完整路径"
	}
	finally {
		foreach ($临时路径 in @($对象临时路径, $还原临时路径, $备份临时路径)) {
			if (Test-Path -LiteralPath $临时路径) {
				Remove-Item -LiteralPath $临时路径 -Force
			}
		}
	}
}
