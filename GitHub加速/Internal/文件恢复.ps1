# 历史文件恢复所需的二进制进程与 Git LFS 辅助函数

function 引用-Git进程参数 {
	# ProcessStartInfo 在 Windows PowerShell 5.1 中没有 ArgumentList，按 Windows 命令行规则逐个引用参数，确保中文、空格、引号和末尾反斜杠不被改写。
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$参数
	)

	if ($参数.Length -eq 0) {
		return '""'
	}

	$结果 = [System.Text.StringBuilder]::new()
	[void]$结果.Append('"')
	$反斜杠数 = 0
	foreach ($字符 in $参数.ToCharArray()) {
		if ($字符 -eq '\') {
			$反斜杠数++
			continue
		}

		if ($字符 -eq '"') {
			[void]$结果.Append(('\' * ($反斜杠数 * 2 + 1)))
			[void]$结果.Append('"')
			$反斜杠数 = 0
			continue
		}

		[void]$结果.Append(('\' * $反斜杠数))
		[void]$结果.Append($字符)
		$反斜杠数 = 0
	}

	# 结尾的反斜杠必须翻倍，否则会转义包围参数的右引号。
	[void]$结果.Append(('\' * ($反斜杠数 * 2)))
	[void]$结果.Append('"')
	return $结果.ToString()
}

function 执行-Git二进制命令 {
	# 直接复制标准输入、标准输出的字节流，避免 PowerShell 管道按文本解码或改写换行；标准错误异步读取，防止缓冲区填满后死锁。
	param(
		[Parameter(Mandatory = $true)]
		[string[]]$参数,

		[Parameter(Mandatory = $true)]
		[string]$输出路径,

		[Parameter()]
		[string]$输入路径,

		[Parameter(Mandatory = $true)]
		[string]$工作目录
	)

	$启动信息 = [System.Diagnostics.ProcessStartInfo]::new()
	$启动信息.FileName = (Get-Command git -CommandType Application -ErrorAction Stop).Source
	$启动信息.Arguments = (@($参数 | ForEach-Object { 引用-Git进程参数 $_ }) -join " ")
	$启动信息.WorkingDirectory = $工作目录
	$启动信息.UseShellExecute = $false
	$启动信息.CreateNoWindow = $true
	$启动信息.RedirectStandardOutput = $true
	$启动信息.RedirectStandardError = $true
	$启动信息.RedirectStandardInput = -not [string]::IsNullOrEmpty($输入路径)
	# git-lfs 只要检测到此变量存在就可能跳过 smudge，即使值为 0 也一样，因此必须彻底移除才能确保还原真实内容。
	[void]$启动信息.EnvironmentVariables.Remove("GIT_LFS_SKIP_SMUDGE")

	$进程 = [System.Diagnostics.Process]::new()
	$进程.StartInfo = $启动信息
	try {
		# Process.Start 创建 StandardInput 的 StreamWriter 时会按 Console.InputEncoding 写入前导字节；当前环境默认 UTF-8 BOM 会使 LFS 指针无法解析，因此必须在启动前临时改用无前导字节的 ASCII，取得底层流后立即恢复控制台编码。
		$原输入编码 = $null
		try {
			if ($启动信息.RedirectStandardInput) {
				$原输入编码 = [Console]::InputEncoding
				[Console]::InputEncoding = [System.Text.ASCIIEncoding]::new()
			}
			if (-not $进程.Start()) {
				throw "无法启动 git 进程。"
			}
			if ($启动信息.RedirectStandardInput) {
				$标准输入流 = $进程.StandardInput.BaseStream
			}
		}
		finally {
			if ($null -ne $原输入编码) {
				[Console]::InputEncoding = $原输入编码
			}
		}

		$错误任务 = $进程.StandardError.ReadToEndAsync()
		if ($启动信息.RedirectStandardInput) {
			$输入流 = [System.IO.File]::OpenRead($输入路径)
			try {
				$输入流.CopyTo($标准输入流)
				$标准输入流.Close()
			}
			finally {
				$输入流.Dispose()
			}
		}

		$输出流 = [System.IO.File]::Create($输出路径)
		try {
			$进程.StandardOutput.BaseStream.CopyTo($输出流)
		}
		finally {
			$输出流.Dispose()
		}

		$进程.WaitForExit()
		$错误文本 = $错误任务.Result.Trim()
		if (-not [string]::IsNullOrWhiteSpace($错误文本)) {
			Write-Host $错误文本
		}
		if ($进程.ExitCode -ne 0) {
			throw "git $($参数 -join ' ') 执行失败（退出码 $($进程.ExitCode)）。"
		}
	}
	finally {
		$进程.Dispose()
	}
}

function 读取-LFS指针信息 {
	# Git LFS 指针很小且以 ASCII 编写，只读取文件头即可识别，不把大型普通文件整体载入内存。
	param(
		[Parameter(Mandatory = $true)]
		[string]$路径
	)

	$流 = [System.IO.File]::OpenRead($路径)
	try {
		$缓冲区 = [byte[]]::new(1024)
		$长度 = $流.Read($缓冲区, 0, $缓冲区.Length)
	}
	finally {
		$流.Dispose()
	}

	$文件头 = [System.Text.Encoding]::ASCII.GetString($缓冲区, 0, $长度)
	if ($文件头 -notmatch "\Aversion https://git-lfs\.github\.com/spec/v1\r?\n") {
		return $null
	}

	$对象匹配 = [regex]::Match($文件头, "(?m)^oid sha256:([0-9a-f]{64})\r?$")
	$大小匹配 = [regex]::Match($文件头, "(?m)^size ([0-9]+)\r?$")
	if (-not $对象匹配.Success -or -not $大小匹配.Success) {
		throw "文件带有 Git LFS 指针头，但缺少有效的 SHA-256 或大小字段：$路径"
	}

	return [pscustomobject]@{
		对象ID = $对象匹配.Groups[1].Value
		大小   = [long]::Parse($大小匹配.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
	}
}

function 校验-LFS恢复结果 {
	param(
		[Parameter(Mandatory = $true)]
		[string]$路径,

		[Parameter(Mandatory = $true)]
		[pscustomobject]$指针
	)

	$文件信息 = [System.IO.FileInfo]::new($路径)
	if ($文件信息.Length -ne $指针.大小) {
		throw "LFS 文件恢复后大小不符：期望 $($指针.大小) 字节，实际 $($文件信息.Length) 字节。目标文件尚未替换。"
	}

	$实际哈希 = (Get-FileHash -LiteralPath $路径 -Algorithm SHA256).Hash.ToLowerInvariant()
	if ($实际哈希 -ne $指针.对象ID) {
		throw "LFS 文件恢复后 SHA-256 校验失败：期望 $($指针.对象ID)，实际 $实际哈希。目标文件尚未替换。"
	}
}
