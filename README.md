通过多个 GitHub 镜像站点自动尝试 git 操作，按历史成功率智能排序，实现中国大陆无障碍访问 GitHub 仓库。

# 安装

```powershell
Import-Module '.\GitHub加速\GitHub加速.psd1'
```

# 命令

| 命令 | 用途 |
|------|------|
| `拉取-GitHub镜像` | 在现有仓库中通过镜像站 git fetch + 快进合并 |
| `克隆-GitHub镜像` | 通过镜像站浅克隆仓库（只取默认分支最新提交） |
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

## 统计管理

```powershell
# 查看各镜像站历史表现
查看-镜像统计

# 重置统计
重置-镜像统计
```

# 工作原理

1. 获取仓库 HTTPS 地址（SSH 地址自动转换）
2. 读取本地镜像成功/失败记录，按评分排序（成功率 × 100 + 成功次数 × 2 − 失败次数 × 2 + 最近结果修正）
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