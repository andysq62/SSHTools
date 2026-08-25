#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'SSHTools.psd1') -Force
}

Describe 'Install-OpenSSH' {

    BeforeEach {
        Mock -ModuleName SSHTools Invoke-SSHToolsScriptBlock { }
    }

    It 'passes DownloadOnly = $true in the ArgumentList when -DownloadOnly is used' {
        Install-OpenSSH -DownloadOnly -Confirm:$false
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[0] -eq $true
        }
    }

    It 'passes DownloadOnly = $false by default' {
        Install-OpenSSH -Confirm:$false
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[0] -eq $false
        }
    }

    It 'forwards -ComputerName' {
        Install-OpenSSH -ComputerName 'srv1' -Confirm:$false
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ComputerName -contains 'srv1'
        }
    }

    It 'does not invoke the dispatcher under -WhatIf' {
        Install-OpenSSH -ComputerName 'srv1' -WhatIf
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 0
    }

    It 'supports ShouldProcess' {
        (Get-Command Install-OpenSSH).Parameters.Keys | Should -Contain 'WhatIf'
    }
}
