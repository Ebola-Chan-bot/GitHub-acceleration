function 推送-分支 {
	# 推送分支；若被远端以 non-fast-forward 拒绝，交互询问是否用
	# --force-with-lease 强推覆盖远端。确认通过则改为强推并重试。
	param(
		[Parameter(Mandatory = $true)]
		[string[]]$推送参数,

		[Parameter()]
		[AllowEmptyString()]
		[string]$代理 = "",

		[Parameter()]
		[string]$远程名 = "",

		[Parameter()]
		[string]$分支 = ""
	)

	while ($true) {
		# 不捕获 git 输出：让 stderr（进度与错误信息均走 stderr）直接流向控制台实时显示，避免重定向进管道后被行缓冲卡住。
		# 失败原因事后用 fetch + 祖先关系判断，不依赖解析错误文本。
		$原错误策略 = $ErrorActionPreference
		$ErrorActionPreference = "Continue"
		& git @(组成-Git参数 $推送参数 $代理)
		$退出码 = $LASTEXITCODE
		$ErrorActionPreference = $原错误策略

		if ($退出码 -eq 0) {
			return
		}

		$已强推过 = $推送参数 -contains "--force-with-lease"
		if ($已强推过) {
			throw "强推仍被远端拒绝（远端在你 fetch 后又有新提交），已停止以防误覆盖，请拉取后重试。"
		}

		# fetch 远端最新状态，判断失败是否为分支分叉（non-fast-forward）
		$获取成功 = 尝试-Git命令 @("fetch", $远程名) -代理 $代理
		if (-not $获取成功) {
			throw "git push 执行失败，且无法获取远端状态，请检查网络或代理（错误详情见上方 git 输出）。"
		}

		$远端提交 = 尝试读取-Git文本 @("rev-parse", "$远程名/$分支")
		if (-not [string]::IsNullOrWhiteSpace($远端提交)) {
			# 远端分支尖端不是本地 HEAD 的祖先 => 分叉（远端有本地没有的提交）
			$远端在本地历史内 = 尝试-Git命令 @("merge-base", "--is-ancestor", $远端提交, "HEAD")
			if (-not $远端在本地历史内) {
				Write-Host ""
				Write-Host "远端 $远程名/$分支 上存在本地没有的提交，普通推送无法完成。" -ForegroundColor Yellow
				$选择 = $null
				while ($null -eq $选择 -or $选择 -notmatch "^[yYnN]$") {
					$输入 = Read-Host "是否强推覆盖远端？（--force-with-lease；远端独有的提交将丢失，请谨慎）[y/N]"
					if ([string]::IsNullOrWhiteSpace($输入)) { $选择 = "n" }
					else { $选择 = $输入.Substring(0, 1) }
				}

				if ($选择 -match "^[yY]$") {
					Write-Host "将以 --force-with-lease 强推覆盖远端（刚才已 fetch，校验基准为最新）..." -ForegroundColor Yellow
					$推送参数 = @($推送参数[0], "--force-with-lease") + @($推送参数 | Select-Object -Skip 1)
					continue
				}

				throw "已放弃推送。远端领先于本地，请先拉取并合并远端的更改后再推送。"
			}
		}

		# 到这里说明不是分叉：可能是 pre-push 钩子失败（如 Git LFS 懒加载超时 / missing object）、权限不足等，真实原因已在上方 git 输出中打印。
		throw "git push 执行失败，具体原因见上方 git 输出（常见原因：pre-push 钩子失败（如 LFS 对象懒加载失败）、权限不足等）。"
	}
}

function LFS推送范围有改动 {
	# 检测本次推送范围（HEAD 相对所有远程的新提交）内是否改动了 LFS指针文件。合并提交不参与检测（git log --name-only 对合并提交默认不输出文件名）。任何检测失败都保守地返回 $true（宁可多传 LFS，也不误跳过）。
	try {
		$原错误策略 = $ErrorActionPreference
		$ErrorActionPreference = "Continue"

		$路径行 = @(git log --name-only --pretty=format: HEAD --not --remotes 2>$null)
		$log退出码 = $LASTEXITCODE
		$ErrorActionPreference = $原错误策略

		if ($log退出码 -ne 0) {
			return $true
		}

		$改动路径 = @($路径行 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
		if ($改动路径.Count -eq 0) {
			return $false
		}

		# 分批以命令行参数方式查询 filter 属性（不走 stdin，避免编码问题），值为 lfs 即 LFS 指针文件被改动
		for ($批 = 0; $批 -lt [math]::Ceiling($改动路径.Count / 100); $批++) {
			$段 = @($改动路径 | Select-Object -Skip ($批 * 100) -First 100)
			$属性行 = @(& git @(@("check-attr", "filter", "--") + $段) 2>$null)
			if ($LASTEXITCODE -ne 0) {
				return $true
			}
			foreach ($行 in $属性行) {
				if ($行 -match ': filter: lfs$') {
					return $true
				}
			}
		}
		return $false
	}
	catch {
		return $true
	}
}

function 是-LFS仓库 {
	if (Test-Path ".git\lfs") {
		return $true
	}

	if (Test-Path ".git\hooks\pre-push") {
		return [bool](Select-String -LiteralPath ".git\hooks\pre-push" -Pattern "git[l]fs" -Quiet)
	}

	return $false
}

function 确保-Fetch引用规范 {
	# 某些 fork（如 GitHub CLI / API 创建的）的远程可能缺少 fetch refspec，导致 fetch 不生成 refs/remotes/<远程>/* 引用，分支跟踪名存实亡（git push -u 只写 branch.<分支>.merge 配置，但不产生远端跟踪引用）。检测到缺失时自动补上标准 refspec，并立即 fetch 当前分支生成跟踪引用。
	param(
		[Parameter(Mandatory = $true)]
		[string]$远程名,

		[Parameter(Mandatory = $true)]
		[string]$分支,

		[Parameter()]
		[AllowEmptyString()]
		[string]$代理 = ""
	)

	$原错误策略 = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	$现有规范 = @(git config --get-all "remote.$远程名.fetch" 2>$null)
	$ErrorActionPreference = $原错误策略

	if ($现有规范.Count -gt 0) {
		return
	}

	Write-Host "检测到远程 $远程名 缺少 fetch refspec（此类仓库的分支跟踪会失效），自动补上标准配置..." -ForegroundColor Cyan
	git config "remote.$远程名.fetch" "+refs/heads/*:refs/remotes/$远程名/*"

	# 立即获取当前分支，生成 refs/remotes/<远程>/<分支>，使跟踪（@{u}）真正可用
	$原错误策略 = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	& git @(组成-Git参数 @("fetch", "--progress", $远程名, "${分支}:refs/remotes/$远程名/$分支") $代理) 2>&1 | ForEach-Object { Write-Host $_ }
	$ErrorActionPreference = $原错误策略
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
	若推送被远端以 non-fast-forward 拒绝（远端存在本地没有的提交），会交互式询问是否强推覆盖远端：确认则使用 --force-with-lease 强推，否则放弃推送。
	若仓库启用 Git LFS，会自动检测本次推送范围的提交是否真正改动了 LFS 文件：未改动则自动跳过 LFS 对象上传（仅推送 git 对象与 LFS 指针，等同于 GIT_LFS_SKIP_PUSH=1），避免为上游的大体积 LFS 数据白等；改动了则正常上传。
	若检测到远程缺少 fetch refspec（常见于 GitHub CLI/API 创建的 fork，会导致分支跟踪名存实亡），会自动补上标准 refspec 并 fetch 生成跟踪引用。
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
		[string]$记录文件路径 = $script:默认记录路径
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

		# 显式加 --progress：输出被重定向时仍可看到实时推送进度
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

		$自动跳过LFS = $false
		if ((是-LFS仓库) -and -not (LFS推送范围有改动)) {
			$env:GIT_LFS_SKIP_PUSH = "1"
			$自动跳过LFS = $true
			Write-Host "检测到推送范围内的提交未改动 LFS 文件，自动跳过 LFS 对象上传。" -ForegroundColor Cyan
		}

		# 确保远程有 fetch refspec（fork 可能缺失），否则分支跟踪名存实亡
		确保-Fetch引用规范 $远程名 $分支 -代理 $使用代理

		# 检查当前分支是否已有跟踪（上游）
		$上游 = 尝试读取-Git文本 @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
		if ([string]::IsNullOrWhiteSpace($上游)) {
			# 尚未设置跟踪，推送时用 -u 一并建立
			Write-Host "当前分支尚无跟踪，将推送并建立跟踪关系。"
			推送-分支 @("push", "--progress", "-u", $远程名, $分支) -代理 $使用代理 -远程名 $远程名 -分支 $分支
		}
		else {
			推送-分支 @("push", "--progress", $远程名, $分支) -代理 $使用代理 -远程名 $远程名 -分支 $分支
		}

		Write-Host "推送完成。已推送 $分支 到 $远程名。"
	}
	finally {
		if ($自动跳过LFS) {
			Remove-Item Env:GIT_LFS_SKIP_PUSH -ErrorAction SilentlyContinue
		}
		Pop-Location
	}
}
