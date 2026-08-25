#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'SSHTools.psd1') -Force
}

Describe 'Test-SSHDListening' {

    Context 'Plumbing' {
        BeforeEach {
            Mock -ModuleName SSHTools Invoke-SSHToolsScriptBlock { }
        }

        It 'defaults the port to 22 in the ArgumentList' {
            Test-SSHDListening
            Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
                $ArgumentList[0] -eq 22
            }
        }

        It 'passes a custom -Port through the ArgumentList' {
            Test-SSHDListening -Port 2222
            Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
                $ArgumentList[0] -eq 2222
            }
        }

        It 'forwards -ComputerName' {
            Test-SSHDListening -ComputerName 'srv1'
            Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
                $ComputerName -contains 'srv1'
            }
        }

        It 'rejects an out-of-range port' {
            { Test-SSHDListening -Port 70000 } | Should -Throw
        }
    }

    Context 'Local execution (real dispatcher)' {
        It 'returns a well-formed result object for the local machine' {
            $result = Test-SSHDListening -Port 22
            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.Port         | Should -Be 22
            $result.Listening    | Should -BeOfType [bool]
        }
    }
}
