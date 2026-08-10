通过多个 GitHub 镜像站点自动尝试 git 操作，按历史成功率智能排序，实现中国大陆无障碍访问 GitHub 仓库。

# 安装

```powershell
Install-Module -Name GitHub加速 -Scope AllUsers
```

# 命令

| 命令 | 用途 |
|------|------|
| `拉取-GitHub镜像` | 在现有仓库中通过镜像站 git fetch + 快进合并 |
| `克隆-GitHub镜像` | 通过镜像站浅克隆仓库（只取默认分支最新提交） |
| `推送-GitHub` | 推送当前分支，支持可选代理（首次指定即永久记住） |
| `查看-镜像统计` | 查看各镜像站的历史成功率、耗时等统计 |
| `重置-镜像统计` | 清除统计记录，从头开始 |

# 用法

## 拉取

在任意 Git 仓库中执行：

```powershell
# 拉取当前分支，使用默认镜像站
拉取-GitHub镜像

# 指定自定义镜像站
拉取-GitHub镜像 -镜像站前缀 "https://gh.llkk.cc/", "https://gh-proxy.com/"

# 从 upstream 拉取
拉取-GitHub镜像 -远程名 "upstream"
```

## 克隆

```powershell
# 克隆仓库到本地
克隆-GitHub镜像 "https://github.com/PowerShell/PowerShell.git" "D:\PowerShell"

# 支持 SSH 地址
克隆-GitHub镜像 "git@github.com:用户/仓库.git" "D:\Repo"

# 指定自定义镜像站
克隆-GitHub镜像 "https://github.com/torvalds/linux.git" "D:\linux" -镜像站前缀 "https://gh.llkk.cc/"
```

克隆完成后，模块会自动将远程 `origin` 的地址改回原始 GitHub 地址（而非镜像站），因此之后的 `git pull`、`git push`、以及 `拉取-GitHub镜像` 等操作都直接面向 GitHub，不受克隆时所用镜像的影响。

## 推送（支持可选代理）

拉取走镜像，推送需要直连 GitHub。`推送-GitHub` 支持通过本地代理推送。代理只需在第一次推送时通过 `-代理` 参数指定一次，之后永久记住，以后直接推送即可：

```powershell
# 首次推送：指定代理，自动保存，之后无需再指定
推送-GitHub -代理 "http://127.0.0.1:7890"

# 以后推送：自动使用记住的代理
推送-GitHub

# 指定仓库目录（默认当前目录）
推送-GitHub -仓库目录 "D:\Repo"

# 显式指定远程（不指定时自动选择：有 origin 用 origin；
# 无 origin 且仅一个远程则用该远程；无 origin 且多个远程则报错）
推送-GitHub -远程名 "upstream"

# 清除记住的代理，恢复直连
推送-GitHub -代理 ""
```

代理只影响本模块的推送功能：代理仅以 `git -c http.proxy=... -c https.proxy=...` 命令行参数形式在本次进程内生效，不写入任何 git 配置、不修改全局环境变量，用户手动执行的 `git push` 等命令完全不受影响。代理保存在 `%TEMP%\镜像拉取记录.json` 中。

## 统计管理

```powershell
# 查看各镜像站历史表现
查看-镜像统计

# 重置统计
重置-镜像统计
```

# 工作原理

1. 获取仓库 HTTPS 地址（SSH 地址自动转换）
2. 读取本地镜像成功/失败记录，按成功率排序（无记录的镜像视为成功失败各 1 次，初始成功率 50%）
3. 按评分从高到低依次尝试各镜像站
4. 成功后记录统计并继续操作（fetch 后自动 `git merge --ff-only FETCH_HEAD`）

# 默认镜像站

| 镜像站 | URL |
|--------|-----|
| gh.llkk.cc | `https://gh.llkk.cc/` |
| gh-proxy.com | `https://gh-proxy.com/` |
| ghfast.top | `https://ghfast.top/` |
| gh-proxy.net | `https://gh-proxy.net/` |
| hub.gitmirror.com | `https://hub.gitmirror.com/` |

## 安全发布

```powershell
# 发布当前目录下的模块
.\Gallery发布.ps1

# 指定模块路径
.\Gallery发布.ps1 -模块路径 ".\GitHub加速"

# 将 Gallery发布 脚本自身发布到 PSGallery
.\Gallery发布.ps1 -自身
```

首次运行会提示输入 PowerShell Gallery API 密钥，之后自动加密保存（Windows DPAPI，仅本机当前用户可解密），后续发布无需任何输入。密钥文件 `.apikey` 自动加入 `.gitignore`。

API 密钥获取：PowerShell Gallery 右上角 → API Keys → Create。

## 许可

MIT