# GitHub加速 模块清单
# 通过多个 GitHub 镜像站点自动尝试 git fetch，按历史成功率智能排序。

@{

    # 模块版本
    ModuleVersion     = '1.1.0'

    # 模块 GUID
    GUID              = '120952b7-5ab7-4f8c-bb27-3aa50bf5929f'

    # 作者
    Author            = '埃博拉酱-机器人'

    # 公司名称
    CompanyName       = '一致行动党'

    # 版权声明
    Copyright         = '(c) 2026 一致行动党。MIT 许可证。'

    # 模块描述
    Description       = '通过多个 GitHub 镜像站点自动尝试 git 操作，按历史成功率智能排序，实现国内无障碍访问 GitHub 仓库。

命令用法：

1. 拉取-GitHub镜像：在现有仓库中通过镜像站 fetch + 快进合并拉取当前分支。
   拉取-GitHub镜像 [-镜像站前缀 <镜像URL列表>] [-远程名 origin]
   例：拉取-GitHub镜像；拉取-GitHub镜像 -远程名 upstream

2. 克隆-GitHub镜像：通过镜像站浅克隆仓库（--depth 1 --single-branch），仅取默认分支最新提交；克隆完成后自动将远程 origin 改回原始 GitHub 地址，后续 git 操作不受镜像影响。
   克隆-GitHub镜像 <仓库HTTPS/SSH地址> <本地路径> [-镜像站前缀 <镜像URL列表>]
   例：克隆-GitHub镜像 "git@github.com:用户/仓库.git" "D:\Repo"

3. 推送-GitHub：直连推送当前分支，支持可选代理。
   推送-GitHub [-代理 <代理地址>] [-远程名 <远程>] [-仓库目录 <路径，默认当前目录>]
   远程自动解析：有 origin 用 origin；无 origin 且仅一个远程则用该远程；无 origin 且多个远程则报错。
   代理首次指定即永久记住，以后无需再指定；传空字符串可清除。代理仅以 git -c http.proxy/-c https.proxy 本次进程内生效，不影响手动 git。
   例：推送-GitHub -代理 "http://127.0.0.1:7890"；推送-GitHub

4. 查看-镜像统计：查看各镜像站的历史成功率、耗时等统计。
   查看-镜像统计

5. 重置-镜像统计：清除镜像统计记录，从头开始。
   重置-镜像统计'

    # PowerShell 最低版本
    PowerShellVersion = '5.1'

    # 模块脚本（.psm1 文件）
    RootModule        = 'GitHub加速.psm1'

    # 导出函数
    FunctionsToExport = @(
        '拉取-GitHub镜像',
        '克隆-GitHub镜像',
        '推送-GitHub',
        '查看-镜像统计',
        '重置-镜像统计'
    )

    # 私有数据
    PrivateData       = @{
        PSData = @{
            Tags         = @('git', 'github', 'mirror', 'proxy', 'fetch', 'pull', '镜像', '加速', 'China')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/Ebola-Chan-bot/GitHub-Acceleration'
            ReleaseNotes = '新增 推送-GitHub 命令，支持可选代理推送（代理首次指定即永久记住，仅作用于本模块推送，不影响手动 git）。'
        }
    }
}
