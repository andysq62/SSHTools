#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'SSHTools.psd1') -Force
}

Describe 'Get-OpenSSHFirewallRule' {

    BeforeEach {
        Mock -ModuleName SSHTools Invoke-SSHToolsScriptBlock { }
    }

    It 'defaults the DisplayName filter to *OpenSSH* in the ArgumentList' {
        Get-OpenSSHFirewallRule
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[0] -eq '*OpenSSH*'
        }
    }

    It 'passes a custom -DisplayName through the ArgumentList' {
        Get-OpenSSHFirewallRule -DisplayName 'OpenSSH SSH Server*'
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ArgumentList[0] -eq 'OpenSSH SSH Server*'
        }
    }

    It 'forwards -ComputerName' {
        Get-OpenSSHFirewallRule -ComputerName 'srv1'
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ComputerName -contains 'srv1'
        }
    }

    It 'runs locally when no target is given' {
        Get-OpenSSHFirewallRule
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            -not $ComputerName -and -not $Session
        }
    }
}
