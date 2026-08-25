#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'SSHTools.psd1') -Force
}

Describe 'Backup-OpenSSHConfiguration' {

    BeforeEach {
        Mock -ModuleName SSHTools Invoke-SSHToolsScriptBlock { }
    }

    It 'defaults Path and Destination in the ArgumentList' {
        Backup-OpenSSHConfiguration
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[0] -like '*\ssh' -and $ArgumentList[1] -eq 'C:\Backup\ssh_backup'
        }
    }

    It 'passes custom -Path and -Destination through the ArgumentList' {
        Backup-OpenSSHConfiguration -Path 'C:\ProgramData\ssh' -Destination 'D:\Backups\ssh'
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[0] -eq 'C:\ProgramData\ssh' -and $ArgumentList[1] -eq 'D:\Backups\ssh'
        }
    }

    It 'forwards -ComputerName' {
        Backup-OpenSSHConfiguration -ComputerName 'srv1'
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ComputerName -contains 'srv1'
        }
    }

    It 'does not invoke the dispatcher under -WhatIf' {
        Backup-OpenSSHConfiguration -WhatIf
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 0
    }
}
