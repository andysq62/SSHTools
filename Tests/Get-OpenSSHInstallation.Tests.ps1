#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'SSHTools.psd1') -Force
}

Describe 'Get-OpenSSHInstallation' {

    BeforeEach {
        Mock -ModuleName SSHTools Invoke-SSHToolsScriptBlock { }
    }

    It 'runs against the local machine when no target is given' {
        Get-OpenSSHInstallation
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            -not $ComputerName -and -not $Session
        }
    }

    It 'forwards -ComputerName to the dispatcher' {
        Get-OpenSSHInstallation -ComputerName 'srv1', 'srv2'
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ComputerName -contains 'srv1' -and $ComputerName -contains 'srv2'
        }
    }

    It 'forwards -Credential to the dispatcher' {
        $cred = [pscredential]::new('u', (ConvertTo-SecureString 'p' -AsPlainText -Force))
        Get-OpenSSHInstallation -ComputerName 'srv1' -Credential $cred
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $null -ne $Credential
        }
    }

    It 'invokes once per pipeline computer' {
        'srv1', 'srv2', 'srv3' | Get-OpenSSHInstallation
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 3
    }

    It 'rejects -ComputerName and -Session together' {
        { Get-OpenSSHInstallation -ComputerName 'srv1' -Session 'x' } | Should -Throw
    }
}
