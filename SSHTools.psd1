@{
    RootModule        = 'SSHTools.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '04d9f850-f10a-49c6-baff-516828270eb6'
    Author            = 'Andy Squires'
    CompanyName       = 'Stellarfire'
    Copyright         = '(c) Andy Squires. All rights reserved.'
    Description       = 'Tools for installing, configuring, and troubleshooting Win32-OpenSSH (sshd) on Windows. Every function runs against the local machine, a remote computer (-ComputerName), or an existing PSSession (-Session).'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-OpenSSHInstallation'
        'Install-OpenSSH'
        'Get-OpenSSHFirewallRule'
        'Set-OpenSSHFirewallRule'
        'Test-SSHDListening'
        'Backup-OpenSSHConfiguration'
        'Test-OpenSSHStrictModesPath'
        'Repair-OpenSSHPathPermission'
        'Restart-SSHDService'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('OpenSSH', 'SSH', 'SFTP', 'sshd', 'Win32-OpenSSH', 'Remoting', 'Windows')
            ProjectUri = ''
        }
    }
}
