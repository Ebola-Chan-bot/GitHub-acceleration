# GitHub加速 - 通过多个 GitHub 镜像站点自动尝试 git fetch
# 按历史成功率智能排序，实现国内无障碍拉取 GitHub 仓库。

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# 内部辅助函数
# ============================================================

function 执行-Git命令 {
	param(
		[Parameter(Mandatory = $true)]
		[string[]]$参数,

		[Parameter()]
		[AllowEmptyString()]
		[string]$代理 = ""
	)

	if ([string]::IsNullOrWhiteSpace($代理)) {
		& git @参数
	}
	else {
		& git @("-c", "http.proxy=$代理", "-c", "https.proxy=$代理") @参数
	}
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

	if ([string]::IsNullOrWhiteSpace($代理)) {
		& git @参数
	}
	else {
		& git @("-c", "http.proxy=$代理", "-c", "https.proxy=$代理") @参数
	}
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

	if ([string]::IsNullOrWhiteSpace($代理)) {
		$输出 = & git @参数
	}
	else {
		$输出 = & git @("-c", "http.proxy=$代理", "-c", "https.proxy=$代理") @参数
	}
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
		$git参数 = @()
		if (-not [string]::IsNullOrWhiteSpace($代理)) {
			$git参数 += @("-c", "http.proxy=$代理", "-c", "https.proxy=$代理")
		}
		$git参数 += $参数

		$输出 = & git @git参数 2>&1
		if ($LASTEXITCODE -ne 0) {
			return ""
		}

		return (($输出 | ForEach-Object { "$_" }) -join "`n").Trim()
	}
	catch {
		return ""
	}
}

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

# ============================================================
# 公开函数
# ============================================================

<#
.SYNOPSIS
	通过多个 GitHub 镜像站点自动尝试 git fetch，按历史成功率智能排序。
.DESCRIPTION
	自动检测当前仓库的 origin 远程和当前分支，通过多个镜像代理站点依次尝试 git fetch，
	并根据历史成功/失败记录智能排序，优先使用成功率最高的镜像。拉取成功后自动执行快进合并（--ff-only）。
.PARAMETER 镜像站前缀
	镜像站地址前缀列表，默认内置 5 个国内常用镜像站。
.PARAMETER 远程名
	Git 远程名称，默认为 "origin"。
.PARAMETER 记录文件路径
	镜像统计记录文件的保存路径，默认为 "$env:TEMP\镜像拉取记录.json"。
.EXAMPLE
	拉取-GitHub镜像
	从 origin 拉取当前分支，使用默认镜像站列表，快进合并。
.EXAMPLE
	拉取-GitHub镜像 -镜像站前缀 "https://gh.llkk.cc/", "https://gh-proxy.com/"
	仅使用指定的两个镜像站。
.EXAMPLE
	拉取-GitHub镜像 -远程名 "upstream"
	从 upstream 远程拉取当前分支。
#>
function 拉取-GitHub镜像 {
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[string[]]$镜像站前缀 = @(
			"https://gh.llkk.cc/",
			"https://gh-proxy.com/",
			"https://ghfast.top/",
			"https://gh-proxy.net/",
			"https://hub.gitmirror.com/"
		),

		[Parameter()]
		[string]$远程名 = "origin",

		[Parameter()]
		[string]$记录文件路径 = (Join-Path $env:TEMP "镜像拉取记录.json")
	)

	$分支 = 读取-Git文本 @("branch", "--show-current")
	if ([string]::IsNullOrWhiteSpace($分支)) {
		throw "当前处于分离 HEAD 状态，无法执行加速拉取。"
	}

	$源仓库地址 = 读取-Git文本 @("remote", "get-url", $远程名)
	$HTTPS仓库地址 = 转换为-HTTPS仓库地址 $源仓库地址

	$镜像记录 = 读取-镜像记录 $记录文件路径

	# 统计按镜像站（前缀）记录，与具体仓库无关，可跨仓库共享历史经验
	$已加入站点 = @()
	$候选镜像条目 = @()
	foreach ($镜像站 in $镜像站前缀) {
		if ([string]::IsNullOrWhiteSpace($镜像站)) {
			continue
		}

		$站点 = $镜像站.TrimEnd("/")
		if ($已加入站点 -contains $站点) {
			continue
		}
		$已加入站点 += $站点

		$候选镜像条目 += [pscustomobject]@{
			站点 = $站点
			地址 = 合成-镜像仓库地址 $镜像站 $HTTPS仓库地址
			评分 = 计算-镜像评分 (读取-镜像统计 $镜像记录 $站点)
		}
	}

	if ($候选镜像条目.Count -eq 0) {
		throw "没有可用的镜像站地址，请检查 -镜像站前缀 参数。"
	}

	$候选镜像条目 = @($候选镜像条目 | Sort-Object -Property 评分 -Descending)

	$成功镜像地址 = ""
	foreach ($镜像条目 in $候选镜像条目) {
		$镜像地址 = $镜像条目.地址
		$显示评分 = [math]::Round($镜像条目.评分 * 100, 1)
		Write-Host "尝试从镜像拉取（成功率 $显示评分%）：$镜像地址"

		$开始时间 = Get-Date
		$拉取成功 = 尝试-Git命令 @("fetch", $镜像地址, $分支)
		$耗时毫秒 = [int]((Get-Date) - $开始时间).TotalMilliseconds
		记录-镜像尝试 $镜像记录 $镜像条目.站点 $拉取成功 $耗时毫秒
		保存-镜像记录 $镜像记录 $记录文件路径

		if ($拉取成功) {
			$成功镜像地址 = $镜像地址
			break
		}

		Write-Host "该镜像不可用，继续尝试下一个。"
	}

	if ([string]::IsNullOrWhiteSpace($成功镜像地址)) {
		throw "所有镜像站都未能获取 $分支。"
	}

	Write-Host "将当前分支快进到镜像中的 $分支..."
	执行-Git命令 @("merge", "--ff-only", "FETCH_HEAD")

	$最新提交 = 读取-Git文本 @("log", "-1", "--pretty=format:%h %s")
	Write-Host "完成。当前最新提交：$最新提交"
}

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
	镜像站地址前缀列表，默认内置 5 个国内常用镜像站。
.PARAMETER 记录文件路径
	镜像统计记录文件的保存路径，默认为 "$env:TEMP\镜像拉取记录.json"。
.EXAMPLE
	克隆-GitHub镜像 -仓库地址 "https://github.com/PowerShell/PowerShell.git" -本地路径 "D:\PowerShell"
	通过镜像站克隆 PowerShell 仓库到本地 D:\PowerShell。
.EXAMPLE
	克隆-GitHub镜像 "https://github.com/torvalds/linux.git" "D:\linux" -镜像站前缀 "https://gh.llkk.cc/"
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
		[string[]]$镜像站前缀 = @(
			"https://gh.llkk.cc/",
			"https://gh-proxy.com/",
			"https://ghfast.top/",
			"https://gh-proxy.net/",
			"https://hub.gitmirror.com/"
		),

		[Parameter()]
		[string]$记录文件路径 = (Join-Path $env:TEMP "镜像拉取记录.json")
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

	# 统计按镜像站（前缀）记录，与具体仓库无关，可跨仓库共享历史经验
	$已加入站点 = @()
	$候选镜像条目 = @()
	foreach ($镜像站 in $镜像站前缀) {
		if ([string]::IsNullOrWhiteSpace($镜像站)) {
			continue
		}

		$站点 = $镜像站.TrimEnd("/")
		if ($已加入站点 -contains $站点) {
			continue
		}
		$已加入站点 += $站点

		$候选镜像条目 += [pscustomobject]@{
			站点 = $站点
			地址 = 合成-镜像仓库地址 $镜像站 $HTTPS仓库地址
			评分 = 计算-镜像评分 (读取-镜像统计 $镜像记录 $站点)
		}
	}

	if ($候选镜像条目.Count -eq 0) {
		throw "没有可用的镜像站地址，请检查 -镜像站前缀 参数。"
	}

	$候选镜像条目 = @($候选镜像条目 | Sort-Object -Property 评分 -Descending)

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

<#
.SYNOPSIS
	将本地提交推送到 GitHub 仓库，支持可选代理。
.DESCRIPTION
	在指定仓库目录（默认当前目录）中向远程推送当前分支。
	若当前分支尚未建立跟踪（上游）关系，推送时会自动建立跟踪（git push -u），
	以后即可直接用 git pull/push 等命令。
	不指定 -远程名 时自动解析：优先使用 origin；没有 origin 且仅有一个远程则使用该远程；
	没有 origin 且存在多个远程时报错，需显式指定 -远程名。
	代理只需通过 -代理 参数指定一次，之后永久记住，以后直接运行 推送-GitHub 会自动使用记住的代理。代理仅以命令行参数 -c http.proxy / -c https.proxy 的形式在本次进程内生效，不写入任何 git 配置文件、不修改全局环境变量，因此完全不影响用户手动执行 git push 或其他 git 命令。指定空字符串（""）可清除已记住的代理，恢复直连推送。
.PARAMETER 仓库目录
	第一个位置参数。仓库所在目录路径，默认为当前目录。
.PARAMETER 代理
	可选。代理地址，如 "http://127.0.0.1:7890" 或 "socks5://127.0.0.1:1080"。
	指定后自动保存，无需再次指定；以后每次推送自动使用记住的代理。
	传入空字符串可清除已记住的代理。不指定则沿用已记住的代理（若无则直连）。
.PARAMETER 远程名
	可选。Git 远程名称。不指定时自动选择：有 origin 则用 origin；
	无 origin 且只有一个远程则用该远程；无 origin 且有多个远程则报错。
.PARAMETER 记录文件路径
	镜像统计记录文件的保存路径（代理也保存在此文件中），默认为 "$env:TEMP\镜像拉取记录.json"。
.EXAMPLE
	推送-GitHub -代理 "http://127.0.0.1:7890"
	首次推送：通过指定代理推送，并永久记住该代理。
.EXAMPLE
	推送-GitHub
	以后推送：自动使用记住的代理和自动解析的远程。
.EXAMPLE
	推送-GitHub "D:\Repo"
	推送指定目录下的仓库（仓库目录为第一个位置参数，可不写参数名）。
.EXAMPLE
	推送-GitHub -代理 ""
	清除记住的代理并直连推送。
#>
function 推送-GitHub {
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[string]$仓库目录 = ".",

		[Parameter()]
		[AllowEmptyString()]
		[string]$代理,

		[Parameter()]
		[string]$远程名,

		[Parameter()]
		[string]$记录文件路径 = (Join-Path $env:TEMP "镜像拉取记录.json")
	)

	if (-not (Test-Path -LiteralPath $仓库目录 -PathType Container)) {
		throw "仓库目录不存在或不是目录：$仓库目录"
	}
	$仓库目录 = (Resolve-Path -LiteralPath $仓库目录).Path

	# 相对记录文件路径先按调用者当前目录解析，避免进入仓库目录后基准改变
	if (-not [System.IO.Path]::IsPathRooted($记录文件路径)) {
		$记录文件路径 = Join-Path (Get-Location).Path $记录文件路径
	}

	Push-Location $仓库目录
	try {
		$分支 = 读取-Git文本 @("branch", "--show-current")
		if ([string]::IsNullOrWhiteSpace($分支)) {
			throw "当前处于分离 HEAD 状态，无法执行推送。"
		}

		if ([string]::IsNullOrWhiteSpace($远程名)) {
			$远程名 = 解析-推送远程名
			Write-Host "自动选择远程：$远程名"
		}

		$记录 = 读取-镜像记录 $记录文件路径

		if ($PSBoundParameters.ContainsKey("代理")) {
			# 用户显式指定了代理：保存并永久记住；显式传空字符串则清除代理
			$记录.代理 = $代理
			保存-镜像记录 $记录 $记录文件路径
			Write-Host "已保存推送代理，以后无需再指定：$代理"
		}

		$使用代理 = 获取-已存代理 $记录

		if ([string]::IsNullOrWhiteSpace($使用代理)) {
			Write-Host "未设置代理，直连推送。"
		}
		else {
			Write-Host "将通过已记住的代理推送：$使用代理"
		}

		# 检查当前分支是否已有跟踪（上游）
		$上游 = 尝试读取-Git文本 @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
		if ([string]::IsNullOrWhiteSpace($上游)) {
			# 尚未设置跟踪，推送时用 -u 一并建立
			Write-Host "当前分支尚无跟踪，将推送并建立跟踪关系。"
			执行-Git命令 @("push", "-u", $远程名, $分支) -代理 $使用代理
		}
		else {
			执行-Git命令 @("push", $远程名, $分支) -代理 $使用代理
		}

		Write-Host "推送完成。已推送 $分支 到 $远程名。"
	}
	finally {
		Pop-Location
	}
}

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
		[string]$记录文件路径 = (Join-Path $env:TEMP "镜像拉取记录.json")
	)

	$镜像记录 = 读取-镜像记录 $记录文件路径

	if ($镜像记录.镜像.PSObject.Properties.Count -eq 0) {
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
		[string]$记录文件路径 = (Join-Path $env:TEMP "镜像拉取记录.json")
	)

	if (Test-Path -LiteralPath $记录文件路径) {
		Remove-Item -LiteralPath $记录文件路径 -Force
		Write-Host "已删除镜像统计记录：$记录文件路径"
	}
	else {
		Write-Host "镜像统计记录文件不存在，无需重置。"
	}
}

# ============================================================
# 模块初始化：加载时输出提示
# ============================================================

Write-Verbose "GitHub加速 模块已加载。使用 '拉取-GitHub镜像' 开始拉取。" -Verbose:$false
