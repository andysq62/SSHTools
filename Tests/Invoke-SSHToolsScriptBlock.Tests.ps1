#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'SSHTools.psd1') -Force

    # Try to stand up a loopback session so the -Session routing branch can be
    # exercised. Where WinRM is not configured, those tests skip rather than fail.
    $script:LocalSession = $null
    try {
        $opt = New-PSSessionOption -OpenTimeout 3000
        $script:LocalSession = New-PSSession -ComputerName localhost -SessionOption $opt -ErrorAction Stop
    }
    catch { }
    $script:NoSession = -not $script:LocalSession
}

AfterAll {
    if ($script:LocalSession) { Remove-PSSession $script:LocalSession }
}

Describe 'Invoke-SSHToolsScriptBlock (dispatcher)' {

    It 'runs in-process (no ComputerName/Session) when given no target' {
        InModuleScope SSHTools {
            Mock Invoke-Command { }
            Invoke-SSHToolsScriptBlock -ScriptBlock { 1 }
            Should -Invoke Invoke-Command -Exactly -Times 1 -ParameterFilter {
                -not $ComputerName -and -not $Session
            }
        }
    }

    It 'routes to Invoke-Command -ComputerName when -ComputerName is supplied' {
        InModuleScope SSHTools {
            Mock Invoke-Command { }
            Invoke-SSHToolsScriptBlock -ScriptBlock { 1 } -ComputerName 'server1'
            Should -Invoke Invoke-Command -Exactly -Times 1 -ParameterFilter {
                $ComputerName -contains 'server1' -and -not $Session
            }
        }
    }

    It 'forwards -Credential together with -ComputerName' {
        InModuleScope SSHTools {
            Mock Invoke-Command { }
            $cred = [pscredential]::new('u', (ConvertTo-SecureString 'p' -AsPlainText -Force))
            Invoke-SSHToolsScriptBlock -ScriptBlock { 1 } -ComputerName 'server1' -Credential $cred
            Should -Invoke Invoke-Command -Exactly -Times 1 -ParameterFilter {
                $ComputerName -contains 'server1' -and $null -ne $Credential
            }
        }
    }

    It 'forwards the ArgumentList to Invoke-Command' {
        InModuleScope SSHTools {
            Mock Invoke-Command { }
            Invoke-SSHToolsScriptBlock -ScriptBlock { param($a) $a } -ArgumentList 'hello', 42
            Should -Invoke Invoke-Command -Exactly -Times 1 -ParameterFilter {
                $ArgumentList[0] -eq 'hello' -and $ArgumentList[1] -eq 42
            }
        }
    }

    It 'actually executes the block locally and returns its output' {
        InModuleScope SSHTools {
            $result = Invoke-SSHToolsScriptBlock -ScriptBlock { param($x) $x * 2 } -ArgumentList 21
            $result | Should -Be 42
        }
    }

    It 'routes to Invoke-Command -Session when -Session is supplied' {
        if (-not $script:LocalSession) {
            Set-ItResult -Skipped -Because 'no loopback PSSession available (WinRM not configured)'
            return
        }
        InModuleScope SSHTools -Parameters @{ Sess = $script:LocalSession } {
            param($Sess)
            Mock Invoke-Command { }
            Invoke-SSHToolsScriptBlock -ScriptBlock { 1 } -Session $Sess
            Should -Invoke Invoke-Command -Exactly -Times 1 -ParameterFilter {
                $null -ne $Session -and -not $ComputerName
            }
        }
    }
}
