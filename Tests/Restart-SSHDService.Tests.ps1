#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'SSHTools.psd1') -Force
}

Describe 'Restart-SSHDService' {

    BeforeEach {
        Mock -ModuleName SSHTools Invoke-SSHToolsScriptBlock { }
    }

    It 'runs locally when no target is given' {
        Restart-SSHDService
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            -not $ComputerName -and -not $Session
        }
    }

    It 'forwards -ComputerName' {
        Restart-SSHDService -ComputerName 'srv1'
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
            $ComputerName -contains 'srv1'
        }
    }

    It 'does not invoke the dispatcher under -WhatIf' {
        Restart-SSHDService -WhatIf
        Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 0
    }

    It 'supports ShouldProcess' {
        (Get-Command Restart-SSHDService).Parameters.Keys | Should -Contain 'WhatIf'
    }
}
