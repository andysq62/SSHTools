#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'SSHTools.psd1') -Force
}

Describe 'Set-OpenSSHFirewallRule' {

    BeforeEach {
        Mock -ModuleName SSHTools Invoke-SSHToolsScriptBlock { }
    }

    It 'defaults DisplayName and Profile (Domain, Private) in the ArgumentList' {
        Set-OpenSSHFirewallRule
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[0] -eq 'OpenSSH SSH Server Preview (sshd)' -and
            $ArgumentList[1] -contains 'Domain' -and $ArgumentList[1] -contains 'Private'
        }
    }

    It 'passes custom -Profile through the ArgumentList' {
        Set-OpenSSHFirewallRule -Profile Domain, Private, Public
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[1] -contains 'Public'
        }
    }

    It 'flags EnabledSet only when -Enabled is supplied' {
        Set-OpenSSHFirewallRule                 # EnabledSet ($ArgumentList[2]) should be $false
        Set-OpenSSHFirewallRule -Enabled $true  # EnabledSet should be $true, Enabled ($ArgumentList[3]) $true
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[2] -eq $false
        }
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[2] -eq $true -and $ArgumentList[3] -eq $true
        }
    }

    It 'rejects an invalid profile name' {
        { Set-OpenSSHFirewallRule -Profile 'Nonsense' } | Should -Throw
    }

    It 'does not invoke the dispatcher under -WhatIf' {
        Set-OpenSSHFirewallRule -ComputerName 'srv1' -WhatIf
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 0
    }
}
