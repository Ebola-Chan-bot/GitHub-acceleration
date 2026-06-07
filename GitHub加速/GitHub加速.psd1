# GitHub加速 模块清单
# 通过多个 GitHub 镜像站点自动尝试 git fetch，按历史成功率智能排序。

@{

    # 模块版本
    ModuleVersion     = '1.0.0'

    # 模块 GUID
    GUID              = '120952b7-5ab7-4f8c-bb27-3aa50bf5929f'

    # 作者
    Author            = '埃博拉酱-机器人'

    # 公司名称
    CompanyName       = '一致行动党'

    # 版权声明
    Copyright         = '(c) 2026 一致行动党。MIT 许可证。'

    # 模块描述
    Description       = '通过多个 GitHub 镜像站点自动尝试 git 操作，按历史成功率智能排序，实现国内无障碍访问 GitHub 仓库。支持镜像 fetch 快进合并、镜像浅克隆（--depth 1 --single-branch），提供镜像统计查看和重置功能。'

    # PowerShell 最低版本
    PowerShellVersion = '5.1'

    # 模块脚本（.psm1 文件）
    RootModule        = 'GitHub加速.psm1'

    # 导出函数
    FunctionsToExport = @(
        '拉取-GitHub镜像',
        '克隆-GitHub镜像',
        '查看-镜像统计',
        '重置-镜像统计'
    )

    # 导出变量
    VariablesToExport = @()

    # 导出别名
    AliasesToExport   = @()

    # 私有数据
    PrivateData       = @{
        PSData = @{
            Tags         = @('git', 'github', 'mirror', 'proxy', 'fetch', 'pull', '镜像', '加速', 'China')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/Ebola-Chan/GitHub-Acceleration'
            ReleaseNotes = '新增 查看-镜像统计、克隆-GitHub镜像 和 重置-镜像统计 命令。'
        }
    }

    # 帮助信息 URI
    HelpInfoURI       = ''

    # 默认命令前缀
    DefaultCommandPrefix = ''
}
