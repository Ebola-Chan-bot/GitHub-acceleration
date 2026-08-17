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
		# 捕获 stderr 用于判断失败原因。git 的正常进度输出走 stderr，
		# 在模块 EAP=Stop 下会升级为终止性错误，故临时放宽错误策略。
		$原错误策略 = $ErrorActionPreference
		$ErrorActionPreference = "Continue"
		$输出 = & git @(组成-Git参数 $推送参数 $代理) 2>&1
		$LASTEXITCODE2 = $LASTEXITCODE
		$ErrorActionPreference = $原错误策略

		if ($LASTEXITCODE2 -eq 0) {
			if ($输出) { $输出 | ForEach-Object { Write-Host $_ } }
			return
		}

		$输出文本 = (($输出 | ForEach-Object { "$_" }) -join "`n").Trim()
		if ($输出文本) { Write-Host $输出文本 }

		$已强推过 = $推送参数 -contains "--force-with-lease"
		if (-not $已强推过 -and $输出文本 -match "non-fast-forward|\[rejected\]") {
			Write-Host ""
			Write-Host "远端 $远程名/$分支 上存在本地没有的提交，普通推送无法完成。" -ForegroundColor Yellow
			$选择 = $null
			while ($null -eq $选择 -or $选择 -notmatch "^[yYnN]$") {
				$输入 = Read-Host "是否强推覆盖远端？（--force-with-lease；远端独有的提交将丢失，请谨慎）[y/N]"
				if ([string]::IsNullOrWhiteSpace($输入)) { $选择 = "n" }
				else { $选择 = $输入.Substring(0, 1) }
			}

			if ($选择 -match "^[yY]$") {
				Write-Host "将强推覆盖远端。先获取远端最新状态，以确保 --force-with-lease 有最新校验基准..." -ForegroundColor Yellow
				$获取成功 = 尝试-Git命令 @("fetch", $远程名) -代理 $代理
				if (-not $获取成功) {
					throw "无法获取远端 $远程名 的最新状态（请检查网络或代理），不能安全地强推。"
				}
				$推送参数 = @($推送参数[0], "--force-with-lease") + @($推送参数 | Select-Object -Skip 1)
				continue
			}

			throw "已放弃推送。远端领先于本地，请先拉取并合并远端的更改后再推送。"
		}

		throw "git $($推送参数 -join ' ') 执行失败。"
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
	若推送被远端以 non-fast-forward 拒绝（远端存在本地没有的提交），会交互式询问是否强推覆盖远端：确认则使用 --force-with-lease 强推，否则放弃推送。
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
			推送-分支 @("push", "-u", $远程名, $分支) -代理 $使用代理 -远程名 $远程名 -分支 $分支
		}
		else {
			推送-分支 @("push", $远程名, $分支) -代理 $使用代理 -远程名 $远程名 -分支 $分支
		}

		Write-Host "推送完成。已推送 $分支 到 $远程名。"
	}
	finally {
		Pop-Location
	}
}
