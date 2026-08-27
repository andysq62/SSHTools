#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'SSHTools.psd1') -Force

    # A synthetic snapshot shaped exactly like the collector's output, used to drive the
    # report-formatting path without touching the real machine.
    function New-FakeSnapshot {
        [pscustomobject]@{
            ComputerName = 'TESTPC'
            CollectedAt  = '2026-01-01T00:00:00.0000000Z'
            Installation = [pscustomobject]@{
                Installs         = @(
                    [pscustomobject]@{ Type = 'Installed'; Path = 'C:\Program Files\OpenSSH\sshd.exe'; ProductVersion = '9.8.1.0'; FileVersion = '9.8.1.0' }
                )
                ClientOnPath     = 'C:\Windows\System32\OpenSSH\ssh.exe'
                ServiceName      = 'sshd'
                ServiceStatus    = 'Running'
                ServiceStartType = 'Automatic'
            }
            Firewall     = @(
                [pscustomobject]@{ DisplayName = 'OpenSSH SSH Server (sshd)'; Enabled = 'True'; Direction = 'Inbound'; Action = 'Allow'; Profiles = 'Domain, Private' }
            )
            Listening    = [pscustomobject]@{ Port = 22; Listening = $true; OwningProcess = 'sshd' }
            Paths        = @(
                [pscustomobject]@{
                    Path = 'C:\ProgramData\ssh'; Exists = $true; IsContainer = $true; Owner = 'NT AUTHORITY\SYSTEM'
                    Sha256 = $null; Length = $null; LastWriteTimeUtc = $null
                    Access = @(
                        # Deliberately out of order to prove the formatter sorts.
                        [pscustomobject]@{ Identity = 'NT AUTHORITY\SYSTEM';    Type = 'Allow'; Rights = 'FullControl'; Inherited = $false; InheritanceFlags = 'ContainerInherit, ObjectInherit'; PropagationFlags = 'None' }
                        [pscustomobject]@{ Identity = 'BUILTIN\Administrators'; Type = 'Allow'; Rights = 'FullControl'; Inherited = $false; InheritanceFlags = 'ContainerInherit, ObjectInherit'; PropagationFlags = 'None' }
                    )
                }
            )
            StrictModes  = @()
        }
    }
}

Describe 'Get-OpenSSHStatusReport' {

    Context 'Plumbing' {
        BeforeEach {
            Mock -ModuleName SSHTools Invoke-SSHToolsScriptBlock { }
        }

        It 'runs against the local machine when no target is given' {
            Get-OpenSSHStatusReport
            Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
                -not $ComputerName -and -not $Session
            }
        }

        It 'forwards -ComputerName and -Credential to the dispatcher' {
            $cred = [pscredential]::new('u', (ConvertTo-SecureString 'p' -AsPlainText -Force))
            Get-OpenSSHStatusReport -ComputerName 'srv1' -Credential $cred
            Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
                $ComputerName -contains 'srv1' -and $null -ne $Credential
            }
        }

        It 'passes port and firewall filter through the ArgumentList by default' {
            Get-OpenSSHStatusReport
            Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
                $ArgumentList[1] -eq '*OpenSSH*' -and $ArgumentList[2] -eq 22
            }
        }

        It 'passes -Path through as a single array argument' {
            Get-OpenSSHStatusReport -Path 'D:\a', 'D:\b'
            Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
                $ArgumentList[0] -contains 'D:\a' -and $ArgumentList[0] -contains 'D:\b'
            }
        }

        It 'rejects -ComputerName and -Session together' {
            { Get-OpenSSHStatusReport -ComputerName 'srv1' -Session 'x' } | Should -Throw
        }
    }

    Context 'Report file' {
        BeforeEach {
            Mock -ModuleName SSHTools Invoke-SSHToolsScriptBlock { New-FakeSnapshot }
            $script:OutFile = Join-Path ([System.IO.Path]::GetTempPath()) ("sshreport_" + [guid]::NewGuid().ToString('N') + '.txt')
        }
        AfterEach {
            if ($script:OutFile -and (Test-Path $script:OutFile)) { Remove-Item $script:OutFile -Force }
        }

        It 'writes a report containing each section and returns the snapshot object' {
            $obj = Get-OpenSSHStatusReport -OutFile $script:OutFile
            $obj.ComputerName | Should -Be 'TESTPC'
            Test-Path $script:OutFile | Should -BeTrue

            $text = Get-Content $script:OutFile -Raw
            $text | Should -Match '\[Installation\]'
            $text | Should -Match 'ServiceStatus\s+= Running'
            $text | Should -Match "Rule 'OpenSSH SSH Server \(sshd\)' \[Inbound\] Enabled=True"
            $text | Should -Match '\[Paths\]'
            $text | Should -Match 'Path C:\\ProgramData\\ssh'
            $text | Should -Match 'ACE = Allow \| BUILTIN\\Administrators \| FullControl'
            $text | Should -Match '\[StrictModes offending ACEs\]'
            $text | Should -Match '\(none\)'
        }

        It 'sorts ACEs deterministically for clean diffs' {
            Get-OpenSSHStatusReport -OutFile $script:OutFile | Out-Null
            $lines = Get-Content $script:OutFile
            $admin  = ($lines | Select-String -SimpleMatch 'ACE = Allow | BUILTIN\Administrators').LineNumber | Select-Object -First 1
            $system = ($lines | Select-String -SimpleMatch 'ACE = Allow | NT AUTHORITY\SYSTEM').LineNumber   | Select-Object -First 1
            $admin | Should -BeLessThan $system
        }
    }

    Context 'Local snapshot (real dispatcher)' {
        It 'returns a shaped snapshot for the local machine' {
            $r = Get-OpenSSHStatusReport
            $r | Should -Not -BeNullOrEmpty
            $r.ComputerName | Should -Be $env:COMPUTERNAME
            $names = $r.PSObject.Properties.Name
            foreach ($section in 'Installation', 'Firewall', 'Listening', 'Paths', 'StrictModes') {
                $names | Should -Contain $section
            }
            # The ssh data directory is always included as a permission target.
            @($r.Paths.Path) | Should -Contain (Join-Path $env:ProgramData 'ssh')
        }
    }
}
