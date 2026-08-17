<#
.SYNOPSIS
	通过镜像站点克隆 GitHub 仓库，仅获取默认分支的最新提交（浅克隆）。
.DESCRIPTION
	接受仓库远程地址和本地路径作为参数，使用与拉取相同的动态镜像排序策略，
	依次尝试克隆，成功后记录镜像统计。仅克隆默认分支（--single-branch）且
	只获取最新一次提交（--depth 1），适合快速获取大型仓库的最新代码。
	克隆完成后自动将远程 origin 的地址改回原始 GitHub 地址，
	因此后续手动 git pull/push 等操作直接走 GitHub，不受镜像影响。
.PARAMETER 仓库地址
	GitHub 仓库的 HTTPS 或 SSH 地址，如 https://github.com/用户/仓库.git 或 git@github.com:用户/仓库.git。
.PARAMETER 本地路径
	克隆到的本地目标路径。若该路径不存在则直接克隆到此路径；
	若已存在且为目录，则自动在其下创建与仓库同名的子目录并克隆进去；
	若已存在但不是目录（如同名文件）则报错。
	若目标目录下已存在同一仓库的上次未完成的克隆，则从断点续传（保留已下载的对象）。
.PARAMETER 镜像站前缀
	镜像站地址前缀列表，默认内置多个常用镜像站。
.PARAMETER 记录文件路径
	镜像统计记录文件的保存路径，默认为 "$env:TEMP\镜像拉取记录.json"。
.EXAMPLE
	克隆-GitHub镜像 -仓库地址 "https://github.com/PowerShell/PowerShell.git" -本地路径 "D:\PowerShell"
	通过镜像站克隆 PowerShell 仓库到本地 D:\PowerShell。
.EXAMPLE
	克隆-GitHub镜像 "https://github.com/torvalds/linux.git" "D:\linux" -镜像站前缀 "https://gh-proxy.cn/"
	仅使用指定镜像站克隆 Linux 内核仓库。
#>
function 克隆-GitHub镜像 {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$仓库地址,

		[Parameter(Mandatory = $true, Position = 1)]
		[string]$本地路径,

		[Parameter(Position = 2)]
		[string[]]$镜像站前缀 = $script:镜像站前缀,

		[Parameter()]
		[string]$记录文件路径 = $script:默认记录路径
	)

	$HTTPS仓库地址 = 转换为-HTTPS仓库地址 $仓库地址

	# 续传识别：目标目录已存在且是同一仓库的半成品克隆（origin 相同）则复用之，
	# 保留已下载的对象，从断点继续；否则仍报错。
	$续传 = $false
	if (Test-Path -LiteralPath $本地路径) {
		if (-not (Test-Path -LiteralPath $本地路径 -PathType Container)) {
			throw "目标路径已存在且不是目录：$本地路径"
		}

		if (Test-Path -LiteralPath (Join-Path $本地路径 ".git")) {
			$已有origin = 尝试读取-Git文本 @("-C", $本地路径, "remote", "get-url", "origin")
			if ($已有origin -eq $HTTPS仓库地址) {
				$续传 = $true
				Write-Host "目标目录已存在同一仓库的未完成克隆，将从断点续传：$本地路径"
			}
			else {
				throw "目标路径已存在且是其他仓库：$本地路径"
			}
		}
		else {
			$仓库名 = $HTTPS仓库地址.TrimEnd("/").Split("/")[-1] -replace "(?i)\.git$", ""
			if ([string]::IsNullOrWhiteSpace($仓库名)) {
				throw "无法从仓库地址解析出仓库名：$仓库地址"
			}

			$子目录 = Join-Path $本地路径 $仓库名

			if (Test-Path -LiteralPath (Join-Path $子目录 ".git")) {
				$已有origin = 尝试读取-Git文本 @("-C", $子目录, "remote", "get-url", "origin")
				if ($已有origin -eq $HTTPS仓库地址) {
					$续传 = $true
					$本地路径 = $子目录
					Write-Host "目标子目录已存在同一仓库的未完成克隆，将从断点续传：$本地路径"
				}
				else {
					throw "目标子目录已存在且是其他仓库：$子目录"
				}
			}
			else {
				$本地路径 = $子目录
				Write-Host "目标路径已存在，改为克隆到子目录：$本地路径"

				if (Test-Path -LiteralPath $本地路径) {
					throw "目标子目录已存在：$本地路径"
				}
			}
		}
	}

	$镜像记录 = 读取-镜像记录 $记录文件路径

	# 统计按镜像站（前缀）记录，与具体仓库无关，可跨仓库共享历史经验；
	# 候选条目按各站历史成功率排序
	$候选镜像条目 = 排序-镜像候选 $镜像记录 $镜像站前缀 $HTTPS仓库地址

	# 用 init + fetch 代替 clone：已下载的对象保留在本地，
	# 失败重试或换镜像续传时只补拉缺失部分，实现断点续传
	if (-not $续传) {
		执行-Git命令 @("init", $本地路径)
		执行-Git命令 @("-C", $本地路径, "remote", "add", "origin", $HTTPS仓库地址)
	}

	Push-Location $本地路径
	$成功镜像地址 = ""
	try {
		foreach ($镜像条目 in $候选镜像条目) {
			$镜像地址 = $镜像条目.地址
			$显示评分 = [math]::Round($镜像条目.评分 * 100, 1)
			Write-Host "尝试从镜像拉取（成功率 $显示评分%）：$镜像地址"

			$开始时间 = Get-Date
			$拉取成功 = 尝试-Git命令 @("fetch", "--depth", "1", "--update-shallow", $镜像地址, "HEAD")

			if ($拉取成功) {
				# 镜像可能对上游有提交的仓库返回空数据，造成"成功"的空克隆。
				# 本地为空时用 ls-remote 向该镜像核对：远端确有提交则判定此镜像失败，继续尝试下一个。
				$本地HEAD = 尝试读取-Git文本 @("rev-parse", "FETCH_HEAD")
				if ([string]::IsNullOrWhiteSpace($本地HEAD)) {
					$远程HEAD = 尝试读取-Git文本 @("ls-remote", $镜像地址, "HEAD")
					if (-not [string]::IsNullOrWhiteSpace($远程HEAD)) {
						Write-Host "该镜像返回了空仓库，但远端实际有提交，判定此镜像失败。"
						$拉取成功 = $false
					}
				}
			}

			$耗时毫秒 = [int]((Get-Date) - $开始时间).TotalMilliseconds
			记录-镜像尝试 $镜像记录 $镜像条目.站点 $拉取成功 $耗时毫秒
			保存-镜像记录 $镜像记录 $记录文件路径

			if ($拉取成功) {
				$成功镜像地址 = $镜像地址
				break
			}

			Write-Host "该镜像不可用，继续尝试下一个。"
		}
	}
	finally {
		Pop-Location
	}

	if ([string]::IsNullOrWhiteSpace($成功镜像地址)) {
		Write-Host "已保留 $本地路径 中已下载的部分，再次运行本命令可断点续传。"
		throw "所有镜像站都未能克隆仓库：$仓库地址"
	}

	Push-Location $本地路径
	try {
		# 查远端默认分支名，避免硬编码 main
		$远程HEAD行 = 尝试读取-Git文本 @("ls-remote", "--symref", $成功镜像地址, "HEAD")
		$默认分支 = "main"
		foreach ($行 in $远程HEAD行 -split "`n") {
			if ($行 -match "^ref:\s+refs/heads/(.+)\s+HEAD\s*$") {
				$默认分支 = $Matches[1].Trim()
				break
			}
		}

		# 把拉到的 HEAD 提交检出到本地默认分支
		$浅提交 = 读取-Git文本 @("rev-parse", "FETCH_HEAD")
		执行-Git命令 @("checkout", "--force", "-B", $默认分支, $浅提交)

		# origin 从 init 起就指向原始 GitHub 地址，后续 git pull/push 直接走 GitHub

		Write-Host "克隆完成。已将远程 origin 设置为 $HTTPS仓库地址"

		# 空仓库（尚无任何提交）无法查看提交信息
		$最新提交 = 尝试读取-Git文本 @("log", "-1", "--pretty=format:%h %s")

		if ([string]::IsNullOrWhiteSpace($最新提交)) {
			Write-Host "提示：该仓库目前为空（尚无任何提交）。"
		}
		else {
			Write-Host "当前最新提交：$最新提交"
		}
	}
	finally {
		Pop-Location
	}
}
