#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'SSHTools.psd1') -Force
}

Describe 'Repair-OpenSSHPathPermission' {

    BeforeEach {
        Mock -ModuleName SSHTools Invoke-SSHToolsScriptBlock { }
    }

    It 'requires -Path' {
        (Get-Command Repair-OpenSSHPathPermission).Parameters['Path'].Attributes.Mandatory |
            Should -Contain $true
    }

    It 'defaults Identity to Authenticated Users and Recurse to $false in the ArgumentList' {
        Repair-OpenSSHPathPermission -Path 'D:\' -Confirm:$false
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[0] -eq 'D:\' -and
            $ArgumentList[1] -eq 'NT AUTHORITY\Authenticated Users' -and
            $ArgumentList[2] -eq $false
        }
    }

    It 'passes -Identity and -Recurse through the ArgumentList' {
        Repair-OpenSSHPathPermission -Path 'D:\AU\Data' -Identity 'DOMAIN\Grp' -Recurse -Confirm:$false
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[1] -eq 'DOMAIN\Grp' -and $ArgumentList[2] -eq $true
        }
    }

    It 'forwards -ComputerName' {
        Repair-OpenSSHPathPermission -Path 'D:\' -ComputerName 'srv1' -Confirm:$false
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ComputerName -contains 'srv1'
        }
    }

    It 'does not invoke the dispatcher under -WhatIf' {
        Repair-OpenSSHPathPermission -Path 'D:\' -WhatIf
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 0
    }
}
